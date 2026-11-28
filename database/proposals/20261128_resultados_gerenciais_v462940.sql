-- Relatório gerencial de competência e rastreabilidade; não é DRE contábil final.
BEGIN;
CREATE FUNCTION public.ew_resultados_gerenciais(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_result jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT public.ew_pode(p_empresa_id,'relatorios.financeiros') OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') OR NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'Sem permissão para resultados gerenciais.';END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Selecione período de até 367 dias.';END IF;
 WITH docs AS MATERIALIZED (
 SELECT f.* ,round(f.valor_total*100)::bigint cents
 FROM public.ew_obra_faturamentos f WHERE f.empresa_id=p_empresa_id AND f.status='emitido' AND f.cancelado_em IS NULL AND f.data_faturamento BETWEEN p_inicio AND p_fim
), linhas AS MATERIALIZED (
 SELECT d.id doc_id,d.obra_id,d.categoria,d.data_faturamento,d.criado_em,i.esquadria_id,round(i.valor_total*100)::bigint cents,
  e.id item_ok,coalesce(i.area_m2,i.quantidade*e.largura_mm*e.altura_mm/1000000) area
 FROM docs d JOIN public.ew_obra_faturamentos_itens i ON i.empresa_id=d.empresa_id AND i.faturamento_id=d.id
 LEFT JOIN public.esquadrias e ON e.empresa_id=d.empresa_id AND e.obra_id=d.obra_id AND e.id=i.esquadria_id
), docs_ok AS (
 SELECT d.id FROM docs d JOIN linhas l ON l.doc_id=d.id GROUP BY d.id,d.cents
 HAVING sum(l.cents)=d.cents AND bool_and(l.item_ok IS NOT NULL AND l.cents>0 AND coalesce(l.area,0)>0)
), atrib AS (
 SELECT l.obra_id,l.esquadria_id,l.cents,l.area,
  CASE WHEN a.n>0 AND a.n=a.n_nome AND a.n=a.n_area AND a.n_fabricas=1 AND a.area>=h.area AND h.area>0 THEN a.fabrica ELSE NULL END fabrica
 FROM linhas l JOIN docs_ok k ON k.id=l.doc_id
 LEFT JOIN LATERAL (
  SELECT count(*) n,count(nullif(btrim(ri.fabrica),'')) n_nome,count(DISTINCT nullif(btrim(ri.fabrica),'')) n_fabricas,count(*) FILTER(WHERE ri.area_m2>0) n_area,
   min(nullif(btrim(ri.fabrica),'')) fabrica,coalesce(sum(ri.area_m2),0) area
  FROM public.romaneios r JOIN public.romaneios_itens ri ON ri.romaneio_id=r.id AND ri.natureza='esquadria'
  WHERE r.empresa_id=p_empresa_id AND r.obra_id=l.obra_id AND r.status='emitido' AND r.cancelado_em IS NULL
   AND r.data_saida<=l.data_faturamento AND r.criado_em<=l.criado_em AND ri.esquadria_id=l.esquadria_id
 ) a ON true
 LEFT JOIN LATERAL (
  SELECT coalesce(sum(coalesce(i.area_m2,i.quantidade*e.largura_mm*e.altura_mm/1000000)),0) area
  FROM public.ew_obra_faturamentos f JOIN public.ew_obra_faturamentos_itens i ON i.empresa_id=f.empresa_id AND i.faturamento_id=f.id
  JOIN public.esquadrias e ON e.empresa_id=f.empresa_id AND e.obra_id=f.obra_id AND e.id=i.esquadria_id
  WHERE f.empresa_id=p_empresa_id AND f.obra_id=l.obra_id AND f.categoria=l.categoria AND f.status='emitido' AND f.cancelado_em IS NULL
   AND (f.criado_em,f.id)<=(l.criado_em,l.doc_id) AND i.esquadria_id=l.esquadria_id
 ) h ON true
 WHERE l.categoria='fabricacao'
), receita AS (
 SELECT obra_id,fabrica,sum(cents)::bigint valor_centavos,count(*) linhas FROM atrib GROUP BY obra_id,fabrica
 UNION ALL SELECT d.obra_id,NULL,sum(d.cents)::bigint,count(*) FROM docs d WHERE d.categoria='fabricacao' AND NOT EXISTS(SELECT 1 FROM docs_ok k WHERE k.id=d.id) GROUP BY d.obra_id
), exped AS (
 SELECT r.obra_id,nullif(btrim(i.fabrica),'') fabrica,sum(i.area_m2) FILTER(WHERE i.area_m2>0) area_m2,count(*) FILTER(WHERE i.area_m2 IS NULL OR i.area_m2<=0) pendencias
 FROM public.romaneios r JOIN public.romaneios_itens i ON i.romaneio_id=r.id AND i.natureza='esquadria'
 WHERE r.empresa_id=p_empresa_id AND r.status='emitido' AND r.cancelado_em IS NULL AND r.data_saida BETWEEN p_inicio AND p_fim
 GROUP BY r.obra_id,nullif(btrim(i.fabrica),'')
), movimentos AS MATERIALIZED (
 SELECT m.*, -m.quantidade_delta-coalesce(z.qtd,0) qtd_liquida,
  CASE WHEN m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND e.id IS NOT NULL THEN e.id ELSE NULL END esquadria_id,
  CASE WHEN m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND e.id IS NOT NULL AND l.cancelado_em IS NULL THEN nullif(btrim(l.fabrica),'')
       WHEN m.origem='PLANO_CORTE_LOTE' AND b.id IS NOT NULL AND b.cancelado_em IS NULL THEN nullif(btrim(b.fabrica),'') ELSE NULL END fabrica
 FROM public.ew_estoque_obras_movimentos m
 LEFT JOIN public.liberacoes_corte l ON l.id=m.liberacao_id
 LEFT JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=m.empresa_id AND e.obra_id=m.obra_id
 LEFT JOIN public.ew_liberacoes_lotes b ON b.id=m.lote_id AND b.empresa_id=m.empresa_id AND b.obra_id=m.obra_id
 LEFT JOIN LATERAL (
  SELECT coalesce(sum(x.quantidade_delta),0) qtd FROM public.ew_estoque_obras_movimentos x
  WHERE x.empresa_id=m.empresa_id AND x.obra_id=m.obra_id AND x.origem='ESTORNO' AND x.quantidade_delta>0
   AND (x.estorno_de_id=m.id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=m.empresa_id AND ep.movimento_original_id=m.id AND ep.movimento_estorno_id=x.id AND ep.quantidade=abs(x.quantidade_delta)))
 ) z ON true
 WHERE m.empresa_id=p_empresa_id AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND m.quantidade_delta<0
 AND (m.criado_em AT TIME ZONE 'America/Recife')::date BETWEEN p_inicio AND p_fim
), consumos AS MATERIALIZED (
 SELECT m.obra_id,m.esquadria_id,m.fabrica,m.id,
  CASE WHEN m.qtd_liquida>0 AND m.qtd_liquida=-m.quantidade_delta AND c.quantidade=m.qtd_liquida AND c.estornado_em IS NULL AND a.qtd=c.quantidade AND a.valido THEN a.cents ELSE NULL END valor_centavos
 FROM movimentos m LEFT JOIN ew_compras_interna.custo_consumos_integrados c ON c.empresa_id=m.empresa_id AND c.movimento_id=m.id
 LEFT JOIN LATERAL (
  SELECT sum(ev.quantidade) qtd,sum(ev.custo_centavos)::bigint cents,
   bool_and(ev.destino_tipo='PRODUCAO' AND ev.destino_id=m.obra_id AND ev.destino_galpao=m.local_estoque AND EXISTS(
    SELECT 1 FROM ew_compras_interna.custo_lotes lo JOIN ew_compras_interna.lotes_aquisicao_evidencias v ON v.empresa_id=lo.empresa_id AND v.fonte=lo.fonte AND v.item_fiscal_id=lo.item_fiscal_id AND v.movimento_id=lo.movimento_id AND v.quantidade=lo.quantidade AND v.custo_centavos=lo.custo_centavos AND v.categoria=lo.categoria
    WHERE lo.empresa_id=ev.empresa_id AND lo.lote_id=ev.lote_id AND lo.cancelado_em IS NULL)) valido
  FROM ew_compras_interna.custo_eventos ev WHERE ev.empresa_id=m.empresa_id AND ev.operacao_id=c.operacao_custo AND ev.estornado_em IS NULL
 ) a ON true
 WHERE m.qtd_liquida<>0
), custos AS (
 SELECT obra_id,fabrica,coalesce(sum(valor_centavos),0)::bigint custo_centavos,count(*) FILTER(WHERE valor_centavos IS NULL) pendencias,count(*) n
 FROM consumos GROUP BY obra_id,fabrica
), por_fabrica AS (
 SELECT fabrica, sum(receita)::bigint faturamento_centavos,sum(area) area_expedida_m2,sum(custo)::bigint material_centavos,sum(pend)::bigint consumos_pendentes,sum(n)::bigint consumos,sum(area_pend)::bigint areas_pendentes
 FROM (SELECT fabrica,valor_centavos receita,0::numeric area,0::bigint custo,0::bigint pend,0::bigint n,0::bigint area_pend FROM receita
 UNION ALL SELECT fabrica,0,coalesce(area_m2,0),0,0,0,pendencias FROM exped
 UNION ALL SELECT fabrica,0,0,custo_centavos,pendencias,n,0 FROM custos) x GROUP BY fabrica
), por_obra AS (
 SELECT x.obra_id,o.nome,o.codigo,sum(receita)::bigint faturamento_centavos,sum(custo)::bigint material_centavos,sum(pend)::bigint consumos_pendentes,sum(n)::bigint consumos
 FROM (SELECT obra_id,cents receita,0::bigint custo,0::bigint pend,0::bigint n FROM docs
 UNION ALL SELECT obra_id,0,custo_centavos,pendencias,n FROM custos) x
 JOIN public.obras o ON o.empresa_id=p_empresa_id AND o.id=x.obra_id GROUP BY x.obra_id,o.nome,o.codigo
), por_item AS (
 SELECT c.obra_id,c.esquadria_id,o.nome obra,e.codigo,coalesce(sum(c.valor_centavos),0)::bigint material_centavos,count(*) FILTER(WHERE c.valor_centavos IS NULL) pendencias,count(*) n
 FROM consumos c JOIN public.obras o ON o.empresa_id=p_empresa_id AND o.id=c.obra_id
 LEFT JOIN public.esquadrias e ON e.empresa_id=p_empresa_id AND e.obra_id=c.obra_id AND e.id=c.esquadria_id
 GROUP BY c.obra_id,c.esquadria_id,o.nome,e.codigo
), manuais AS (
 SELECT tipo,categoria,centro_custo,sum(valor_centavos)::bigint valor_centavos FROM ew_financeiro_interna.titulos
 WHERE empresa_id=p_empresa_id AND origem_tipo='MANUAL' AND cancelado_em IS NULL AND competencia BETWEEN p_inicio AND p_fim
 GROUP BY tipo,categoria,centro_custo
)
SELECT jsonb_build_object(
 'fabricacao_centavos',coalesce((SELECT sum(cents) FROM docs WHERE categoria='fabricacao'),0),
 'instalacao_centavos',coalesce((SELECT sum(cents) FROM docs WHERE categoria='instalacao'),0),
 'material_centavos',coalesce((SELECT sum(valor_centavos) FROM consumos),0),
 'consumos_pendentes',(SELECT count(*) FROM consumos WHERE valor_centavos IS NULL),
 'consumos',(SELECT count(*) FROM consumos),
 'material_sem_item_centavos',coalesce((SELECT sum(valor_centavos) FROM consumos WHERE esquadria_id IS NULL),0),
 'manuais_pagar_centavos',coalesce((SELECT sum(valor_centavos) FROM manuais WHERE tipo='PAGAR'),0),
 'manuais_receber_centavos',coalesce((SELECT sum(valor_centavos) FROM manuais WHERE tipo='RECEBER'),0),
 'fabrica',coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.fabrica NULLS LAST) FROM por_fabrica f),'[]'::jsonb),
 'obras',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.nome,o.obra_id) FROM por_obra o),'[]'::jsonb),
 'itens_total',(SELECT count(*) FROM por_item),
 'itens',coalesce((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.obra,i.codigo NULLS LAST) FROM (SELECT * FROM por_item ORDER BY obra,codigo NULLS LAST,obra_id,esquadria_id LIMIT 500)i),'[]'::jsonb),
 'manuais',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.tipo,m.categoria,m.centro_custo) FROM manuais m),'[]'::jsonb)) INTO v_result;
 RETURN v_result;
END;$function$;
REVOKE EXECUTE ON FUNCTION public.ew_resultados_gerenciais(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_resultados_gerenciais(uuid,date,date) TO authenticated;
COMMIT;
