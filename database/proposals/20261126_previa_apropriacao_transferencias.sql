-- Prévia interna: somente primeira transferência de lote inequivocamente identificado.
-- Não contabiliza, não grava apropriação e não elimina pendências. A prévia não é saldo reservado.
-- Antes de persistir: proteger cancelamento/desvinculação fiscal, concorrência e saídas posteriores.
CREATE VIEW ew_compras_interna.previa_apropriacao_transferencias WITH (security_invoker=true) AS
WITH todos_movimentos AS (
 SELECT empresa_id,id,'OBRA'::text local_tipo,obra_id local_id,'TECNICO'::text tipo_material,variacao_id material_id,comprimento_mm,unidade,local_estoque galpao,criado_em FROM public.ew_estoque_obras_movimentos
 UNION ALL SELECT empresa_id,id,'EMPRESA',local_empresa_id,'TECNICO',variacao_id,comprimento_mm,unidade,galpao,criado_em FROM public.ew_compras_estoque_empresa
 UNION ALL SELECT m.empresa_id,m.id,'OBRA',m.obra_id,'INSUMO',m.insumo_id,NULL::integer,c.unidade,m.local_estoque,m.criado_em FROM public.ew_insumos_movimentos m JOIN public.ew_insumos_catalogo c ON c.empresa_id=m.empresa_id AND c.id=m.insumo_id
), elegiveis AS (
 SELECT t.empresa_id,t.fluxo,t.transferencia_id,t.estado,t.origem_tipo,t.origem_id,t.destino_tipo,t.destino_id,t.quantidade,
 l.fonte,l.item_fiscal_id,l.recebimento_id,l.movimento_id lote_movimento_id,l.categoria,
 round(l.custo_centavos::numeric*t.quantidade/l.quantidade)::bigint custo_centavos,
 l.quantidade quantidade_lote,l.custo_centavos custo_lote_centavos
 FROM ew_compras_interna.transferencias_fisicas_custo t
 JOIN ew_compras_interna.lotes_aquisicao_evidencias l ON l.empresa_id=t.empresa_id AND l.local_tipo=t.origem_tipo AND l.local_id=t.origem_id
 AND l.galpao=t.origem_galpao AND l.tipo_material=t.tipo_material AND l.material_id=t.material_id AND l.comprimento_mm IS NOT DISTINCT FROM t.comprimento_mm
 AND l.unidade=t.unidade AND l.criado_em<t.criado_em AND l.quantidade>=t.quantidade
 WHERE t.estado='ATIVA' AND t.quantidade>0
 -- Caso estrito: nenhuma outra movimentação anterior ou simultânea na origem.
 -- Sem FIFO, sem reconstituição de lotes misturados, sem custos presumidos.
 AND NOT EXISTS(SELECT 1 FROM todos_movimentos m WHERE m.empresa_id=t.empresa_id AND m.local_tipo=t.origem_tipo AND m.local_id=t.origem_id
 AND m.tipo_material=t.tipo_material AND m.material_id=t.material_id AND m.comprimento_mm IS NOT DISTINCT FROM t.comprimento_mm AND m.unidade=t.unidade
 AND m.criado_em<=t.criado_em AND m.id NOT IN(l.movimento_id,t.origem_movimento_id))
), contados AS (
 SELECT e.*,count(*) OVER(PARTITION BY empresa_id,fluxo,transferencia_id) por_transferencia,
 count(*) OVER(PARTITION BY empresa_id,fonte,item_fiscal_id) por_item
 FROM elegiveis e
)
SELECT empresa_id,fluxo,transferencia_id,estado,origem_tipo,origem_id,destino_tipo,destino_id,quantidade,fonte,item_fiscal_id,recebimento_id,lote_movimento_id,categoria,custo_centavos,quantidade_lote,custo_lote_centavos
FROM contados WHERE por_transferencia=1 AND por_item=1;
REVOKE ALL ON ew_compras_interna.previa_apropriacao_transferencias FROM PUBLIC,anon,authenticated;
