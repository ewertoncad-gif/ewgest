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
