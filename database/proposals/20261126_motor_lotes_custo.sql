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
