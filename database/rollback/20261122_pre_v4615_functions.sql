-- EWGEST v46.15: snapshot das quatro RPCs de produção anterior à migração.
-- Resgate somente antes de estornos novos por parcelas, ou após revisão detalhada
-- dos vínculos para não perder a compatibilidade. Não apaga dados nem tabelas.
BEGIN;
CREATE OR REPLACE FUNCTION public.ew_estornar_estoque_obra(p_obra_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;v_conciliadas int:=0;
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
    v_audit.detalhes->'movimentos_estornados',
    'conciliados',coalesce((v_audit.detalhes->>'transferencias_conciliadas')::int,0),
    'historico_preservado',true);
 end if;
 if (v_status->'resumo'->>'romaneios')::int>0
   or (v_status->'resumo'->>'saidas_producao')::int>0
   or (v_status->'resumo'->>'liberacoes')::int>0
   or (v_status->'resumo'->>'lotes_cem')::int>0
   or (v_status->'resumo'->>'planos_liberados')::int>0
   or (v_status->'resumo'->>'unidades_liberadas')::int>0
   or (v_status->'resumo'->>'fabricadas')::int>0
 then raise exception 'Cancele romaneios, saídas e liberações antes de estornar o estoque.';end if;
 -- Se as NF-e foram totalmente estornadas E somente restam pares de
 -- transferências internas equilibradas, NÃO gerar novos movimentos inversos:
 -- isso recriaria saldo negativo na origem/positivo no destino.
 v_conciliadas:=public.ew_transferencias_nfe_conciliadas(p_obra_id);
 IF v_conciliadas>0 THEN
  IF NOT (v_status->>'permitido')::boolean
    OR (v_status->'resumo'->>'transferencias_nfe_conciliadas')::int<>v_conciliadas
    OR (v_status->'resumo'->>'movimentos_pendentes')::int<>0
    OR (v_status->'resumo'->>'saldos_nao_zerados')::int<>0 THEN
   RAISE EXCEPTION 'Transferências não estão totalmente conciliadas. Verifique saldos e pendências.';
  END IF;
  INSERT INTO public.ew_auditoria_operacoes
   (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
  VALUES(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
   p_operacao_id,v_motivo,jsonb_build_object(
    'modo','CONCILIAR_TRANSFERENCIAS_NFE',
    'movimentos_estornados',0,
    'transferencias_conciliadas',v_conciliadas,
    'saldo_zerado_sem_novos_lancamentos',true));
  RETURN jsonb_build_object('repetida',false,'estornados',0,
   'conciliados',v_conciliadas,'saldos_zerados',true,
   'historico_preservado',true);
 END IF;
 -- Reverter estoque inteiro com NF vinculada pode desfazer uma devolução
 -- física sem atualizar o histórico da nota. Exigir fluxo específico.
 if exists(select 1 from public.ew_nfe_recebimentos n where n.obra_id=p_obra_id) then
  raise exception 'A obra contém recebimentos de NF-e. Use o estorno por recebimento; não zere o estoque inteiro.';
 end if;
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
end;$function$

CREATE OR REPLACE FUNCTION public.ew_estornar_movimento_obra(p_obra_id uuid, p_movimento_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid := auth.uid();
 v_obra public.obras%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_audit public.ew_auditoria_operacoes%rowtype;
 v_ver jsonb;
 v_mov public.ew_estoque_obras_movimentos%rowtype;
 v_motivo text := btrim(coalesce(p_motivo,''));
 v_saldo numeric;
 v_n integer := 0;
 v_par integer;
 v_soma numeric;
 v_materials integer;
 v_locais integer;
 v_originais jsonb := '[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_obra_id is null or p_movimento_id is null or p_operacao_id is null then
  raise exception 'Obra, movimento, operação e usuário são obrigatórios.';
 end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo com 5 a 400 caracteres.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_obra from public.obras where id=p_obra_id for update;
 if not found or v_obra.arquivada_em is not null then
  raise exception 'Obra não encontrada ou já arquivada.';
 end if;
 if not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_obra.empresa_id
   and ue.perfil in ('administrador','gerenciador')
   and ul.perfil=ue.perfil and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem realizar estornos.'; end if;
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao <> 'ESTORNAR_ESTOQUE'
   or v_audit.obra_id is distinct from p_obra_id or v_audit.usuario_id <> v_uid
   or v_audit.referencia_id is distinct from p_movimento_id then
   raise exception 'Identificador de operação já usado em outro estorno.';
  end if;
  return jsonb_build_object('repetida',true,
   'estornados',v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 select * into v_original from public.ew_estoque_obras_movimentos
 where id=p_movimento_id and obra_id=p_obra_id for update;
 if not found then raise exception 'Movimentação não encontrada nesta obra.'; end if;
 if v_original.origem='ESTORNO' and v_original.observacao like 'Estorno do recebimento NF%' then
  raise exception 'Estorno de recebimento NF-e não pode ser revertido pela função genérica.';
 end if;
 if exists(select 1 from public.ew_nfe_recebimentos n where n.movimento_id=v_original.id) then
  raise exception 'Movimento vinculado à NF-e: use Estornar recebimento na tela Recebimento.';
 end if;
 if v_original.estorno_de_id is not null then
  raise exception 'Uma contrapartida de estorno não pode ser cancelada novamente.';
 end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos e
  where e.estorno_de_id=p_movimento_id) then
  raise exception 'Esta movimentação já foi estornada.';
 end if;
 v_ver := public.ew_inspecionar_reversao_obra(p_obra_id);
 if exists (
  select 1 from pg_catalog.jsonb_array_elements_text(v_ver->'motivos') as x(motivo)
  where x.motivo not like 'Estorne as movimentações do estoque%'
 ) then
  raise exception 'Cancele romaneios, saídas e liberações e resolva outras pendências antes do estorno individual.';
 end if;
 -- Transferência entre galpões é uma operação única de duas pernas.
 if v_original.transferencia_id is not null then
  if v_original.origem<>'TRANSFERENCIA' then
   raise exception 'Movimento de transferência possui origem inconsistente.';
  end if;
  select count(*),coalesce(sum(m.quantidade_delta),0),
   count(distinct (m.variacao_id::text||'|'||coalesce(m.comprimento_mm::text,'')||'|'||m.unidade)),
   count(distinct m.local_estoque)
  into v_par,v_soma,v_materials,v_locais
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.transferencia_id=v_original.transferencia_id;
  if v_par<>2 or v_soma<>0 or v_materials<>1 or v_locais<>2 then
   raise exception 'Transferência incompleta ou inconsistente. Não é seguro estornar uma perna isoladamente.';
  end if;
 end if;
 -- Toda a obra é serializada pelo mesmo bloqueio da reversão total.
 perform 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
  and (m.id=p_movimento_id or
   (v_original.transferencia_id is not null
    and m.transferencia_id=v_original.transferencia_id))
 order by m.id for update;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  if v_mov.estorno_de_id is not null or exists(
   select 1 from public.ew_estoque_obras_movimentos s where s.estorno_de_id=v_mov.id
  ) then raise exception 'Uma das movimentações já foi estornada. Recarregue o histórico.'; end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.variacao_id=v_mov.variacao_id
   and m.comprimento_mm is not distinct from v_mov.comprimento_mm
   and m.unidade=v_mov.unidade and m.local_estoque=v_mov.local_estoque;
  if v_saldo-v_mov.quantidade_delta<0 then
   raise exception 'Estorno individual deixaria saldo negativo em % (% %). Desfaça antes as movimentações posteriores dependentes.',
    v_mov.local_estoque,v_saldo,v_mov.unidade;
  end if;
 end loop;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  insert into public.ew_estoque_obras_movimentos (
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id
  ) values (
   v_mov.empresa_id,v_mov.obra_id,v_mov.variacao_id,v_mov.comprimento_mm,
   v_mov.unidade,-v_mov.quantidade_delta,'ESTORNO',pg_catalog.gen_random_uuid(),
   left('Estorno individual: '||v_motivo,500),v_uid,v_mov.local_estoque,v_mov.id
  );
  v_n:=v_n+1;
  v_originais:=v_originais||jsonb_build_array(jsonb_build_object(
   'movimento_id',v_mov.id,'origem',v_mov.origem,'quantidade',v_mov.quantidade_delta,
   'variacao_id',v_mov.variacao_id,'comprimento_mm',v_mov.comprimento_mm,
   'unidade',v_mov.unidade,'galpao',v_mov.local_estoque,
   'usuario_original',v_mov.usuario_id,'registrado_em',v_mov.criado_em,
   'transferencia_id',v_mov.transferencia_id
  ));
 end loop;
 insert into public.ew_auditoria_operacoes (
  empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
  referencia_id,operacao_id,motivo,detalhes
 ) values (
  v_obra.empresa_id,p_obra_id,v_obra.nome,v_obra.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_movimento_id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','individual','movimentos_estornados',v_n,
   'movimentos_originais',v_originais)
 );
 return jsonb_build_object('repetida',false,'estornados',v_n,
  'historico_preservado',true);
end;
$function$

CREATE OR REPLACE FUNCTION public.ew_estornar_transferencia_entre_obras(p_empresa_id uuid, p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.ew_inspecionar_reversao_obra(p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_obra public.obras%rowtype;v_uid uuid:=auth.uid();
 v_n_esq int;v_lib int;v_lib_cancel int;v_lotes int;v_planos int;
 v_rom int;v_rom_cancel int;v_saida int;v_saida_cancel int;
 v_mov int;v_mov_abertos int;v_fabr int;v_liberadas int;v_refs int;
 v_saldos int;v_insumos_saldos int;v_conciliadas int:=0;v_motivos text[]:=array[]::text[];
begin
 perform public.ew_exigir_sessao_atual();
 select * into v_obra from public.obras where id=p_obra_id;
 if not found then raise exception 'Obra não encontrada.';end if;
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.empresa_id=v_obra.empresa_id and ue.usuario_id=v_uid
   and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
   and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem conferir reversões.';end if;
 select count(*),coalesce(sum(e.qtd_liberada),0),coalesce(sum(e.qtd_fabricada),0)
 into v_n_esq,v_liberadas,v_fabr from public.esquadrias e where e.obra_id=p_obra_id;
 select count(*) filter(where l.cancelado_em is null),
 count(*) filter(where l.cancelado_em is not null)
 into v_lib,v_lib_cancel from public.liberacoes_corte l
 join public.esquadrias e on e.id=l.esquadria_id where e.obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
 where obra_id=p_obra_id and cancelado_em is null;
 select count(*) into v_planos from public.ew_planos_liberados p
 left join public.liberacoes_corte l on l.id=p.liberacao_id
 where p.obra_id=p_obra_id and (l.id is null or l.cancelado_em is null);
 select count(*) filter(where status<>'cancelado'),
 count(*) filter(where status='cancelado')
 into v_rom,v_rom_cancel from public.romaneios where obra_id=p_obra_id;
 select count(*) filter(where s.cancelado_em is null),
 count(*) filter(where s.cancelado_em is not null)
 into v_saida,v_saida_cancel from public.saidas_producao s
 join public.esquadrias e on e.id=s.esquadria_id where e.obra_id=p_obra_id;
 select count(*),
 count(*) filter(where m.estorno_de_id is null
  and not exists(select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id))
 into v_mov,v_mov_abertos from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id;
 select count(*) into v_saldos from (
  select m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
  from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
  group by 1,2,3,4 having sum(m.quantidade_delta)<>0
 ) saldo;
 select count(*) into v_insumos_saldos from (
  select m.insumo_id,m.local_estoque from public.ew_insumos_movimentos m
  where m.empresa_id=v_obra.empresa_id and m.obra_id=p_obra_id
  group by m.insumo_id,m.local_estoque having sum(m.quantidade_delta)<>0
 ) x;
 select count(*) into v_refs from (
  select a.id from public.classificacoes_tipologias_auditoria a
   join public.esquadrias e on e.id=a.esquadria_referencia_id
   where e.obra_id=p_obra_id and a.obra_id<>p_obra_id
  union all
  select r.id from public.esquadrias_descricoes_revisoes r
   join public.esquadrias e on e.id=r.esquadria_referencia_id
   where e.obra_id=p_obra_id and r.obra_id<>p_obra_id
 ) xs;
 -- Transferências internas históricas ficam conciliadas quando todas as NF-e
 -- físicas foram estornadas e o saldo em cada galpão já é exatamente zero.
 v_conciliadas:=public.ew_transferencias_nfe_conciliadas(p_obra_id);
 IF v_conciliadas>0 AND v_conciliadas=v_mov_abertos THEN
   v_mov_abertos:=0;
 ELSE
   v_conciliadas:=0;
 END IF;
 if v_rom>0 then v_motivos:=array_append(v_motivos,'Cancele todos os romaneios emitidos.');end if;
 if v_saida>0 then v_motivos:=array_append(v_motivos,'Estorne todas as saídas de produção ainda ativas.');end if;
 if v_lib>0 or v_lotes>0 or v_planos>0 or v_liberadas>0 then
  v_motivos:=array_append(v_motivos,'Cancele as liberações para corte e seus lotes.');end if;
 if v_fabr>0 then v_motivos:=array_append(v_motivos,'Existem quantidades fabricadas a conciliar.');end if;
 if v_mov_abertos>0 or v_saldos>0 then
  v_motivos:=array_append(v_motivos,'Estorne as movimentações do estoque e confira saldo zero por material e galpão.');end if;
 if v_insumos_saldos>0 then v_motivos:=array_append(v_motivos,
  'Estorne ou transfira todo o estoque de vidros e outros insumos antes de arquivar a obra.');end if;
 if v_refs>0 then v_motivos:=array_append(v_motivos,'Há referências vinculadas a outra obra.');end if;
 if v_obra.arquivada_em is not null then
  v_motivos:=array_append(v_motivos,'Esta obra já foi retirada do acompanhamento ativo.');end if;
 return jsonb_build_object(
 'obra_id',v_obra.id,'nome',v_obra.nome,'codigo',v_obra.codigo,'motivos',to_jsonb(v_motivos),
 'permitido',cardinality(v_motivos)=0,'arquivada_em',v_obra.arquivada_em,
 'resumo',jsonb_build_object(
  'esquadrias',v_n_esq,'liberacoes',v_lib,'liberacoes_canceladas',v_lib_cancel,
  'unidades_liberadas',v_liberadas,'fabricadas',v_fabr,'lotes_cem',v_lotes,
  'planos_liberados',v_planos,'romaneios',v_rom,'romaneios_cancelados',v_rom_cancel,
  'saidas_producao',v_saida,'saidas_canceladas',v_saida_cancel,
  'movimentos_estoque',v_mov,'movimentos_pendentes',v_mov_abertos,
  'transferencias_nfe_conciliadas',v_conciliadas,
  'saldos_nao_zerados',v_saldos,'saldos_insumos_nao_zerados',v_insumos_saldos,
  'referencias_externas',v_refs));
end;$function$
COMMIT;
