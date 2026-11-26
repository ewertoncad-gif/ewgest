-- Esperado: elegiveis=1, valores_corretos=true. Sem escrita em tabelas reais.
WITH cenarios AS (
 SELECT n,md5('emp'||n)::uuid emp,md5('orig'||n)::uuid orig,md5('dest'||n)::uuid dest,md5('material'||n)::uuid mat,md5('lote'||n)::uuid lote,md5('transfer'||n)::uuid tr,md5('mov'||n)::uuid mov
 FROM generate_series(1,8) n
), lotes AS (
 SELECT CASE WHEN n=4 THEN md5('outra_empresa')::uuid ELSE emp END empresa_id,
 'OBRA'::text local_tipo,orig local_id,'G1'::text galpao,'TECNICO'::text tipo_material,mat material_id,6000 comprimento_mm,'BARRA'::text unidade,
 timestamp '2026-01-01' criado_em,3::numeric quantidade,10000::bigint custo_centavos,'NFE_DIRETA'::text fonte,lote item_fiscal_id,lote recebimento_id,lote movimento_id,'aluminio'::text categoria
 FROM cenarios WHERE n<>6
 UNION ALL
 SELECT emp,'OBRA',orig,'G1','TECNICO',mat,6000,'BARRA',timestamp '2026-01-01',3,10000,'NFE_DIRETA',md5('dup')::uuid,md5('dup')::uuid,md5('dup')::uuid,'aluminio' FROM cenarios WHERE n=8
), transferencias AS (
 SELECT emp empresa_id,'OBRAS'::text fluxo,tr transferencia_id,CASE WHEN n=3 THEN 'ESTORNADA' ELSE 'ATIVA' END estado,
 'OBRA'::text origem_tipo,orig origem_id,'OBRA'::text destino_tipo,dest destino_id,'G1'::text origem_galpao,'TECNICO'::text tipo_material,mat material_id,6000 comprimento_mm,
 CASE WHEN n=7 THEN 'PC' ELSE 'BARRA' END unidade,CASE WHEN n=5 THEN 4 ELSE 1 END::numeric quantidade,timestamp '2026-01-02' criado_em,mov origem_movimento_id
 FROM cenarios
), obra_mov AS (
 SELECT emp empresa_id,lote id,orig obra_id,mat variacao_id,6000 comprimento_mm,'BARRA'::text unidade,'G1'::text local_estoque,timestamp '2026-01-01' criado_em FROM cenarios
 UNION ALL SELECT emp,mov,orig,mat,6000,'BARRA','G1',timestamp '2026-01-02' FROM cenarios
 UNION ALL SELECT emp,md5('extra')::uuid,orig,mat,6000,'BARRA','G1',timestamp '2026-01-01 12:00' FROM cenarios WHERE n=2
 UNION ALL SELECT emp,md5('dup')::uuid,orig,mat,6000,'BARRA','G1',timestamp '2026-01-01' FROM cenarios WHERE n=8
), empresa_mov AS (
 SELECT empresa_id,id,obra_id local_empresa_id,variacao_id,comprimento_mm,unidade,local_estoque galpao,criado_em FROM obra_mov WHERE false
), insumo_mov AS (
 SELECT empresa_id,id,obra_id,variacao_id insumo_id,local_estoque,criado_em FROM obra_mov WHERE false
), catalogo AS (
 SELECT empresa_id,id,unidade FROM obra_mov WHERE false
), resultado AS (
WITH todos_movimentos AS (
 SELECT empresa_id,id,'OBRA'::text local_tipo,obra_id local_id,'TECNICO'::text tipo_material,variacao_id material_id,comprimento_mm,unidade,local_estoque galpao,criado_em FROM obra_mov
 UNION ALL SELECT empresa_id,id,'EMPRESA',local_empresa_id,'TECNICO',variacao_id,comprimento_mm,unidade,galpao,criado_em FROM empresa_mov
 UNION ALL SELECT m.empresa_id,m.id,'OBRA',m.obra_id,'INSUMO',m.insumo_id,NULL::integer,c.unidade,m.local_estoque,m.criado_em FROM insumo_mov m JOIN catalogo c ON c.empresa_id=m.empresa_id AND c.id=m.insumo_id
), elegiveis AS (
 SELECT t.empresa_id,t.fluxo,t.transferencia_id,t.estado,t.origem_tipo,t.origem_id,t.destino_tipo,t.destino_id,t.quantidade,
 l.fonte,l.item_fiscal_id,l.recebimento_id,l.movimento_id lote_movimento_id,l.categoria,
 round(l.custo_centavos::numeric*t.quantidade/l.quantidade)::bigint custo_centavos,
 l.quantidade quantidade_lote,l.custo_centavos custo_lote_centavos
 FROM transferencias t
 JOIN lotes l ON l.empresa_id=t.empresa_id AND l.local_tipo=t.origem_tipo AND l.local_id=t.origem_id
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
FROM contados WHERE por_transferencia=1 AND por_item=1
)
SELECT count(*) elegiveis,coalesce(bool_and(transferencia_id=md5('transfer1')::uuid AND custo_centavos=3333),false) valores_corretos FROM resultado;
