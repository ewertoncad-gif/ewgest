-- Reconciliação prévia da base fiscal para futura capitalização do frete.
BEGIN;
CREATE FUNCTION public.ew_fin_frete_previa_fiscal(p_empresa_id uuid,p_vinculo_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE f ew_financeiro_interna.fretes_pedidos%ROWTYPE;p public.ew_compras_pedidos%ROWTYPE;t ew_financeiro_interna.titulos%ROWTYPE;
 v jsonb;n int;validos int;total numeric;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.consultar') THEN RAISE EXCEPTION 'Sem acesso a compras.';END IF;
 SELECT * INTO f FROM ew_financeiro_interna.fretes_pedidos WHERE empresa_id=p_empresa_id AND operacao_id=p_vinculo_id AND estornado_em IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Vínculo indisponível.';END IF;
 SELECT * INTO p FROM public.ew_compras_pedidos WHERE empresa_id=p_empresa_id AND id=f.pedido_id AND cancelado_em IS NULL AND status='CONCLUIDO';
 IF NOT FOUND THEN RAISE EXCEPTION 'Aguarde o recebimento integral do pedido.';END IF;
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=f.titulo_id AND tipo='PAGAR' AND origem_tipo='MANUAL' AND cancelado_em IS NULL AND lower(btrim(categoria))='frete' AND valor_centavos>0;
 IF NOT FOUND THEN RAISE EXCEPTION 'Título de frete indisponível.';END IF;
 IF jsonb_typeof(p.itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p.itens)=0 THEN RAISE EXCEPTION 'Pedido sem itens conciliáveis.';END IF;
 IF EXISTS(
 WITH ped AS (SELECT chave,quantidade FROM jsonb_to_recordset(p.itens) z(chave text,quantidade numeric)),
 rec AS (SELECT z.chave,sum(z.quantidade) quantidade FROM public.ew_compras_recebimentos r CROSS JOIN LATERAL jsonb_to_recordset(r.itens) z(chave text,quantidade numeric) WHERE r.empresa_id=p_empresa_id AND r.pedido_id=p.id AND r.estornado_em IS NULL GROUP BY z.chave)
 SELECT 1 FROM ped FULL JOIN rec USING(chave) WHERE ped.chave IS NULL OR rec.chave IS NULL OR ped.quantidade IS DISTINCT FROM rec.quantidade OR ped.quantidade<=0
 ) THEN RAISE EXCEPTION 'Quantidades recebidas divergentes.';END IF;
 WITH recebidos AS MATERIALIZED(
 SELECT r.id recebimento_id,i.chave,i.quantidade,coalesce(x.movimento_obra_id,x.movimento_empresa_id) movimento_id
 FROM public.ew_compras_recebimentos r CROSS JOIN LATERAL jsonb_to_recordset(r.itens) i(chave text,quantidade numeric)
 LEFT JOIN public.ew_compras_recebimentos_movimentos x ON x.empresa_id=r.empresa_id AND x.recebimento_id=r.id AND x.chave=i.chave
 WHERE r.empresa_id=p_empresa_id AND r.pedido_id=p.id AND r.estornado_em IS NULL
 ), evidencias AS (
 SELECT r.*,e.item_fiscal_id,e.fonte,e.custo_centavos,l.lote_id,
 count(*) OVER(PARTITION BY r.recebimento_id,r.chave) repeticoes
 FROM recebidos r LEFT JOIN ew_compras_interna.lotes_aquisicao_evidencias e ON e.empresa_id=p_empresa_id AND e.recebimento_id=r.recebimento_id AND e.movimento_id=r.movimento_id AND e.quantidade=r.quantidade AND e.fonte IN ('PEDIDO_OBRA','PEDIDO_EMPRESA')
 LEFT JOIN ew_compras_interna.custo_lotes l ON l.empresa_id=e.empresa_id AND l.fonte=e.fonte AND l.item_fiscal_id=e.item_fiscal_id AND l.movimento_id=e.movimento_id AND l.quantidade=e.quantidade AND l.custo_centavos=e.custo_centavos AND l.cancelado_em IS NULL
 ), aprovados AS (
 SELECT * FROM evidencias WHERE repeticoes=1 AND lote_id IS NOT NULL AND custo_centavos>=0
 ), partes AS (
 SELECT *,div(t.valor_centavos::numeric*custo_centavos,sum(custo_centavos) OVER()) base,mod(t.valor_centavos::numeric*custo_centavos,sum(custo_centavos) OVER()) resto
 FROM aprovados WHERE (SELECT coalesce(sum(custo_centavos),0) FROM aprovados)>0
 ), ord AS (
 SELECT *,sum(base) OVER() soma,row_number() OVER(ORDER BY resto DESC,lote_id) pos FROM partes
 )
 SELECT (SELECT count(*) FROM recebidos),(SELECT count(DISTINCT lote_id) FROM aprovados),(SELECT sum(custo_centavos) FROM aprovados),
 (SELECT jsonb_agg(jsonb_build_object('lote_id',lote_id,'chave',chave,'material_centavos',custo_centavos,'quantidade',quantidade,'frete_centavos',base+CASE WHEN pos<=t.valor_centavos-soma THEN 1 ELSE 0 END) ORDER BY lote_id) FROM ord)
 INTO n,validos,total,v;
 IF n=0 OR n<>validos OR coalesce(total,0)<=0 OR jsonb_array_length(v) IS DISTINCT FROM n THEN RAISE EXCEPTION 'Existem recebimentos sem lote fiscal ativo e conciliado.';END IF;
 RETURN jsonb_build_object('numero',p.numero,'material_centavos',total,'frete_centavos',t.valor_centavos,'itens',v,'consultivo',true);
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_fin_frete_previa_fiscal(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_fin_frete_previa_fiscal(uuid,uuid) TO authenticated;
COMMIT;
