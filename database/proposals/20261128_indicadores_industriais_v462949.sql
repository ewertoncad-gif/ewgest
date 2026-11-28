-- Indicadores consultivos: área faturada atribuída, contribuição e peso de consumo.
BEGIN;
CREATE FUNCTION public.ew_indicadores_industriais(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE resultado jsonb; financeiro jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT public.ew_pode(p_empresa_id,'relatorios.financeiros') OR NOT public.ew_pode(p_empresa_id,'compras.consultar_valores') OR NOT public.ew_pode(p_empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'Sem permissão para indicadores industriais.';END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Selecione período de até 367 dias.';END IF;
 financeiro:=public.ew_rateio_industrial_consultar(p_empresa_id,p_inicio,p_fim);
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

 ), areas AS (
 SELECT fabrica,sum(area) area_m2,sum(cents)::bigint receita FROM atrib GROUP BY fabrica
 ), movimentos AS MATERIALIZED (
 SELECT m.id,m.liberacao_id,m.lote_id,m.unidade,m.comprimento_mm,p.peso_kg_m,
 CASE WHEN m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND e.id IS NOT NULL AND l.cancelado_em IS NULL THEN nullif(btrim(l.fabrica),'')
 WHEN m.origem='PLANO_CORTE_LOTE' AND b.id IS NOT NULL AND b.cancelado_em IS NULL THEN nullif(btrim(b.fabrica),'') ELSE NULL END fabrica,
 -m.quantidade_delta-coalesce(z.qtd,0) qtd
 FROM public.ew_estoque_obras_movimentos m
 JOIN public.ew_materiais_variacoes v ON v.empresa_id=m.empresa_id AND v.id=m.variacao_id AND v.tipo='perfil'
 LEFT JOIN public.ew_perfis p ON p.empresa_id=v.empresa_id AND p.id=v.perfil_id
 LEFT JOIN public.liberacoes_corte l ON l.id=m.liberacao_id
 LEFT JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=m.empresa_id AND e.obra_id=m.obra_id
 LEFT JOIN public.ew_liberacoes_lotes b ON b.id=m.lote_id AND b.empresa_id=m.empresa_id AND b.obra_id=m.obra_id
 LEFT JOIN LATERAL (
 SELECT sum(CASE WHEN ep.qtd IS NOT NULL THEN ep.qtd ELSE x.quantidade_delta END) qtd
 FROM public.ew_estoque_obras_movimentos x
 LEFT JOIN LATERAL(SELECT sum(p.quantidade) qtd FROM public.ew_estornos_parcelas p WHERE p.empresa_id=m.empresa_id AND p.movimento_original_id=m.id AND p.movimento_estorno_id=x.id) ep ON true
 WHERE x.empresa_id=m.empresa_id AND x.obra_id=m.obra_id AND x.origem='ESTORNO' AND x.quantidade_delta>0 AND (x.estorno_de_id=m.id OR ep.qtd IS NOT NULL)
 ) z ON true
 WHERE m.empresa_id=p_empresa_id AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND m.quantidade_delta<0 AND (m.criado_em AT TIME ZONE 'America/Recife')::date BETWEEN p_inicio AND p_fim
 ), pesos AS (
 SELECT *, CASE WHEN qtd>0 AND unidade='KG' THEN qtd WHEN qtd>0 AND unidade='BARRA' AND comprimento_mm>0 AND peso_kg_m>0 THEN qtd*comprimento_mm*peso_kg_m/1000 WHEN qtd>0 AND unidade IN ('M','MT') AND peso_kg_m>0 THEN qtd*peso_kg_m ELSE NULL END kg
 FROM movimentos WHERE qtd<>0
 ), por_fabrica AS (
 SELECT fabrica,coalesce(sum(kg) FILTER(WHERE unidade='KG'),0) kg_registrado,
 coalesce(sum(kg) FILTER(WHERE unidade<>'KG'),0) kg_estimado,
 count(*) FILTER(WHERE kg IS NULL) peso_pendente,count(*) FILTER(WHERE kg IS NOT NULL) peso_com_base
 FROM pesos GROUP BY fabrica
 ), fin AS (
 SELECT * FROM jsonb_to_recordset(financeiro->'fabrica') x(fabrica text,receita_centavos bigint,material_centavos bigint,rateio_centavos bigint)
 ), chaves AS (SELECT fabrica FROM areas UNION SELECT fabrica FROM por_fabrica UNION SELECT fabrica FROM fin)
 SELECT jsonb_build_object('fabrica',coalesce(jsonb_agg(jsonb_build_object('fabrica',k.fabrica,'receita_centavos',coalesce(f.receita_centavos,0),'material_centavos',coalesce(f.material_centavos,0),'rateio_centavos',coalesce(f.rateio_centavos,0),'area_m2',CASE WHEN k.fabrica IS NOT NULL AND a.receita=f.receita_centavos AND a.area_m2>0 THEN a.area_m2 ELSE NULL END,'kg_registrado',coalesce(p.kg_registrado,0),'kg_estimado',coalesce(p.kg_estimado,0),'peso_pendente',coalesce(p.peso_pendente,0),'peso_com_base',coalesce(p.peso_com_base,0)) ORDER BY k.fabrica NULLS LAST),'[]'::jsonb),
 'peso_pendente',coalesce(sum(p.peso_pendente),0)) INTO resultado
 FROM chaves k LEFT JOIN fin f ON f.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN areas a ON a.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN por_fabrica p ON p.fabrica IS NOT DISTINCT FROM k.fabrica;
 RETURN resultado;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_indicadores_industriais(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_indicadores_industriais(uuid,date,date) TO authenticated;
COMMIT;
