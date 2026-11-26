-- Rateio fiscal integral de uma única linha de nota vinculada a recebimentos parciais.
ALTER TABLE ew_compras_interna.custo_lotes DROP CONSTRAINT custo_lotes_empresa_id_fonte_item_fiscal_id_key;
CREATE UNIQUE INDEX custo_lotes_item_unico_nao_fracionado ON ew_compras_interna.custo_lotes(empresa_id,fonte,item_fiscal_id) WHERE fonte<>'PEDIDO_OBRA';
CREATE INDEX custo_lotes_item_fiscal_idx ON ew_compras_interna.custo_lotes(empresa_id,fonte,item_fiscal_id);
-- Candidatos a lotes de aquisição; não representam saldo disponível e não apropriam automaticamente.
-- Conversões ambíguas ou vínculos fracionados ficam pendentes. Não usar preço de cadastro.
-- Esta visão deve permanecer interna; validar lotes e travar saldo antes de persistir qualquer custo.
CREATE OR REPLACE VIEW ew_compras_interna.lotes_aquisicao_evidencias WITH (security_invoker=true) AS
WITH docs AS (
 SELECT d.empresa_id,d.id,d.obra_id,d.categoria
 FROM public.ew_obra_despesas d
 JOIN LATERAL (SELECT sum(i.valor_total) total, bool_and(i.valor_total>=0 AND i.valor_total=round(i.valor_total,2) AND i.quantidade>0) valido
 FROM public.ew_obra_despesas_itens i WHERE i.empresa_id=d.empresa_id AND i.despesa_id=d.id) t ON t.valido AND t.total=d.valor
 WHERE d.status='aprovada' AND d.valor>0
 AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.notas_estado(d.empresa_id,d.obra_id) n WHERE n.despesa_id=d.id AND n.pendente)
), pedido_base AS (
 SELECT m.empresa_id,i.id item_fiscal_id,r.id recebimento_id,m.id movimento_id,m.variacao_id material_id,m.comprimento_mm,m.unidade,m.obra_id local_id,m.local_estoque galpao,d.categoria,m.quantidade_delta quantidade,round(i.valor_total*100)::bigint total_centavos,m.criado_em,v.id vinculo_id,v.quantidade_nota,i.quantidade total_nota
 FROM public.ew_compras_nfe_vinculos v
 JOIN public.ew_compras_nfe_conciliacoes c ON c.id=v.conciliacao_id AND c.empresa_id=v.empresa_id AND c.desvinculado_em IS NULL
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.empresa_id=v.empresa_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 JOIN public.ew_compras_pedidos p ON p.id=r.pedido_id AND p.empresa_id=r.empresa_id AND p.status<>'CANCELADO'
 JOIN public.ew_compras_recebimentos_movimentos x ON x.empresa_id=r.empresa_id AND x.recebimento_id=r.id AND x.chave=v.chave
 JOIN public.ew_estoque_obras_movimentos m ON m.id=x.movimento_obra_id AND m.empresa_id=x.empresa_id AND m.obra_id=p.obra_id
 JOIN public.ew_obra_despesas_itens i ON i.id=v.despesa_item_id AND i.empresa_id=v.empresa_id AND i.despesa_id=c.despesa_id
 JOIN docs d ON d.id=i.despesa_id AND d.empresa_id=i.empresa_id AND d.obra_id=m.obra_id
 JOIN public.ew_materiais_variacoes mv ON mv.empresa_id=m.empresa_id AND mv.id=m.variacao_id
 WHERE v.desvinculado_em IS NULL AND m.origem='COMPRA' AND m.quantidade_delta>0 AND v.quantidade_fisica=m.quantidade_delta AND v.quantidade_nota>0
 AND ((d.categoria='aluminio' AND mv.tipo='perfil' AND i.perfil_id=mv.perfil_id) OR (d.categoria='acessorios' AND mv.tipo='acessorio' AND i.acessorio_id=mv.acessorio_id))
 AND ((v.unidade_nota=m.unidade AND v.quantidade_nota=m.quantidade_delta) OR (m.unidade='BARRA' AND v.unidade_nota='MT' AND v.quantidade_nota=m.quantidade_delta*m.comprimento_mm/1000) OR (m.unidade IN ('PC','UN') AND v.unidade_nota IN ('PC','UN') AND v.quantidade_nota=m.quantidade_delta))
 AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos z WHERE z.empresa_id=m.empresa_id AND z.estorno_de_id=m.id)
 AND (SELECT count(*) FROM public.ew_compras_nfe_vinculos k WHERE k.empresa_id=v.empresa_id AND k.recebimento_id=r.id AND k.chave=v.chave AND k.desvinculado_em IS NULL)=1

), pedido_rateado AS (
 SELECT pb.*,sum(quantidade_nota) OVER(PARTITION BY empresa_id,item_fiscal_id) soma_nota,
 count(*) OVER(PARTITION BY empresa_id,item_fiscal_id) n_validos,
 (SELECT count(DISTINCT z.movimento_id) FROM pedido_base z WHERE z.empresa_id=pb.empresa_id AND z.item_fiscal_id=pb.item_fiscal_id) n_movimentos,
 sum(quantidade_nota) OVER(PARTITION BY empresa_id,item_fiscal_id ORDER BY criado_em,movimento_id,vinculo_id ROWS UNBOUNDED PRECEDING) acumulado
 FROM pedido_base pb
), candidatos AS (
 SELECT r.empresa_id,'NFE_DIRETA'::text fonte,i.id item_fiscal_id,r.id recebimento_id,m.id movimento_id,
 'TECNICO'::text tipo_material,m.variacao_id material_id,m.comprimento_mm,m.unidade,
 'OBRA'::text local_tipo,m.obra_id local_id,m.local_estoque galpao,d.categoria,m.quantidade_delta quantidade,
 round(i.valor_total*100)::bigint custo_centavos,m.criado_em
 FROM public.ew_nfe_recebimentos r
 JOIN public.ew_estoque_obras_movimentos m ON m.id=r.movimento_id AND m.empresa_id=r.empresa_id AND m.obra_id=r.obra_id
 JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id AND i.empresa_id=r.empresa_id
 JOIN docs d ON d.id=i.despesa_id AND d.empresa_id=i.empresa_id AND d.obra_id=m.obra_id
 WHERE r.estornado_em IS NULL AND m.origem='COMPRA' AND m.quantidade_delta=r.quantidade AND m.quantidade_delta>0
 AND m.variacao_id=r.variacao_id AND m.comprimento_mm IS NOT DISTINCT FROM r.comprimento_mm AND m.unidade=r.unidade
 AND m.local_estoque=r.local_estoque AND (
 (upper(btrim(i.unidade))=r.unidade AND i.quantidade=r.quantidade)
 OR (d.categoria='aluminio' AND r.unidade='BARRA' AND upper(btrim(i.unidade)) IN ('MT','M') AND i.quantidade=r.quantidade*r.comprimento_mm/1000)
 OR (d.categoria='aluminio' AND r.unidade='BARRA' AND upper(btrim(i.unidade))='BR' AND i.quantidade=r.quantidade))
 AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos z WHERE z.empresa_id=m.empresa_id AND z.estorno_de_id=m.id)
 AND NOT EXISTS(SELECT 1 FROM public.ew_compras_nfe_vinculos v WHERE v.empresa_id=i.empresa_id AND v.despesa_item_id=i.id AND v.desvinculado_em IS NULL)
 UNION ALL
 SELECT m.empresa_id,'INSUMO',i.id,m.id,m.id,'INSUMO',m.insumo_id,NULL::integer,c.unidade,
 'OBRA',m.obra_id,m.local_estoque,d.categoria,m.quantidade_delta,round(i.valor_total*100)::bigint,m.criado_em
 FROM public.ew_insumos_movimentos m JOIN public.ew_obra_despesas_itens i ON i.id=m.despesa_item_id AND i.empresa_id=m.empresa_id
 JOIN docs d ON d.id=i.despesa_id AND d.empresa_id=i.empresa_id AND d.obra_id=m.obra_id
 JOIN public.ew_insumos_catalogo c ON c.id=m.insumo_id AND c.empresa_id=m.empresa_id AND c.categoria=d.categoria
 WHERE m.origem='RECEBIMENTO' AND m.quantidade_delta>0 AND i.quantidade=m.quantidade_delta AND i.unidade=c.unidade
 AND NOT EXISTS(SELECT 1 FROM public.ew_insumos_movimentos z WHERE z.empresa_id=m.empresa_id AND z.estorno_de_id=m.id)
 UNION ALL
 SELECT empresa_id,'PEDIDO_OBRA',item_fiscal_id,recebimento_id,movimento_id,'TECNICO',material_id,comprimento_mm,unidade,
 'OBRA',local_id,galpao,categoria,quantidade,
 (round(total_centavos::numeric*acumulado/total_nota)-round(total_centavos::numeric*(acumulado-quantidade_nota)/total_nota))::bigint,criado_em
 FROM pedido_rateado pr
 WHERE soma_nota=total_nota AND n_validos=(SELECT count(*) FROM public.ew_compras_nfe_vinculos k WHERE k.empresa_id=pr.empresa_id AND k.despesa_item_id=pr.item_fiscal_id AND k.desvinculado_em IS NULL)
 AND n_validos=n_movimentos
 UNION ALL
 SELECT m.empresa_id,'PEDIDO_EMPRESA',i.id,r.id,m.id,'TECNICO',m.variacao_id,m.comprimento_mm,m.unidade,
 'EMPRESA',m.local_empresa_id,m.galpao,CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END,m.quantidade_delta,i.valor_total_centavos,m.criado_em
 FROM public.ew_compras_notas_empresa_itens i
 JOIN public.ew_compras_notas_empresa n ON n.id=i.nota_id AND n.empresa_id=i.empresa_id AND n.status='ATIVA' AND n.cancelado_em IS NULL
 JOIN public.ew_compras_recebimentos r ON r.id=i.recebimento_id AND r.empresa_id=i.empresa_id AND r.pedido_id=n.pedido_id AND r.estornado_em IS NULL
 JOIN public.ew_compras_recebimentos_movimentos x ON x.empresa_id=r.empresa_id AND x.recebimento_id=r.id AND x.chave=i.chave
 JOIN public.ew_compras_estoque_empresa m ON m.id=x.movimento_empresa_id AND m.empresa_id=x.empresa_id AND m.local_empresa_id=n.local_empresa_id
 JOIN public.ew_materiais_variacoes v ON v.id=m.variacao_id AND v.empresa_id=m.empresa_id
 WHERE i.cancelado_em IS NULL AND i.valor_total_centavos>=0 AND m.quantidade_delta>0 AND i.quantidade_fisica=m.quantidade_delta
 AND i.variacao_id=m.variacao_id AND i.unidade=m.unidade AND i.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm
 AND (SELECT sum(k.valor_total_centavos) FROM public.ew_compras_notas_empresa_itens k WHERE k.empresa_id=n.empresa_id AND k.nota_id=n.id AND k.cancelado_em IS NULL)=n.valor_centavos
 AND NOT EXISTS(SELECT 1 FROM public.ew_compras_estoque_empresa z WHERE z.empresa_id=m.empresa_id AND z.estorno_de_id=m.id)
), unicos AS (
 SELECT c.*,count(*) OVER(PARTITION BY empresa_id,tipo_material,movimento_id) por_movimento,
 count(*) OVER(PARTITION BY empresa_id,fonte,item_fiscal_id) por_item
 FROM candidatos c
)
SELECT empresa_id,fonte,item_fiscal_id,recebimento_id,movimento_id,tipo_material,material_id,comprimento_mm,unidade,local_tipo,local_id,galpao,categoria,quantidade,custo_centavos,criado_em
FROM unicos WHERE por_movimento=1 AND (por_item=1 OR fonte='PEDIDO_OBRA');
REVOKE ALL ON ew_compras_interna.lotes_aquisicao_evidencias FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ew_compras_interna.custo_abrir_lote(p_empresa uuid,p_fonte text,p_item uuid,p_mov uuid,p_categoria text,p_qtd numeric,p_custo bigint,p_tipo text,p_local uuid,p_galpao text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE l uuid; antigo ew_compras_interna.custo_lotes%ROWTYPE;
BEGIN
 IF p_tipo NOT IN ('OBRA','EMPRESA') OR p_tipo IS NULL THEN RAISE EXCEPTION 'Origem de aquisição inválida'; END IF;
 IF p_fonte<>'PEDIDO_OBRA' AND EXISTS(SELECT 1 FROM ew_compras_interna.custo_lotes WHERE empresa_id=p_empresa AND fonte=p_fonte AND item_fiscal_id=p_item AND movimento_id<>p_mov) THEN RAISE EXCEPTION 'Identidade fiscal reutilizada'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('CUSTO_AQUISICAO|'||p_empresa::text||'|'||p_fonte||'|'||p_item::text,7261));
 SELECT * INTO antigo FROM ew_compras_interna.custo_lotes WHERE empresa_id=p_empresa AND fonte=p_fonte AND item_fiscal_id=p_item AND movimento_id=p_mov;
 IF FOUND THEN
  IF antigo.cancelado_em IS NOT NULL OR (antigo.movimento_id,antigo.categoria,antigo.quantidade,antigo.custo_centavos) IS DISTINCT FROM (p_mov,p_categoria,p_qtd,p_custo)
  OR NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_fragmentos f WHERE f.empresa_id=p_empresa AND f.lote_id=antigo.lote_id AND f.evento_origem IS NULL AND (f.tipo,f.local_id,f.galpao)=(p_tipo,p_local,p_galpao)) THEN RAISE EXCEPTION 'Identidade fiscal reutilizada'; END IF;
  RETURN antigo.lote_id;
 END IF;
 INSERT INTO ew_compras_interna.custo_lotes(empresa_id,fonte,item_fiscal_id,movimento_id,categoria,quantidade,custo_centavos)
 VALUES(p_empresa,p_fonte,p_item,p_mov,p_categoria,p_qtd,p_custo) RETURNING lote_id INTO l;
 INSERT INTO ew_compras_interna.custo_fragmentos(empresa_id,lote_id,inicio,fim,tipo,local_id,galpao) VALUES(p_empresa,l,0,p_qtd,p_tipo,p_local,p_galpao);
 RETURN l;
END;$f$;
CREATE OR REPLACE FUNCTION ew_compras_interna.custo_abrir_evidencia(p_empresa uuid,p_fonte text,p_item uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE e record; abriu boolean:=false;
BEGIN
 FOR e IN SELECT * FROM ew_compras_interna.lotes_aquisicao_evidencias
 WHERE empresa_id=p_empresa AND fonte=p_fonte AND item_fiscal_id=p_item ORDER BY criado_em,movimento_id LOOP
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_lotes l WHERE l.empresa_id=p_empresa AND l.fonte=p_fonte AND l.item_fiscal_id=p_item AND l.movimento_id=e.movimento_id) THEN CONTINUE; END IF;
 IF e.quantidade>1000000 OR e.quantidade<>round(e.quantidade,3) THEN CONTINUE; END IF;
 IF e.tipo_material='TECNICO' AND e.local_tipo='OBRA' THEN
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.empresa_id=p_empresa AND m.obra_id=e.local_id AND m.variacao_id=e.material_id AND m.comprimento_mm IS NOT DISTINCT FROM e.comprimento_mm AND m.unidade=e.unidade AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN CONTINUE; END IF;
 ELSIF e.tipo_material='TECNICO' AND e.local_tipo='EMPRESA' THEN
  IF EXISTS(SELECT 1 FROM public.ew_compras_estoque_empresa m WHERE m.empresa_id=p_empresa AND m.local_empresa_id=e.local_id AND m.variacao_id=e.material_id AND m.comprimento_mm IS NOT DISTINCT FROM e.comprimento_mm AND m.unidade=e.unidade AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN CONTINUE; END IF;
 ELSIF e.tipo_material='INSUMO' THEN
  IF EXISTS(SELECT 1 FROM public.ew_insumos_movimentos m WHERE m.empresa_id=p_empresa AND m.obra_id=e.local_id AND m.insumo_id=e.material_id AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN CONTINUE; END IF;
 ELSE CONTINUE;
 END IF;
 PERFORM ew_compras_interna.custo_abrir_lote(p_empresa,e.fonte,e.item_fiscal_id,e.movimento_id,e.categoria,e.quantidade,e.custo_centavos,e.local_tipo,e.local_id,e.galpao);
 abriu:=true;
 END LOOP;
 RETURN abriu;
END;$f$;
