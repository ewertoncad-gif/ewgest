-- EWGEST 46.29.41 — classificação de competência e reconhecimento explícito de custo de material.
-- Não movimenta estoque, caixa ou documentos originais. Resultado sempre parcial até fechamento contábil.
BEGIN;
CREATE TABLE ew_financeiro_interna.classificacoes_resultado (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,titulo_id uuid NOT NULL,operacao_id uuid NOT NULL,
 versao integer NOT NULL CHECK(versao>0),classe text NOT NULL CHECK(classe IN ('RECEITA_OPERACIONAL','OUTRAS_RECEITAS','DEDUCOES','CUSTO_MAO_OBRA','CUSTO_INDIRETO','CUSTO_SERVICOS','DESPESA_ADMIN','DESPESA_COMERCIAL','DESPESA_FINANCEIRA','IMPOSTO_LUCRO','FORA_RESULTADO')),
 motivo text NOT NULL CHECK(length(btrim(motivo)) BETWEEN 5 AND 400),criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(empresa_id,titulo_id) REFERENCES ew_financeiro_interna.titulos(empresa_id,id),UNIQUE(empresa_id,operacao_id),UNIQUE(empresa_id,titulo_id,versao)
);
ALTER TABLE ew_financeiro_interna.classificacoes_resultado ENABLE ROW LEVEL SECURITY;
CREATE VIEW ew_financeiro_interna.classificacao_atual AS SELECT DISTINCT ON (empresa_id,titulo_id) * FROM ew_financeiro_interna.classificacoes_resultado ORDER BY empresa_id,titulo_id,versao DESC;
CREATE VIEW ew_financeiro_interna.consumo_comprovado AS
 SELECT m.empresa_id,m.id movimento_id,m.obra_id,
 CASE WHEN m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND l.cancelado_em IS NULL THEN e.id END esquadria_id,
 CASE WHEN m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND e.id IS NOT NULL AND l.cancelado_em IS NULL THEN nullif(btrim(l.fabrica),'')
 WHEN m.origem='PLANO_CORTE_LOTE' AND b.id IS NOT NULL AND b.cancelado_em IS NULL THEN nullif(btrim(b.fabrica),'') END fabrica,
 m.criado_em,(m.criado_em AT TIME ZONE 'America/Recife')::date data_consumo, c.quantidade,a.cents custo_centavos
 FROM public.ew_estoque_obras_movimentos m
 JOIN ew_compras_interna.custo_consumos_integrados c ON c.empresa_id=m.empresa_id AND c.movimento_id=m.id AND c.estornado_em IS NULL AND c.quantidade=-m.quantidade_delta
 LEFT JOIN public.liberacoes_corte l ON l.id=m.liberacao_id
 LEFT JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=m.empresa_id AND e.obra_id=m.obra_id
 LEFT JOIN public.ew_liberacoes_lotes b ON b.id=m.lote_id AND b.empresa_id=m.empresa_id AND b.obra_id=m.obra_id
 JOIN LATERAL (
 SELECT sum(ev.quantidade) qtd,sum(ev.custo_centavos)::bigint cents,
 bool_and(ev.destino_tipo='PRODUCAO' AND ev.destino_id=m.obra_id AND ev.destino_galpao=m.local_estoque AND EXISTS(
 SELECT 1 FROM ew_compras_interna.custo_lotes lo JOIN ew_compras_interna.lotes_aquisicao_evidencias v
 ON v.empresa_id=lo.empresa_id AND v.fonte=lo.fonte AND v.item_fiscal_id=lo.item_fiscal_id AND v.movimento_id=lo.movimento_id AND v.quantidade=lo.quantidade AND v.custo_centavos=lo.custo_centavos AND v.categoria=lo.categoria
 WHERE lo.empresa_id=ev.empresa_id AND lo.lote_id=ev.lote_id AND lo.cancelado_em IS NULL)) valido
 FROM ew_compras_interna.custo_eventos ev WHERE ev.empresa_id=m.empresa_id AND ev.operacao_id=c.operacao_custo AND ev.estornado_em IS NULL
 ) a ON a.qtd=c.quantidade AND a.valido AND a.cents>=0
 WHERE m.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND m.quantidade_delta<0
 AND ((m.origem='PLANO_CORTE' AND m.lote_id IS NULL AND e.id IS NOT NULL AND l.cancelado_em IS NULL) OR (m.origem='PLANO_CORTE_LOTE' AND b.id IS NOT NULL AND b.cancelado_em IS NULL))
 AND NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos x WHERE x.empresa_id=m.empresa_id AND x.obra_id=m.obra_id AND x.origem='ESTORNO' AND x.quantidade_delta>0
 AND (x.estorno_de_id=m.id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=m.empresa_id AND ep.movimento_original_id=m.id AND ep.movimento_estorno_id=x.id AND ep.quantidade=abs(x.quantidade_delta))));
CREATE TABLE ew_financeiro_interna.reconhecimento_material(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,movimento_id uuid NOT NULL,faturamento_id uuid NOT NULL,operacao_id uuid NOT NULL,
 obra_id uuid NOT NULL,esquadria_id uuid,fabrica text,competencia date NOT NULL,valor_centavos bigint NOT NULL CHECK(valor_centavos>0),
 motivo text NOT NULL CHECK(length(btrim(motivo)) BETWEEN 5 AND 400),criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 estornado_em timestamptz,estornado_por uuid,estorno_motivo text,estorno_operacao_id uuid,
 UNIQUE(empresa_id,operacao_id),UNIQUE(empresa_id,estorno_operacao_id),
 CHECK((estornado_em IS NULL AND estornado_por IS NULL AND estorno_motivo IS NULL AND estorno_operacao_id IS NULL) OR (estornado_em IS NOT NULL AND estornado_por IS NOT NULL AND length(btrim(estorno_motivo)) BETWEEN 5 AND 400 AND estorno_operacao_id IS NOT NULL))
);
CREATE INDEX ew_fin_reconhecimento_mov ON ew_financeiro_interna.reconhecimento_material(empresa_id,movimento_id) WHERE estornado_em IS NULL;
CREATE INDEX ew_fin_reconhecimento_data ON ew_financeiro_interna.reconhecimento_material(empresa_id,competencia);
ALTER TABLE ew_financeiro_interna.reconhecimento_material ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION ew_financeiro_interna.exigir_resultado(p_empresa uuid,p_gravar boolean DEFAULT false,p_estornar boolean DEFAULT false) RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa);
 IF NOT public.ew_pode(p_empresa,'estoque.consultar') OR NOT public.ew_pode(p_empresa,'compras.consultar_valores') THEN RAISE EXCEPTION 'Sem acesso aos custos de resultado.';END IF;
 IF p_gravar AND NOT (public.ew_pode(p_empresa,'financeiro.despesas') AND public.ew_pode(p_empresa,'financeiro.faturar')) THEN RAISE EXCEPTION 'Sem permissão para classificar resultado.';END IF;
 IF p_estornar AND NOT public.ew_pode(p_empresa,'financeiro.cancelar_despesas') THEN RAISE EXCEPTION 'Sem permissão para estornar reconhecimento.';END IF;
END $$;
CREATE FUNCTION public.ew_dre_classificar_titulo(p_empresa_id uuid,p_titulo_id uuid,p_operacao_id uuid,p_versao int,p_classe text,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE;v_old ew_financeiro_interna.classificacoes_resultado%ROWTYPE;v_versao int;v_id uuid;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=p_titulo_id FOR UPDATE;
 IF NOT FOUND OR t.cancelado_em IS NOT NULL OR t.origem_tipo<>'MANUAL' THEN RAISE EXCEPTION 'Somente títulos manuais ativos podem ser classificados.';END IF;
 IF p_operacao_id IS NULL OR p_versao IS NULL OR p_classe IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Classificação ou justificativa inválida.';END IF;
 IF (t.tipo='RECEBER' AND p_classe NOT IN ('RECEITA_OPERACIONAL','OUTRAS_RECEITAS','FORA_RESULTADO')) OR
 (t.tipo='PAGAR' AND p_classe NOT IN ('DEDUCOES','CUSTO_MAO_OBRA','CUSTO_INDIRETO','CUSTO_SERVICOS','DESPESA_ADMIN','DESPESA_COMERCIAL','DESPESA_FINANCEIRA','IMPOSTO_LUCRO','FORA_RESULTADO')) THEN RAISE EXCEPTION 'Classe incompatível com o tipo do título.';END IF;
 SELECT * INTO v_old FROM ew_financeiro_interna.classificacoes_resultado WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
 IF v_old.titulo_id<>p_titulo_id OR v_old.versao<>p_versao+1 OR v_old.classe<>p_classe OR v_old.motivo<>btrim(p_motivo) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
 RETURN jsonb_build_object('id',v_old.id,'repetido',true);END IF;
 SELECT coalesce(max(versao),0) INTO v_versao FROM ew_financeiro_interna.classificacoes_resultado WHERE empresa_id=p_empresa_id AND titulo_id=p_titulo_id;
 IF v_versao<>p_versao THEN RAISE EXCEPTION 'Classificação foi alterada. Atualize a consulta.';END IF;
 IF v_versao>0 AND NOT public.ew_pode(p_empresa_id,CASE WHEN t.tipo='PAGAR' THEN 'financeiro.cancelar_despesas' ELSE 'financeiro.cancelar_faturamento' END) THEN RAISE EXCEPTION 'Sem permissão para revisar classificação.';END IF;
 INSERT INTO ew_financeiro_interna.classificacoes_resultado(empresa_id,titulo_id,operacao_id,versao,classe,motivo,criado_por)
 VALUES(p_empresa_id,p_titulo_id,p_operacao_id,v_versao+1,p_classe,btrim(p_motivo),auth.uid()) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'versao',v_versao+1,'repetido',false);
END $$;
CREATE FUNCTION public.ew_dre_reconhecer_material(p_empresa_id uuid,p_movimento_id uuid,p_faturamento_id uuid,p_operacao_id uuid,p_valor_centavos bigint,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE c ew_financeiro_interna.consumo_comprovado%ROWTYPE;f public.ew_obra_faturamentos%ROWTYPE;v_old ew_financeiro_interna.reconhecimento_material%ROWTYPE;v_usado bigint;v_id uuid;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 IF p_operacao_id IS NULL OR p_valor_centavos IS NULL OR p_valor_centavos<=0 OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Valor ou justificativa inválidos.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_empresa_id::text||'|dre-consumo|'||p_movimento_id::text,0));
 SELECT * INTO v_old FROM ew_financeiro_interna.reconhecimento_material WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN IF v_old.movimento_id<>p_movimento_id OR v_old.faturamento_id<>p_faturamento_id OR v_old.valor_centavos<>p_valor_centavos OR v_old.motivo<>btrim(p_motivo) OR v_old.estornado_em IS NOT NULL THEN RAISE EXCEPTION 'Operação já utilizada ou estornada.';END IF;
 RETURN jsonb_build_object('id',v_old.id,'repetido',true);END IF;
 PERFORM 1 FROM ew_compras_interna.custo_consumos_integrados WHERE empresa_id=p_empresa_id AND movimento_id=p_movimento_id FOR SHARE;
 SELECT * INTO c FROM ew_financeiro_interna.consumo_comprovado WHERE empresa_id=p_empresa_id AND movimento_id=p_movimento_id;
 IF NOT FOUND OR c.custo_centavos<=0 THEN RAISE EXCEPTION 'Consumo sem custo fiscal comprovado.';END IF;
 SELECT * INTO f FROM public.ew_obra_faturamentos WHERE empresa_id=p_empresa_id AND id=p_faturamento_id FOR SHARE;
 IF NOT FOUND OR f.obra_id<>c.obra_id OR f.categoria<>'fabricacao' OR f.status<>'emitido' OR f.cancelado_em IS NOT NULL OR f.data_faturamento<c.data_consumo OR f.criado_em<c.criado_em THEN RAISE EXCEPTION 'Faturamento incompatível com o consumo.';END IF;
 IF c.esquadria_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.ew_obra_faturamentos_itens i WHERE i.empresa_id=p_empresa_id AND i.faturamento_id=f.id AND i.esquadria_id=c.esquadria_id) THEN RAISE EXCEPTION 'Faturamento não contém a esquadria do consumo.';END IF;
 SELECT coalesce(sum(valor_centavos),0)::bigint INTO v_usado FROM ew_financeiro_interna.reconhecimento_material WHERE empresa_id=p_empresa_id AND movimento_id=p_movimento_id AND estornado_em IS NULL;
 IF v_usado+p_valor_centavos>c.custo_centavos THEN RAISE EXCEPTION 'Reconhecimento supera custo comprovado disponível.';END IF;
 INSERT INTO ew_financeiro_interna.reconhecimento_material(empresa_id,movimento_id,faturamento_id,operacao_id,obra_id,esquadria_id,fabrica,competencia,valor_centavos,motivo,criado_por)
 VALUES(p_empresa_id,p_movimento_id,p_faturamento_id,p_operacao_id,c.obra_id,c.esquadria_id,c.fabrica,f.data_faturamento,p_valor_centavos,btrim(p_motivo),auth.uid()) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'repetido',false);
END $$;
CREATE FUNCTION public.ew_dre_estornar_material(p_empresa_id uuid,p_id uuid,p_operacao_id uuid,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r ew_financeiro_interna.reconhecimento_material%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,true);
 SELECT * INTO r FROM ew_financeiro_interna.reconhecimento_material WHERE empresa_id=p_empresa_id AND id=p_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reconhecimento indisponível.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_empresa_id::text||'|dre-consumo|'||r.movimento_id::text,0));
 SELECT * INTO STRICT r FROM ew_financeiro_interna.reconhecimento_material WHERE empresa_id=p_empresa_id AND id=p_id FOR UPDATE;
 IF p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Informe motivo válido.';END IF;
 IF r.estornado_em IS NOT NULL THEN IF r.estorno_operacao_id=p_operacao_id AND r.estorno_motivo=btrim(p_motivo) THEN RETURN jsonb_build_object('id',r.id,'repetido',true);END IF;RAISE EXCEPTION 'Reconhecimento já estornado.';END IF;
 UPDATE ew_financeiro_interna.reconhecimento_material SET estornado_em=now(),estornado_por=auth.uid(),estorno_motivo=btrim(p_motivo),estorno_operacao_id=p_operacao_id WHERE empresa_id=p_empresa_id AND id=p_id;
 RETURN jsonb_build_object('id',r.id,'repetido',false);
END $$;
CREATE FUNCTION public.ew_dre_consultar(p_empresa_id uuid,p_inicio date,p_fim date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_result jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Selecione período de até 367 dias.';END IF;
 WITH manuais AS MATERIALIZED (
 SELECT t.id,t.tipo,t.descricao,t.categoria,t.centro_custo,t.competencia,t.valor_centavos,coalesce(c.versao,0) versao,c.classe,c.motivo
 FROM ew_financeiro_interna.titulos t LEFT JOIN ew_financeiro_interna.classificacao_atual c ON c.empresa_id=t.empresa_id AND c.titulo_id=t.id
 WHERE t.empresa_id=p_empresa_id AND t.origem_tipo='MANUAL' AND t.cancelado_em IS NULL AND t.competencia BETWEEN p_inicio AND p_fim
 ), faturas AS MATERIALIZED (
 SELECT f.id,f.obra_id,f.categoria,f.data_faturamento,f.numero_documento,f.criado_em,round(f.valor_total*100)::bigint valor_centavos,o.nome obra
 FROM public.ew_obra_faturamentos f JOIN public.obras o ON o.empresa_id=f.empresa_id AND o.id=f.obra_id
 WHERE f.empresa_id=p_empresa_id AND f.status='emitido' AND f.cancelado_em IS NULL AND f.data_faturamento BETWEEN p_inicio AND p_fim
 ), reconhecidos AS MATERIALIZED (
 SELECT r.*,c.custo_centavos,
  (f.id IS NOT NULL AND f.categoria='fabricacao' AND f.obra_id=r.obra_id AND f.data_faturamento=r.competencia AND c.movimento_id IS NOT NULL AND c.obra_id=r.obra_id
   AND c.esquadria_id IS NOT DISTINCT FROM r.esquadria_id AND c.fabrica IS NOT DISTINCT FROM r.fabrica AND c.criado_em<=f.criado_em AND c.data_consumo<=f.data_faturamento
   AND (c.esquadria_id IS NULL OR EXISTS(SELECT 1 FROM public.ew_obra_faturamentos_itens i WHERE i.empresa_id=p_empresa_id AND i.faturamento_id=f.id AND i.esquadria_id=c.esquadria_id))
   AND c.custo_centavos>=(SELECT coalesce(sum(z.valor_centavos),0) FROM ew_financeiro_interna.reconhecimento_material z WHERE z.empresa_id=r.empresa_id AND z.movimento_id=r.movimento_id AND z.estornado_em IS NULL)) valido
 FROM ew_financeiro_interna.reconhecimento_material r LEFT JOIN faturas f ON f.id=r.faturamento_id
 LEFT JOIN ew_financeiro_interna.consumo_comprovado c ON c.empresa_id=r.empresa_id AND c.movimento_id=r.movimento_id
 WHERE r.empresa_id=p_empresa_id AND r.estornado_em IS NULL AND r.competencia BETWEEN p_inicio AND p_fim
 ), classes AS (
 SELECT classe,sum(valor_centavos)::bigint valor_centavos FROM manuais WHERE classe IS NOT NULL GROUP BY classe
 ), disponiveis AS (
 SELECT c.movimento_id,c.obra_id,c.esquadria_id,c.fabrica,c.data_consumo,c.custo_centavos,c.custo_centavos-coalesce(x.usado,0)::bigint saldo_centavos,o.nome obra,e.codigo,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'numero',f.numero_documento,'data',f.data_faturamento) ORDER BY f.data_faturamento,f.id),'[]'::jsonb) FROM faturas f
 WHERE f.categoria='fabricacao' AND f.obra_id=c.obra_id AND f.data_faturamento>=c.data_consumo AND f.criado_em>=c.criado_em AND (c.esquadria_id IS NULL OR EXISTS(SELECT 1 FROM public.ew_obra_faturamentos_itens i WHERE i.empresa_id=p_empresa_id AND i.faturamento_id=f.id AND i.esquadria_id=c.esquadria_id))) faturas
 FROM ew_financeiro_interna.consumo_comprovado c JOIN public.obras o ON o.empresa_id=c.empresa_id AND o.id=c.obra_id LEFT JOIN public.esquadrias e ON e.empresa_id=c.empresa_id AND e.id=c.esquadria_id
 LEFT JOIN LATERAL (SELECT sum(valor_centavos) usado FROM ew_financeiro_interna.reconhecimento_material r WHERE r.empresa_id=c.empresa_id AND r.movimento_id=c.movimento_id AND r.estornado_em IS NULL)x ON true
 WHERE c.empresa_id=p_empresa_id AND c.custo_centavos>coalesce(x.usado,0) AND c.data_consumo<=p_fim
 ), material_disponivel AS (SELECT * FROM disponiveis WHERE jsonb_array_length(faturas)>0)
 SELECT jsonb_build_object(
 'fabricacao_centavos',coalesce((SELECT sum(valor_centavos) FROM faturas WHERE categoria='fabricacao'),0),
 'instalacao_centavos',coalesce((SELECT sum(valor_centavos) FROM faturas WHERE categoria='instalacao'),0),
 'material_reconhecido_centavos',coalesce((SELECT sum(valor_centavos) FROM reconhecidos WHERE valido),0),
 'reconhecimentos_pendentes',(SELECT count(*) FROM reconhecidos WHERE NOT coalesce(valido,false)),
 'manuais_pendentes',(SELECT count(*) FROM manuais WHERE classe IS NULL),
 'manuais_total',(SELECT count(*) FROM manuais),
 'materiais_disponiveis_total',(SELECT count(*) FROM material_disponivel),
 'classes',coalesce((SELECT jsonb_object_agg(classe,valor_centavos) FROM classes),'{}'::jsonb),
 'manuais',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY competencia,id) FROM (SELECT * FROM manuais ORDER BY competencia,id LIMIT 500)m),'[]'::jsonb),
 'materiais',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY data_consumo,movimento_id) FROM (SELECT * FROM material_disponivel ORDER BY data_consumo,movimento_id LIMIT 500)m),'[]'::jsonb),
 'reconhecimentos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'obra_id',r.obra_id,'fabrica',r.fabrica,'competencia',r.competencia,'valor_centavos',r.valor_centavos,'motivo',r.motivo,'valido',coalesce(r.valido,false),'faturamento_id',r.faturamento_id,'movimento_id',r.movimento_id) ORDER BY r.competencia,r.id) FROM reconhecidos r),'[]'::jsonb)
 ) INTO v_result;
 RETURN v_result;
END $$;
REVOKE ALL ON ew_financeiro_interna.classificacoes_resultado,ew_financeiro_interna.classificacao_atual,ew_financeiro_interna.consumo_comprovado,ew_financeiro_interna.reconhecimento_material FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION ew_financeiro_interna.exigir_resultado(uuid,boolean,boolean) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.ew_dre_classificar_titulo(uuid,uuid,uuid,int,text,text),public.ew_dre_reconhecer_material(uuid,uuid,uuid,uuid,bigint,text),public.ew_dre_estornar_material(uuid,uuid,uuid,text),public.ew_dre_consultar(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_dre_classificar_titulo(uuid,uuid,uuid,int,text,text),public.ew_dre_reconhecer_material(uuid,uuid,uuid,uuid,bigint,text),public.ew_dre_estornar_material(uuid,uuid,uuid,text),public.ew_dre_consultar(uuid,date,date) TO authenticated;
COMMIT;
