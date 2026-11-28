-- Vínculo de frete externo já programado e previsão de pagamentos documentais.
BEGIN;
CREATE TABLE ew_financeiro_interna.fretes_pedidos (
 empresa_id uuid NOT NULL,titulo_id uuid NOT NULL,pedido_id uuid NOT NULL,
 operacao_id uuid NOT NULL,justificativa text NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,titulo_id),UNIQUE(empresa_id,operacao_id)
);
ALTER TABLE ew_financeiro_interna.fretes_pedidos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.fretes_pedidos FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_fin_vincular_frete(p_empresa_id uuid,p_titulo_id uuid,p_pedido_id uuid,p_operacao_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE;v ew_financeiro_interna.fretes_pedidos%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id,'PAGAR');
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') OR NOT public.ew_pode(p_empresa_id,'compras.consultar') THEN RAISE EXCEPTION 'Sem acesso aos dados de compras.';END IF;
 IF p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Informe justificativa válida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FRETE|'||p_operacao_id::text,0));
 SELECT * INTO v FROM ew_financeiro_interna.fretes_pedidos WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF v.titulo_id<>p_titulo_id OR v.pedido_id<>p_pedido_id OR v.justificativa<>btrim(p_motivo) THEN RAISE EXCEPTION 'Identificador já utilizado com outros dados.';END IF;
  RETURN jsonb_build_object('repetido',true,'titulo_id',v.titulo_id);
 END IF;
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=p_titulo_id FOR UPDATE;
 IF NOT FOUND OR t.tipo<>'PAGAR' OR t.origem_tipo<>'MANUAL' OR t.cancelado_em IS NOT NULL OR lower(btrim(t.categoria))<>'frete' OR nullif(btrim(t.numero_documento),'') IS NULL THEN RAISE EXCEPTION 'Escolha título manual ativo da categoria Frete, com documento identificado.';END IF;
 PERFORM 1 FROM public.ew_compras_pedidos WHERE empresa_id=p_empresa_id AND id=p_pedido_id AND cancelado_em IS NULL AND status<>'CANCELADO' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pedido indisponível.';END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.fretes_pedidos WHERE empresa_id=p_empresa_id AND titulo_id=p_titulo_id) THEN RAISE EXCEPTION 'Título de frete já vinculado.';END IF;
 INSERT INTO ew_financeiro_interna.fretes_pedidos(empresa_id,titulo_id,pedido_id,operacao_id,justificativa,criado_por) VALUES(p_empresa_id,p_titulo_id,p_pedido_id,p_operacao_id,btrim(p_motivo),auth.uid());
 RETURN jsonb_build_object('repetido',false,'titulo_id',p_titulo_id);
END $$;
CREATE FUNCTION public.ew_fin_compras_previsao(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id);
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') OR NOT public.ew_pode(p_empresa_id,'compras.consultar') THEN RAISE EXCEPTION 'Sem acesso aos dados de compras.';END IF;
 WITH pedidos AS MATERIALIZED (
 SELECT p.id,p.numero,p.cancelado_em,p.status FROM public.ew_compras_pedidos p WHERE p.empresa_id=p_empresa_id
 ), vinculos AS (
 SELECT 'DESPESA_OBRA'::text origem_tipo,c.despesa_id origem_id,c.pedido_id FROM public.ew_compras_nfe_conciliacoes c WHERE c.empresa_id=p_empresa_id AND c.desvinculado_em IS NULL
 UNION SELECT 'NOTA_ESTOQUE',n.id,n.pedido_id FROM public.ew_compras_notas_empresa n WHERE n.empresa_id=p_empresa_id AND n.pedido_id IS NOT NULL
 ), docs AS (
 SELECT v.origem_tipo,v.origem_id,array_agg(DISTINCT p.numero ORDER BY p.numero) pedidos,bool_and(p.cancelado_em IS NULL AND p.status<>'CANCELADO') pedidos_ativos
 FROM vinculos v JOIN pedidos p ON p.id=v.pedido_id GROUP BY v.origem_tipo,v.origem_id
 ), base AS (
 SELECT d.origem_tipo,d.origem_id,d.pedidos,d.pedidos_ativos,o.numero_documento,o.contraparte,o.valor_centavos,o.valido,t.id titulo_id,t.vencimento,t.valor_centavos titulo_valor,t.cancelado_em titulo_cancelado,
 coalesce(b.pago,0)::bigint pago,'DOCUMENTO_COMPRA'::text natureza
 FROM docs d LEFT JOIN ew_financeiro_interna.documentos_origem o ON o.empresa_id=p_empresa_id AND o.origem_tipo=d.origem_tipo AND o.origem_id=d.origem_id
 LEFT JOIN ew_financeiro_interna.titulos t ON t.empresa_id=p_empresa_id AND t.origem_tipo=d.origem_tipo AND t.origem_id=d.origem_id AND t.tipo='PAGAR' AND t.cancelado_em IS NULL
 LEFT JOIN LATERAL(SELECT sum(valor_centavos) pago FROM ew_financeiro_interna.baixas b WHERE b.empresa_id=p_empresa_id AND b.titulo_id=t.id AND b.estornado_em IS NULL)b ON true
 UNION ALL
 SELECT 'MANUAL',t.id,ARRAY[p.numero],p.cancelado_em IS NULL AND p.status<>'CANCELADO',t.numero_documento,t.contraparte,t.valor_centavos,
 t.tipo='PAGAR' AND t.origem_tipo='MANUAL' AND lower(btrim(t.categoria))='frete',t.id,t.vencimento,t.valor_centavos,t.cancelado_em,coalesce(b.pago,0)::bigint,'FRETE_EXTERNO'
 FROM ew_financeiro_interna.fretes_pedidos f JOIN ew_financeiro_interna.titulos t ON t.empresa_id=f.empresa_id AND t.id=f.titulo_id JOIN pedidos p ON p.id=f.pedido_id
 LEFT JOIN LATERAL(SELECT sum(valor_centavos) pago FROM ew_financeiro_interna.baixas b WHERE b.empresa_id=p_empresa_id AND b.titulo_id=t.id AND b.estornado_em IS NULL)b ON true
 WHERE f.empresa_id=p_empresa_id
 ), linhas AS (
 SELECT *,CASE WHEN NOT coalesce(valido,false) OR NOT coalesce(pedidos_ativos,false) OR titulo_cancelado IS NOT NULL OR coalesce(valor_centavos,0)<=0 THEN 'CONFERIR_ORIGEM'
 WHEN titulo_id IS NULL THEN 'SEM_PROGRAMACAO'
 WHEN titulo_valor IS DISTINCT FROM valor_centavos OR pago<0 OR pago>titulo_valor OR vencimento IS NULL THEN 'CONFERIR_TITULO'
 ELSE 'PROGRAMADO' END situacao FROM base
 ), pos AS (
 SELECT natureza,origem_tipo,origem_id,pedidos,numero_documento,contraparte,valor_centavos,titulo_id,vencimento,situacao,CASE WHEN situacao='PROGRAMADO' THEN titulo_valor-pago ELSE NULL END saldo_centavos FROM linhas
 )
 SELECT jsonb_build_object('saldo_programado_centavos',coalesce(sum(saldo_centavos),0),'sem_programacao_centavos',coalesce(sum(valor_centavos) FILTER(WHERE situacao='SEM_PROGRAMACAO'),0),'pendencias',count(*) FILTER(WHERE situacao NOT IN ('PROGRAMADO','SEM_PROGRAMACAO')),'total',count(*),'linhas',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.vencimento NULLS LAST,l.origem_id) FROM (SELECT * FROM pos ORDER BY vencimento NULLS LAST,origem_id LIMIT 500)l),'[]'::jsonb),
 'pedidos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'numero',numero) ORDER BY numero) FROM pedidos WHERE cancelado_em IS NULL AND status<>'CANCELADO'),'[]'::jsonb),
 'fretes_disponiveis',coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'descricao',t.descricao,'numero_documento',t.numero_documento,'valor_centavos',t.valor_centavos) ORDER BY t.vencimento,t.id) FROM ew_financeiro_interna.titulos t WHERE t.empresa_id=p_empresa_id AND t.tipo='PAGAR' AND t.origem_tipo='MANUAL' AND t.cancelado_em IS NULL AND lower(btrim(t.categoria))='frete' AND nullif(btrim(t.numero_documento),'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.fretes_pedidos f WHERE f.empresa_id=t.empresa_id AND f.titulo_id=t.id)),'[]'::jsonb)) INTO r FROM pos;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_fin_vincular_frete(uuid,uuid,uuid,uuid,text),public.ew_fin_compras_previsao(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_fin_vincular_frete(uuid,uuid,uuid,uuid,text),public.ew_fin_compras_previsao(uuid) TO authenticated;
COMMIT;
