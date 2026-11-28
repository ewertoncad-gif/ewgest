-- Condições comerciais da proposta, imutáveis após seu registro.
BEGIN;
ALTER TABLE public.ew_compras_cotacoes ADD COLUMN condicoes_comerciais jsonb;
CREATE FUNCTION public.ew_compras_cotar_com_condicoes(p_empresa_id uuid,p_solicitacao_id uuid,p_fornecedor_id uuid,p_precos jsonb,p_operacao_id uuid,p_condicoes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb; c jsonb; q public.ew_compras_cotacoes%ROWTYPE;
 prazo int; validade date; pagamento text; frete text; observacao text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.cotar') OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') THEN RAISE EXCEPTION 'Sem permissão para cotar.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_compras_solicitacoes s WHERE s.id=p_solicitacao_id AND s.empresa_id=p_empresa_id) THEN RAISE EXCEPTION 'Solicitação indisponível.';END IF;
 IF jsonb_typeof(p_condicoes) IS DISTINCT FROM 'object' OR (p_condicoes-ARRAY['prazo_dias','validade','pagamento','frete','observacao']::text[])<>'{}'::jsonb THEN RAISE EXCEPTION 'Condições comerciais inválidas.';END IF;
 IF p_condicoes->>'prazo_dias' IS NOT NULL THEN
  IF (p_condicoes->>'prazo_dias')!~'^[0-9]{1,4}$' THEN RAISE EXCEPTION 'Prazo inválido.';END IF;
  prazo:=(p_condicoes->>'prazo_dias')::int;IF prazo>3650 THEN RAISE EXCEPTION 'Prazo inválido.';END IF;
 END IF;
 IF p_condicoes->>'validade' IS NOT NULL THEN
  IF (p_condicoes->>'validade')!~'^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Validade inválida.';END IF;
  validade:=(p_condicoes->>'validade')::date;
 END IF;
 pagamento:=nullif(btrim(coalesce(p_condicoes->>'pagamento','')),'');
 observacao:=nullif(btrim(coalesce(p_condicoes->>'observacao','')),'');
 frete:=coalesce(p_condicoes->>'frete','NAO_INFORMADO');
 IF length(coalesce(pagamento,''))>200 OR length(coalesce(observacao,''))>400 OR frete NOT IN ('NAO_INFORMADO','INCLUSO','RETIRADA','A_COMBINAR') THEN RAISE EXCEPTION 'Condições comerciais inválidas.';END IF;
 c:=jsonb_build_object('prazo_dias',prazo,'validade',validade,'pagamento',pagamento,'frete',frete,'observacao',observacao);
 r:=public.ew_compras_criar_cotacao(p_solicitacao_id,p_fornecedor_id,p_precos,p_operacao_id);
 SELECT * INTO STRICT q FROM public.ew_compras_cotacoes WHERE empresa_id=p_empresa_id AND id=(r->>'id')::uuid FOR UPDATE;
 IF coalesce((r->>'repetida')::boolean,false) THEN
  IF q.condicoes_comerciais IS DISTINCT FROM c THEN RAISE EXCEPTION 'Identificador já utilizado com outras condições.';END IF;
 ELSE
  UPDATE public.ew_compras_cotacoes SET condicoes_comerciais=c WHERE empresa_id=p_empresa_id AND id=q.id;
 END IF;
 RETURN r||jsonb_build_object('condicoes_comerciais',c);
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_compras_cotar_com_condicoes(uuid,uuid,uuid,jsonb,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_compras_cotar_com_condicoes(uuid,uuid,uuid,jsonb,uuid,jsonb) TO authenticated;
COMMIT;
