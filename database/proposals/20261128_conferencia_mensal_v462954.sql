-- Conferência mensal: não soma folha/depreciação aos custos já reconhecidos.
BEGIN;
CREATE FUNCTION public.ew_industrial_conferencia_mes(p_empresa_id uuid,p_competencia date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE fim date;r jsonb;ind jsonb;rateio jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_pessoal(p_empresa_id,false);
 IF auth.uid() IS NULL OR p_competencia IS NULL OR extract(day from p_competencia)<>1 OR p_competencia>date_trunc('month',now() AT TIME ZONE 'America/Recife')::date THEN RAISE EXCEPTION 'Competência inválida.';END IF;
 fim:=(p_competencia+interval '1 month - 1 day')::date;
 ind:=public.ew_indicadores_industriais(p_empresa_id,p_competencia,fim);
 rateio:=public.ew_rateio_industrial_consultar(p_empresa_id,p_competencia,fim);
 WITH custos AS(
 SELECT fabrica,receita_centavos,material_centavos,rateio_centavos,area_m2
 FROM jsonb_to_recordset(ind->'fabrica') z(fabrica text,receita_centavos bigint,material_centavos bigint,rateio_centavos bigint,area_m2 numeric)
 ), folha AS(
 SELECT g.nome fabrica,sum(f.salarios+f.encargos+f.beneficios) total,count(*) n
 FROM ew_financeiro_interna.folhas_industriais f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.galpao_id WHERE f.empresa_id=p_empresa_id AND f.competencia=p_competencia AND f.estornado_em IS NULL GROUP BY g.nome
 ), ativos AS(
 SELECT g.nome fabrica,a.id,d.valor_centavos,d.ativo_id IS NULL pendente
 FROM ew_financeiro_interna.ativos_industriais a
 LEFT JOIN LATERAL(SELECT destino_id FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=a.empresa_id AND m.tipo='ATIVO' AND m.entidade_id=a.id AND m.data_evento<=p_competencia ORDER BY data_evento DESC LIMIT 1)m ON true
 LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=a.empresa_id AND g.id=coalesce(m.destino_id,a.galpao_id)
 LEFT JOIN ew_financeiro_interna.depreciacoes_industriais d ON d.empresa_id=a.empresa_id AND d.ativo_id=a.id AND d.competencia=p_competencia
 WHERE a.empresa_id=p_empresa_id AND p_competencia>=a.inicio AND p_competencia<a.inicio+make_interval(months=>a.vida_meses)
 ), dep AS(
 SELECT fabrica,coalesce(sum(valor_centavos),0) total,count(*) FILTER(WHERE pendente) pendencias,count(*) ativos FROM ativos GROUP BY fabrica
 ), mao AS(
 SELECT fabrica,sum(valor_centavos) total FROM jsonb_to_recordset(rateio->'rateios') z(fabrica text,valor_centavos bigint,classe text,valido boolean) WHERE classe='CUSTO_MAO_OBRA' AND valido GROUP BY fabrica
 ), chaves AS(SELECT fabrica FROM custos UNION SELECT fabrica FROM folha UNION SELECT fabrica FROM dep UNION SELECT fabrica FROM mao)
 SELECT jsonb_build_object('competencia',p_competencia,'mes_encerrado',fim<(now() AT TIME ZONE 'America/Recife')::date,
 'rateio_pendente_centavos',(rateio->>'industrial_classificado_centavos')::numeric-(rateio->>'rateado_centavos')::numeric,
 'rateios_pendentes',rateio->'rateios_pendentes',
 'fabrica',coalesce(jsonb_agg(jsonb_build_object('fabrica',k.fabrica,'receita_centavos',coalesce(c.receita_centavos,0),'material_centavos',coalesce(c.material_centavos,0),'rateio_centavos',coalesce(c.rateio_centavos,0),'area_m2',c.area_m2,'folha_centavos',f.total,'folhas',coalesce(f.n,0),'mao_obra_rateada_centavos',coalesce(m.total,0),'diferenca_folha_centavos',CASE WHEN f.n=1 THEN f.total-coalesce(m.total,0) END,'depreciacao_centavos',coalesce(d.total,0),'ativos',coalesce(d.ativos,0),'depreciacoes_pendentes',coalesce(d.pendencias,0)) ORDER BY k.fabrica NULLS LAST),'[]'::jsonb)) INTO r
 FROM chaves k LEFT JOIN custos c ON c.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN folha f ON f.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN dep d ON d.fabrica IS NOT DISTINCT FROM k.fabrica LEFT JOIN mao m ON m.fabrica IS NOT DISTINCT FROM k.fabrica;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_industrial_conferencia_mes(uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_industrial_conferencia_mes(uuid,date) TO authenticated;
COMMIT;
