-- Produção: compara liberação e expedição no período sem chamar liberação de produção concluída.
BEGIN;
CREATE FUNCTION public.ew_industrial_produtividade(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF auth.uid() IS NULL OR p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Período inválido.';END IF;
 WITH liberadas AS (
 SELECT nullif(btrim(l.fabrica),'') fabrica,sum(l.quantidade)::bigint quantidade,
 sum(CASE WHEN e.largura_mm>0 AND e.altura_mm>0 THEN l.quantidade*e.largura_mm::numeric*e.altura_mm::numeric/1000000 ELSE 0 END) area,
 count(*) FILTER(WHERE e.largura_mm IS NULL OR e.altura_mm IS NULL OR e.largura_mm<=0 OR e.altura_mm<=0) pendencias
 FROM public.liberacoes_corte l JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=p_empresa_id
 WHERE l.cancelado_em IS NULL AND l.tipo_componente='completo' AND l.quantidade>0 AND l.data_liberacao BETWEEN p_inicio AND p_fim GROUP BY 1
 ), expedidas AS (
 SELECT nullif(btrim(i.fabrica),'') fabrica,sum(i.area_m2) FILTER(WHERE i.area_m2>0) area,count(*) FILTER(WHERE i.area_m2 IS NULL OR i.area_m2<=0) pendencias
 FROM public.romaneios r JOIN public.romaneios_itens i ON i.romaneio_id=r.id AND i.natureza='esquadria'
 WHERE r.empresa_id=p_empresa_id AND r.status='emitido' AND r.cancelado_em IS NULL AND r.data_saida BETWEEN p_inicio AND p_fim GROUP BY 1
 ), chaves AS (SELECT fabrica FROM liberadas UNION SELECT fabrica FROM expedidas)
 SELECT jsonb_build_object('dias',p_fim-p_inicio+1,'fabrica',coalesce(jsonb_agg(jsonb_build_object('fabrica',c.fabrica,'unidades_liberadas',coalesce(l.quantidade,0),'area_liberada',coalesce(l.area,0),'area_expedida',coalesce(e.area,0),'pendencias_liberacao',coalesce(l.pendencias,0),'pendencias_expedicao',coalesce(e.pendencias,0)) ORDER BY c.fabrica NULLS LAST),'[]'::jsonb)) INTO r
 FROM chaves c LEFT JOIN liberadas l ON l.fabrica IS NOT DISTINCT FROM c.fabrica LEFT JOIN expedidas e ON e.fabrica IS NOT DISTINCT FROM c.fabrica;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_industrial_produtividade(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_industrial_produtividade(uuid,date,date) TO authenticated;
COMMIT;
