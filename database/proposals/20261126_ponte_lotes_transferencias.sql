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
