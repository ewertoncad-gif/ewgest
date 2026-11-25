BEGIN;
-- Necessidades de compras por variação, unidade e comprimento planejado.
-- Atendimento = saldo físico + consumo efetivo não estornado. Transferências
-- para fora da obra e estornos de entradas reduzem o atendimento.
CREATE OR REPLACE FUNCTION public.ew_compras_necessidades_obra(p_empresa_id uuid,p_obra_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF NOT public.ew_pode(p_empresa_id,'compras.solicitar') OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Obra indisponível ou sem permissão para solicitar compras.'; END IF;
 RETURN (
 WITH plano AS (
 SELECT c.variacao_id,'BARRA'::text AS unidade,(b->>'comprimento_mm')::integer AS comprimento_mm,sum((b->>'quantidade')::numeric) AS prevista
 FROM public.ew_cem_obras_materiais c CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c.barras_planejadas)='array' THEN c.barras_planejadas ELSE '[]'::jsonb END) b
 WHERE c.empresa_id=p_empresa_id AND c.obra_id=p_obra_id AND c.tipo='perfil'
 GROUP BY c.variacao_id,(b->>'comprimento_mm')::integer
 UNION ALL
 SELECT c.variacao_id,upper(btrim(a.unidade_item)),NULL::integer,sum(c.quantidade_prevista)
 FROM public.ew_cem_obras_materiais c JOIN public.ew_acessorios a ON a.id=c.acessorio_id AND a.empresa_id=p_empresa_id
 WHERE c.empresa_id=p_empresa_id AND c.obra_id=p_obra_id AND c.tipo='acessorio'
 GROUP BY c.variacao_id,upper(btrim(a.unidade_item))
 ), saldo AS (
 SELECT m.variacao_id,m.unidade,m.comprimento_mm,sum(m.quantidade_delta) AS fisico,
 sum(CASE WHEN m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','SAIDA_OBRA') THEN -m.quantidade_delta
 WHEN original.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','SAIDA_OBRA') THEN -m.quantidade_delta ELSE 0 END) AS consumido
 FROM public.ew_estoque_obras_movimentos m LEFT JOIN public.ew_estoque_obras_movimentos original ON original.id=m.estorno_de_id
 WHERE m.empresa_id=p_empresa_id AND m.obra_id=p_obra_id
 GROUP BY m.variacao_id,m.unidade,m.comprimento_mm
 ), dados AS (
 SELECT p.variacao_id,p.unidade,p.comprimento_mm,p.prevista,coalesce(s.fisico,0) AS fisico,greatest(0,coalesce(s.fisico,0)+coalesce(s.consumido,0)) AS atendida
 FROM plano p LEFT JOIN saldo s ON s.variacao_id=p.variacao_id AND s.unidade=p.unidade AND s.comprimento_mm IS NOT DISTINCT FROM p.comprimento_mm
 UNION ALL
 SELECT c.variacao_id,'BARRA',NULL::integer,NULL::numeric,0::numeric,0::numeric
 FROM public.ew_cem_obras_materiais c WHERE c.empresa_id=p_empresa_id AND c.obra_id=p_obra_id AND c.tipo='perfil'
 AND NOT EXISTS(SELECT 1 FROM plano p WHERE p.variacao_id=c.variacao_id)
 GROUP BY c.variacao_id
 )
 SELECT coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('faltante',CASE WHEN d.prevista>0 THEN greatest(0,d.prevista-d.atendida) ELSE NULL END) ORDER BY d.variacao_id,d.comprimento_mm),'[]'::jsonb) FROM dados d
 );
END;$f$;
REVOKE ALL ON FUNCTION public.ew_compras_necessidades_obra(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_compras_necessidades_obra(uuid,uuid) TO authenticated;
COMMIT;
