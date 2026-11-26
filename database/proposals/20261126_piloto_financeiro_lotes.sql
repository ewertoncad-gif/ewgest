-- Piloto de leitura: mantém pendências existentes até a cobertura operacional completa.
-- Não soma ajuste ao realizado fiscal; o cliente exibe ambos separadamente.
CREATE OR REPLACE FUNCTION public.ew_compras_compromissos_obra(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Sem acesso financeiro à obra.';END IF;
 RETURN (WITH notas AS MATERIALIZED (SELECT * FROM ew_compras_interna.notas_estado(p_empresa_id,p_obra_id)), linhas AS (
 SELECT p.id pedido_id,x->>'chave' chave,CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END categoria,
 (x->>'quantidade')::numeric qtd,(x->>'preco_unitario_centavos')::bigint preco
 FROM public.ew_compras_pedidos p CROSS JOIN LATERAL jsonb_array_elements(p.itens) x
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x->>'variacao_id')::uuid AND v.empresa_id=p.empresa_id
 WHERE p.empresa_id=p_empresa_id AND p.obra_id=p_obra_id AND p.status<>'CANCELADO'
 ), conciliado AS (
 SELECT c.pedido_id,v.chave,sum(v.quantidade_fisica) qtd
 FROM public.ew_compras_nfe_conciliacoes c JOIN public.ew_compras_nfe_vinculos v ON v.conciliacao_id=c.id AND v.desvinculado_em IS NULL
 JOIN notas d ON d.despesa_id=c.despesa_id AND NOT d.pendente
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 WHERE c.empresa_id=p_empresa_id AND c.desvinculado_em IS NULL GROUP BY c.pedido_id,v.chave
 ), compromissos AS (
 SELECT l.categoria,sum(round(l.qtd*l.preco)) total_pedido_centavos,
 sum(round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) conciliado_centavos,
 sum(round(l.qtd*l.preco)-round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) pendente_centavos
 FROM linhas l LEFT JOIN conciliado c ON c.pedido_id=l.pedido_id AND c.chave=l.chave GROUP BY l.categoria
 ), despesas AS (
 SELECT categoria,coalesce(sum(valor_centavos) FILTER(WHERE NOT pendente),0) realizado_centavos,
 coalesce(sum(valor_centavos) FILTER(WHERE pendente),0) pendencia_centavos,
 coalesce(jsonb_agg(jsonb_build_object('id',despesa_id,'fornecedor',fornecedor,'numero_documento',numero_documento,'valor_centavos',valor_centavos,'assinatura',assinatura) ORDER BY despesa_id) FILTER(WHERE pendente),'[]'::jsonb) notas_pendentes FROM notas GROUP BY categoria
 ), transferencias AS MATERIALIZED (
 SELECT categoria,count(*) n FROM ew_compras_interna.transferencias_custo_pendentes(p_empresa_id,p_obra_id) GROUP BY categoria
 ), ajustes AS MATERIALIZED (
 SELECT categoria,ajuste_centavos FROM ew_compras_interna.custo_transferencias_ajustes_financeiros WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id
 ), categorias AS (SELECT categoria FROM compromissos UNION SELECT categoria FROM despesas UNION SELECT categoria FROM transferencias UNION SELECT categoria FROM ajustes)
 SELECT coalesce(jsonb_agg(jsonb_build_object('categoria',k.categoria,'pedido_centavos',coalesce(c.total_pedido_centavos,0),'conciliado_centavos',coalesce(c.conciliado_centavos,0),'comprometido_pendente_centavos',coalesce(c.pendente_centavos,0),'realizado_centavos',coalesce(d.realizado_centavos,0),'ajuste_transferencias_centavos',coalesce(a.ajuste_centavos,0),'transferencias_custo_pendentes',coalesce(t.n,0),'consumido_centavos',CASE WHEN coalesce(t.n,0)>0 OR coalesce(d.pendencia_centavos,0)>0 THEN NULL ELSE coalesce(c.pendente_centavos,0)+coalesce(d.realizado_centavos,0)+coalesce(a.ajuste_centavos,0) END,'pendencia_centavos',coalesce(d.pendencia_centavos,0),'notas_pendentes',coalesce(d.notas_pendentes,'[]'::jsonb)) ORDER BY k.categoria),'[]'::jsonb)
 FROM categorias k LEFT JOIN compromissos c USING(categoria) LEFT JOIN despesas d USING(categoria) LEFT JOIN transferencias t USING(categoria) LEFT JOIN ajustes a USING(categoria));
END;$function$;