-- EWGEST v46.15: PROPOSTA em branch, NÃO aplicada em produção.
-- Reverter entrada e transferência entre obras com base em disponibilidade e cadeia de dependências.
-- Operações com saldo dividido em vários galpões ficam bloqueadas até homologação de alocação por parcelas.
BEGIN;
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
 v_local_disponivel text;
 v_saldo_total numeric;
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
 -- O saldo disponível não prova que o lote transferido não foi utilizado:
 -- sem lote individual, bloquear consumos posteriores ainda não estornados.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0
   AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE')
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Estorno bloqueado: material consumido na obra de destino. Cancele o romaneio, reverta a saída e estorne a baixa primeiro.';END IF;
 -- Transferências posteriores para OUTRAS obras devem ser desfeitas em ordem inversa.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
   AND m.transferencia_id IS DISTINCT FROM p_transferencia_id
   AND EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
    WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
     AND other.obra_id<>m.obra_id)
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
    WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Material enviado posteriormente para outra obra. Devolva-o primeiro à obra de destino antes de estornar esta transferência.'; END IF;
 -- Reverter pelo galpão onde o material está agora, não onde foi recebido.
 SELECT m.local_estoque,sum(m.quantidade_delta)
 INTO v_local_disponivel,v_saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
 GROUP BY m.local_estoque
 HAVING sum(m.quantidade_delta)>=v_credito.quantidade_delta
 ORDER BY (m.local_estoque=v_credito.local_estoque) DESC,m.local_estoque
 LIMIT 1;
 IF v_local_disponivel IS NULL THEN
  SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_saldo_total FROM
  (SELECT sum(m.quantidade_delta) saldo FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
    AND m.variacao_id=v_credito.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
    AND m.unidade=v_credito.unidade GROUP BY m.local_estoque) t;
  IF v_saldo_total<v_credito.quantidade_delta THEN
   RAISE EXCEPTION 'Saldo insuficiente na obra destino: disponível % de % %.',v_saldo_total,v_credito.quantidade_delta,v_credito.unidade;
  END IF;
  RAISE EXCEPTION 'Saldo dividido entre galpões. Estorno por parcelas exige vínculo de auditoria; nenhum movimento foi alterado.';
 END IF;

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
  v_local_disponivel,p_operacao_id,v_credito.id);
 RETURN jsonb_build_object('repetida',false,'estornados',2,
  'origem_obra_id',v_debito.obra_id,'destino_obra_id',v_credito.obra_id,
  'galpao_da_retirada',v_local_disponivel);
END;
$function$;

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
 v_local_retirada text;
 v_total_disponivel numeric;
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
 -- Cancelar entrada não vinculada a NF-e: a localização física é irrelevante,
 -- mas material consumido ou transferido a outra obra continua indisponível.
 IF v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0 THEN
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade AND m.criado_em>=v_original.criado_em
    AND m.quantidade_delta<0
    AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE')
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id))
  THEN RAISE EXCEPTION 'Material consumido na fabricação. Cancele primeiro romaneios, saídas e baixas.';END IF;
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade AND m.criado_em>=v_original.criado_em
    AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
    AND EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
      WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
       AND other.obra_id<>m.obra_id)
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id))
  THEN RAISE EXCEPTION 'Material transferido a outra obra. Devolva-o antes de estornar a entrada.';END IF;
  SELECT m.local_estoque,sum(m.quantidade_delta) INTO v_local_retirada,v_saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
   AND m.variacao_id=v_original.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
   AND m.unidade=v_original.unidade
  GROUP BY m.local_estoque
  HAVING sum(m.quantidade_delta)>=v_original.quantidade_delta
  ORDER BY (m.local_estoque=v_original.local_estoque) DESC,m.local_estoque LIMIT 1;
  IF v_local_retirada IS NULL THEN
   SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_total_disponivel
   FROM(SELECT sum(m.quantidade_delta) saldo FROM public.ew_estoque_obras_movimentos m
     WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
      AND m.variacao_id=v_original.variacao_id
      AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
      AND m.unidade=v_original.unidade GROUP BY m.local_estoque) t;
   IF v_total_disponivel<v_original.quantidade_delta THEN
    RAISE EXCEPTION 'Saldo insuficiente na obra. Devolva material transferido ou usado antes do estorno.';
   END IF;
   RAISE EXCEPTION 'Saldo dividido entre galpões. Estorno por parcelas ainda não homologado; nenhuma baixa foi realizada.';
  END IF;
 END IF;
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
  if v_original.transferencia_id IS NOT NULL AND v_saldo-v_mov.quantidade_delta<0 then
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
   left('Estorno individual: '||v_motivo,500),v_uid,
   CASE WHEN v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0
    THEN v_local_retirada ELSE v_mov.local_estoque END,v_mov.id
  );
  v_n:=v_n+1;
  v_originais:=v_originais||jsonb_build_array(jsonb_build_object(
   'movimento_id',v_mov.id,'origem',v_mov.origem,'quantidade',v_mov.quantidade_delta,
   'variacao_id',v_mov.variacao_id,'comprimento_mm',v_mov.comprimento_mm,
   'unidade',v_mov.unidade,'galpao',v_mov.local_estoque,
   'usuario_original',v_mov.usuario_id,'registrado_em',v_mov.criado_em,
   'transferencia_id',v_mov.transferencia_id,
   'galpao_do_estorno',CASE WHEN v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0
    THEN v_local_retirada ELSE v_mov.local_estoque END
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
$function$;
COMMIT;
