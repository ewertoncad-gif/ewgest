-- Migração aplicada no Supabase de produção em 21/11/2026.
-- 20261121134428_transferencia_entre_obras_estorno_e_guardas_20261121
-- RPCs de transferência/estorno atômico e guardas em estorno total/arquivamento.
-- Nenhum saldo existente foi alterado durante a implantação.

-- database/proposals/20261121_transferencia_estoque_entre_obras.sql
-- EWGEST | Transferência entre estoques de obras da mesma empresa.
-- Não cria estoque físico; registra saída e entrada vinculadas na mesma transação.
-- Compatível com a função existente de transferência ENTRE GALPÕES da mesma obra.
CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_entre_obras(
 p_empresa_id uuid,
 p_origem_obra_id uuid,
 p_destino_obra_id uuid,
 p_variacao_id uuid,
 p_comprimento_mm integer,
 p_unidade text,
 p_quantidade numeric,
 p_origem_local text,
 p_destino_local text,
 p_observacao text,
 p_operacao_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $ewg$
DECLARE
 v_usuario uuid:=auth.uid();
 v_origem_local text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino_local text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;
 v_unidade_acessorio text;
 v_saldo numeric;
 v_quantidade_movimentos integer;
 v_origem_codigo text;
 v_destino_codigo text;
 v_chave_origem text;
 v_chave_destino text;
 v_observacao text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
  NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
    WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_usuario
     AND u.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode transferir estoque entre obras.'; END IF;

 IF p_origem_obra_id IS NULL OR p_destino_obra_id IS NULL OR
    p_origem_obra_id=p_destino_obra_id
 THEN RAISE EXCEPTION 'Selecione obras de origem e destino diferentes.'; END IF;

 SELECT codigo INTO v_origem_codigo FROM public.obras
 WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 SELECT codigo INTO v_destino_codigo FROM public.obras
 WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 IF NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_origem_obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_destino_obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Obra ou estoque inexistente, de outra empresa ou arquivado.'; END IF;

 IF v_origem_local='' OR v_destino_local='' OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_origem_local AND ativo) OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_destino_local AND ativo)
 THEN RAISE EXCEPTION 'Galpão de origem ou destino inválido.'; END IF;

 SELECT v.tipo,upper(btrim(a.unidade_item))
 INTO v_tipo,v_unidade_acessorio
 FROM public.ew_materiais_variacoes v
 LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id AND a.empresa_id=p_empresa_id
 WHERE v.id=p_variacao_id AND v.empresa_id=p_empresa_id AND v.ativo;
 IF v_tipo IS NULL OR p_quantidade IS NULL OR p_quantidade<=0 OR p_quantidade>1000000 OR
    (v_tipo='perfil' AND
      (p_unidade IS DISTINCT FROM 'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000
       OR p_comprimento_mm IS NULL OR p_quantidade<>trunc(p_quantidade))) OR
    (v_tipo='acessorio' AND
      (p_comprimento_mm IS NOT NULL OR
       p_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') OR
       p_unidade IS DISTINCT FROM v_unidade_acessorio OR
       p_quantidade<>round(p_quantidade,3)))
 THEN RAISE EXCEPTION 'Material, comprimento, unidade ou quantidade inválidos.'; END IF;
 IF char_length(btrim(coalesce(p_observacao,''))) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe um motivo de 5 a 350 caracteres.'; END IF;

 -- Uma mesma operação não pode ser executada em paralelo, nem reutilizada
 -- para mudar origem, destino, material ou quantidade.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'TRANSF_OBRAS|'||p_operacao_id::text,62841));
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
    WHERE m.transferencia_id=p_operacao_id AND m.empresa_id<>p_empresa_id)
 THEN RAISE EXCEPTION 'Identificador de transferência já utilizado.'; END IF;

 SELECT count(*) INTO v_quantidade_movimentos
 FROM public.ew_estoque_obras_movimentos
 WHERE transferencia_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF v_quantidade_movimentos>0 THEN
  IF v_quantidade_movimentos<>2 OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_origem_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_origem_local
      AND quantidade_delta=-p_quantidade AND origem='TRANSFERENCIA') OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_destino_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_destino_local
      AND quantidade_delta=p_quantidade AND origem='TRANSFERENCIA')
  THEN RAISE EXCEPTION 'Identificador já utilizado para outra transferência.'; END IF;
  RETURN jsonb_build_object('repetida',true,'quantidade',p_quantidade,
    'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id);
 END IF;

 -- Mesma chave de lock do estoque normal. Ordenação estável evita deadlock
 -- quando duas obras transferem materiais entre si ao mesmo tempo.
 v_chave_origem:=p_origem_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 v_chave_destino:=p_destino_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   least(v_chave_origem,v_chave_destino),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   greatest(v_chave_origem,v_chave_destino),34777));
 SELECT coalesce(sum(m.quantidade_delta),0) INTO v_saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=p_empresa_id AND m.obra_id=p_origem_obra_id
  AND m.variacao_id=p_variacao_id AND
  m.comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
  AND m.unidade=p_unidade AND m.local_estoque=v_origem_local;
 IF v_saldo<p_quantidade
 THEN RAISE EXCEPTION 'Saldo insuficiente na obra de origem. Disponível: % %.',v_saldo,p_unidade; END IF;

 v_observacao:='Remanejamento entre obras '||coalesce(v_origem_codigo,'—')||
  ' → '||coalesce(v_destino_codigo,'—')||' · '||btrim(p_observacao);
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 VALUES
 (p_empresa_id,p_origem_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  -p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_origem_local,p_operacao_id),
 (p_empresa_id,p_destino_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_destino_local,p_operacao_id);
 RETURN jsonb_build_object('repetida',false,'quantidade',p_quantidade,
  'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id,
  'saldo_origem',v_saldo-p_quantidade,'comprimento_mm',p_comprimento_mm);
END;
$ewg$;

REVOKE ALL ON FUNCTION public.ew_transferir_estoque_entre_obras(
 uuid,uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_transferir_estoque_entre_obras(
 uuid,uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid)
 TO authenticated;
NOTIFY pgrst, 'reload schema';


-- database/proposals/20261121_estorno_transferencia_entre_obras.sql
-- EWGEST: estorno ATÔMICO das duas pernas de transferência entre obras.
-- Um estorno só é permitido se o destino ainda possui as quantidades recebidas.
CREATE OR REPLACE FUNCTION public.ew_estornar_transferencia_entre_obras(
 p_empresa_id uuid,p_transferencia_id uuid,p_motivo text,p_operacao_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $ewg$
DECLARE
 v_uid uuid:=auth.uid();
 v_debito public.ew_estoque_obras_movimentos%rowtype;
 v_credito public.ew_estoque_obras_movimentos%rowtype;
 v_n integer;
 v_saldo numeric;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_status jsonb;
 v_key_a text;
 v_key_b text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF p_empresa_id IS NULL OR p_transferencia_id IS NULL OR p_operacao_id IS NULL
 OR v_uid IS NULL OR NOT EXISTS (
  SELECT 1 FROM public.usuarios_empresas u WHERE u.empresa_id=p_empresa_id
   AND u.usuario_id=v_uid AND u.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente ADM pode estornar transferências entre obras.'; END IF;
 IF char_length(v_motivo) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe motivo de 5 a 350 caracteres.'; END IF;

 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'ESTORNO_TRANSF_OBRAS|'||p_operacao_id::text,62841));
 -- Idempotência por operação, sem estornar duas vezes.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE transferencia_id=p_operacao_id AND origem='ESTORNO') THEN
  IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos m
       JOIN public.ew_estoque_obras_movimentos o ON o.id=m.estorno_de_id
       WHERE m.empresa_id=p_empresa_id AND m.transferencia_id=p_operacao_id
        AND m.origem='ESTORNO' AND o.transferencia_id=p_transferencia_id)=2
   THEN RETURN jsonb_build_object('repetida',true,'estornados',2); END IF;
  RAISE EXCEPTION 'Identificador já utilizado para outro estorno.';
 END IF;

 SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id AND origem='TRANSFERENCIA';
 IF v_n<>2 THEN RAISE EXCEPTION 'Transferência entre obras não localizada ou incompleta.';END IF;
 SELECT * INTO v_debito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta<0;
 SELECT * INTO v_credito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta>0;
 IF v_debito.id IS NULL OR v_credito.id IS NULL OR
  v_debito.obra_id=v_credito.obra_id OR
  v_debito.variacao_id IS DISTINCT FROM v_credito.variacao_id OR
  v_debito.comprimento_mm IS DISTINCT FROM v_credito.comprimento_mm OR
  v_debito.unidade IS DISTINCT FROM v_credito.unidade OR
  v_debito.quantidade_delta<>-v_credito.quantidade_delta
 THEN RAISE EXCEPTION 'Movimentos da transferência não formam um par íntegro.'; END IF;

 v_key_a:=v_debito.obra_id::text;
 v_key_b:=v_credito.obra_id::text;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),977124));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),977124));
 IF NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_debito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_credito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_debito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_credito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL)
 THEN RAISE EXCEPTION 'Uma das obras ou estoques está arquivada.'; END IF;

 v_status:=public.ew_inspecionar_reversao_obra(v_debito.obra_id);
 IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements_text(v_status->'motivos') AS motivo(texto)
  WHERE motivo.texto NOT LIKE 'Estorne as movimentações do estoque%')
 THEN RAISE EXCEPTION 'Existem liberações ou outras pendências na obra de origem. Concilie antes.';END IF;
 v_status:=public.ew_inspecionar_reversao_obra(v_credito.obra_id);
 IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements_text(v_status->'motivos') AS motivo(texto)
  WHERE motivo.texto NOT LIKE 'Estorne as movimentações do estoque%')
 THEN RAISE EXCEPTION 'Existem liberações ou outras pendências na obra de destino. Concilie antes.';END IF;

 -- Mesmo lock do estoque normal; origem e destino em ordem estável.
 v_key_a:=v_debito.obra_id::text||'|'||v_debito.variacao_id::text||'|'||
  coalesce(v_debito.comprimento_mm::text,'-')||'|'||v_debito.unidade;
 v_key_b:=v_credito.obra_id::text||'|'||v_credito.variacao_id::text||'|'||
  coalesce(v_credito.comprimento_mm::text,'-')||'|'||v_credito.unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),34777));

 IF EXISTS (SELECT 1 FROM public.ew_estoque_obras_movimentos
  WHERE estorno_de_id IN (v_debito.id,v_credito.id))
 THEN RAISE EXCEPTION 'Uma das pernas já foi estornada. Recarregue o histórico.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND obra_id=v_credito.obra_id AND
  variacao_id=v_credito.variacao_id AND comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
  AND unidade=v_credito.unidade AND local_estoque=v_credito.local_estoque;
 IF v_saldo<v_credito.quantidade_delta
 THEN RAISE EXCEPTION 'Saldo insuficiente no destino para estornar. Disponível: % %.',v_saldo,v_credito.unidade;END IF;

 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
 VALUES
 (p_empresa_id,v_debito.obra_id,v_debito.variacao_id,v_debito.comprimento_mm,v_debito.unidade,
  -v_debito.quantidade_delta,'ESTORNO',gen_random_uuid(),
  left('Estorno da transferência entre obras: '||v_motivo,500),v_uid,
  v_debito.local_estoque,p_operacao_id,v_debito.id),
 (p_empresa_id,v_credito.obra_id,v_credito.variacao_id,v_credito.comprimento_mm,v_credito.unidade,
  -v_credito.quantidade_delta,'ESTORNO',gen_random_uuid(),
  left('Estorno da transferência entre obras: '||v_motivo,500),v_uid,
  v_credito.local_estoque,p_operacao_id,v_credito.id);
 RETURN jsonb_build_object('repetida',false,'estornados',2,
  'origem_obra_id',v_debito.obra_id,'destino_obra_id',v_credito.obra_id);
END;
$ewg$;

REVOKE ALL ON FUNCTION public.ew_estornar_transferencia_entre_obras(
 uuid,uuid,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_estornar_transferencia_entre_obras(
 uuid,uuid,text,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';


-- database/proposals/20261121_guard_estorno_estoque_transferencias_obras.sql
-- Protege estorno total contra reversão isolada de transferências entre obras.
-- Função completa versionada, sem apagar histórico.
CREATE OR REPLACE FUNCTION public.ew_estornar_estoque_obra(p_obra_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Identificador de operação obrigatório.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 v_status:=public.ew_inspecionar_reversao_obra(p_obra_id);
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao<>'ESTORNAR_ESTOQUE' or v_audit.obra_id<>p_obra_id or v_audit.usuario_id<>v_uid
   then raise exception 'Identificador de operação já utilizado.';end if;
  return jsonb_build_object('repetida',true,'estornados',
    v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 if (v_status->'resumo'->>'romaneios')::int>0
   or (v_status->'resumo'->>'saidas_producao')::int>0
   or (v_status->'resumo'->>'liberacoes')::int>0
   or (v_status->'resumo'->>'lotes_cem')::int>0
   or (v_status->'resumo'->>'planos_liberados')::int>0
   or (v_status->'resumo'->>'unidades_liberadas')::int>0
   or (v_status->'resumo'->>'fabricadas')::int>0
 then raise exception 'Cancele romaneios, saídas e liberações antes de estornar o estoque.';end if;
 -- Uma transferência ENTRE OBRAS não pode ser revertida em apenas uma
 -- das obras. Ela deve ser estornada atomicamente nas duas pontas.
 IF EXISTS (
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id AND m.origem='TRANSFERENCIA'
    AND m.transferencia_id IS NOT NULL
    AND EXISTS (
     SELECT 1 FROM public.ew_estoque_obras_movimentos outra
     WHERE outra.transferencia_id=m.transferencia_id
       AND outra.origem='TRANSFERENCIA' AND outra.obra_id<>m.obra_id
    )
    AND NOT EXISTS (
     SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id
    )
 ) THEN
  RAISE EXCEPTION 'Há transferência ativa entre obras. Estorne as duas pontas pelo histórico de movimentações antes de estornar o estoque inteiro.';
 END IF;
 perform 1 from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id order by m.id for update;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
   group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
   having sum(m.quantidade_delta)<0) then
  raise exception 'Saldo negativo em galpão. Concilie o estoque antes do estorno.';end if;
 -- Registra em detalhes cada movimento que será revertido.
 select count(*),
  coalesce(jsonb_agg(jsonb_build_object('id',m.id,'origem',m.origem,
   'quantidade',m.quantidade_delta,'local',m.local_estoque,
   'unidade',m.unidade,'comprimento_mm',m.comprimento_mm,
   'variacao_id',m.variacao_id,'criado_em',m.criado_em,'usuario_original',m.usuario_id)),
   '[]'::jsonb)
 into v_n,v_originais from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if v_n=0 then
  if (v_status->'resumo'->>'saldos_nao_zerados')::int>0 then
   raise exception 'Não existem movimentos pendentes, mas há saldos diferentes de zero.';end if;
  return jsonb_build_object('repetida',false,'estornados',0,'historico_preservado',true);
 end if;
 insert into public.ew_estoque_obras_movimentos (
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
 select m.empresa_id,m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,
  -m.quantidade_delta,'ESTORNO',gen_random_uuid(),left('Estorno para reimportação: '||v_motivo,500),
  v_uid,m.local_estoque,m.id
 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if exists(select 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
 group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
 having sum(m.quantidade_delta)<>0) then
  raise exception 'A operação não zerou todos os saldos. Nenhum estorno foi confirmado.';end if;
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_operacao_id,v_motivo,jsonb_build_object('movimentos_estornados',v_n,
   'movimentos_originais',v_originais));
 return jsonb_build_object('repetida',false,'estornados',v_n,'historico_preservado',true);
end;$function$;


-- database/proposals/20261121_guard_arquivar_estoque_transferencias_obras.sql
-- Impede arquivar somente uma ponta de transferência entre obras.
CREATE OR REPLACE FUNCTION public.ew_excluir_estoque_local(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_count integer;v_deleted_at timestamptz;v_item uuid;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
   WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_uid AND u.perfil IN ('administrador','gerenciador'))
 THEN RAISE EXCEPTION 'Somente o ADM pode excluir um estoque.';END IF;
 SELECT id INTO v_item FROM public.ew_estoques_locais
 WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND excluido_em IS NULL FOR UPDATE;
 IF v_item IS NULL THEN RAISE EXCEPTION 'Estoque não encontrado ou já excluído.';END IF;
 -- Transferência entre obras ativa mantém obrigação em ambas as pontas.
 -- Arquivar uma das pontas impediria seu estorno transacional.
 IF EXISTS (
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=p_obra_id
   AND m.origem='TRANSFERENCIA' AND m.transferencia_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.ew_estoque_obras_movimentos outra
    WHERE outra.transferencia_id=m.transferencia_id
     AND outra.origem='TRANSFERENCIA' AND outra.obra_id<>m.obra_id)
   AND NOT EXISTS (SELECT 1 FROM public.ew_estoque_obras_movimentos est
    WHERE est.estorno_de_id=m.id)
 ) THEN RAISE EXCEPTION 'Existe transferência entre obras ainda ativa. Concilie e estorne a transferência vinculada antes de arquivar esta obra.';
 END IF;
 SELECT count(distinct variacao_id) INTO v_count FROM public.ew_estoque_obras_movimentos
   WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id;
 v_deleted_at:=now();
 UPDATE public.ew_estoques_locais
 SET excluido_em=v_deleted_at,excluido_por=v_uid,
   restauravel_ate=v_deleted_at+interval '48 hours' WHERE id=v_item;
 RETURN jsonb_build_object('materiais_com_movimento',v_count,
   'restauravel_ate',v_deleted_at+interval '48 hours',
   'aviso','O estoque foi arquivado. Obra, materiais e histórico permanecem preservados.');
END;$function$;
