BEGIN;
CREATE TABLE ew_compras_interna.convites(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,
 solicitacao_id uuid NOT NULL REFERENCES public.ew_compras_solicitacoes(id) ON DELETE CASCADE,
 fornecedor_id uuid NOT NULL REFERENCES public.ew_fornecedores(id),
 criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(solicitacao_id,fornecedor_id)
);
ALTER TABLE ew_compras_interna.convites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.convites FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_compras_replicar_cotacao(p_empresa_id uuid,p_solicitacao_id uuid,p_fornecedores uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE ids uuid[]; n int;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'compras.replicar_cotacao') AND public.ew_pode(p_empresa_id,'compras.cotar') AND public.ew_pode(p_empresa_id,'compras.consultar_valores')) THEN RAISE EXCEPTION 'Sem permissão para replicar cotações.';END IF;
 IF p_fornecedores IS NULL OR cardinality(p_fornecedores) NOT BETWEEN 1 AND 50 OR array_position(p_fornecedores,NULL) IS NOT NULL THEN RAISE EXCEPTION 'Selecione de 1 a 50 fornecedores.';END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_fornecedores) x;
 IF cardinality(ids)<>cardinality(p_fornecedores) THEN RAISE EXCEPTION 'Fornecedor repetido.';END IF;
 PERFORM 1 FROM public.ew_compras_solicitacoes s WHERE s.id=p_solicitacao_id AND s.empresa_id=p_empresa_id AND s.status='ABERTA' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitação indisponível.';END IF;
 SELECT count(*) INTO n FROM public.ew_fornecedores WHERE id=ANY(ids) AND empresa_id=p_empresa_id AND ativo;
 IF n<>cardinality(ids) THEN RAISE EXCEPTION 'Fornecedor indisponível ou de outra empresa.';END IF;
 INSERT INTO ew_compras_interna.convites(empresa_id,solicitacao_id,fornecedor_id,criado_por)
 SELECT p_empresa_id,p_solicitacao_id,x,auth.uid() FROM unnest(ids) x ON CONFLICT(solicitacao_id,fornecedor_id) DO NOTHING;
 RETURN jsonb_build_object('solicitacao_id',p_solicitacao_id,'fornecedores',cardinality(ids));
END;$f$;
CREATE FUNCTION public.ew_compras_convites_cotacao(p_empresa_id uuid,p_solicitacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'compras.cotar') AND public.ew_pode(p_empresa_id,'compras.consultar_valores')) THEN RAISE EXCEPTION 'Sem permissão para consultar convites.';END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.fornecedor,a.id),'[]'::jsonb) FROM (
 SELECT c.id,c.solicitacao_id,c.fornecedor_id,f.nome fornecedor,c.criado_em,f.ativo,
 CASE WHEN s.status<>'ABERTA' THEN 'ENCERRADA' WHEN EXISTS(SELECT 1 FROM public.ew_compras_cotacoes q WHERE q.empresa_id=c.empresa_id AND q.solicitacao_id=c.solicitacao_id AND q.fornecedor_id=c.fornecedor_id AND q.status='ABERTA') THEN 'RESPONDIDA' ELSE 'AGUARDANDO_RETORNO' END status
 FROM ew_compras_interna.convites c JOIN public.ew_compras_solicitacoes s ON s.id=c.solicitacao_id AND s.empresa_id=c.empresa_id
 JOIN public.ew_fornecedores f ON f.id=c.fornecedor_id AND f.empresa_id=c.empresa_id
 WHERE c.empresa_id=p_empresa_id AND c.solicitacao_id=p_solicitacao_id) a);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_compras_replicar_cotacao(uuid,uuid,uuid[]),public.ew_compras_convites_cotacao(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_replicar_cotacao(uuid,uuid,uuid[]),public.ew_compras_convites_cotacao(uuid,uuid) TO authenticated;
COMMIT;
