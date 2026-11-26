-- Somente retirar pendência quando o par físico, as parcelas de lote e a evidência
-- fiscal estiverem íntegros; transferências sem custo continuam pendentes.
CREATE VIEW ew_compras_interna.custo_transferencias_conferidas WITH(security_invoker=true) AS
SELECT v.empresa_id,v.fluxo,v.transferencia_id,t.estado
FROM ew_compras_interna.custo_transferencias_integradas v
JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
WHERE v.quantidade=t.quantidade
AND ((t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL))
AND v.quantidade=(SELECT sum(e.quantidade) FROM ew_compras_interna.custo_eventos e WHERE e.empresa_id=v.empresa_id AND e.operacao_id=v.operacao_custo)
AND NOT EXISTS(
 SELECT 1 FROM ew_compras_interna.custo_eventos e
 JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.custo_fragmentos f ON f.empresa_id=e.empresa_id AND f.lote_id=e.lote_id AND f.fragmento_id=e.fragmento_origem
 WHERE e.empresa_id=v.empresa_id AND e.operacao_id=v.operacao_custo
 AND (
 (e.estornado_em IS NULL) IS DISTINCT FROM (v.estornado_em IS NULL)
 OR (f.tipo,f.local_id,f.galpao,e.destino_tipo,e.destino_id,e.destino_galpao) IS DISTINCT FROM (t.origem_tipo,t.origem_id,t.origem_galpao,t.destino_tipo,t.destino_id,t.destino_galpao)
 OR (t.estado='ATIVA' AND (l.cancelado_em IS NOT NULL OR NOT EXISTS(
 SELECT 1 FROM ew_compras_interna.lotes_aquisicao_evidencias ev
 WHERE ev.empresa_id=l.empresa_id AND ev.fonte=l.fonte AND ev.item_fiscal_id=l.item_fiscal_id AND ev.movimento_id=l.movimento_id AND ev.quantidade=l.quantidade AND ev.custo_centavos=l.custo_centavos AND ev.categoria=l.categoria
 AND ev.tipo_material=t.tipo_material AND ev.material_id=t.material_id AND ev.comprimento_mm IS NOT DISTINCT FROM t.comprimento_mm AND ev.unidade=t.unidade
 )))
 ));
REVOKE ALL ON ew_compras_interna.custo_transferencias_conferidas FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION ew_compras_interna.transferencias_custo_pendentes(e uuid, o uuid)
 RETURNS TABLE(categoria text, transferencia_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 WITH tecnicos AS (
 SELECT a.transferencia_id,a.variacao_id,'OBRAS'::text fluxo
 FROM public.ew_estoque_obras_movimentos a
 JOIN public.ew_estoque_obras_movimentos b ON b.empresa_id=a.empresa_id AND b.transferencia_id=a.transferencia_id AND b.obra_id<>a.obra_id AND b.origem='TRANSFERENCIA' AND b.variacao_id=a.variacao_id
 WHERE a.empresa_id=e AND a.obra_id=o AND a.origem='TRANSFERENCIA' AND a.transferencia_id IS NOT NULL
 AND (a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM public.ew_estoque_obras_movimentos z WHERE z.empresa_id=e AND z.estorno_de_id=a.id),0)<>0
 OR b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM public.ew_estoque_obras_movimentos z WHERE z.empresa_id=e AND z.estorno_de_id=b.id),0)<>0)
 UNION
 SELECT t.id,t.variacao_id,'LOCAIS'::text FROM public.ew_compras_transferencias t
 WHERE t.empresa_id=e AND t.estornado_em IS NULL
 AND ((t.origem_tipo='OBRA' AND t.origem_id=o) OR (t.destino_tipo='OBRA' AND t.destino_id=o))
 ), insumos AS (
 SELECT DISTINCT a.transferencia_id,a.insumo_id FROM public.ew_insumos_movimentos a
 JOIN public.ew_insumos_movimentos b ON b.empresa_id=a.empresa_id AND b.transferencia_id=a.transferencia_id AND b.obra_id<>a.obra_id AND b.origem='TRANSFERENCIA' AND b.insumo_id=a.insumo_id
 WHERE a.empresa_id=e AND a.obra_id=o AND a.origem='TRANSFERENCIA' AND a.transferencia_id IS NOT NULL
 AND (a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM public.ew_insumos_movimentos z WHERE z.empresa_id=e AND z.estorno_de_id=a.id),0)<>0
 OR b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM public.ew_insumos_movimentos z WHERE z.empresa_id=e AND z.estorno_de_id=b.id),0)<>0)
 )
 SELECT DISTINCT CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END,t.transferencia_id
 FROM tecnicos t LEFT JOIN public.ew_materiais_variacoes v ON v.id=t.variacao_id AND v.empresa_id=e
 WHERE NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_transferencias_conferidas c WHERE c.empresa_id=e AND c.fluxo=t.fluxo AND c.transferencia_id=t.transferencia_id)
 UNION ALL
 SELECT DISTINCT CASE WHEN c.categoria='vidros' THEN 'vidros' ELSE 'outros' END,i.transferencia_id
 FROM insumos i LEFT JOIN public.ew_insumos_catalogo c ON c.id=i.insumo_id AND c.empresa_id=e
 WHERE NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_transferencias_conferidas x WHERE x.empresa_id=e AND x.fluxo='INSUMOS' AND x.transferencia_id=i.transferencia_id)
$function$;
REVOKE ALL ON FUNCTION ew_compras_interna.transferencias_custo_pendentes(uuid,uuid) FROM PUBLIC,anon,authenticated;
