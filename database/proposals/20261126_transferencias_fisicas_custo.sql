-- Apenas pares físicos completos, com identidade, empresa e quantidade verificadas.
-- Pares ausentes ou inconsistentes não autorizam apropriação. Não remove pendências.
CREATE VIEW ew_compras_interna.transferencias_fisicas_custo WITH (security_invoker=true) AS
WITH movimentos AS (
 SELECT empresa_id,id,'OBRA'::text tipo,obra_id local_id,'TECNICO'::text tipo_material,variacao_id material_id,comprimento_mm,unidade,local_estoque galpao,quantidade_delta,origem,transferencia_id,estorno_de_id,criado_em
 FROM public.ew_estoque_obras_movimentos
 UNION ALL
 SELECT empresa_id,id,'EMPRESA',local_empresa_id,'TECNICO',variacao_id,comprimento_mm,unidade,galpao,quantidade_delta,origem,transferencia_id,estorno_de_id,criado_em
 FROM public.ew_compras_estoque_empresa
 UNION ALL
 SELECT m.empresa_id,m.id,'OBRA',m.obra_id,'INSUMO',m.insumo_id,NULL::integer,c.unidade,m.local_estoque,m.quantidade_delta,m.origem,m.transferencia_id,m.estorno_de_id,m.criado_em
 FROM public.ew_insumos_movimentos m JOIN public.ew_insumos_catalogo c ON c.empresa_id=m.empresa_id AND c.id=m.insumo_id
), pares AS (
 SELECT a.empresa_id,CASE a.tipo_material WHEN 'INSUMO' THEN 'INSUMOS' ELSE 'OBRAS' END fluxo,a.transferencia_id,a.id origem_movimento_id,b.id destino_movimento_id,
 NULL::boolean estornado_registro
 FROM movimentos a JOIN movimentos b ON b.empresa_id=a.empresa_id AND b.transferencia_id=a.transferencia_id
 AND b.tipo_material=a.tipo_material AND b.tipo='OBRA' AND b.local_id<>a.local_id
 AND b.origem='TRANSFERENCIA' AND b.quantidade_delta>0
 WHERE a.tipo='OBRA' AND a.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND a.transferencia_id IS NOT NULL
 AND (SELECT count(*) FROM movimentos k WHERE k.empresa_id=a.empresa_id AND k.transferencia_id=a.transferencia_id AND k.tipo_material=a.tipo_material AND k.tipo='OBRA' AND k.origem='TRANSFERENCIA')=2
 UNION ALL
 SELECT t.empresa_id,'LOCAIS',t.id,coalesce(t.movimento_origem_obra_id,t.movimento_origem_empresa_id),
 coalesce(t.movimento_destino_obra_id,t.movimento_destino_empresa_id),t.estornado_em IS NOT NULL
 FROM public.ew_compras_transferencias t WHERE t.origem_tipo='OBRA' OR t.destino_tipo='OBRA'
), verificadas AS (
 SELECT p.empresa_id,p.fluxo,p.transferencia_id,a.id origem_movimento_id,b.id destino_movimento_id,
 a.tipo origem_tipo,a.local_id origem_id,a.galpao origem_galpao,b.tipo destino_tipo,b.local_id destino_id,b.galpao destino_galpao,
 a.tipo_material,a.material_id,a.comprimento_mm,a.unidade,-a.quantidade_delta quantidade,a.criado_em,
 a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=a.empresa_id AND z.tipo=a.tipo AND z.tipo_material=a.tipo_material AND z.estorno_de_id=a.id),0) saldo_origem,
 b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=b.empresa_id AND z.tipo=b.tipo AND z.tipo_material=b.tipo_material AND z.estorno_de_id=b.id),0) saldo_destino,
 p.estornado_registro
 FROM pares p JOIN movimentos a ON a.empresa_id=p.empresa_id AND a.id=p.origem_movimento_id
 JOIN movimentos b ON b.empresa_id=p.empresa_id AND b.id=p.destino_movimento_id
 WHERE a.origem='TRANSFERENCIA' AND b.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND b.quantidade_delta=-a.quantidade_delta
 AND a.tipo_material=b.tipo_material AND a.material_id=b.material_id AND a.comprimento_mm IS NOT DISTINCT FROM b.comprimento_mm
 AND a.unidade=b.unidade AND (a.tipo,a.local_id)<>(b.tipo,b.local_id)
 AND (p.fluxo<>'LOCAIS' OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t WHERE t.empresa_id=p.empresa_id AND t.id=p.transferencia_id
 AND t.origem_tipo=a.tipo AND t.origem_id=a.local_id AND t.origem_galpao=a.galpao AND t.destino_tipo=b.tipo AND t.destino_id=b.local_id AND t.destino_galpao=b.galpao
 AND t.variacao_id=a.material_id AND t.comprimento_mm IS NOT DISTINCT FROM a.comprimento_mm AND t.unidade=a.unidade AND t.quantidade=-a.quantidade_delta))
)
SELECT v.*,CASE WHEN saldo_origem=-quantidade AND saldo_destino=quantidade AND estornado_registro IS DISTINCT FROM true THEN 'ATIVA'
 WHEN saldo_origem=0 AND saldo_destino=0 AND estornado_registro IS DISTINCT FROM false THEN 'ESTORNADA'
 ELSE 'INCONSISTENTE' END estado
FROM verificadas v;
REVOKE ALL ON ew_compras_interna.transferencias_fisicas_custo FROM PUBLIC,anon,authenticated;
