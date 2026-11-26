DO $check$ BEGIN IF to_regclass('ew_compras_interna.custo_lotes') IS NOT NULL THEN RAISE EXCEPTION 'Motor já instalado'; END IF; END $check$;
-- lotes_aquisicao_evidencias
-- Candidatos a lotes de aquisição; não representam saldo disponível e não apropriam automaticamente.
-- Conversões ambíguas ou vínculos fracionados ficam pendentes. Não usar preço de cadastro.
-- Esta visão deve permanecer interna; validar lotes e travar saldo antes de persistir qualquer custo.
CREATE VIEW ew_compras_interna.lotes_aquisicao_evidencias WITH (security_invoker=true) AS
WITH docs AS (
 SELECT d.empresa_id,d.id,d.obra_id,d.categoria
 FROM public.ew_obra_despesas d
 JOIN LATERAL (SELECT sum(i.valor_total) total, bool_and(i.valor_total>=0 AND i.valor_total=round(i.valor_total,2) AND i.quantidade>0) valido
 FROM public.ew_obra_despesas_itens i WHERE i.empresa_id=d.empresa_id AND i.despesa_id=d.id) t ON t.valido AND t.total=d.valor
 WHERE d.status='aprovada' AND d.valor>0
 AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.notas_estado(d.empresa_id,d.obra_id) n WHERE n.despesa_id=d.id AND n.pendente)
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
 SELECT m.empresa_id,'PEDIDO_OBRA',i.id,r.id,m.id,'TECNICO',m.variacao_id,m.comprimento_mm,m.unidade,
 'OBRA',m.obra_id,m.local_estoque,d.categoria,m.quantidade_delta,round(i.valor_total*100)::bigint,m.criado_em
 FROM public.ew_compras_nfe_vinculos v
 JOIN public.ew_compras_nfe_conciliacoes c ON c.id=v.conciliacao_id AND c.empresa_id=v.empresa_id AND c.desvinculado_em IS NULL
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.empresa_id=v.empresa_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 JOIN public.ew_compras_pedidos p ON p.id=r.pedido_id AND p.empresa_id=r.empresa_id AND p.status<>'CANCELADO'
 JOIN public.ew_compras_recebimentos_movimentos x ON x.empresa_id=r.empresa_id AND x.recebimento_id=r.id AND x.chave=v.chave
 JOIN public.ew_estoque_obras_movimentos m ON m.id=x.movimento_obra_id AND m.empresa_id=x.empresa_id AND m.obra_id=p.obra_id
 JOIN public.ew_obra_despesas_itens i ON i.id=v.despesa_item_id AND i.empresa_id=v.empresa_id AND i.despesa_id=c.despesa_id
 JOIN docs d ON d.id=i.despesa_id AND d.empresa_id=i.empresa_id AND d.obra_id=m.obra_id
 WHERE v.desvinculado_em IS NULL AND m.quantidade_delta>0 AND v.quantidade_fisica=m.quantidade_delta AND v.quantidade_nota=i.quantidade
 AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos z WHERE z.empresa_id=m.empresa_id AND z.estorno_de_id=m.id)
 AND (SELECT count(*) FROM public.ew_compras_nfe_vinculos k WHERE k.empresa_id=v.empresa_id AND k.despesa_item_id=i.id AND k.desvinculado_em IS NULL)=1
 AND (SELECT count(*) FROM public.ew_compras_nfe_vinculos k WHERE k.empresa_id=v.empresa_id AND k.recebimento_id=r.id AND k.chave=v.chave AND k.desvinculado_em IS NULL)=1
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
FROM unicos WHERE por_movimento=1 AND por_item=1;
REVOKE ALL ON ew_compras_interna.lotes_aquisicao_evidencias FROM PUBLIC,anon,authenticated;

-- transferencias_fisicas_custo
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
 a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=a.empresa_id AND z.tipo=a.tipo AND z.tipo_material=a.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=a.id OR (a.tipo='OBRA' AND a.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=a.empresa_id AND ep.obra_id=a.local_id AND ep.movimento_original_id=a.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_origem,
 b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=b.empresa_id AND z.tipo=b.tipo AND z.tipo_material=b.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=b.id OR (b.tipo='OBRA' AND b.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=b.empresa_id AND ep.obra_id=b.local_id AND ep.movimento_original_id=b.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_destino,
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

-- previa_apropriacao_transferencias
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

-- motor_lotes_custo
-- Motor interno de rastreabilidade, ainda não ligado às RPCs operacionais.
-- Instalar após a proposta de evidências fiscais. Nenhum backfill implícito.
-- Cada fragmento representa um intervalo do lote; o custo de seus limites
-- é calculado em centavos acumulados, sem arredondamento repetido.
CREATE TABLE ew_compras_interna.custo_lotes (
 empresa_id uuid NOT NULL, lote_id uuid NOT NULL DEFAULT gen_random_uuid(),
 fonte text NOT NULL CHECK (fonte IN ('NFE_DIRETA','PEDIDO_OBRA','PEDIDO_EMPRESA','INSUMO')),
 item_fiscal_id uuid NOT NULL, movimento_id uuid NOT NULL,
 categoria text NOT NULL CHECK (categoria IN ('aluminio','acessorios','vidros','outros')),
 quantidade numeric NOT NULL CHECK (quantidade>0 AND quantidade<=1000000 AND quantidade=round(quantidade,3)),
 custo_centavos bigint NOT NULL CHECK(custo_centavos>=0),
 cancelado_em timestamptz, cancelado_por uuid, cancelamento_operacao uuid,
 PRIMARY KEY(empresa_id,lote_id), UNIQUE(empresa_id,fonte,item_fiscal_id), UNIQUE(empresa_id,fonte,movimento_id),
 CHECK ((cancelado_em IS NULL AND cancelado_por IS NULL AND cancelamento_operacao IS NULL) OR
 (cancelado_em IS NOT NULL AND cancelado_por IS NOT NULL AND cancelamento_operacao IS NOT NULL))
);
CREATE TABLE ew_compras_interna.custo_fragmentos (
 empresa_id uuid NOT NULL,lote_id uuid NOT NULL,fragmento_id uuid NOT NULL DEFAULT gen_random_uuid(),
 inicio numeric NOT NULL CHECK(inicio>=0 AND inicio<=1000000 AND inicio=round(inicio,3)),
 fim numeric NOT NULL CHECK(fim>inicio AND fim<=1000000 AND fim=round(fim,3)),
 tipo text NOT NULL CHECK(tipo IN ('OBRA','EMPRESA','PRODUCAO')),
 local_id uuid NOT NULL, galpao text NOT NULL CHECK(length(btrim(galpao))>0),
 evento_origem uuid,
 PRIMARY KEY(empresa_id,lote_id,fragmento_id),
 FOREIGN KEY(empresa_id,lote_id) REFERENCES ew_compras_interna.custo_lotes(empresa_id,lote_id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX custo_raiz_unica ON ew_compras_interna.custo_fragmentos(empresa_id,lote_id) WHERE evento_origem IS NULL;
CREATE TABLE ew_compras_interna.custo_eventos (
 empresa_id uuid NOT NULL,lote_id uuid NOT NULL,evento_id uuid NOT NULL DEFAULT gen_random_uuid(),
 operacao_id uuid NOT NULL,parte integer NOT NULL CHECK(parte>0),fragmento_origem uuid NOT NULL,
 quantidade numeric NOT NULL CHECK(quantidade>0 AND quantidade<=1000000 AND quantidade=round(quantidade,3)),
 destino_tipo text NOT NULL CHECK(destino_tipo IN ('OBRA','EMPRESA','PRODUCAO')),
 destino_id uuid NOT NULL,destino_galpao text NOT NULL CHECK(length(btrim(destino_galpao))>0),
 custo_centavos bigint NOT NULL CHECK(custo_centavos>=0),
 criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),
 estornado_em timestamptz,estornado_por uuid,estorno_operacao uuid,
 PRIMARY KEY(empresa_id,lote_id,evento_id),UNIQUE(empresa_id,operacao_id,parte),
 FOREIGN KEY(empresa_id,lote_id,fragmento_origem) REFERENCES ew_compras_interna.custo_fragmentos(empresa_id,lote_id,fragmento_id) ON DELETE RESTRICT,
 CHECK ((estornado_em IS NULL AND estornado_por IS NULL AND estorno_operacao IS NULL) OR
 (estornado_em IS NOT NULL AND estornado_por IS NOT NULL AND estorno_operacao IS NOT NULL))
);
CREATE UNIQUE INDEX custo_fragmento_consumido ON ew_compras_interna.custo_eventos(empresa_id,lote_id,fragmento_origem) WHERE estornado_em IS NULL;
ALTER TABLE ew_compras_interna.custo_fragmentos ADD FOREIGN KEY(empresa_id,lote_id,evento_origem) REFERENCES ew_compras_interna.custo_eventos(empresa_id,lote_id,evento_id) ON DELETE RESTRICT;
CREATE VIEW ew_compras_interna.custo_saldos_fragmentos WITH(security_invoker=true) AS
 SELECT f.*,f.fim-f.inicio quantidade,
 (round(l.custo_centavos::numeric*f.fim/l.quantidade)-round(l.custo_centavos::numeric*f.inicio/l.quantidade))::bigint custo_centavos
 FROM ew_compras_interna.custo_fragmentos f JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 WHERE l.cancelado_em IS NULL
 AND (f.evento_origem IS NULL OR EXISTS(SELECT 1 FROM ew_compras_interna.custo_eventos e WHERE e.empresa_id=f.empresa_id AND e.lote_id=f.lote_id AND e.evento_id=f.evento_origem AND e.estornado_em IS NULL))
 AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_eventos e WHERE e.empresa_id=f.empresa_id AND e.lote_id=f.lote_id AND e.fragmento_origem=f.fragmento_id AND e.estornado_em IS NULL);
-- Recebe somente evidências verificadas por adaptador interno; não expor ao cliente.
CREATE FUNCTION ew_compras_interna.custo_abrir_lote(p_empresa uuid,p_fonte text,p_item uuid,p_mov uuid,p_categoria text,p_qtd numeric,p_custo bigint,p_tipo text,p_local uuid,p_galpao text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE l uuid; antigo ew_compras_interna.custo_lotes%ROWTYPE;
BEGIN
 IF p_tipo NOT IN ('OBRA','EMPRESA') OR p_tipo IS NULL THEN RAISE EXCEPTION 'Origem de aquisição inválida'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('CUSTO_AQUISICAO|'||p_empresa::text||'|'||p_fonte||'|'||p_item::text,7261));
 SELECT * INTO antigo FROM ew_compras_interna.custo_lotes WHERE empresa_id=p_empresa AND fonte=p_fonte AND item_fiscal_id=p_item;
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
CREATE FUNCTION ew_compras_interna.custo_mover_fragmento(p_empresa uuid,p_lote uuid,p_fragmento uuid,p_op uuid,p_parte integer,p_qtd numeric,p_tipo text,p_local uuid,p_galpao text,p_usuario uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE l ew_compras_interna.custo_lotes%ROWTYPE; a ew_compras_interna.custo_fragmentos%ROWTYPE; e ew_compras_interna.custo_eventos%ROWTYPE; v uuid; cent bigint;
BEGIN
 IF p_usuario IS NULL OR p_op IS NULL OR p_qtd IS NULL OR p_qtd<=0 OR p_qtd>1000000 OR p_qtd<>round(p_qtd,3) THEN RAISE EXCEPTION 'Operação inválida'; END IF;
 SELECT * INTO l FROM ew_compras_interna.custo_lotes WHERE empresa_id=p_empresa AND lote_id=p_lote FOR UPDATE;
 IF NOT FOUND OR l.cancelado_em IS NOT NULL THEN RAISE EXCEPTION 'Lote indisponível'; END IF;
 SELECT * INTO e FROM ew_compras_interna.custo_eventos WHERE empresa_id=p_empresa AND operacao_id=p_op AND parte=p_parte;
 IF FOUND THEN
  IF e.estornado_em IS NOT NULL OR (e.lote_id,e.fragmento_origem,e.quantidade,e.destino_tipo,e.destino_id,e.destino_galpao) IS DISTINCT FROM (p_lote,p_fragmento,p_qtd,p_tipo,p_local,p_galpao) THEN RAISE EXCEPTION 'Operação reutilizada'; END IF;
  RETURN e.evento_id;
 END IF;
 SELECT f.* INTO a FROM ew_compras_interna.custo_fragmentos f JOIN ew_compras_interna.custo_saldos_fragmentos s USING(empresa_id,lote_id,fragmento_id)
 WHERE f.empresa_id=p_empresa AND f.lote_id=p_lote AND f.fragmento_id=p_fragmento;
 IF NOT FOUND OR a.tipo='PRODUCAO' OR p_qtd>a.fim-a.inicio OR (a.tipo,a.local_id,a.galpao)=(p_tipo,p_local,p_galpao)
 OR (p_tipo='PRODUCAO' AND (a.tipo<>'OBRA' OR a.local_id<>p_local)) THEN RAISE EXCEPTION 'Fragmento indisponível ou destino inválido'; END IF;
 cent:=(round(l.custo_centavos::numeric*(a.inicio+p_qtd)/l.quantidade)-round(l.custo_centavos::numeric*a.inicio/l.quantidade))::bigint;
 INSERT INTO ew_compras_interna.custo_eventos(empresa_id,lote_id,operacao_id,parte,fragmento_origem,quantidade,destino_tipo,destino_id,destino_galpao,custo_centavos,criado_por)
 VALUES(p_empresa,p_lote,p_op,p_parte,p_fragmento,p_qtd,p_tipo,p_local,p_galpao,cent,p_usuario) RETURNING evento_id INTO v;
 INSERT INTO ew_compras_interna.custo_fragmentos(empresa_id,lote_id,inicio,fim,tipo,local_id,galpao,evento_origem)
 VALUES(p_empresa,p_lote,a.inicio,a.inicio+p_qtd,p_tipo,p_local,p_galpao,v);
 IF a.inicio+p_qtd<a.fim THEN
 INSERT INTO ew_compras_interna.custo_fragmentos(empresa_id,lote_id,inicio,fim,tipo,local_id,galpao,evento_origem)
 VALUES(p_empresa,p_lote,a.inicio+p_qtd,a.fim,a.tipo,a.local_id,a.galpao,v);
 END IF;
 RETURN v;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_estornar_evento(p_empresa uuid,p_lote uuid,p_evento uuid,p_op uuid,p_usuario uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE e ew_compras_interna.custo_eventos%ROWTYPE;
BEGIN
 IF p_op IS NULL OR p_usuario IS NULL THEN RAISE EXCEPTION 'Estorno inválido'; END IF;
 PERFORM 1 FROM ew_compras_interna.custo_lotes WHERE empresa_id=p_empresa AND lote_id=p_lote AND cancelado_em IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Lote indisponível'; END IF;
 SELECT * INTO e FROM ew_compras_interna.custo_eventos WHERE empresa_id=p_empresa AND lote_id=p_lote AND evento_id=p_evento;
 IF NOT FOUND THEN RAISE EXCEPTION 'Evento inexistente'; END IF;
 IF e.estornado_em IS NOT NULL THEN IF e.estorno_operacao=p_op THEN RETURN; END IF; RAISE EXCEPTION 'Evento já estornado'; END IF;
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_fragmentos f JOIN ew_compras_interna.custo_eventos z ON z.empresa_id=f.empresa_id AND z.lote_id=f.lote_id AND z.fragmento_origem=f.fragmento_id AND z.estornado_em IS NULL WHERE f.empresa_id=p_empresa AND f.lote_id=p_lote AND f.evento_origem=p_evento) THEN RAISE EXCEPTION 'Estorne primeiro as movimentações dependentes'; END IF;
 UPDATE ew_compras_interna.custo_eventos SET estornado_em=clock_timestamp(),estornado_por=p_usuario,estorno_operacao=p_op WHERE empresa_id=p_empresa AND lote_id=p_lote AND evento_id=p_evento;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_cancelar_lote(p_empresa uuid,p_lote uuid,p_op uuid,p_usuario uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE l ew_compras_interna.custo_lotes%ROWTYPE;
BEGIN
 IF p_op IS NULL OR p_usuario IS NULL THEN RAISE EXCEPTION 'Cancelamento inválido'; END IF;
 SELECT * INTO l FROM ew_compras_interna.custo_lotes WHERE empresa_id=p_empresa AND lote_id=p_lote FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Lote inexistente'; END IF;
 IF l.cancelado_em IS NOT NULL THEN IF l.cancelamento_operacao=p_op THEN RETURN; END IF; RAISE EXCEPTION 'Lote já cancelado'; END IF;
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_eventos WHERE empresa_id=p_empresa AND lote_id=p_lote AND estornado_em IS NULL) THEN RAISE EXCEPTION 'Existem transferências ou consumos ativos'; END IF;
 UPDATE ew_compras_interna.custo_lotes SET cancelado_em=clock_timestamp(),cancelado_por=p_usuario,cancelamento_operacao=p_op WHERE empresa_id=p_empresa AND lote_id=p_lote;
END;$f$;
-- O custo de produção já pertence à obra: não é uma nova despesa.
-- A mesma obra em galpões diferentes também não altera orçamento.
CREATE VIEW ew_compras_interna.custo_ajustes_obra WITH(security_invoker=true) AS
 SELECT e.empresa_id,e.operacao_id,e.evento_id,l.categoria,v.obra_id,v.delta_centavos,e.criado_em,'TRANSFERENCIA'::text evento
 FROM ew_compras_interna.custo_eventos e JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.custo_fragmentos f ON f.empresa_id=e.empresa_id AND f.lote_id=e.lote_id AND f.fragmento_id=e.fragmento_origem
 CROSS JOIN LATERAL (VALUES (f.tipo,f.local_id,-e.custo_centavos),(e.destino_tipo,e.destino_id,e.custo_centavos)) v(tipo,obra_id,delta_centavos)
 WHERE v.tipo='OBRA' AND e.destino_tipo<>'PRODUCAO' AND (f.tipo,f.local_id)<>(e.destino_tipo,e.destino_id)
 UNION ALL
 SELECT e.empresa_id,e.estorno_operacao,e.evento_id,l.categoria,v.obra_id,v.delta_centavos,e.estornado_em,'ESTORNO'
 FROM ew_compras_interna.custo_eventos e JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.custo_fragmentos f ON f.empresa_id=e.empresa_id AND f.lote_id=e.lote_id AND f.fragmento_id=e.fragmento_origem
 CROSS JOIN LATERAL (VALUES (f.tipo,f.local_id,e.custo_centavos),(e.destino_tipo,e.destino_id,-e.custo_centavos)) v(tipo,obra_id,delta_centavos)
 WHERE e.estornado_em IS NOT NULL AND v.tipo='OBRA' AND e.destino_tipo<>'PRODUCAO' AND (f.tipo,f.local_id)<>(e.destino_tipo,e.destino_id);
ALTER TABLE ew_compras_interna.custo_lotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_compras_interna.custo_fragmentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_compras_interna.custo_eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.custo_lotes,ew_compras_interna.custo_fragmentos,ew_compras_interna.custo_eventos,ew_compras_interna.custo_saldos_fragmentos,ew_compras_interna.custo_ajustes_obra FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_abrir_lote(uuid,text,uuid,uuid,text,numeric,bigint,text,uuid,text),ew_compras_interna.custo_mover_fragmento(uuid,uuid,uuid,uuid,integer,numeric,text,uuid,text,uuid),ew_compras_interna.custo_estornar_evento(uuid,uuid,uuid,uuid,uuid),ew_compras_interna.custo_cancelar_lote(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

-- ponte_lotes_transferencias
-- Ponte interna entre o motor de lotes e pares físicos validados.
-- Executar SOMENTE dentro da mesma transação da RPC de estoque autorizada,
-- sob os locks físicos existentes. Alocações devem vir do rastreador interno,
-- nunca do navegador. Não instala hooks nem altera RPCs em produção.
CREATE TABLE ew_compras_interna.custo_transferencias_integradas (
 empresa_id uuid NOT NULL, fluxo text NOT NULL CHECK(fluxo IN ('OBRAS','LOCAIS','INSUMOS')),
 transferencia_id uuid NOT NULL, operacao_custo uuid NOT NULL DEFAULT gen_random_uuid(),
 quantidade numeric NOT NULL CHECK(quantidade>0 AND quantidade<=1000000 AND quantidade=round(quantidade,3)),
 criado_por uuid NOT NULL, criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),
 estorno_operacao uuid, estornado_em timestamptz,
 PRIMARY KEY(empresa_id,fluxo,transferencia_id),UNIQUE(empresa_id,operacao_custo),
 CHECK((estorno_operacao IS NULL)=(estornado_em IS NULL))
);
ALTER TABLE ew_compras_interna.custo_transferencias_integradas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.custo_transferencias_integradas FROM PUBLIC,anon,authenticated;
CREATE FUNCTION ew_compras_interna.custo_integrar_transferencia(p_empresa uuid,p_fluxo text,p_transferencia uuid,p_alocacoes jsonb,p_usuario uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE t record; v ew_compras_interna.custo_transferencias_integradas%ROWTYPE; a record; n int:=0; qtd numeric:=0; op uuid;
BEGIN
 IF p_usuario IS NULL OR p_empresa IS NULL OR p_transferencia IS NULL OR jsonb_typeof(p_alocacoes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_alocacoes) NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Alocação de lote inválida'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('CUSTO_TRANSFERENCIA|'||p_empresa::text||'|'||p_fluxo||'|'||p_transferencia::text,7215));
 SELECT * INTO STRICT t FROM ew_compras_interna.transferencias_fisicas_custo WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF t.estado<>'ATIVA' THEN RAISE EXCEPTION 'Transferência física não ativa'; END IF;
 SELECT * INTO v FROM ew_compras_interna.custo_transferencias_integradas WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF FOUND THEN
  IF v.estornado_em IS NOT NULL OR v.quantidade<>t.quantidade OR EXISTS(
   SELECT 1 FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric)
   WHERE NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_eventos e WHERE e.empresa_id=p_empresa AND e.operacao_id=v.operacao_custo AND e.lote_id=x.lote_id AND e.fragmento_origem=x.fragmento_id AND e.quantidade=x.quantidade AND e.estornado_em IS NULL)
  ) OR jsonb_array_length(p_alocacoes)<>(SELECT count(*) FROM ew_compras_interna.custo_eventos e WHERE e.empresa_id=p_empresa AND e.operacao_id=v.operacao_custo)
  OR (SELECT count(DISTINCT (x.lote_id,x.fragmento_id)) FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric))<>jsonb_array_length(p_alocacoes)
  THEN RAISE EXCEPTION 'Transferência já integrada com alocação diferente'; END IF;
  RETURN v.operacao_custo;
 END IF;
 IF (SELECT count(DISTINCT (x.lote_id,x.fragmento_id)) FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric))<>jsonb_array_length(p_alocacoes) THEN RAISE EXCEPTION 'Fragmento duplicado'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric)
 WHERE x.lote_id IS NULL OR x.fragmento_id IS NULL OR x.quantidade IS NULL OR x.quantidade<=0 OR x.quantidade>1000000 OR x.quantidade<>round(x.quantidade,3)) THEN RAISE EXCEPTION 'Quantidade de alocação inválida'; END IF;
 SELECT sum(x.quantidade) INTO qtd FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric);
 IF qtd IS DISTINCT FROM t.quantidade THEN RAISE EXCEPTION 'Alocação não cobre a quantidade física'; END IF;
 -- Bloquear lotes em ordem determinística antes de conferir o saldo.
 PERFORM 1 FROM ew_compras_interna.custo_lotes l
 WHERE l.empresa_id=p_empresa AND l.lote_id IN (SELECT x.lote_id FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric))
 ORDER BY l.lote_id FOR UPDATE;
 FOR a IN SELECT x.* FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric) ORDER BY x.lote_id,x.fragmento_id LOOP
  IF NOT EXISTS(
   SELECT 1 FROM ew_compras_interna.custo_saldos_fragmentos s
   JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
   JOIN ew_compras_interna.lotes_aquisicao_evidencias ev ON ev.empresa_id=l.empresa_id AND ev.fonte=l.fonte AND ev.item_fiscal_id=l.item_fiscal_id AND ev.movimento_id=l.movimento_id
   WHERE s.empresa_id=p_empresa AND s.lote_id=a.lote_id AND s.fragmento_id=a.fragmento_id
   AND s.tipo=t.origem_tipo AND s.local_id=t.origem_id AND s.galpao=t.origem_galpao AND s.quantidade>=a.quantidade
   AND ev.tipo_material=t.tipo_material AND ev.material_id=t.material_id AND ev.comprimento_mm IS NOT DISTINCT FROM t.comprimento_mm AND ev.unidade=t.unidade
   AND ev.quantidade=l.quantidade AND ev.custo_centavos=l.custo_centavos AND ev.categoria=l.categoria
  ) THEN RAISE EXCEPTION 'Fragmento sem saldo, evidência fiscal ou identidade compatível'; END IF;
 END LOOP;
 INSERT INTO ew_compras_interna.custo_transferencias_integradas(empresa_id,fluxo,transferencia_id,quantidade,criado_por)
 VALUES(p_empresa,p_fluxo,p_transferencia,t.quantidade,p_usuario) RETURNING operacao_custo INTO op;
 FOR a IN SELECT x.* FROM jsonb_to_recordset(p_alocacoes) x(lote_id uuid,fragmento_id uuid,quantidade numeric) ORDER BY x.lote_id,x.fragmento_id LOOP
  n:=n+1;
  PERFORM ew_compras_interna.custo_mover_fragmento(p_empresa,a.lote_id,a.fragmento_id,op,n,a.quantidade,t.destino_tipo,t.destino_id,t.destino_galpao,p_usuario);
 END LOOP;
 RETURN op;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_integrar_estorno(p_empresa uuid,p_fluxo text,p_transferencia uuid,p_op uuid,p_usuario uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE t record; v ew_compras_interna.custo_transferencias_integradas%ROWTYPE; e record;
BEGIN
 IF p_op IS NULL OR p_usuario IS NULL THEN RAISE EXCEPTION 'Estorno inválido'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('CUSTO_TRANSFERENCIA|'||p_empresa::text||'|'||p_fluxo||'|'||p_transferencia::text,7215));
 SELECT * INTO STRICT t FROM ew_compras_interna.transferencias_fisicas_custo WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF t.estado<>'ESTORNADA' THEN RAISE EXCEPTION 'Estorno físico não concluído'; END IF;
 SELECT * INTO STRICT v FROM ew_compras_interna.custo_transferencias_integradas WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia FOR UPDATE;
 IF v.estornado_em IS NOT NULL THEN IF v.estorno_operacao=p_op THEN RETURN; END IF; RAISE EXCEPTION 'Estorno já registrado'; END IF;
 IF v.quantidade IS DISTINCT FROM (SELECT sum(x.quantidade) FROM ew_compras_interna.custo_eventos x WHERE x.empresa_id=p_empresa AND x.operacao_id=v.operacao_custo AND x.estornado_em IS NULL) THEN RAISE EXCEPTION 'Razão incompleto'; END IF;
 PERFORM 1 FROM ew_compras_interna.custo_lotes l WHERE l.empresa_id=p_empresa AND l.lote_id IN (SELECT x.lote_id FROM ew_compras_interna.custo_eventos x WHERE x.empresa_id=p_empresa AND x.operacao_id=v.operacao_custo) ORDER BY l.lote_id FOR UPDATE;
 FOR e IN SELECT x.lote_id,x.evento_id FROM ew_compras_interna.custo_eventos x WHERE x.empresa_id=p_empresa AND x.operacao_id=v.operacao_custo ORDER BY x.lote_id,x.parte DESC LOOP
  PERFORM ew_compras_interna.custo_estornar_evento(p_empresa,e.lote_id,e.evento_id,p_op,p_usuario);
 END LOOP;
 UPDATE ew_compras_interna.custo_transferencias_integradas SET estorno_operacao=p_op,estornado_em=clock_timestamp() WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
END;$f$;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_integrar_transferencia(uuid,text,uuid,jsonb,uuid),ew_compras_interna.custo_integrar_estorno(uuid,text,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
-- Projeção para futura integração ao saldo da obra. Só inclui operações com vínculo físico.
-- Não somar esta projeção ao razão antigo simultaneamente; ambos são alternativas.
CREATE VIEW ew_compras_interna.custo_transferencias_ajustes_financeiros WITH(security_invoker=true) AS
 SELECT r.empresa_id,r.obra_id,r.categoria,sum(r.delta_centavos) ajuste_centavos
 FROM ew_compras_interna.custo_ajustes_obra r
 JOIN ew_compras_interna.custo_eventos e ON e.empresa_id=r.empresa_id AND e.evento_id=r.evento_id
 JOIN ew_compras_interna.custo_transferencias_integradas v ON v.empresa_id=e.empresa_id AND v.operacao_custo=e.operacao_id
 JOIN ew_compras_interna.transferencias_fisicas_custo t ON t.empresa_id=v.empresa_id AND t.fluxo=v.fluxo AND t.transferencia_id=v.transferencia_id
 WHERE ((t.estado='ATIVA' AND v.estornado_em IS NULL AND e.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL AND e.estornado_em IS NOT NULL))
 AND v.quantidade=t.quantidade
 AND v.quantidade=(SELECT sum(x.quantidade) FROM ew_compras_interna.custo_eventos x WHERE x.empresa_id=v.empresa_id AND x.operacao_id=v.operacao_custo)
 GROUP BY r.empresa_id,r.obra_id,r.categoria;
REVOKE ALL ON ew_compras_interna.custo_transferencias_ajustes_financeiros FROM PUBLIC,anon,authenticated;

-- piloto_rpc_custo_entre_obras
-- Integração piloto (não publicar antes de cobrir todos os caminhos de estoque).
-- Usa a prévia estrita apenas para aquisição inequívoca e primeira transferência.
-- Operações sem evidência continuam com custo pendente, sem preço estimado.
CREATE FUNCTION ew_compras_interna.custo_primeira_transferencia(p_empresa uuid,p_fluxo text,p_transferencia uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE x record; ev record; l uuid; f uuid; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT public.ew_pode(p_empresa,'estoque.transferir_obras') THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 SELECT * INTO x FROM ew_compras_interna.previa_apropriacao_transferencias WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO STRICT ev FROM ew_compras_interna.lotes_aquisicao_evidencias
 WHERE empresa_id=p_empresa AND fonte=x.fonte AND item_fiscal_id=x.item_fiscal_id AND movimento_id=x.lote_movimento_id;
 l:=ew_compras_interna.custo_abrir_lote(p_empresa,ev.fonte,ev.item_fiscal_id,ev.movimento_id,ev.categoria,ev.quantidade,ev.custo_centavos,ev.local_tipo,ev.local_id,ev.galpao);
 SELECT fragmento_id INTO STRICT f FROM ew_compras_interna.custo_saldos_fragmentos
 WHERE empresa_id=p_empresa AND lote_id=l AND evento_origem IS NULL AND tipo=ev.local_tipo AND local_id=ev.local_id AND galpao=ev.galpao;
 PERFORM ew_compras_interna.custo_integrar_transferencia(p_empresa,p_fluxo,p_transferencia,jsonb_build_array(jsonb_build_object('lote_id',l,'fragmento_id',f,'quantidade',x.quantidade)),uid);
 RETURN true;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_estornar_se_integrada(p_empresa uuid,p_fluxo text,p_transferencia uuid,p_op uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
BEGIN
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa,'estoque.estornar') THEN RAISE EXCEPTION 'Sem autorização para estornar'; END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_transferencias_integradas WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia) THEN RETURN false; END IF;
 PERFORM ew_compras_interna.custo_integrar_estorno(p_empresa,p_fluxo,p_transferencia,p_op,auth.uid());
 RETURN true;
END;$f$;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_primeira_transferencia(uuid,text,uuid),ew_compras_interna.custo_estornar_se_integrada(uuid,text,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_entre_obras(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_usuario uuid:=auth.uid();
 v_origem_local text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino_local text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;
 v_unidade_acessorio text;
 v_saldo numeric;
 v_quantidade_movimentos integer;
 v_origem_codigo text;
 v_destino_codigo text;
 v_chave_origem text;
 v_chave_destino text;
 v_observacao text;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.transferir_obras');
 PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
  NOT EXISTS (SELECT 1 FROM public.usuarios_empresas u
    WHERE u.empresa_id=p_empresa_id AND u.usuario_id=v_usuario
     AND public.ew_pode(p_empresa_id,'estoque.transferir_obras'))
 THEN RAISE EXCEPTION 'Somente ADM pode transferir estoque entre obras.'; END IF;

 IF p_origem_obra_id IS NULL OR p_destino_obra_id IS NULL OR
    p_origem_obra_id=p_destino_obra_id
 THEN RAISE EXCEPTION 'Selecione obras de origem e destino diferentes.'; END IF;

 SELECT codigo INTO v_origem_codigo FROM public.obras
 WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 SELECT codigo INTO v_destino_codigo FROM public.obras
 WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL;
 IF NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_origem_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras
   WHERE id=p_destino_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_origem_obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_destino_obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Obra ou estoque inexistente, de outra empresa ou arquivado.'; END IF;

 IF v_origem_local='' OR v_destino_local='' OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_origem_local AND ativo) OR
  NOT EXISTS (SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_destino_local AND ativo)
 THEN RAISE EXCEPTION 'Galpão de origem ou destino inválido.'; END IF;

 SELECT v.tipo,upper(btrim(a.unidade_item))
 INTO v_tipo,v_unidade_acessorio
 FROM public.ew_materiais_variacoes v
 LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id AND a.empresa_id=p_empresa_id
 WHERE v.id=p_variacao_id AND v.empresa_id=p_empresa_id AND v.ativo;
 IF v_tipo IS NULL OR p_quantidade IS NULL OR p_quantidade<=0 OR p_quantidade>1000000 OR
    (v_tipo='perfil' AND
      (p_unidade IS DISTINCT FROM 'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000
       OR p_comprimento_mm IS NULL OR p_quantidade<>trunc(p_quantidade))) OR
    (v_tipo='acessorio' AND
      (p_comprimento_mm IS NOT NULL OR
       p_unidade NOT IN ('PC','PR','CJ','MT','KG','UN') OR
       p_unidade IS DISTINCT FROM v_unidade_acessorio OR
       p_quantidade<>round(p_quantidade,3)))
 THEN RAISE EXCEPTION 'Material, comprimento, unidade ou quantidade inválidos.'; END IF;
 IF char_length(btrim(coalesce(p_observacao,''))) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe um motivo de 5 a 350 caracteres.'; END IF;

 -- Uma mesma operação não pode ser executada em paralelo, nem reutilizada
 -- para mudar origem, destino, material ou quantidade.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'TRANSF_OBRAS|'||p_operacao_id::text,62841));
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
    WHERE m.transferencia_id=p_operacao_id AND m.empresa_id<>p_empresa_id)
 THEN RAISE EXCEPTION 'Identificador de transferência já utilizado.'; END IF;

 SELECT count(*) INTO v_quantidade_movimentos
 FROM public.ew_estoque_obras_movimentos
 WHERE transferencia_id=p_operacao_id AND empresa_id=p_empresa_id;
 IF v_quantidade_movimentos>0 THEN
  IF v_quantidade_movimentos<>2 OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_origem_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_origem_local
      AND quantidade_delta=-p_quantidade AND origem='TRANSFERENCIA') OR
   NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE empresa_id=p_empresa_id AND transferencia_id=p_operacao_id
      AND obra_id=p_destino_obra_id AND variacao_id=p_variacao_id
      AND comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
      AND unidade=p_unidade AND local_estoque=v_destino_local
      AND quantidade_delta=p_quantidade AND origem='TRANSFERENCIA')
  THEN RAISE EXCEPTION 'Identificador já utilizado para outra transferência.'; END IF;
  RETURN jsonb_build_object('repetida',true,'quantidade',p_quantidade,
    'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id);
 END IF;

 -- Mesma chave de lock do estoque normal. Ordenação estável evita deadlock
 -- quando duas obras transferem materiais entre si ao mesmo tempo.
 v_chave_origem:=p_origem_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 v_chave_destino:=p_destino_obra_id::text||'|'||p_variacao_id::text||'|'||
   coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   least(v_chave_origem,v_chave_destino),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   greatest(v_chave_origem,v_chave_destino),34777));
 SELECT coalesce(sum(m.quantidade_delta),0) INTO v_saldo
 FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=p_empresa_id AND m.obra_id=p_origem_obra_id
  AND m.variacao_id=p_variacao_id AND
  m.comprimento_mm IS NOT DISTINCT FROM p_comprimento_mm
  AND m.unidade=p_unidade AND m.local_estoque=v_origem_local;
 IF v_saldo<p_quantidade
 THEN RAISE EXCEPTION 'Saldo insuficiente na obra de origem. Disponível: % %.',v_saldo,p_unidade; END IF;

 v_observacao:='Remanejamento entre obras '||coalesce(v_origem_codigo,'—')||
  ' → '||coalesce(v_destino_codigo,'—')||' · '||btrim(p_observacao);
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 VALUES
 (p_empresa_id,p_origem_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  -p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_origem_local,p_operacao_id),
 (p_empresa_id,p_destino_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,
  p_quantidade,'TRANSFERENCIA',gen_random_uuid(),v_observacao,
  v_usuario,v_destino_local,p_operacao_id);
 PERFORM ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'OBRAS',p_operacao_id);
 RETURN jsonb_build_object('repetida',false,'quantidade',p_quantidade,
  'origem_obra_id',p_origem_obra_id,'destino_obra_id',p_destino_obra_id,
  'saldo_origem',v_saldo-p_quantidade,'comprimento_mm',p_comprimento_mm);
END;
$function$;
-- Preserva toda a lógica física e valida a flag da empresa alvo, sem restringir perfil nominal.
CREATE OR REPLACE FUNCTION public.ew_estornar_transferencia_entre_obras(p_empresa_id uuid, p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_debito public.ew_estoque_obras_movimentos%rowtype;
 v_credito public.ew_estoque_obras_movimentos%rowtype;
 v_n integer;
 v_saldo numeric;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_key_a text;
 v_key_b text;
 v_local_disponivel text;
 v_saldo_total numeric;
 v_alocacao record;
 v_falta numeric;
 v_parcela numeric;
 v_estorno_id uuid;
 v_primeiro boolean:=true;
 v_locais jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF p_empresa_id IS NULL OR p_transferencia_id IS NULL OR p_operacao_id IS NULL
 OR v_uid IS NULL OR NOT public.ew_pode(p_empresa_id,'estoque.estornar')
 THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: estorno de transferência entre obras.'; END IF;
 IF char_length(v_motivo) NOT BETWEEN 5 AND 350
 THEN RAISE EXCEPTION 'Informe motivo de 5 a 350 caracteres.'; END IF;

 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'ESTORNO_TRANSF_OBRAS|'||p_operacao_id::text,62841));
 -- Operação repetida só pode corresponder à mesma transferência, empresa
 -- e a TODAS as parcelas: o primeiro estorno está no campo estorno_de_id
 -- (UNIQUE), as demais são ligadas pela tabela interna ew_estornos_parcelas.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
    WHERE transferencia_id=p_operacao_id AND origem='ESTORNO') THEN
  SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos m
  WHERE m.transferencia_id=p_operacao_id AND m.origem='ESTORNO';
  IF v_n>=2 AND
   (SELECT count(*) FROM public.ew_estornos_parcelas ep
    WHERE ep.operacao_id=p_operacao_id AND ep.empresa_id=p_empresa_id)=v_n
   AND NOT EXISTS(
    SELECT 1 FROM public.ew_estoque_obras_movimentos m
    LEFT JOIN public.ew_estornos_parcelas ep
     ON ep.movimento_estorno_id=m.id AND ep.operacao_id=p_operacao_id
    LEFT JOIN public.ew_estoque_obras_movimentos original
     ON original.id=ep.movimento_original_id
    WHERE m.transferencia_id=p_operacao_id AND m.origem='ESTORNO'
    AND (ep.id IS NULL OR ep.empresa_id<>p_empresa_id
     OR original.transferencia_id IS DISTINCT FROM p_transferencia_id
     OR m.empresa_id<>p_empresa_id
     OR ep.quantidade<>abs(m.quantidade_delta)
     OR ep.local_estoque<>m.local_estoque)
   )
  THEN RETURN jsonb_build_object('repetida',true,'estornados',v_n); END IF;
  RAISE EXCEPTION 'Identificador já utilizado ou estorno parcial inconsistente.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estornos_parcelas
   WHERE operacao_id=p_operacao_id) THEN
   RAISE EXCEPTION 'Identificador de estorno já utilizado.';
 END IF;

 SELECT count(*) INTO v_n FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id AND origem='TRANSFERENCIA';
 IF v_n<>2 THEN RAISE EXCEPTION 'Transferência entre obras não localizada ou incompleta.';END IF;
 SELECT * INTO v_debito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta<0;
 SELECT * INTO v_credito FROM public.ew_estoque_obras_movimentos
 WHERE empresa_id=p_empresa_id AND transferencia_id=p_transferencia_id
  AND origem='TRANSFERENCIA' AND quantidade_delta>0;
 IF v_debito.id IS NULL OR v_credito.id IS NULL OR
  v_debito.obra_id=v_credito.obra_id OR
  v_debito.variacao_id IS DISTINCT FROM v_credito.variacao_id OR
  v_debito.comprimento_mm IS DISTINCT FROM v_credito.comprimento_mm OR
  v_debito.unidade IS DISTINCT FROM v_credito.unidade OR
  v_debito.quantidade_delta<>-v_credito.quantidade_delta
 THEN RAISE EXCEPTION 'Movimentos da transferência não formam um par íntegro.'; END IF;

 v_key_a:=v_debito.obra_id::text;
 v_key_b:=v_credito.obra_id::text;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),977124));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),977124));
 IF NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_debito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.ew_estoques_locais WHERE empresa_id=p_empresa_id
   AND obra_id=v_credito.obra_id AND excluido_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_debito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL) OR
  NOT EXISTS (SELECT 1 FROM public.obras WHERE id=v_credito.obra_id
   AND empresa_id=p_empresa_id AND arquivada_em IS NULL)
 THEN RAISE EXCEPTION 'Uma das obras ou estoques está arquivada.'; END IF;

 -- Estorno individual: dependências físicas do material, não pendências gerais da obra.
 -- Mesmo lock do estoque normal; origem e destino em ordem estável.
 v_key_a:=v_debito.obra_id::text||'|'||v_debito.variacao_id::text||'|'||
  coalesce(v_debito.comprimento_mm::text,'-')||'|'||v_debito.unidade;
 v_key_b:=v_credito.obra_id::text||'|'||v_credito.variacao_id::text||'|'||
  coalesce(v_credito.comprimento_mm::text,'-')||'|'||v_credito.unidade;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key_a,v_key_b),34777));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key_a,v_key_b),34777));

 IF EXISTS (SELECT 1 FROM public.ew_estoque_obras_movimentos
  WHERE estorno_de_id IN (v_debito.id,v_credito.id))
 THEN RAISE EXCEPTION 'Uma das pernas já foi estornada. Recarregue o histórico.';END IF;
 -- O saldo disponível não prova que o lote transferido não foi utilizado:
 -- sem lote individual, bloquear consumos posteriores ainda não estornados.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0
   AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','SAIDA_OBRA','AJUSTE')
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Estorno bloqueado: material consumido na obra de destino. Cancele o romaneio, reverta a saída e estorne a baixa primeiro.';END IF;
 -- Transferências posteriores para OUTRAS obras devem ser desfeitas em ordem inversa.
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade AND m.criado_em>=v_credito.criado_em
   AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
   AND m.transferencia_id IS DISTINCT FROM p_transferencia_id
   AND (EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
    WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
     AND other.obra_id<>m.obra_id) OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t
      WHERE t.empresa_id=p_empresa_id AND t.movimento_origem_obra_id=m.id AND t.estornado_em IS NULL
        AND t.destino_tipo='EMPRESA'))
   AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos est
    WHERE est.estorno_de_id=m.id))
 THEN RAISE EXCEPTION 'Material enviado posteriormente para outra obra. Devolva-o primeiro à obra de destino antes de estornar esta transferência.'; END IF;
 -- Não cancelar um material enquanto algum galpão da obra apresenta
 -- saldo negativo para a mesma combinação de variação, unidade e medida.
 IF EXISTS(
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)<0
 ) THEN RAISE EXCEPTION 'Saldo negativo na obra destino. Concilie antes de devolver.'; END IF;
 SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_saldo_total
 FROM (SELECT sum(m.quantidade_delta) saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
    AND m.variacao_id=v_credito.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
    AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque) t;
 IF v_saldo_total<v_credito.quantidade_delta THEN
  RAISE EXCEPTION 'Saldo insuficiente na obra destino: disponível % de % %.',
    v_saldo_total,v_credito.quantidade_delta,v_credito.unidade;
 END IF;
 v_falta:=v_credito.quantidade_delta;
 v_n:=0;
 -- Descontar exatamente a quantidade que está em cada galpão, sem transferir
 -- o material de volta ao galpão histórico antes de cancelar a operação.
 FOR v_alocacao IN
  SELECT m.local_estoque,sum(m.quantidade_delta) saldo
  FROM public.ew_estoque_obras_movimentos m
  WHERE m.empresa_id=p_empresa_id AND m.obra_id=v_credito.obra_id
   AND m.variacao_id=v_credito.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM v_credito.comprimento_mm
   AND m.unidade=v_credito.unidade
  GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)>0
  ORDER BY (m.local_estoque=v_credito.local_estoque) DESC,m.local_estoque
 LOOP
  EXIT WHEN v_falta<=0;
  v_parcela:=least(v_falta,v_alocacao.saldo);
  INSERT INTO public.ew_estoque_obras_movimentos
  (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
  VALUES (p_empresa_id,v_credito.obra_id,v_credito.variacao_id,
   v_credito.comprimento_mm,v_credito.unidade,-v_parcela,'ESTORNO',
   gen_random_uuid(),left('Estorno transferência entre obras: '||v_motivo,500),
   v_uid,v_alocacao.local_estoque,p_operacao_id,
   CASE WHEN v_primeiro THEN v_credito.id ELSE NULL END)
  RETURNING id INTO v_estorno_id;
  INSERT INTO public.ew_estornos_parcelas
   (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
    local_estoque,quantidade)
  VALUES(p_empresa_id,v_credito.obra_id,p_operacao_id,v_credito.id,v_estorno_id,
   v_alocacao.local_estoque,v_parcela);
  IF v_primeiro THEN v_local_disponivel:=v_alocacao.local_estoque; END IF;
  v_primeiro:=false;
  v_falta:=v_falta-v_parcela;
  v_n:=v_n+1;
  v_locais:=v_locais||jsonb_build_array(jsonb_build_object(
   'obra_id',v_credito.obra_id,'galpao',v_alocacao.local_estoque,
   'quantidade',v_parcela,'movimento_estorno_id',v_estorno_id,
   'movimento_original_id',v_credito.id));
 END LOOP;
 IF v_falta<>0 THEN
  RAISE EXCEPTION 'Alocação física inconsistente: faltam % %. Operação revertida.',v_falta,v_credito.unidade;
 END IF;
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id,estorno_de_id)
 VALUES (p_empresa_id,v_debito.obra_id,v_debito.variacao_id,v_debito.comprimento_mm,
  v_debito.unidade,-v_debito.quantidade_delta,'ESTORNO',gen_random_uuid(),
  left('Devolução para obra de origem: '||v_motivo,500),v_uid,
  v_debito.local_estoque,p_operacao_id,v_debito.id)
 RETURNING id INTO v_estorno_id;
 INSERT INTO public.ew_estornos_parcelas
  (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
   local_estoque,quantidade)
 VALUES (p_empresa_id,v_debito.obra_id,p_operacao_id,v_debito.id,v_estorno_id,
  v_debito.local_estoque,-v_debito.quantidade_delta);
 v_n:=v_n+1;
 INSERT INTO public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
   referencia_id,operacao_id,motivo,detalhes)
 VALUES (p_empresa_id,v_debito.obra_id,
  (SELECT nome FROM public.obras WHERE id=v_debito.obra_id),
  (SELECT codigo FROM public.obras WHERE id=v_debito.obra_id),
  v_uid,'ESTORNAR_ESTOQUE',v_debito.id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','transferencia_entre_obras',
   'transferencia_original_id',p_transferencia_id,
   'obra_origem_id',v_debito.obra_id,'obra_destino_id',v_credito.obra_id,
   'galpao_devolucao_origem',v_debito.local_estoque,
   'parcelas_destino',v_locais,'movimentos_estornados',v_n));
 PERFORM ew_compras_interna.custo_estornar_se_integrada(p_empresa_id,'OBRAS',p_transferencia_id,p_operacao_id);
 RETURN jsonb_build_object('repetida',false,'estornados',v_n,
  'origem_obra_id',v_debito.obra_id,'destino_obra_id',v_credito.obra_id,
  'galpao_da_retirada',v_local_disponivel,'parcelas',v_locais,
  'historico_preservado',true);
END;
$function$;

-- piloto_rpc_custo_locais_insumos
-- Extensão do piloto. Sem rastreabilidade integral, manter custos pendentes.
-- Executar depois do piloto entre obras e antes dos testes; não publicar isoladamente.
CREATE OR REPLACE FUNCTION public.ew_compras_estornar_transferencia(p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_t public.ew_compras_transferencias%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_key1 text;v_key2 text;v_saldo numeric;v_destino_criado timestamptz;v_destino uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if p_transferencia_id is null or p_operacao_id is null or v_uid is null
 then raise exception 'Sessão ou operação inválida.';end if;
 if length(v_motivo) not between 5 and 400 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 select * into v_t from public.ew_compras_transferencias where id=p_transferencia_id for update;
 if not found then raise exception 'Transferência inexistente.';end if;
 if not public.ew_pode(v_t.empresa_id,'estoque.estornar') then
  raise exception 'Sem permissão para estornar transferência.';end if;
 if v_t.estornado_em is not null then
  if v_t.estorno_operacao_id=p_operacao_id then
   return jsonb_build_object('id',v_t.id,'ja_estornado',true,'repetida',true);
  end if;
  raise exception 'Transferência já estornada.';end if;
 if exists(select 1 from public.ew_compras_transferencias t where
   t.estorno_operacao_id=p_operacao_id and t.id<>v_t.id)
 then raise exception 'Identificador de estorno já utilizado.';end if;
 v_key1:=case when v_t.origem_tipo='OBRA' then v_t.origem_id::text else
  'COMPRA_EMPRESA|'||v_t.origem_id::text end||'|'||v_t.variacao_id::text||'|'||
  coalesce(v_t.comprimento_mm::text,'-')||'|'||v_t.unidade;
 v_key2:=case when v_t.destino_tipo='OBRA' then v_t.destino_id::text else
  'COMPRA_EMPRESA|'||v_t.destino_id::text end||'|'||v_t.variacao_id::text||'|'||
  coalesce(v_t.comprimento_mm::text,'-')||'|'||v_t.unidade;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key1,v_key2),34777));
 if v_key2<>v_key1 then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key1,v_key2),34777));
 end if;
 if v_t.destino_tipo='OBRA' then
  select m.criado_em into v_destino_criado from public.ew_estoque_obras_movimentos m
  where m.id=v_t.movimento_destino_obra_id and m.empresa_id=v_t.empresa_id
    and m.obra_id=v_t.destino_id and m.quantidade_delta=v_t.quantidade
    and m.origem='TRANSFERENCIA';
  if not found then raise exception 'Movimento do destino não confere.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
   where m.empresa_id=v_t.empresa_id and m.obra_id=v_t.destino_id
     and m.variacao_id=v_t.variacao_id
     and m.comprimento_mm is not distinct from v_t.comprimento_mm
     and m.unidade=v_t.unidade and m.local_estoque=v_t.destino_galpao
     and m.quantidade_delta<0 and m.origem<>'ESTORNO' and m.criado_em>=v_destino_criado
       and not exists(select 1 from public.ew_estoque_obras_movimentos rev where rev.estorno_de_id=m.id))
  then raise exception 'Destino possui saídas posteriores. Desfaça dependências antes do estorno.';end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=v_t.empresa_id and m.obra_id=v_t.destino_id
    and m.variacao_id=v_t.variacao_id
    and m.comprimento_mm is not distinct from v_t.comprimento_mm
    and m.unidade=v_t.unidade and m.local_estoque=v_t.destino_galpao;
 else
  select m.criado_em into v_destino_criado from public.ew_compras_estoque_empresa m
  where m.id=v_t.movimento_destino_empresa_id and m.empresa_id=v_t.empresa_id
    and m.local_empresa_id=v_t.destino_id and m.quantidade_delta=v_t.quantidade
    and m.origem='TRANSFERENCIA';
  if not found then raise exception 'Movimento empresarial do destino não confere.';end if;
  if exists(select 1 from public.ew_compras_estoque_empresa m
    where m.empresa_id=v_t.empresa_id and m.local_empresa_id=v_t.destino_id
      and m.variacao_id=v_t.variacao_id
      and m.comprimento_mm is not distinct from v_t.comprimento_mm
      and m.unidade=v_t.unidade and m.galpao=v_t.destino_galpao
      and m.quantidade_delta<0 and m.origem not in ('ESTORNO_PEDIDO','ESTORNO_TRANSFERENCIA')
       and m.criado_em>=v_destino_criado
       and not exists(select 1 from public.ew_compras_estoque_empresa rev where rev.estorno_de_id=m.id))
  then raise exception 'Destino possui saídas posteriores. Desfaça dependências antes do estorno.';end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_compras_estoque_empresa m
  where m.empresa_id=v_t.empresa_id and m.local_empresa_id=v_t.destino_id
    and m.variacao_id=v_t.variacao_id
    and m.comprimento_mm is not distinct from v_t.comprimento_mm
    and m.unidade=v_t.unidade and m.galpao=v_t.destino_galpao;
 end if;
 if v_saldo<v_t.quantidade then raise exception 'Saldo físico insuficiente no destino.';end if;

 -- A saída original e a entrada de destino são revertidas em uma única transação.
 if v_t.destino_tipo='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(v_t.empresa_id,v_t.destino_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   -v_t.quantidade,'ESTORNO',gen_random_uuid(),left('Estorno transferência: '||v_motivo,500),
   v_uid,v_t.destino_galpao,v_t.movimento_destino_obra_id);
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,estorno_de_id,transferencia_id)
  values(v_t.empresa_id,v_t.destino_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.destino_galpao,-v_t.quantidade,'ESTORNO_TRANSFERENCIA',v_t.movimento_destino_empresa_id,
   v_t.operacao_id);
 end if;
 if v_t.origem_tipo='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(v_t.empresa_id,v_t.origem_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.quantidade,'ESTORNO',gen_random_uuid(),left('Estorno transferência: '||v_motivo,500),
   v_uid,v_t.origem_galpao,v_t.movimento_origem_obra_id);
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,estorno_de_id,transferencia_id)
  values(v_t.empresa_id,v_t.origem_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.origem_galpao,v_t.quantidade,'ESTORNO_TRANSFERENCIA',v_t.movimento_origem_empresa_id,
   v_t.operacao_id);
 end if;
 update public.ew_compras_transferencias set
  estornado_em=now(),estornado_por=v_uid,estorno_motivo=v_motivo,
  estorno_operacao_id=p_operacao_id where id=v_t.id;
 if v_t.origem_tipo='OBRA' or v_t.destino_tipo='OBRA' then
  perform ew_compras_interna.custo_estornar_se_integrada(v_t.empresa_id,'LOCAIS',v_t.id,p_operacao_id);
 end if;
 return jsonb_build_object('id',v_t.id,'repetida',false,'estornado',true);
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_compras_transferir_locais(p_empresa_id uuid, p_origem_tipo text, p_origem_id uuid, p_destino_tipo text, p_destino_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_galpao text, p_destino_galpao text, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_tipo1 text:=upper(btrim(coalesce(p_origem_tipo,'')));
 v_tipo2 text:=upper(btrim(coalesce(p_destino_tipo,'')));
 v_galpao1 text:=upper(btrim(coalesce(p_origem_galpao,'')));
 v_galpao2 text:=upper(btrim(coalesce(p_destino_galpao,'')));
 v_un text:=upper(btrim(coalesce(p_unidade,'')));
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_var public.ew_materiais_variacoes%rowtype;
 v_unidade_cadastro text;v_key1 text;v_key2 text;v_saldo numeric;
 v_trans public.ew_compras_transferencias%rowtype;
 v_origem_mov uuid;v_destino_mov uuid;v_novo_id uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_operacao_id is null then
  raise exception 'Sessão ou operação inválida.';end if;
 if not public.ew_pode(p_empresa_id,'estoque.transferir_obras') then
  raise exception 'Sem permissão para transferência entre locais.';end if;
 if v_tipo1 not in ('OBRA','EMPRESA') or v_tipo2 not in ('OBRA','EMPRESA') or
    p_origem_id is null or p_destino_id is null or
    (v_tipo1=v_tipo2 and p_origem_id=p_destino_id and v_galpao1=v_galpao2)
 then raise exception 'Informe origem e destino de estoque diferentes.';end if;
 -- Obra -> obra continua no fluxo legado, inclusive romaneio automático.
 if v_tipo1='OBRA' and v_tipo2='OBRA' then
  raise exception 'Para transferir entre duas obras, utilize Transferência entre obras.';
 end if;
 if length(v_motivo) not between 5 and 350 then
  raise exception 'Informe motivo de 5 a 350 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('COMPRAS_TRANSF|'||p_operacao_id::text,95823));
 select * into v_trans from public.ew_compras_transferencias where operacao_id=p_operacao_id;
 if found then
  if v_trans.empresa_id<>p_empresa_id or v_trans.origem_tipo<>v_tipo1 or
   v_trans.origem_id<>p_origem_id or v_trans.destino_tipo<>v_tipo2 or
   v_trans.destino_id<>p_destino_id or v_trans.variacao_id<>p_variacao_id or
   v_trans.comprimento_mm is distinct from p_comprimento_mm or v_trans.unidade<>v_un or
   v_trans.quantidade<>p_quantidade or v_trans.origem_galpao<>v_galpao1 or
   v_trans.destino_galpao<>v_galpao2 or v_trans.estornado_em is not null
  then raise exception 'Identificador de transferência já utilizado para outra operação.';end if;
  return jsonb_build_object('id',v_trans.id,'repetida',true);
 end if;
 if not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_galpao1 and ativo) or
    not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_galpao2 and ativo)
 then raise exception 'Galpão físico de origem/destino inválido.';end if;
 if (v_tipo1='OBRA' and not exists(select 1 from public.obras o
   join public.ew_estoques_locais l on l.obra_id=o.id and l.empresa_id=o.empresa_id
    where o.id=p_origem_id and o.empresa_id=p_empresa_id
     and o.arquivada_em is null and l.excluido_em is null))
 or (v_tipo2='OBRA' and not exists(select 1 from public.obras o
   join public.ew_estoques_locais l on l.obra_id=o.id and l.empresa_id=o.empresa_id
    where o.id=p_destino_id and o.empresa_id=p_empresa_id
     and o.arquivada_em is null and l.excluido_em is null))
 or (v_tipo1='EMPRESA' and not exists(select 1 from public.ew_compras_locais_empresa
    where id=p_origem_id and empresa_id=p_empresa_id and ativo))
 or (v_tipo2='EMPRESA' and not exists(select 1 from public.ew_compras_locais_empresa
    where id=p_destino_id and empresa_id=p_empresa_id and ativo))
 then raise exception 'Local de estoque inexistente, arquivado ou de outra empresa.';end if;
 select * into v_var from public.ew_materiais_variacoes
 where id=p_variacao_id and empresa_id=p_empresa_id and ativo;
 if not found then raise exception 'Material sem vínculo com esta empresa.';end if;
 if v_var.tipo='acessorio' then
  select upper(btrim(a.unidade_item)) into v_unidade_cadastro from public.ew_acessorios a
  where a.id=v_var.acessorio_id and a.empresa_id=p_empresa_id;
  if v_un<>v_unidade_cadastro then raise exception 'Unidade do acessório não coincide com o cadastro.';end if;
 end if;
 if p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000 or
   p_quantidade<>round(p_quantidade,3) or
   (v_var.tipo='perfil' and (v_un<>'BARRA' or p_comprimento_mm not between 100 and 20000)) or
   (v_var.tipo<>'perfil' and (v_un not in ('PC','PR','CJ','MT','KG','UN') or p_comprimento_mm is not null)) or
   (v_un in ('BARRA','PC','PR','CJ','UN','MT') and p_quantidade<>trunc(p_quantidade))
 then raise exception 'Quantidade, unidade ou comprimento inválido.';end if;

 v_key1:=case when v_tipo1='OBRA' then p_origem_id::text else
  'COMPRA_EMPRESA|'||p_origem_id::text end||'|'||p_variacao_id::text||'|'||
  coalesce(p_comprimento_mm::text,'-')||'|'||v_un;
 v_key2:=case when v_tipo2='OBRA' then p_destino_id::text else
  'COMPRA_EMPRESA|'||p_destino_id::text end||'|'||p_variacao_id::text||'|'||
  coalesce(p_comprimento_mm::text,'-')||'|'||v_un;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key1,v_key2),34777));
 if v_key2<>v_key1 then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key1,v_key2),34777));
 end if;

 if v_tipo1='OBRA' then
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=p_origem_id
    and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm
    and m.unidade=v_un and m.local_estoque=v_galpao1;
 else
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_compras_estoque_empresa m
  where m.empresa_id=p_empresa_id and m.local_empresa_id=p_origem_id
    and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm
    and m.unidade=v_un and m.galpao=v_galpao1;
 end if;
 if v_saldo<p_quantidade then
  raise exception 'Saldo insuficiente na origem: % %. Transferência não realizada.',v_saldo,v_un;
 end if;
 if v_tipo1='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_origem_id,p_variacao_id,p_comprimento_mm,v_un,-p_quantidade,
    'TRANSFERENCIA',gen_random_uuid(),left('Transferência local '||p_operacao_id::text||': '||v_motivo,500),v_uid,v_galpao1)
  returning id into v_origem_mov;
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,transferencia_id)
  values(p_empresa_id,p_origem_id,p_variacao_id,p_comprimento_mm,v_un,v_galpao1,
    -p_quantidade,'TRANSFERENCIA',p_operacao_id) returning id into v_origem_mov;
 end if;
 if v_tipo2='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_destino_id,p_variacao_id,p_comprimento_mm,v_un,p_quantidade,
    'TRANSFERENCIA',gen_random_uuid(),left('Transferência local '||p_operacao_id::text||': '||v_motivo,500),v_uid,v_galpao2)
  returning id into v_destino_mov;
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,transferencia_id)
  values(p_empresa_id,p_destino_id,p_variacao_id,p_comprimento_mm,v_un,v_galpao2,
    p_quantidade,'TRANSFERENCIA',p_operacao_id) returning id into v_destino_mov;
 end if;
 insert into public.ew_compras_transferencias(
  empresa_id,operacao_id,origem_tipo,origem_id,destino_tipo,destino_id,
  origem_galpao,destino_galpao,variacao_id,comprimento_mm,unidade,quantidade,motivo,
  movimento_origem_obra_id,movimento_destino_obra_id,
  movimento_origem_empresa_id,movimento_destino_empresa_id,criado_por)
 values(p_empresa_id,p_operacao_id,v_tipo1,p_origem_id,v_tipo2,p_destino_id,
  v_galpao1,v_galpao2,p_variacao_id,p_comprimento_mm,v_un,p_quantidade,v_motivo,
  case when v_tipo1='OBRA' then v_origem_mov else null end,
  case when v_tipo2='OBRA' then v_destino_mov else null end,
  case when v_tipo1='EMPRESA' then v_origem_mov else null end,
  case when v_tipo2='EMPRESA' then v_destino_mov else null end,v_uid)
 returning id into v_novo_id;
 if v_tipo1='OBRA' or v_tipo2='OBRA' then
  perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'LOCAIS',v_novo_id);
 end if;
 return jsonb_build_object('id',v_novo_id,'repetida',false,
   'saldo_origem',v_saldo-p_quantidade,'quantidade',p_quantidade);
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_insumos_estornar_transferencia(p_empresa_id uuid, p_transferencia_operacao_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_saida public.ew_insumos_movimentos%rowtype;
 v_entrada public.ew_insumos_movimentos%rowtype;v_total integer;
 v_saldo numeric;v_op uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,'estoque.estornar')) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid)
 then raise exception 'Somente ADM pode estornar transferências.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400 or p_transferencia_operacao_id is null
 then raise exception 'Informe motivo de 5 a 400 caracteres e operação válida.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_transferencia_operacao_id::text,9011));
 select count(*) into v_total from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_transferencia_operacao_id
   and m.origem='TRANSFERENCIA';
 if v_total<>2 then raise exception 'Transferência original não encontrada ou incompleta.';end if;
 select * into v_saida from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 for update;
 select * into v_entrada from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta>0 for update;
 if v_saida.id is null or v_entrada.id is null or v_saida.insumo_id<>v_entrada.insumo_id
    or v_saida.quantidade_delta<>-v_entrada.quantidade_delta
 then raise exception 'Movimentos da transferência não conferem.';end if;
 if exists(select 1 from public.ew_insumos_movimentos m where m.estorno_de_id in (v_saida.id,v_entrada.id))
 then raise exception 'Transferência já estornada.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||v_entrada.obra_id::text||'|'||
   v_entrada.insumo_id::text||'|'||v_entrada.local_estoque,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_entrada.obra_id
   and m.insumo_id=v_entrada.insumo_id and m.local_estoque=v_entrada.local_estoque;
 if v_saldo<v_entrada.quantidade_delta then
  raise exception 'Estorno bloqueado: destino já utilizou/transferiu parte do material.';end if;
 insert into public.ew_insumos_movimentos(
  empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
  origem,operacao_id,estorno_de_id,observacao,usuario_id
 ) values
 (p_empresa_id,v_entrada.obra_id,v_entrada.insumo_id,v_entrada.local_estoque,
  -v_entrada.quantidade_delta,'ESTORNO',v_op,v_entrada.id,btrim(p_motivo),v_uid),
 (p_empresa_id,v_saida.obra_id,v_saida.insumo_id,v_saida.local_estoque,
  -v_saida.quantidade_delta,'ESTORNO',v_op,v_saida.id,btrim(p_motivo),v_uid);
 if v_saida.obra_id<>v_entrada.obra_id then
  perform ew_compras_interna.custo_estornar_se_integrada(p_empresa_id,'INSUMOS',v_saida.transferencia_id,v_op);
 end if;
 return jsonb_build_object('estornado',true,'operacao_estorno',v_op);
end
$function$;
CREATE OR REPLACE FUNCTION public.ew_insumos_transferir(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_insumo_id uuid, p_origem_local text, p_destino_local text, p_quantidade numeric, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_saldo numeric;v_qtd integer;v_transfer uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,case when p_origem_obra_id=p_destino_obra_id then 'estoque.transferir_galpoes' else 'estoque.transferir_obras' end)) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
 then raise exception 'Somente ADM transfere estes materiais.';end if;
 if p_operacao_id is null or p_origem_obra_id is null or p_destino_obra_id is null
  or p_insumo_id is null or (p_origem_obra_id=p_destino_obra_id and v_origem=v_destino)
  or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
  or p_quantidade<>round(p_quantidade,3) or length(coalesce(p_observacao,''))>400
 then raise exception 'Transferência inválida.';end if;
 if not exists(select 1 from public.ew_insumos_catalogo c where c.id=p_insumo_id
    and c.empresa_id=p_empresa_id and c.ativo)
 then raise exception 'Material não pertence à empresa ou está inativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_origem and l.ativo)
 or not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_destino and l.ativo)
 then raise exception 'Galpão de origem/destino inválido.';end if;
 if not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_origem_obra_id and l.excluido_em is null)
 or not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_destino_obra_id and l.excluido_em is null)
 then raise exception 'Obras com estoque ativo são obrigatórias.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,9011));
 select count(*) into v_qtd from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.origem='TRANSFERENCIA';
 if v_qtd>0 then
   if v_qtd<>2 or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_origem_obra_id and m.local_estoque=v_origem
     and m.quantidade_delta=-p_quantidade
   ) or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_destino_obra_id and m.local_estoque=v_destino
     and m.quantidade_delta=p_quantidade
   ) then raise exception 'Operação já utilizada em outra transferência.';end if;
   return jsonb_build_object('ja_registrado',true);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_origem_obra_id::text||'|'||
   p_insumo_id::text||'|'||v_origem,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo
 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
  and m.obra_id=p_origem_obra_id and m.insumo_id=p_insumo_id
  and m.local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente na origem. Disponível: %',v_saldo;end if;
 insert into public.ew_insumos_movimentos(
   empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
   operacao_id,transferencia_id,observacao,usuario_id
 ) values
 (p_empresa_id,p_origem_obra_id,p_insumo_id,v_origem,-p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid),
 (p_empresa_id,p_destino_obra_id,p_insumo_id,v_destino,p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid);
 if p_origem_obra_id<>p_destino_obra_id then
  perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'INSUMOS',v_transfer);
 end if;
 return jsonb_build_object('transferencia_id',v_transfer,'ja_registrado',false);
end
$function$;

-- piloto_financeiro_lotes
-- Piloto de leitura: mantém pendências existentes até a cobertura operacional completa.
-- Não soma ajuste ao realizado fiscal; o cliente exibe ambos separadamente.
CREATE OR REPLACE FUNCTION public.ew_compras_compromissos_obra(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'financeiro.consultar') OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Sem acesso financeiro à obra.';END IF;
 RETURN (WITH notas AS MATERIALIZED (SELECT * FROM ew_compras_interna.notas_estado(p_empresa_id,p_obra_id)), linhas AS (
 SELECT p.id pedido_id,x->>'chave' chave,CASE v.tipo WHEN 'perfil' THEN 'aluminio' WHEN 'acessorio' THEN 'acessorios' ELSE 'outros' END categoria,
 (x->>'quantidade')::numeric qtd,(x->>'preco_unitario_centavos')::bigint preco
 FROM public.ew_compras_pedidos p CROSS JOIN LATERAL jsonb_array_elements(p.itens) x
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x->>'variacao_id')::uuid AND v.empresa_id=p.empresa_id
 WHERE p.empresa_id=p_empresa_id AND p.obra_id=p_obra_id AND p.status<>'CANCELADO'
 ), conciliado AS (
 SELECT c.pedido_id,v.chave,sum(v.quantidade_fisica) qtd
 FROM public.ew_compras_nfe_conciliacoes c JOIN public.ew_compras_nfe_vinculos v ON v.conciliacao_id=c.id AND v.desvinculado_em IS NULL
 JOIN notas d ON d.despesa_id=c.despesa_id AND NOT d.pendente
 JOIN public.ew_compras_recebimentos r ON r.id=v.recebimento_id AND r.pedido_id=c.pedido_id AND r.estornado_em IS NULL
 WHERE c.empresa_id=p_empresa_id AND c.desvinculado_em IS NULL GROUP BY c.pedido_id,v.chave
 ), compromissos AS (
 SELECT l.categoria,sum(round(l.qtd*l.preco)) total_pedido_centavos,
 sum(round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) conciliado_centavos,
 sum(round(l.qtd*l.preco)-round(least(l.qtd,coalesce(c.qtd,0))*l.preco)) pendente_centavos
 FROM linhas l LEFT JOIN conciliado c ON c.pedido_id=l.pedido_id AND c.chave=l.chave GROUP BY l.categoria
 ), despesas AS (
 SELECT categoria,coalesce(sum(valor_centavos) FILTER(WHERE NOT pendente),0) realizado_centavos,
 coalesce(sum(valor_centavos) FILTER(WHERE pendente),0) pendencia_centavos,
 coalesce(jsonb_agg(jsonb_build_object('id',despesa_id,'fornecedor',fornecedor,'numero_documento',numero_documento,'valor_centavos',valor_centavos,'assinatura',assinatura) ORDER BY despesa_id) FILTER(WHERE pendente),'[]'::jsonb) notas_pendentes FROM notas GROUP BY categoria
 ), transferencias AS MATERIALIZED (
 SELECT categoria,count(*) n FROM ew_compras_interna.transferencias_custo_pendentes(p_empresa_id,p_obra_id) GROUP BY categoria
 ), ajustes AS MATERIALIZED (
 SELECT categoria,ajuste_centavos FROM ew_compras_interna.custo_transferencias_ajustes_financeiros WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id
 ), categorias AS (SELECT categoria FROM compromissos UNION SELECT categoria FROM despesas UNION SELECT categoria FROM transferencias UNION SELECT categoria FROM ajustes)
 SELECT coalesce(jsonb_agg(jsonb_build_object('categoria',k.categoria,'pedido_centavos',coalesce(c.total_pedido_centavos,0),'conciliado_centavos',coalesce(c.conciliado_centavos,0),'comprometido_pendente_centavos',coalesce(c.pendente_centavos,0),'realizado_centavos',coalesce(d.realizado_centavos,0),'ajuste_transferencias_centavos',coalesce(a.ajuste_centavos,0),'transferencias_custo_pendentes',coalesce(t.n,0),'consumido_centavos',CASE WHEN coalesce(t.n,0)>0 OR coalesce(d.pendencia_centavos,0)>0 THEN NULL ELSE coalesce(c.pendente_centavos,0)+coalesce(d.realizado_centavos,0)+coalesce(a.ajuste_centavos,0) END,'pendencia_centavos',coalesce(d.pendencia_centavos,0),'notas_pendentes',coalesce(d.notas_pendentes,'[]'::jsonb)) ORDER BY k.categoria),'[]'::jsonb)
 FROM categorias k LEFT JOIN compromissos c USING(categoria) LEFT JOIN despesas d USING(categoria) LEFT JOIN transferencias t USING(categoria) LEFT JOIN ajustes a USING(categoria));
END;$function$;
-- custo_aquisicoes_gatilhos
-- Abertura automática por evidência fiscal completa, após concluir a transação de recebimento.
-- Nunca criar lote retroativo se existiu uma saída posterior à aquisição.
CREATE FUNCTION ew_compras_interna.custo_abrir_evidencia(p_empresa uuid,p_fonte text,p_item uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE e record;
BEGIN
 SELECT * INTO e FROM ew_compras_interna.lotes_aquisicao_evidencias
 WHERE empresa_id=p_empresa AND fonte=p_fonte AND item_fiscal_id=p_item;
 IF NOT FOUND THEN RETURN false; END IF;
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_lotes l WHERE l.empresa_id=p_empresa AND l.fonte=p_fonte AND l.item_fiscal_id=p_item) THEN RETURN false; END IF;
 IF e.quantidade>1000000 OR e.quantidade<>round(e.quantidade,3) THEN RETURN false; END IF;
 IF e.tipo_material='TECNICO' AND e.local_tipo='OBRA' THEN
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.empresa_id=p_empresa AND m.obra_id=e.local_id AND m.variacao_id=e.material_id AND m.comprimento_mm IS NOT DISTINCT FROM e.comprimento_mm AND m.unidade=e.unidade AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN RETURN false; END IF;
 ELSIF e.tipo_material='TECNICO' AND e.local_tipo='EMPRESA' THEN
  IF EXISTS(SELECT 1 FROM public.ew_compras_estoque_empresa m WHERE m.empresa_id=p_empresa AND m.local_empresa_id=e.local_id AND m.variacao_id=e.material_id AND m.comprimento_mm IS NOT DISTINCT FROM e.comprimento_mm AND m.unidade=e.unidade AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN RETURN false; END IF;
 ELSIF e.tipo_material='INSUMO' THEN
  IF EXISTS(SELECT 1 FROM public.ew_insumos_movimentos m WHERE m.empresa_id=p_empresa AND m.obra_id=e.local_id AND m.insumo_id=e.material_id AND m.criado_em>=e.criado_em AND m.quantidade_delta<0) THEN RETURN false; END IF;
 ELSE RETURN false;
 END IF;
 PERFORM ew_compras_interna.custo_abrir_lote(p_empresa,e.fonte,e.item_fiscal_id,e.movimento_id,e.categoria,e.quantidade,e.custo_centavos,e.local_tipo,e.local_id,e.galpao);
 RETURN true;
END;$f$;
CREATE FUNCTION ew_compras_interna.custo_evento_fiscal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE j jsonb:=to_jsonb(NEW); emp uuid:=(j->>'empresa_id')::uuid; item uuid; v_fonte text; l record; u uuid:=auth.uid();
BEGIN
 IF emp IS NULL THEN RAISE EXCEPTION 'Empresa fiscal ausente'; END IF;
 IF TG_TABLE_NAME='ew_nfe_recebimentos' THEN item:=(j->>'despesa_item_id')::uuid; v_fonte:='NFE_DIRETA';
 ELSIF TG_TABLE_NAME='ew_insumos_movimentos' THEN
  IF j->>'origem'='RECEBIMENTO' THEN item:=(j->>'despesa_item_id')::uuid; v_fonte:='INSUMO';
  ELSE RETURN NEW; END IF;
 ELSIF TG_TABLE_NAME='ew_compras_nfe_vinculos' THEN item:=(j->>'despesa_item_id')::uuid; v_fonte:='PEDIDO_OBRA';
 ELSIF TG_TABLE_NAME='ew_compras_notas_empresa_itens' THEN item:=(j->>'id')::uuid; v_fonte:='PEDIDO_EMPRESA';
 ELSE RAISE EXCEPTION 'Tabela fiscal não prevista';
 END IF;
 IF TG_OP='UPDATE' THEN
  FOR l IN SELECT c.lote_id FROM ew_compras_interna.custo_lotes c
   WHERE c.empresa_id=emp AND c.fonte=v_fonte AND c.item_fiscal_id=item AND c.cancelado_em IS NULL
   AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.lotes_aquisicao_evidencias v WHERE v.empresa_id=c.empresa_id AND v.fonte=c.fonte AND v.item_fiscal_id=c.item_fiscal_id AND v.movimento_id=c.movimento_id AND v.quantidade=c.quantidade AND v.custo_centavos=c.custo_centavos AND v.categoria=c.categoria)
   ORDER BY c.lote_id FOR UPDATE
  LOOP
   IF u IS NULL THEN RAISE EXCEPTION 'Estorno fiscal sem usuário'; END IF;
   PERFORM ew_compras_interna.custo_cancelar_lote(emp,l.lote_id,gen_random_uuid(),u);
  END LOOP;
 ELSE
  PERFORM ew_compras_interna.custo_abrir_evidencia(emp,v_fonte,item);
 END IF;
 RETURN NEW;
END;$f$;
-- Deferir até que todos os itens da nota tenham sido gravados.
CREATE CONSTRAINT TRIGGER ew_custo_nfe_recebimento AFTER INSERT OR UPDATE OF estornado_em ON public.ew_nfe_recebimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
CREATE CONSTRAINT TRIGGER ew_custo_insumo_recebimento AFTER INSERT ON public.ew_insumos_movimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
CREATE CONSTRAINT TRIGGER ew_custo_nfe_vinculo AFTER INSERT OR UPDATE OF desvinculado_em ON public.ew_compras_nfe_vinculos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
CREATE CONSTRAINT TRIGGER ew_custo_nota_empresa_item AFTER INSERT OR UPDATE OF cancelado_em ON public.ew_compras_notas_empresa_itens DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_evento_fiscal();
-- Guardar o cancelamento de cabeçalhos (inclusive insumos) após o estorno físico.
CREATE FUNCTION ew_compras_interna.custo_guardar_despesa()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE l record; u uuid:=auth.uid();
BEGIN
 IF NEW.status<>'cancelada' OR OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
 FOR l IN SELECT c.lote_id FROM ew_compras_interna.custo_lotes c
 JOIN public.ew_obra_despesas_itens i ON i.empresa_id=c.empresa_id AND i.id=c.item_fiscal_id
 WHERE c.empresa_id=NEW.empresa_id AND i.despesa_id=NEW.id AND c.fonte IN ('NFE_DIRETA','PEDIDO_OBRA','INSUMO') AND c.cancelado_em IS NULL
 ORDER BY c.lote_id FOR UPDATE OF c
 LOOP
  IF u IS NULL THEN RAISE EXCEPTION 'Estorno fiscal sem usuário'; END IF;
  PERFORM ew_compras_interna.custo_cancelar_lote(NEW.empresa_id,l.lote_id,gen_random_uuid(),u);
 END LOOP;
 RETURN NEW;
END;$f$;
CREATE CONSTRAINT TRIGGER ew_custo_despesa_cancelada AFTER UPDATE OF status ON public.ew_obra_despesas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.custo_guardar_despesa();
REVOKE ALL ON FUNCTION ew_compras_interna.custo_abrir_evidencia(uuid,text,uuid),ew_compras_interna.custo_evento_fiscal(),ew_compras_interna.custo_guardar_despesa() FROM PUBLIC,anon,authenticated;

-- custo_alocacao_sequencial
-- Alocação de lote apenas se o histórico físico da origem for integralmente reconhecido.
-- PEPS (aquisição mais antiga; desempate pelo ID e intervalo do lote), nunca preço de cadastro.
CREATE VIEW ew_compras_interna.custo_movimentos_fisicos WITH(security_invoker=true) AS
 SELECT empresa_id,id,'OBRA'::text tipo,obra_id local_id,local_estoque galpao,'TECNICO'::text tipo_material,variacao_id material_id,comprimento_mm,unidade,quantidade_delta,origem,estorno_de_id
 FROM public.ew_estoque_obras_movimentos
 UNION ALL
 SELECT empresa_id,id,'EMPRESA',local_empresa_id,galpao,'TECNICO',variacao_id,comprimento_mm,unidade,quantidade_delta,origem,estorno_de_id
 FROM public.ew_compras_estoque_empresa
 UNION ALL
 SELECT m.empresa_id,m.id,'OBRA',m.obra_id,m.local_estoque,'INSUMO',m.insumo_id,NULL::integer,c.unidade,m.quantidade_delta,m.origem,m.estorno_de_id
 FROM public.ew_insumos_movimentos m JOIN public.ew_insumos_catalogo c ON c.empresa_id=m.empresa_id AND c.id=m.insumo_id;
CREATE VIEW ew_compras_interna.custo_movimentos_reconhecidos WITH(security_invoker=true) AS
 SELECT l.empresa_id,l.movimento_id id,l.cancelado_em IS NOT NULL estornado FROM ew_compras_interna.custo_lotes l
 UNION
 SELECT t.empresa_id,t.origem_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL)
 UNION
 SELECT t.empresa_id,t.destino_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL);
CREATE FUNCTION ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa uuid,p_mov uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE m record; s numeric; qtd numeric; falta numeric; a record; res jsonb:='[]'::jsonb;
BEGIN
 SELECT * INTO STRICT m FROM ew_compras_interna.custo_movimentos_fisicos WHERE empresa_id=p_empresa AND id=p_mov;
 IF m.quantidade_delta>=0 THEN RAISE EXCEPTION 'Movimento não é saída'; END IF;
 -- O chamador já detém os locks físicos. Não apropriar se existir qualquer
 -- entrada/saída sem vínculo confirmado, mesmo se o saldo líquido coincidir.
 IF EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_fisicos z
 WHERE z.empresa_id=p_empresa AND z.tipo=m.tipo AND z.local_id=m.local_id AND z.galpao=m.galpao AND z.tipo_material=m.tipo_material AND z.material_id=m.material_id AND z.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND z.unidade=m.unidade
 AND z.id<>p_mov AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_reconhecidos r WHERE r.empresa_id=p_empresa AND r.id=z.id)
 AND NOT EXISTS(SELECT 1 FROM ew_compras_interna.custo_movimentos_reconhecidos r WHERE r.empresa_id=p_empresa AND r.estornado AND (r.id=z.estorno_de_id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=p_empresa AND ep.movimento_original_id=r.id AND ep.movimento_estorno_id=z.id AND ep.quantidade=abs(z.quantidade_delta))))
 ) THEN RETURN NULL; END IF;
 SELECT coalesce(sum(z.quantidade_delta),0)-m.quantidade_delta INTO s FROM ew_compras_interna.custo_movimentos_fisicos z
 WHERE z.empresa_id=p_empresa AND z.tipo=m.tipo AND z.local_id=m.local_id AND z.galpao=m.galpao AND z.tipo_material=m.tipo_material AND z.material_id=m.material_id AND z.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND z.unidade=m.unidade;
 SELECT coalesce(sum(f.quantidade),0) INTO qtd FROM ew_compras_interna.custo_saldos_fragmentos f
 JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.lotes_aquisicao_evidencias e ON e.empresa_id=l.empresa_id AND e.fonte=l.fonte AND e.item_fiscal_id=l.item_fiscal_id AND e.movimento_id=l.movimento_id AND e.quantidade=l.quantidade AND e.custo_centavos=l.custo_centavos AND e.categoria=l.categoria
 WHERE f.empresa_id=p_empresa AND f.tipo=m.tipo AND f.local_id=m.local_id AND f.galpao=m.galpao AND e.tipo_material=m.tipo_material AND e.material_id=m.material_id AND e.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND e.unidade=m.unidade;
 IF qtd<>s OR qtd< -m.quantidade_delta THEN RETURN NULL; END IF;
 falta:=-m.quantidade_delta;
 FOR a IN SELECT f.lote_id,f.fragmento_id,f.quantidade FROM ew_compras_interna.custo_saldos_fragmentos f
 JOIN ew_compras_interna.custo_lotes l USING(empresa_id,lote_id)
 JOIN ew_compras_interna.lotes_aquisicao_evidencias e ON e.empresa_id=l.empresa_id AND e.fonte=l.fonte AND e.item_fiscal_id=l.item_fiscal_id AND e.movimento_id=l.movimento_id AND e.quantidade=l.quantidade AND e.custo_centavos=l.custo_centavos AND e.categoria=l.categoria
 WHERE f.empresa_id=p_empresa AND f.tipo=m.tipo AND f.local_id=m.local_id AND f.galpao=m.galpao AND e.tipo_material=m.tipo_material AND e.material_id=m.material_id AND e.comprimento_mm IS NOT DISTINCT FROM m.comprimento_mm AND e.unidade=m.unidade
 ORDER BY e.criado_em,l.lote_id,f.inicio LOOP
  EXIT WHEN falta<=0;
  res:=res||jsonb_build_array(jsonb_build_object('lote_id',a.lote_id,'fragmento_id',a.fragmento_id,'quantidade',least(falta,a.quantidade)));
  falta:=falta-least(falta,a.quantidade);
 END LOOP;
 IF falta<>0 THEN RETURN NULL; END IF;
 RETURN res;
END;$f$;
CREATE OR REPLACE FUNCTION ew_compras_interna.custo_primeira_transferencia(p_empresa uuid,p_fluxo text,p_transferencia uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
DECLARE t record; x record; ev record; l uuid; f uuid; al jsonb; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT public.ew_pode(p_empresa,'estoque.transferir_obras') THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 SELECT * INTO STRICT t FROM ew_compras_interna.transferencias_fisicas_custo WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF t.estado<>'ATIVA' THEN RAISE EXCEPTION 'Transferência física inválida'; END IF;
 al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
 IF al IS NULL THEN
  -- Legado: somente primeira transferência com origem inequívoca.
  SELECT * INTO x FROM ew_compras_interna.previa_apropriacao_transferencias WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO STRICT ev FROM ew_compras_interna.lotes_aquisicao_evidencias WHERE empresa_id=p_empresa AND fonte=x.fonte AND item_fiscal_id=x.item_fiscal_id AND movimento_id=x.lote_movimento_id;
  l:=ew_compras_interna.custo_abrir_lote(p_empresa,ev.fonte,ev.item_fiscal_id,ev.movimento_id,ev.categoria,ev.quantidade,ev.custo_centavos,ev.local_tipo,ev.local_id,ev.galpao);
  al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
  IF al IS NULL THEN RAISE EXCEPTION 'Histórico de custo não conciliado'; END IF;
 END IF;
 PERFORM ew_compras_interna.custo_integrar_transferencia(p_empresa,p_fluxo,p_transferencia,al,uid);
 RETURN true;
END;$f$;
REVOKE ALL ON ew_compras_interna.custo_movimentos_fisicos,ew_compras_interna.custo_movimentos_reconhecidos FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_alocar_saldo_comprovado(uuid,uuid),ew_compras_interna.custo_primeira_transferencia(uuid,text,uuid) FROM PUBLIC,anon,authenticated;

-- custo_consumo_producao
-- Consumo do lote na produção: não gera outro lançamento financeiro.
CREATE TABLE ew_compras_interna.custo_consumos_integrados (
 empresa_id uuid NOT NULL,movimento_id uuid NOT NULL,operacao_custo uuid NOT NULL DEFAULT gen_random_uuid(),
 quantidade numeric NOT NULL CHECK(quantidade>0),criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),
 estornado_em timestamptz,estorno_operacao uuid,
 PRIMARY KEY(empresa_id,movimento_id),UNIQUE(empresa_id,operacao_custo),
 CHECK((estornado_em IS NULL)=(estorno_operacao IS NULL))
);
ALTER TABLE ew_compras_interna.custo_consumos_integrados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.custo_consumos_integrados FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE VIEW ew_compras_interna.custo_movimentos_reconhecidos WITH(security_invoker=true) AS
 SELECT l.empresa_id,l.movimento_id id,l.cancelado_em IS NOT NULL estornado FROM ew_compras_interna.custo_lotes l
 UNION
 SELECT t.empresa_id,t.origem_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL)
 UNION
 SELECT t.empresa_id,t.destino_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL)
 UNION
 SELECT c.empresa_id,c.movimento_id,c.estornado_em IS NOT NULL FROM ew_compras_interna.custo_consumos_integrados c;
CREATE FUNCTION ew_compras_interna.custo_integrar_consumo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE al jsonb; a record; op uuid; n int:=0; u uuid:=auth.uid();
BEGIN
 IF NEW.origem NOT IN ('PLANO_CORTE','PLANO_CORTE_LOTE') OR NEW.quantidade_delta>=0 THEN RETURN NEW; END IF;
 IF u IS NULL OR NOT public.ew_pode(NEW.empresa_id,'estoque.baixar') OR NOT public.ew_pode(NEW.empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'Sem autorização para consumo'; END IF;
 al:=ew_compras_interna.custo_alocar_saldo_comprovado(NEW.empresa_id,NEW.id);
 IF al IS NULL THEN RETURN NEW; END IF;
 INSERT INTO ew_compras_interna.custo_consumos_integrados(empresa_id,movimento_id,quantidade,criado_por)
 VALUES(NEW.empresa_id,NEW.id,-NEW.quantidade_delta,u) RETURNING operacao_custo INTO op;
 FOR a IN SELECT x.* FROM jsonb_to_recordset(al) x(lote_id uuid,fragmento_id uuid,quantidade numeric) ORDER BY x.lote_id,x.fragmento_id LOOP
  n:=n+1;
  PERFORM ew_compras_interna.custo_mover_fragmento(NEW.empresa_id,a.lote_id,a.fragmento_id,op,n,a.quantidade,'PRODUCAO',NEW.obra_id,NEW.local_estoque,u);
 END LOOP;
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_custo_consumo AFTER INSERT ON public.ew_estoque_obras_movimentos
 FOR EACH ROW WHEN (NEW.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND NEW.quantidade_delta<0)
 EXECUTE FUNCTION ew_compras_interna.custo_integrar_consumo();
CREATE FUNCTION ew_compras_interna.custo_estornar_consumo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE c record; orig record; e record; qtd numeric; u uuid:=auth.uid();
BEGIN
 IF NEW.origem<>'ESTORNO' OR NEW.estorno_de_id IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO c FROM ew_compras_interna.custo_consumos_integrados WHERE empresa_id=NEW.empresa_id AND movimento_id=NEW.estorno_de_id FOR UPDATE;
 IF NOT FOUND OR c.estornado_em IS NOT NULL THEN RETURN NEW; END IF;
 SELECT * INTO STRICT orig FROM public.ew_estoque_obras_movimentos WHERE empresa_id=NEW.empresa_id AND id=c.movimento_id;
 IF u IS NULL OR NOT public.ew_pode(NEW.empresa_id,'estoque.estornar') THEN RAISE EXCEPTION 'Sem autorização para estorno de consumo'; END IF;
 SELECT coalesce(sum(m.quantidade_delta),0) INTO qtd FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=NEW.empresa_id AND m.obra_id=orig.obra_id AND m.variacao_id=orig.variacao_id AND m.comprimento_mm IS NOT DISTINCT FROM orig.comprimento_mm AND m.unidade=orig.unidade AND m.local_estoque=orig.local_estoque
 AND m.origem='ESTORNO' AND (m.estorno_de_id=orig.id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=NEW.empresa_id AND ep.movimento_original_id=orig.id AND ep.movimento_estorno_id=m.id AND ep.quantidade=abs(m.quantidade_delta)));
 IF qtd<>c.quantidade THEN RAISE EXCEPTION 'Estorno do consumo deve devolver a quantidade integral ao galpão original'; END IF;
 FOR e IN SELECT lote_id,evento_id FROM ew_compras_interna.custo_eventos WHERE empresa_id=NEW.empresa_id AND operacao_id=c.operacao_custo ORDER BY lote_id,parte DESC LOOP
  PERFORM ew_compras_interna.custo_estornar_evento(NEW.empresa_id,e.lote_id,e.evento_id,NEW.operacao_id,u);
 END LOOP;
 UPDATE ew_compras_interna.custo_consumos_integrados SET estornado_em=clock_timestamp(),estorno_operacao=NEW.operacao_id WHERE empresa_id=NEW.empresa_id AND movimento_id=orig.id;
 RETURN NEW;
END;$f$;
CREATE CONSTRAINT TRIGGER ew_custo_consumo_estorno AFTER INSERT ON public.ew_estoque_obras_movimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 WHEN (NEW.origem='ESTORNO' AND NEW.estorno_de_id IS NOT NULL) EXECUTE FUNCTION ew_compras_interna.custo_estornar_consumo();
REVOKE ALL ON FUNCTION ew_compras_interna.custo_integrar_consumo(),ew_compras_interna.custo_estornar_consumo() FROM PUBLIC,anon,authenticated;

-- custo_pendencias_conferidas
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

-- custo_galpoes
-- Apenas pares físicos completos, com identidade, empresa e quantidade verificadas.
-- Pares ausentes ou inconsistentes não autorizam apropriação. Não remove pendências.
CREATE OR REPLACE VIEW ew_compras_interna.transferencias_fisicas_custo WITH (security_invoker=true) AS
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
 AND b.tipo_material=a.tipo_material AND b.tipo='OBRA' AND (b.local_id,b.galpao)<>(a.local_id,a.galpao)
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
 a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=a.empresa_id AND z.tipo=a.tipo AND z.tipo_material=a.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=a.id OR (a.tipo='OBRA' AND a.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=a.empresa_id AND ep.obra_id=a.local_id AND ep.movimento_original_id=a.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_origem,
 b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=b.empresa_id AND z.tipo=b.tipo AND z.tipo_material=b.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=b.id OR (b.tipo='OBRA' AND b.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=b.empresa_id AND ep.obra_id=b.local_id AND ep.movimento_original_id=b.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_destino,
 p.estornado_registro
 FROM pares p JOIN movimentos a ON a.empresa_id=p.empresa_id AND a.id=p.origem_movimento_id
 JOIN movimentos b ON b.empresa_id=p.empresa_id AND b.id=p.destino_movimento_id
 WHERE a.origem='TRANSFERENCIA' AND b.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND b.quantidade_delta=-a.quantidade_delta
 AND a.tipo_material=b.tipo_material AND a.material_id=b.material_id AND a.comprimento_mm IS NOT DISTINCT FROM b.comprimento_mm
 AND a.unidade=b.unidade AND (a.tipo,a.local_id,a.galpao)<>(b.tipo,b.local_id,b.galpao)
 AND (p.fluxo<>'LOCAIS' OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t WHERE t.empresa_id=p.empresa_id AND t.id=p.transferencia_id
 AND t.origem_tipo=a.tipo AND t.origem_id=a.local_id AND t.origem_galpao=a.galpao AND t.destino_tipo=b.tipo AND t.destino_id=b.local_id AND t.destino_galpao=b.galpao
 AND t.variacao_id=a.material_id AND t.comprimento_mm IS NOT DISTINCT FROM a.comprimento_mm AND t.unidade=a.unidade AND t.quantidade=-a.quantidade_delta))
)
SELECT v.*,CASE WHEN saldo_origem=-quantidade AND saldo_destino=quantidade AND estornado_registro IS DISTINCT FROM true THEN 'ATIVA'
 WHEN saldo_origem=0 AND saldo_destino=0 AND estornado_registro IS DISTINCT FROM false THEN 'ESTORNADA'
 ELSE 'INCONSISTENTE' END estado
FROM verificadas v;
REVOKE ALL ON ew_compras_interna.transferencias_fisicas_custo FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_insumos_estornar_transferencia(p_empresa_id uuid, p_transferencia_operacao_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_saida public.ew_insumos_movimentos%rowtype;
 v_entrada public.ew_insumos_movimentos%rowtype;v_total integer;
 v_saldo numeric;v_op uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,'estoque.estornar')) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid)
 then raise exception 'Somente ADM pode estornar transferências.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400 or p_transferencia_operacao_id is null
 then raise exception 'Informe motivo de 5 a 400 caracteres e operação válida.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_transferencia_operacao_id::text,9011));
 select count(*) into v_total from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_transferencia_operacao_id
   and m.origem='TRANSFERENCIA';
 if v_total<>2 then raise exception 'Transferência original não encontrada ou incompleta.';end if;
 select * into v_saida from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 for update;
 select * into v_entrada from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta>0 for update;
 if v_saida.id is null or v_entrada.id is null or v_saida.insumo_id<>v_entrada.insumo_id
    or v_saida.quantidade_delta<>-v_entrada.quantidade_delta
 then raise exception 'Movimentos da transferência não conferem.';end if;
 if exists(select 1 from public.ew_insumos_movimentos m where m.estorno_de_id in (v_saida.id,v_entrada.id))
 then raise exception 'Transferência já estornada.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||v_entrada.obra_id::text||'|'||
   v_entrada.insumo_id::text||'|'||v_entrada.local_estoque,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_entrada.obra_id
   and m.insumo_id=v_entrada.insumo_id and m.local_estoque=v_entrada.local_estoque;
 if v_saldo<v_entrada.quantidade_delta then
  raise exception 'Estorno bloqueado: destino já utilizou/transferiu parte do material.';end if;
 insert into public.ew_insumos_movimentos(
  empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
  origem,operacao_id,estorno_de_id,observacao,usuario_id
 ) values
 (p_empresa_id,v_entrada.obra_id,v_entrada.insumo_id,v_entrada.local_estoque,
  -v_entrada.quantidade_delta,'ESTORNO',v_op,v_entrada.id,btrim(p_motivo),v_uid),
 (p_empresa_id,v_saida.obra_id,v_saida.insumo_id,v_saida.local_estoque,
  -v_saida.quantidade_delta,'ESTORNO',v_op,v_saida.id,btrim(p_motivo),v_uid);
 perform ew_compras_interna.custo_estornar_se_integrada(p_empresa_id,'INSUMOS',v_saida.transferencia_id,v_op);
 return jsonb_build_object('estornado',true,'operacao_estorno',v_op);
end
$function$;

CREATE OR REPLACE FUNCTION public.ew_estornar_movimento_obra(p_obra_id uuid, p_movimento_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid := auth.uid();
 v_obra public.obras%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_audit public.ew_auditoria_operacoes%rowtype;
 v_ver jsonb;
 v_mov public.ew_estoque_obras_movimentos%rowtype;
 v_motivo text := btrim(coalesce(p_motivo,''));
 v_saldo numeric;
 v_n integer := 0;
 v_par integer;
 v_soma numeric;
 v_materials integer;
 v_locais integer;
 v_local_retirada text;
 v_total_disponivel numeric;
 v_local_alocacao record;
 v_falta numeric;
 v_parcela numeric;
 v_estorno_id uuid;
 v_primeiro boolean:=true;
 v_parcelas jsonb:='[]'::jsonb;
 v_originais jsonb := '[]'::jsonb;
begin
 PERFORM public.ew_exigir_permissao('estoque.estornar');
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_obra_id is null or p_movimento_id is null or p_operacao_id is null then
  raise exception 'Obra, movimento, operação e usuário são obrigatórios.';
 end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo com 5 a 400 caracteres.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_obra from public.obras where id=p_obra_id for update;
 if not found or v_obra.arquivada_em is not null then
  raise exception 'Obra não encontrada ou já arquivada.';
 end if;
 if not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_obra.empresa_id
   and public.ew_pode(v_obra.empresa_id,'estoque.estornar')
   and ul.perfil=ue.perfil and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem realizar estornos.'; end if;
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao <> 'ESTORNAR_ESTOQUE'
   or v_audit.obra_id is distinct from p_obra_id or v_audit.usuario_id <> v_uid
   or v_audit.referencia_id is distinct from p_movimento_id
   or v_audit.detalhes->>'modo' IS DISTINCT FROM 'individual' then
   raise exception 'Identificador de operação já usado em outro estorno.';
  end if;
  return jsonb_build_object('repetida',true,
   'estornados',v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 select * into v_original from public.ew_estoque_obras_movimentos
 where id=p_movimento_id and obra_id=p_obra_id for update;
 if not found then raise exception 'Movimentação não encontrada nesta obra.'; end if;
 if v_original.origem='SAIDA_OBRA' then
   raise exception 'Saída direta de material vinculada a romaneio. Cancele o romaneio e confirme a devolução física; não faça estorno isolado.';
  end if;
 if v_original.origem='ESTORNO' then
  raise exception 'Contrapartida de estorno é somente histórico. Nunca estorne outra vez o mesmo lançamento; revise a origem.';
 end if;
 if exists(select 1 from public.ew_nfe_recebimentos n where n.movimento_id=v_original.id) then
  raise exception 'Movimento vinculado à NF-e: use Estornar recebimento na tela Recebimento.';
 end if;
 if v_original.estorno_de_id is not null then
  raise exception 'Uma contrapartida de estorno não pode ser cancelada novamente.';
 end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos e
  where e.estorno_de_id=p_movimento_id) then
  raise exception 'Esta movimentação já foi estornada.';
 end if;
 -- Fluxos vinculados devem reverter a operação completa, não apenas a perna física.
 if exists(select 1 from public.ew_compras_recebimentos_movimentos x where x.movimento_obra_id=v_original.id) then
  raise exception 'Movimento vinculado a pedido de compra. Estorne o recebimento do pedido.';
 end if;
 if exists(select 1 from public.ew_compras_transferencias t where t.movimento_origem_obra_id=v_original.id or t.movimento_destino_obra_id=v_original.id) then
  raise exception 'Movimento vinculado a transferência de local empresarial. Estorne a transferência completa.';
 end if;
 -- Entradas independentes e transferências internas dependem do material,
 -- não de liberações gerais. Baixas negativas avulsas preservam guardas antigos.
 if v_original.quantidade_delta<0 and v_original.transferencia_id is null then
  v_ver := public.ew_inspecionar_reversao_obra(p_obra_id);
  if exists (
   select 1 from pg_catalog.jsonb_array_elements_text(v_ver->'motivos') as x(motivo)
   where x.motivo not like 'Estorne as movimentações do estoque%'
  ) then
   raise exception 'Cancele romaneios, saídas e liberações e resolva outras pendências antes do estorno individual.';
  end if;
 end if;
 -- Transferência entre galpões é uma operação única de duas pernas.
 if v_original.transferencia_id is not null then
  if v_original.origem<>'TRANSFERENCIA' then
   raise exception 'Movimento de transferência possui origem inconsistente.';
  end if;
  select count(*),coalesce(sum(m.quantidade_delta),0),
   count(distinct (m.variacao_id::text||'|'||coalesce(m.comprimento_mm::text,'')||'|'||m.unidade)),
   count(distinct m.local_estoque)
  into v_par,v_soma,v_materials,v_locais
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.transferencia_id=v_original.transferencia_id;
  if v_par<>2 or v_soma<>0 or v_materials<>1 or v_locais<>2 then
   raise exception 'Transferência incompleta ou inconsistente. Não é seguro estornar uma perna isoladamente.';
  end if;
 end if;
 -- O lock por material/obra é o mesmo usado por transferências e NF-e,
 -- impedindo alteração de saldo enquanto as parcelas são planejadas.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||v_original.variacao_id::text||'|'||
  coalesce(v_original.comprimento_mm::text,'-')||'|'||v_original.unidade,34777));
 -- Transferência ENTRE GALPÕES: o estorno deve respeitar a cadeia das
 -- movimentações e nunca fingir que o material voltou fisicamente de galpão.
 -- Saldo recomposto por compra posterior não prova que o lote não foi usado.
 IF v_original.transferencia_id IS NOT NULL THEN
  SELECT * INTO v_mov FROM public.ew_estoque_obras_movimentos
  WHERE obra_id=p_obra_id AND transferencia_id=v_original.transferencia_id
    AND origem='TRANSFERENCIA' AND quantidade_delta>0
  LIMIT 1;
  IF v_mov.id IS NULL THEN
   RAISE EXCEPTION 'Crédito da transferência entre galpões não localizado.';
  END IF;
  IF EXISTS(
   SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_mov.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_mov.comprimento_mm
    AND m.unidade=v_mov.unidade AND m.criado_em>v_mov.criado_em
    AND m.quantidade_delta<0
    AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE','SAIDA_OBRA')
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id)
  ) THEN
   RAISE EXCEPTION 'Material utilizado após transferência entre galpões. Cancele o romaneio/saída e estorne a baixa de fabricação antes de desfazer a transferência.';
  END IF;
  IF EXISTS(
   SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_mov.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_mov.comprimento_mm
    AND m.unidade=v_mov.unidade AND m.criado_em>v_mov.criado_em
    AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
    AND m.transferencia_id IS DISTINCT FROM v_original.transferencia_id
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id)
  ) THEN
   RAISE EXCEPTION 'Transferência posterior do mesmo material ainda ativa. Estorne primeiro a transferência mais recente, seja para outro galpão ou outra obra.';
  END IF;
 END IF;
 -- Cancelar entrada não vinculada a NF-e: a localização física é irrelevante,
 -- mas material consumido ou transferido a outra obra continua indisponível.
 IF v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0 THEN
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade AND m.criado_em>=v_original.criado_em
    AND m.quantidade_delta<0
    AND m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE','SAIDA_OBRA')
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id))
  THEN RAISE EXCEPTION 'Material consumido na fabricação. Cancele primeiro romaneios, saídas e baixas.';END IF;
  IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade AND m.criado_em>=v_original.criado_em
    AND m.quantidade_delta<0 AND m.origem='TRANSFERENCIA'
    AND (EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos other
      WHERE other.transferencia_id=m.transferencia_id AND other.origem='TRANSFERENCIA'
       AND other.obra_id<>m.obra_id) OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t WHERE t.movimento_origem_obra_id=m.id AND t.estornado_em IS NULL))
    AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos e
      WHERE e.estorno_de_id=m.id))
  THEN RAISE EXCEPTION 'Material transferido a outra obra. Devolva-o antes de estornar a entrada.';END IF;
  IF EXISTS(
   SELECT 1 FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade
   GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)<0
  ) THEN
   RAISE EXCEPTION 'Saldo negativo em galpão da obra: concilie antes do estorno.';
  END IF;
  SELECT coalesce(sum(greatest(t.saldo,0)),0) INTO v_total_disponivel
  FROM(SELECT sum(m.quantidade_delta) saldo FROM public.ew_estoque_obras_movimentos m
    WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
     AND m.variacao_id=v_original.variacao_id
     AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
     AND m.unidade=v_original.unidade GROUP BY m.local_estoque) t;
  IF v_total_disponivel<v_original.quantidade_delta THEN
   RAISE EXCEPTION 'Saldo insuficiente na obra. Devolva material transferido ou usado antes do estorno.';
  END IF;
 END IF;
 -- Toda a obra é serializada pelo mesmo bloqueio da reversão total.
 perform 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
  and (m.id=p_movimento_id or
   (v_original.transferencia_id is not null
    and m.transferencia_id=v_original.transferencia_id))
 order by m.id for update;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  if v_mov.estorno_de_id is not null or exists(
   select 1 from public.ew_estoque_obras_movimentos s where s.estorno_de_id=v_mov.id
  ) then raise exception 'Uma das movimentações já foi estornada. Recarregue o histórico.'; end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.variacao_id=v_mov.variacao_id
   and m.comprimento_mm is not distinct from v_mov.comprimento_mm
   and m.unidade=v_mov.unidade and m.local_estoque=v_mov.local_estoque;
  if v_original.transferencia_id IS NOT NULL AND v_saldo-v_mov.quantidade_delta<0 then
   raise exception 'Estorno individual deixaria saldo negativo em % (% %). Desfaça antes as movimentações posteriores dependentes.',
    v_mov.local_estoque,v_saldo,v_mov.unidade;
  end if;
 end loop;
 IF v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0 THEN
  v_falta:=v_original.quantidade_delta;
  v_originais:=jsonb_build_array(jsonb_build_object(
   'movimento_id',v_original.id,'origem',v_original.origem,
   'quantidade',v_original.quantidade_delta,
   'variacao_id',v_original.variacao_id,
   'comprimento_mm',v_original.comprimento_mm,'unidade',v_original.unidade,
   'galpao_original',v_original.local_estoque,
   'usuario_original',v_original.usuario_id,'registrado_em',v_original.criado_em));
  FOR v_local_alocacao IN
   SELECT m.local_estoque,sum(m.quantidade_delta) saldo
   FROM public.ew_estoque_obras_movimentos m
   WHERE m.empresa_id=v_obra.empresa_id AND m.obra_id=p_obra_id
    AND m.variacao_id=v_original.variacao_id
    AND m.comprimento_mm IS NOT DISTINCT FROM v_original.comprimento_mm
    AND m.unidade=v_original.unidade
   GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)>0
   ORDER BY (m.local_estoque=v_original.local_estoque) DESC,m.local_estoque
  LOOP
   EXIT WHEN v_falta<=0;
   v_parcela:=least(v_falta,v_local_alocacao.saldo);
   INSERT INTO public.ew_estoque_obras_movimentos
   (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
    origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
   VALUES(v_original.empresa_id,v_original.obra_id,v_original.variacao_id,
    v_original.comprimento_mm,v_original.unidade,-v_parcela,'ESTORNO',
    pg_catalog.gen_random_uuid(),left('Estorno individual: '||v_motivo,500),
    v_uid,v_local_alocacao.local_estoque,
    CASE WHEN v_primeiro THEN v_original.id ELSE NULL END)
   RETURNING id INTO v_estorno_id;
   INSERT INTO public.ew_estornos_parcelas
    (empresa_id,obra_id,operacao_id,movimento_original_id,movimento_estorno_id,
     local_estoque,quantidade)
   VALUES(v_original.empresa_id,v_original.obra_id,p_operacao_id,
    v_original.id,v_estorno_id,v_local_alocacao.local_estoque,v_parcela);
   v_primeiro:=false;
   v_n:=v_n+1;
   v_falta:=v_falta-v_parcela;
   v_parcelas:=v_parcelas||jsonb_build_array(jsonb_build_object(
    'galpao',v_local_alocacao.local_estoque,'quantidade',v_parcela,
    'movimento_estorno_id',v_estorno_id,'movimento_original_id',v_original.id));
  END LOOP;
  IF v_falta<>0 THEN
   RAISE EXCEPTION 'Não foi possível alocar todas as parcelas. Operação cancelada.';
  END IF;
 ELSE
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  insert into public.ew_estoque_obras_movimentos (
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id
  ) values (
   v_mov.empresa_id,v_mov.obra_id,v_mov.variacao_id,v_mov.comprimento_mm,
   v_mov.unidade,-v_mov.quantidade_delta,'ESTORNO',pg_catalog.gen_random_uuid(),
   left('Estorno individual: '||v_motivo,500),v_uid,
   CASE WHEN v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0
    THEN v_local_retirada ELSE v_mov.local_estoque END,v_mov.id
  );
  v_n:=v_n+1;
  v_originais:=v_originais||jsonb_build_array(jsonb_build_object(
   'movimento_id',v_mov.id,'origem',v_mov.origem,'quantidade',v_mov.quantidade_delta,
   'variacao_id',v_mov.variacao_id,'comprimento_mm',v_mov.comprimento_mm,
   'unidade',v_mov.unidade,'galpao',v_mov.local_estoque,
   'usuario_original',v_mov.usuario_id,'registrado_em',v_mov.criado_em,
   'transferencia_id',v_mov.transferencia_id,
   'galpao_do_estorno',CASE WHEN v_original.transferencia_id IS NULL AND v_original.quantidade_delta>0
    THEN v_local_retirada ELSE v_mov.local_estoque END
  ));
 end loop;
 END IF;
 insert into public.ew_auditoria_operacoes (
  empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
  referencia_id,operacao_id,motivo,detalhes
 ) values (
  v_obra.empresa_id,p_obra_id,v_obra.nome,v_obra.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_movimento_id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','individual','movimentos_estornados',v_n,
   'movimentos_originais',v_originais,
   'parcelas',v_parcelas)
 );
 IF v_original.transferencia_id IS NOT NULL THEN
  PERFORM ew_compras_interna.custo_estornar_se_integrada(v_obra.empresa_id,'OBRAS',v_original.transferencia_id,p_operacao_id);
 END IF;
 return jsonb_build_object('repetida',false,'estornados',v_n,
  'historico_preservado',true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.ew_insumos_transferir(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_insumo_id uuid, p_origem_local text, p_destino_local text, p_quantidade numeric, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_saldo numeric;v_qtd integer;v_transfer uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,case when p_origem_obra_id=p_destino_obra_id then 'estoque.transferir_galpoes' else 'estoque.transferir_obras' end)) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
 then raise exception 'Somente ADM transfere estes materiais.';end if;
 if p_operacao_id is null or p_origem_obra_id is null or p_destino_obra_id is null
  or p_insumo_id is null or (p_origem_obra_id=p_destino_obra_id and v_origem=v_destino)
  or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
  or p_quantidade<>round(p_quantidade,3) or length(coalesce(p_observacao,''))>400
 then raise exception 'Transferência inválida.';end if;
 if not exists(select 1 from public.ew_insumos_catalogo c where c.id=p_insumo_id
    and c.empresa_id=p_empresa_id and c.ativo)
 then raise exception 'Material não pertence à empresa ou está inativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_origem and l.ativo)
 or not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_destino and l.ativo)
 then raise exception 'Galpão de origem/destino inválido.';end if;
 if not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_origem_obra_id and l.excluido_em is null)
 or not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_destino_obra_id and l.excluido_em is null)
 then raise exception 'Obras com estoque ativo são obrigatórias.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,9011));
 select count(*) into v_qtd from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.origem='TRANSFERENCIA';
 if v_qtd>0 then
   if v_qtd<>2 or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_origem_obra_id and m.local_estoque=v_origem
     and m.quantidade_delta=-p_quantidade
   ) or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_destino_obra_id and m.local_estoque=v_destino
     and m.quantidade_delta=p_quantidade
   ) then raise exception 'Operação já utilizada em outra transferência.';end if;
   return jsonb_build_object('ja_registrado',true);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_origem_obra_id::text||'|'||
   p_insumo_id::text||'|'||v_origem,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo
 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
  and m.obra_id=p_origem_obra_id and m.insumo_id=p_insumo_id
  and m.local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente na origem. Disponível: %',v_saldo;end if;
 insert into public.ew_insumos_movimentos(
   empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
   operacao_id,transferencia_id,observacao,usuario_id
 ) values
 (p_empresa_id,p_origem_obra_id,p_insumo_id,v_origem,-p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid),
 (p_empresa_id,p_destino_obra_id,p_insumo_id,v_destino,p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid);
 perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'INSUMOS',v_transfer);
 return jsonb_build_object('transferencia_id',v_transfer,'ja_registrado',false);
end
$function$;

CREATE OR REPLACE FUNCTION ew_compras_interna.custo_primeira_transferencia(p_empresa uuid, p_fluxo text, p_transferencia uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE t record; x record; ev record; l uuid; f uuid; al jsonb; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 SELECT * INTO STRICT t FROM ew_compras_interna.transferencias_fisicas_custo WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
 IF NOT public.ew_pode(p_empresa,CASE WHEN (t.origem_tipo,t.origem_id)=(t.destino_tipo,t.destino_id) THEN 'estoque.transferir_galpoes' ELSE 'estoque.transferir_obras' END) THEN RAISE EXCEPTION 'Sem autorização para transferir'; END IF;
 IF t.estado<>'ATIVA' THEN RAISE EXCEPTION 'Transferência física inválida'; END IF;
 al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
 IF al IS NULL THEN
  IF (t.origem_tipo,t.origem_id)=(t.destino_tipo,t.destino_id) THEN RETURN false; END IF;
  -- Legado: somente primeira transferência com origem inequívoca.
  SELECT * INTO x FROM ew_compras_interna.previa_apropriacao_transferencias WHERE empresa_id=p_empresa AND fluxo=p_fluxo AND transferencia_id=p_transferencia;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO STRICT ev FROM ew_compras_interna.lotes_aquisicao_evidencias WHERE empresa_id=p_empresa AND fonte=x.fonte AND item_fiscal_id=x.item_fiscal_id AND movimento_id=x.lote_movimento_id;
  l:=ew_compras_interna.custo_abrir_lote(p_empresa,ev.fonte,ev.item_fiscal_id,ev.movimento_id,ev.categoria,ev.quantidade,ev.custo_centavos,ev.local_tipo,ev.local_id,ev.galpao);
  al:=ew_compras_interna.custo_alocar_saldo_comprovado(p_empresa,t.origem_movimento_id);
  IF al IS NULL THEN RAISE EXCEPTION 'Histórico de custo não conciliado'; END IF;
 END IF;
 PERFORM ew_compras_interna.custo_integrar_transferencia(p_empresa,p_fluxo,p_transferencia,al,uid);
 RETURN true;
END;$function$;

CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_obra(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;v_saldo numeric;
BEGIN
 PERFORM public.ew_exigir_permissao('estoque.transferir_galpoes');
  PERFORM public.ew_exigir_sessao_atual();
 if v_uid is null or p_operacao_id is null or not exists(select 1 from public.usuarios_empresas ue
   where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid and public.ew_pode(p_empresa_id,'estoque.transferir_galpoes'))
 then raise exception 'Somente ADM pode transferir estoque.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('TRANSF_OBRAS|'||p_operacao_id::text,62841));
 if exists(select 1 from public.ew_estoque_obras_movimentos where transferencia_id=p_operacao_id) then
 if (select count(*) from public.ew_estoque_obras_movimentos where transferencia_id=p_operacao_id)<>2
 or not exists(select 1 from public.ew_estoque_obras_movimentos m where m.transferencia_id=p_operacao_id and m.empresa_id=p_empresa_id and m.obra_id=p_obra_id and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm and m.unidade=p_unidade and m.local_estoque=v_origem and m.quantidade_delta=-p_quantidade and m.origem='TRANSFERENCIA')
 or not exists(select 1 from public.ew_estoque_obras_movimentos m where m.transferencia_id=p_operacao_id and m.empresa_id=p_empresa_id and m.obra_id=p_obra_id and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm and m.unidade=p_unidade and m.local_estoque=v_destino and m.quantidade_delta=p_quantidade and m.origem='TRANSFERENCIA')
 then raise exception 'Identificador já utilizado para outra transferência.';end if;
 return jsonb_build_object('repetida',true);end if;
 if v_origem=v_destino or not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_origem and ativo)
   or not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_destino and ativo)
 then raise exception 'Selecione galpões de origem e destino diferentes e válidos.';end if;
 if not exists(select 1 from public.ew_estoques_locais where empresa_id=p_empresa_id
   and obra_id=p_obra_id and excluido_em is null)
 then raise exception 'Estoque da obra arquivado ou inexistente.';end if;
 select tipo into v_tipo from public.ew_materiais_variacoes where id=p_variacao_id
   and empresa_id=p_empresa_id and ativo;
 if v_tipo is null or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
   or (v_tipo='perfil' and (p_unidade<>'BARRA' or p_comprimento_mm not between 100 and 20000
     or p_quantidade<>trunc(p_quantidade)))
   or (v_tipo='acessorio' and (p_comprimento_mm is not null or p_unidade not in ('PC','PR','CJ','MT','KG','UN')))
 then raise exception 'Material, comprimento ou quantidade inválidos.';end if;
 if char_length(btrim(coalesce(p_observacao,'')))<5 then raise exception 'Informe motivo da transferência.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||p_variacao_id::text||'|'||coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade,34777));
 select coalesce(sum(quantidade_delta),0) into v_saldo
 from public.ew_estoque_obras_movimentos where empresa_id=p_empresa_id and obra_id=p_obra_id
 and variacao_id=p_variacao_id and comprimento_mm is not distinct from p_comprimento_mm
 and unidade=p_unidade and local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente no galpão %. Disponível % %.',v_origem,v_saldo,p_unidade;end if;
 insert into public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,
  operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 values
 (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,-p_quantidade,'TRANSFERENCIA',
  gen_random_uuid(),p_observacao,v_uid,v_origem,p_operacao_id),
 (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,p_quantidade,'TRANSFERENCIA',
  gen_random_uuid(),p_observacao,v_uid,v_destino,p_operacao_id);
 perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'OBRAS',p_operacao_id);
 return jsonb_build_object('repetida',false,'origem',v_origem,'destino',v_destino,'quantidade',p_quantidade);
end;$function$;
REVOKE ALL ON FUNCTION public.ew_transferir_estoque_obra(uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_transferir_estoque_obra(uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid) TO authenticated;
-- custo_estoques_proprios
-- Apenas pares físicos completos, com identidade, empresa e quantidade verificadas.
-- Pares ausentes ou inconsistentes não autorizam apropriação. Não remove pendências.
CREATE OR REPLACE VIEW ew_compras_interna.transferencias_fisicas_custo WITH (security_invoker=true) AS
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
 AND b.tipo_material=a.tipo_material AND b.tipo='OBRA' AND (b.local_id,b.galpao)<>(a.local_id,a.galpao)
 AND b.origem='TRANSFERENCIA' AND b.quantidade_delta>0
 WHERE a.tipo='OBRA' AND a.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND a.transferencia_id IS NOT NULL
 AND (SELECT count(*) FROM movimentos k WHERE k.empresa_id=a.empresa_id AND k.transferencia_id=a.transferencia_id AND k.tipo_material=a.tipo_material AND k.tipo='OBRA' AND k.origem='TRANSFERENCIA')=2
 UNION ALL
 SELECT t.empresa_id,'LOCAIS',t.id,coalesce(t.movimento_origem_obra_id,t.movimento_origem_empresa_id),
 coalesce(t.movimento_destino_obra_id,t.movimento_destino_empresa_id),t.estornado_em IS NOT NULL
 FROM public.ew_compras_transferencias t
), verificadas AS (
 SELECT p.empresa_id,p.fluxo,p.transferencia_id,a.id origem_movimento_id,b.id destino_movimento_id,
 a.tipo origem_tipo,a.local_id origem_id,a.galpao origem_galpao,b.tipo destino_tipo,b.local_id destino_id,b.galpao destino_galpao,
 a.tipo_material,a.material_id,a.comprimento_mm,a.unidade,-a.quantidade_delta quantidade,a.criado_em,
 a.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=a.empresa_id AND z.tipo=a.tipo AND z.tipo_material=a.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=a.id OR (a.tipo='OBRA' AND a.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=a.empresa_id AND ep.obra_id=a.local_id AND ep.movimento_original_id=a.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_origem,
 b.quantidade_delta+coalesce((SELECT sum(z.quantidade_delta) FROM movimentos z WHERE z.empresa_id=b.empresa_id AND z.tipo=b.tipo AND z.tipo_material=b.tipo_material AND (z.origem='ESTORNO' OR (z.tipo='EMPRESA' AND z.origem='ESTORNO_TRANSFERENCIA'))
 AND (z.estorno_de_id=b.id OR (b.tipo='OBRA' AND b.tipo_material='TECNICO' AND EXISTS(
 SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=b.empresa_id AND ep.obra_id=b.local_id AND ep.movimento_original_id=b.id AND ep.movimento_estorno_id=z.id
 AND ep.quantidade=abs(z.quantidade_delta) AND ep.local_estoque=z.galpao)))),0) saldo_destino,
 p.estornado_registro
 FROM pares p JOIN movimentos a ON a.empresa_id=p.empresa_id AND a.id=p.origem_movimento_id
 JOIN movimentos b ON b.empresa_id=p.empresa_id AND b.id=p.destino_movimento_id
 WHERE a.origem='TRANSFERENCIA' AND b.origem='TRANSFERENCIA' AND a.quantidade_delta<0 AND b.quantidade_delta=-a.quantidade_delta
 AND a.tipo_material=b.tipo_material AND a.material_id=b.material_id AND a.comprimento_mm IS NOT DISTINCT FROM b.comprimento_mm
 AND a.unidade=b.unidade AND (a.tipo,a.local_id,a.galpao)<>(b.tipo,b.local_id,b.galpao)
 AND (p.fluxo<>'LOCAIS' OR EXISTS(SELECT 1 FROM public.ew_compras_transferencias t WHERE t.empresa_id=p.empresa_id AND t.id=p.transferencia_id
 AND t.origem_tipo=a.tipo AND t.origem_id=a.local_id AND t.origem_galpao=a.galpao AND t.destino_tipo=b.tipo AND t.destino_id=b.local_id AND t.destino_galpao=b.galpao
 AND t.variacao_id=a.material_id AND t.comprimento_mm IS NOT DISTINCT FROM a.comprimento_mm AND t.unidade=a.unidade AND t.quantidade=-a.quantidade_delta))
)
SELECT v.*,CASE WHEN saldo_origem=-quantidade AND saldo_destino=quantidade AND estornado_registro IS DISTINCT FROM true THEN 'ATIVA'
 WHEN saldo_origem=0 AND saldo_destino=0 AND estornado_registro IS DISTINCT FROM false THEN 'ESTORNADA'
 ELSE 'INCONSISTENTE' END estado
FROM verificadas v;
REVOKE ALL ON ew_compras_interna.transferencias_fisicas_custo FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.ew_compras_estornar_transferencia(p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_t public.ew_compras_transferencias%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_key1 text;v_key2 text;v_saldo numeric;v_destino_criado timestamptz;v_destino uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if p_transferencia_id is null or p_operacao_id is null or v_uid is null
 then raise exception 'Sessão ou operação inválida.';end if;
 if length(v_motivo) not between 5 and 400 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 select * into v_t from public.ew_compras_transferencias where id=p_transferencia_id for update;
 if not found then raise exception 'Transferência inexistente.';end if;
 if not public.ew_pode(v_t.empresa_id,'estoque.estornar') then
  raise exception 'Sem permissão para estornar transferência.';end if;
 if v_t.estornado_em is not null then
  if v_t.estorno_operacao_id=p_operacao_id then
   return jsonb_build_object('id',v_t.id,'ja_estornado',true,'repetida',true);
  end if;
  raise exception 'Transferência já estornada.';end if;
 if exists(select 1 from public.ew_compras_transferencias t where
   t.estorno_operacao_id=p_operacao_id and t.id<>v_t.id)
 then raise exception 'Identificador de estorno já utilizado.';end if;
 v_key1:=case when v_t.origem_tipo='OBRA' then v_t.origem_id::text else
  'COMPRA_EMPRESA|'||v_t.origem_id::text end||'|'||v_t.variacao_id::text||'|'||
  coalesce(v_t.comprimento_mm::text,'-')||'|'||v_t.unidade;
 v_key2:=case when v_t.destino_tipo='OBRA' then v_t.destino_id::text else
  'COMPRA_EMPRESA|'||v_t.destino_id::text end||'|'||v_t.variacao_id::text||'|'||
  coalesce(v_t.comprimento_mm::text,'-')||'|'||v_t.unidade;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key1,v_key2),34777));
 if v_key2<>v_key1 then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key1,v_key2),34777));
 end if;
 if v_t.destino_tipo='OBRA' then
  select m.criado_em into v_destino_criado from public.ew_estoque_obras_movimentos m
  where m.id=v_t.movimento_destino_obra_id and m.empresa_id=v_t.empresa_id
    and m.obra_id=v_t.destino_id and m.quantidade_delta=v_t.quantidade
    and m.origem='TRANSFERENCIA';
  if not found then raise exception 'Movimento do destino não confere.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
   where m.empresa_id=v_t.empresa_id and m.obra_id=v_t.destino_id
     and m.variacao_id=v_t.variacao_id
     and m.comprimento_mm is not distinct from v_t.comprimento_mm
     and m.unidade=v_t.unidade and m.local_estoque=v_t.destino_galpao
     and m.quantidade_delta<0 and m.origem<>'ESTORNO' and m.criado_em>=v_destino_criado
       and not exists(select 1 from public.ew_estoque_obras_movimentos rev where rev.estorno_de_id=m.id))
  then raise exception 'Destino possui saídas posteriores. Desfaça dependências antes do estorno.';end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=v_t.empresa_id and m.obra_id=v_t.destino_id
    and m.variacao_id=v_t.variacao_id
    and m.comprimento_mm is not distinct from v_t.comprimento_mm
    and m.unidade=v_t.unidade and m.local_estoque=v_t.destino_galpao;
 else
  select m.criado_em into v_destino_criado from public.ew_compras_estoque_empresa m
  where m.id=v_t.movimento_destino_empresa_id and m.empresa_id=v_t.empresa_id
    and m.local_empresa_id=v_t.destino_id and m.quantidade_delta=v_t.quantidade
    and m.origem='TRANSFERENCIA';
  if not found then raise exception 'Movimento empresarial do destino não confere.';end if;
  if exists(select 1 from public.ew_compras_estoque_empresa m
    where m.empresa_id=v_t.empresa_id and m.local_empresa_id=v_t.destino_id
      and m.variacao_id=v_t.variacao_id
      and m.comprimento_mm is not distinct from v_t.comprimento_mm
      and m.unidade=v_t.unidade and m.galpao=v_t.destino_galpao
      and m.quantidade_delta<0 and m.origem not in ('ESTORNO_PEDIDO','ESTORNO_TRANSFERENCIA')
       and m.criado_em>=v_destino_criado
       and not exists(select 1 from public.ew_compras_estoque_empresa rev where rev.estorno_de_id=m.id))
  then raise exception 'Destino possui saídas posteriores. Desfaça dependências antes do estorno.';end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_compras_estoque_empresa m
  where m.empresa_id=v_t.empresa_id and m.local_empresa_id=v_t.destino_id
    and m.variacao_id=v_t.variacao_id
    and m.comprimento_mm is not distinct from v_t.comprimento_mm
    and m.unidade=v_t.unidade and m.galpao=v_t.destino_galpao;
 end if;
 if v_saldo<v_t.quantidade then raise exception 'Saldo físico insuficiente no destino.';end if;

 -- A saída original e a entrada de destino são revertidas em uma única transação.
 if v_t.destino_tipo='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(v_t.empresa_id,v_t.destino_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   -v_t.quantidade,'ESTORNO',gen_random_uuid(),left('Estorno transferência: '||v_motivo,500),
   v_uid,v_t.destino_galpao,v_t.movimento_destino_obra_id);
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,estorno_de_id,transferencia_id)
  values(v_t.empresa_id,v_t.destino_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.destino_galpao,-v_t.quantidade,'ESTORNO_TRANSFERENCIA',v_t.movimento_destino_empresa_id,
   v_t.operacao_id);
 end if;
 if v_t.origem_tipo='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(v_t.empresa_id,v_t.origem_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.quantidade,'ESTORNO',gen_random_uuid(),left('Estorno transferência: '||v_motivo,500),
   v_uid,v_t.origem_galpao,v_t.movimento_origem_obra_id);
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,estorno_de_id,transferencia_id)
  values(v_t.empresa_id,v_t.origem_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.origem_galpao,v_t.quantidade,'ESTORNO_TRANSFERENCIA',v_t.movimento_origem_empresa_id,
   v_t.operacao_id);
 end if;
 update public.ew_compras_transferencias set
  estornado_em=now(),estornado_por=v_uid,estorno_motivo=v_motivo,
  estorno_operacao_id=p_operacao_id where id=v_t.id;
 perform ew_compras_interna.custo_estornar_se_integrada(v_t.empresa_id,'LOCAIS',v_t.id,p_operacao_id);
 return jsonb_build_object('id',v_t.id,'repetida',false,'estornado',true);
end;$function$;

CREATE OR REPLACE FUNCTION public.ew_compras_transferir_locais(p_empresa_id uuid, p_origem_tipo text, p_origem_id uuid, p_destino_tipo text, p_destino_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_galpao text, p_destino_galpao text, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_tipo1 text:=upper(btrim(coalesce(p_origem_tipo,'')));
 v_tipo2 text:=upper(btrim(coalesce(p_destino_tipo,'')));
 v_galpao1 text:=upper(btrim(coalesce(p_origem_galpao,'')));
 v_galpao2 text:=upper(btrim(coalesce(p_destino_galpao,'')));
 v_un text:=upper(btrim(coalesce(p_unidade,'')));
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_var public.ew_materiais_variacoes%rowtype;
 v_unidade_cadastro text;v_key1 text;v_key2 text;v_saldo numeric;
 v_trans public.ew_compras_transferencias%rowtype;
 v_origem_mov uuid;v_destino_mov uuid;v_novo_id uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_operacao_id is null then
  raise exception 'Sessão ou operação inválida.';end if;
 if not public.ew_pode(p_empresa_id,'estoque.transferir_obras') then
  raise exception 'Sem permissão para transferência entre locais.';end if;
 if v_tipo1 not in ('OBRA','EMPRESA') or v_tipo2 not in ('OBRA','EMPRESA') or
    p_origem_id is null or p_destino_id is null or
    (v_tipo1=v_tipo2 and p_origem_id=p_destino_id and v_galpao1=v_galpao2)
 then raise exception 'Informe origem e destino de estoque diferentes.';end if;
 -- Obra -> obra continua no fluxo legado, inclusive romaneio automático.
 if v_tipo1='OBRA' and v_tipo2='OBRA' then
  raise exception 'Para transferir entre duas obras, utilize Transferência entre obras.';
 end if;
 if length(v_motivo) not between 5 and 350 then
  raise exception 'Informe motivo de 5 a 350 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('COMPRAS_TRANSF|'||p_operacao_id::text,95823));
 select * into v_trans from public.ew_compras_transferencias where operacao_id=p_operacao_id;
 if found then
  if v_trans.empresa_id<>p_empresa_id or v_trans.origem_tipo<>v_tipo1 or
   v_trans.origem_id<>p_origem_id or v_trans.destino_tipo<>v_tipo2 or
   v_trans.destino_id<>p_destino_id or v_trans.variacao_id<>p_variacao_id or
   v_trans.comprimento_mm is distinct from p_comprimento_mm or v_trans.unidade<>v_un or
   v_trans.quantidade<>p_quantidade or v_trans.origem_galpao<>v_galpao1 or
   v_trans.destino_galpao<>v_galpao2 or v_trans.estornado_em is not null
  then raise exception 'Identificador de transferência já utilizado para outra operação.';end if;
  return jsonb_build_object('id',v_trans.id,'repetida',true);
 end if;
 if not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_galpao1 and ativo) or
    not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_galpao2 and ativo)
 then raise exception 'Galpão físico de origem/destino inválido.';end if;
 if (v_tipo1='OBRA' and not exists(select 1 from public.obras o
   join public.ew_estoques_locais l on l.obra_id=o.id and l.empresa_id=o.empresa_id
    where o.id=p_origem_id and o.empresa_id=p_empresa_id
     and o.arquivada_em is null and l.excluido_em is null))
 or (v_tipo2='OBRA' and not exists(select 1 from public.obras o
   join public.ew_estoques_locais l on l.obra_id=o.id and l.empresa_id=o.empresa_id
    where o.id=p_destino_id and o.empresa_id=p_empresa_id
     and o.arquivada_em is null and l.excluido_em is null))
 or (v_tipo1='EMPRESA' and not exists(select 1 from public.ew_compras_locais_empresa
    where id=p_origem_id and empresa_id=p_empresa_id and ativo))
 or (v_tipo2='EMPRESA' and not exists(select 1 from public.ew_compras_locais_empresa
    where id=p_destino_id and empresa_id=p_empresa_id and ativo))
 then raise exception 'Local de estoque inexistente, arquivado ou de outra empresa.';end if;
 select * into v_var from public.ew_materiais_variacoes
 where id=p_variacao_id and empresa_id=p_empresa_id and ativo;
 if not found then raise exception 'Material sem vínculo com esta empresa.';end if;
 if v_var.tipo='acessorio' then
  select upper(btrim(a.unidade_item)) into v_unidade_cadastro from public.ew_acessorios a
  where a.id=v_var.acessorio_id and a.empresa_id=p_empresa_id;
  if v_un<>v_unidade_cadastro then raise exception 'Unidade do acessório não coincide com o cadastro.';end if;
 end if;
 if p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000 or
   p_quantidade<>round(p_quantidade,3) or
   (v_var.tipo='perfil' and (v_un<>'BARRA' or p_comprimento_mm not between 100 and 20000)) or
   (v_var.tipo<>'perfil' and (v_un not in ('PC','PR','CJ','MT','KG','UN') or p_comprimento_mm is not null)) or
   (v_un in ('BARRA','PC','PR','CJ','UN','MT') and p_quantidade<>trunc(p_quantidade))
 then raise exception 'Quantidade, unidade ou comprimento inválido.';end if;

 v_key1:=case when v_tipo1='OBRA' then p_origem_id::text else
  'COMPRA_EMPRESA|'||p_origem_id::text end||'|'||p_variacao_id::text||'|'||
  coalesce(p_comprimento_mm::text,'-')||'|'||v_un;
 v_key2:=case when v_tipo2='OBRA' then p_destino_id::text else
  'COMPRA_EMPRESA|'||p_destino_id::text end||'|'||p_variacao_id::text||'|'||
  coalesce(p_comprimento_mm::text,'-')||'|'||v_un;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key1,v_key2),34777));
 if v_key2<>v_key1 then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key1,v_key2),34777));
 end if;

 if v_tipo1='OBRA' then
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=p_origem_id
    and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm
    and m.unidade=v_un and m.local_estoque=v_galpao1;
 else
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_compras_estoque_empresa m
  where m.empresa_id=p_empresa_id and m.local_empresa_id=p_origem_id
    and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm
    and m.unidade=v_un and m.galpao=v_galpao1;
 end if;
 if v_saldo<p_quantidade then
  raise exception 'Saldo insuficiente na origem: % %. Transferência não realizada.',v_saldo,v_un;
 end if;
 if v_tipo1='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_origem_id,p_variacao_id,p_comprimento_mm,v_un,-p_quantidade,
    'TRANSFERENCIA',gen_random_uuid(),left('Transferência local '||p_operacao_id::text||': '||v_motivo,500),v_uid,v_galpao1)
  returning id into v_origem_mov;
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,transferencia_id)
  values(p_empresa_id,p_origem_id,p_variacao_id,p_comprimento_mm,v_un,v_galpao1,
    -p_quantidade,'TRANSFERENCIA',p_operacao_id) returning id into v_origem_mov;
 end if;
 if v_tipo2='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_destino_id,p_variacao_id,p_comprimento_mm,v_un,p_quantidade,
    'TRANSFERENCIA',gen_random_uuid(),left('Transferência local '||p_operacao_id::text||': '||v_motivo,500),v_uid,v_galpao2)
  returning id into v_destino_mov;
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,transferencia_id)
  values(p_empresa_id,p_destino_id,p_variacao_id,p_comprimento_mm,v_un,v_galpao2,
    p_quantidade,'TRANSFERENCIA',p_operacao_id) returning id into v_destino_mov;
 end if;
 insert into public.ew_compras_transferencias(
  empresa_id,operacao_id,origem_tipo,origem_id,destino_tipo,destino_id,
  origem_galpao,destino_galpao,variacao_id,comprimento_mm,unidade,quantidade,motivo,
  movimento_origem_obra_id,movimento_destino_obra_id,
  movimento_origem_empresa_id,movimento_destino_empresa_id,criado_por)
 values(p_empresa_id,p_operacao_id,v_tipo1,p_origem_id,v_tipo2,p_destino_id,
  v_galpao1,v_galpao2,p_variacao_id,p_comprimento_mm,v_un,p_quantidade,v_motivo,
  case when v_tipo1='OBRA' then v_origem_mov else null end,
  case when v_tipo2='OBRA' then v_destino_mov else null end,
  case when v_tipo1='EMPRESA' then v_origem_mov else null end,
  case when v_tipo2='EMPRESA' then v_destino_mov else null end,v_uid)
 returning id into v_novo_id;
 perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'LOCAIS',v_novo_id);
 return jsonb_build_object('id',v_novo_id,'repetida',false,
   'saldo_origem',v_saldo-p_quantidade,'quantidade',p_quantidade);
end;$function$;

-- custo_nota_dividida
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

DO $check$ BEGIN IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='ew_compras_interna'::regnamespace AND proname LIKE 'custo_%' AND (has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('authenticated',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'Funções de custo expostas'; END IF; IF EXISTS(SELECT 1 FROM pg_class WHERE relnamespace='ew_compras_interna'::regnamespace AND relkind='r' AND relname LIKE 'custo_%' AND (NOT relrowsecurity OR has_table_privilege('anon',oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated',oid,'SELECT,INSERT,UPDATE,DELETE'))) THEN RAISE EXCEPTION 'Tabela de custo desprotegida'; END IF; END $check$;
