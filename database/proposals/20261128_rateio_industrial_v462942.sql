-- EWGEST 46.29.42 — rateio analítico de custos industriais já classificados na DRE.
BEGIN;
CREATE TABLE ew_financeiro_interna.rateios_industriais(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,titulo_id uuid NOT NULL,classe_versao int NOT NULL CHECK(classe_versao>0),
 classe text NOT NULL CHECK(classe IN ('CUSTO_MAO_OBRA','CUSTO_INDIRETO','CUSTO_SERVICOS')),
 liberacao_id uuid NOT NULL,obra_id uuid NOT NULL,esquadria_id uuid NOT NULL,fabrica text NOT NULL,competencia date NOT NULL,
 operacao_id uuid NOT NULL,valor_centavos bigint NOT NULL CHECK(valor_centavos>0),
 motivo text NOT NULL CHECK(length(btrim(motivo)) BETWEEN 5 AND 400),criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 estornado_em timestamptz,estornado_por uuid,estorno_motivo text,estorno_operacao_id uuid,
 FOREIGN KEY(empresa_id,titulo_id,classe_versao) REFERENCES ew_financeiro_interna.classificacoes_resultado(empresa_id,titulo_id,versao),
 UNIQUE(empresa_id,operacao_id),UNIQUE(empresa_id,estorno_operacao_id),
 CHECK((estornado_em IS NULL AND estornado_por IS NULL AND estorno_motivo IS NULL AND estorno_operacao_id IS NULL) OR (estornado_em IS NOT NULL AND estornado_por IS NOT NULL AND length(btrim(estorno_motivo)) BETWEEN 5 AND 400 AND estorno_operacao_id IS NOT NULL))
);
ALTER TABLE ew_financeiro_interna.rateios_industriais ENABLE ROW LEVEL SECURITY;
CREATE INDEX ew_rateio_titulo ON ew_financeiro_interna.rateios_industriais(empresa_id,titulo_id) WHERE estornado_em IS NULL;
CREATE INDEX ew_rateio_data ON ew_financeiro_interna.rateios_industriais(empresa_id,competencia);
CREATE FUNCTION public.ew_rateio_industrial_criar(p_empresa_id uuid,p_titulo_id uuid,p_liberacao_id uuid,p_versao int,p_operacao_id uuid,p_valor_centavos bigint,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE;c ew_financeiro_interna.classificacao_atual%ROWTYPE;r ew_financeiro_interna.rateios_industriais%ROWTYPE;l public.liberacoes_corte%ROWTYPE;e public.esquadrias%ROWTYPE;v_usado bigint;v_id uuid;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 IF p_operacao_id IS NULL OR p_valor_centavos IS NULL OR p_valor_centavos<=0 OR p_versao IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Valor ou justificativa inválidos.';END IF;
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=p_titulo_id FOR UPDATE;
 IF NOT FOUND OR t.cancelado_em IS NOT NULL OR t.origem_tipo<>'MANUAL' OR t.tipo<>'PAGAR' THEN RAISE EXCEPTION 'Título industrial ativo indisponível.';END IF;
 SELECT * INTO r FROM ew_financeiro_interna.rateios_industriais WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
 IF r.titulo_id<>p_titulo_id OR r.liberacao_id<>p_liberacao_id OR r.classe_versao<>p_versao OR r.valor_centavos<>p_valor_centavos OR r.motivo<>btrim(p_motivo) OR r.estornado_em IS NOT NULL THEN RAISE EXCEPTION 'Operação já utilizada ou estornada.';END IF;
 RETURN jsonb_build_object('id',r.id,'repetido',true);END IF;
 SELECT * INTO c FROM ew_financeiro_interna.classificacao_atual WHERE empresa_id=p_empresa_id AND titulo_id=p_titulo_id;
 IF NOT FOUND OR c.versao<>p_versao OR c.classe NOT IN ('CUSTO_MAO_OBRA','CUSTO_INDIRETO','CUSTO_SERVICOS') THEN RAISE EXCEPTION 'Classificação industrial alterada ou indisponível.';END IF;
 SELECT lc.* INTO l FROM public.liberacoes_corte lc JOIN public.esquadrias es ON es.id=lc.esquadria_id AND es.empresa_id=p_empresa_id
 WHERE lc.id=p_liberacao_id FOR SHARE OF lc;
 IF NOT FOUND OR l.cancelado_em IS NOT NULL OR l.tipo_componente<>'completo' OR l.quantidade<=0 OR nullif(btrim(l.fabrica),'') IS NULL OR l.data_liberacao> (date_trunc('month',t.competencia::timestamp)+interval '1 month - 1 day')::date THEN RAISE EXCEPTION 'Liberação completa, ativa e compatível com a competência é obrigatória.';END IF;
 SELECT * INTO e FROM public.esquadrias WHERE empresa_id=p_empresa_id AND id=l.esquadria_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria indisponível.';END IF;
 IF t.galpao_id IS NOT NULL AND btrim(t.centro_custo)<>btrim(l.fabrica) THEN RAISE EXCEPTION 'A fábrica não corresponde ao centro de custo do título.';END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.rateios_industriais a WHERE a.empresa_id=p_empresa_id AND a.titulo_id=t.id AND a.estornado_em IS NULL AND a.classe_versao<>c.versao) THEN RAISE EXCEPTION 'Revise e estorne rateios da classificação anterior.';END IF;
 SELECT coalesce(sum(valor_centavos),0)::bigint INTO v_usado FROM ew_financeiro_interna.rateios_industriais WHERE empresa_id=p_empresa_id AND titulo_id=t.id AND estornado_em IS NULL;
 IF v_usado+p_valor_centavos>t.valor_centavos THEN RAISE EXCEPTION 'Rateio supera o saldo do custo industrial.';END IF;
 INSERT INTO ew_financeiro_interna.rateios_industriais(empresa_id,titulo_id,classe_versao,classe,liberacao_id,obra_id,esquadria_id,fabrica,competencia,operacao_id,valor_centavos,motivo,criado_por)
 VALUES(p_empresa_id,t.id,c.versao,c.classe,l.id,e.obra_id,e.id,btrim(l.fabrica),t.competencia,p_operacao_id,p_valor_centavos,btrim(p_motivo),auth.uid()) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'saldo_centavos',t.valor_centavos-v_usado-p_valor_centavos,'repetido',false);
END $$;
CREATE FUNCTION public.ew_rateio_industrial_estornar(p_empresa_id uuid,p_id uuid,p_operacao_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r ew_financeiro_interna.rateios_industriais%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,true);
 SELECT * INTO r FROM ew_financeiro_interna.rateios_industriais WHERE empresa_id=p_empresa_id AND id=p_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Rateio indisponível.';END IF;
 PERFORM 1 FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=r.titulo_id FOR UPDATE;
 SELECT * INTO STRICT r FROM ew_financeiro_interna.rateios_industriais WHERE empresa_id=p_empresa_id AND id=p_id FOR UPDATE;
 IF p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Informe motivo válido.';END IF;
 IF r.estornado_em IS NOT NULL THEN
 IF r.estorno_operacao_id=p_operacao_id AND r.estorno_motivo=btrim(p_motivo) THEN RETURN jsonb_build_object('id',r.id,'repetido',true);END IF;RAISE EXCEPTION 'Rateio já estornado.';END IF;
 UPDATE ew_financeiro_interna.rateios_industriais SET estornado_em=now(),estornado_por=auth.uid(),estorno_motivo=btrim(p_motivo),estorno_operacao_id=p_operacao_id WHERE empresa_id=p_empresa_id AND id=p_id;
 RETURN jsonb_build_object('id',r.id,'repetido',false);
END $$;
CREATE FUNCTION public.ew_rateio_industrial_consultar(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_result jsonb;v_gerencial jsonb;v_dre jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Selecione período de até 367 dias.';END IF;
 v_gerencial:=public.ew_resultados_gerenciais(p_empresa_id,p_inicio,p_fim);
 v_dre:=public.ew_dre_consultar(p_empresa_id,p_inicio,p_fim);
 WITH titulos AS MATERIALIZED (
 SELECT t.id,t.descricao,t.competencia,t.valor_centavos,t.centro_custo,t.galpao_id,c.classe,c.versao,
 coalesce(a.usado,0)::bigint usado_centavos
 FROM ew_financeiro_interna.titulos t JOIN ew_financeiro_interna.classificacao_atual c ON c.empresa_id=t.empresa_id AND c.titulo_id=t.id
 LEFT JOIN LATERAL (SELECT sum(valor_centavos) usado FROM ew_financeiro_interna.rateios_industriais r WHERE r.empresa_id=t.empresa_id AND r.titulo_id=t.id AND r.estornado_em IS NULL)a ON true
 WHERE t.empresa_id=p_empresa_id AND t.origem_tipo='MANUAL' AND t.tipo='PAGAR' AND t.cancelado_em IS NULL AND t.competencia BETWEEN p_inicio AND p_fim AND c.classe IN ('CUSTO_MAO_OBRA','CUSTO_INDIRETO','CUSTO_SERVICOS')
 ), rateios AS MATERIALIZED (
 SELECT r.id,r.titulo_id,r.obra_id,r.esquadria_id,r.liberacao_id,r.fabrica,r.competencia,r.valor_centavos,r.classe,r.motivo,o.nome obra,e.codigo,
 coalesce(t.id IS NOT NULL AND t.versao=r.classe_versao AND t.classe=r.classe AND t.competencia=r.competencia AND t.usado_centavos<=t.valor_centavos
 AND l.id IS NOT NULL AND l.cancelado_em IS NULL AND l.tipo_componente='completo' AND l.quantidade>0 AND e.id IS NOT NULL AND l.esquadria_id=e.id AND btrim(l.fabrica)=r.fabrica
 AND (t.galpao_id IS NULL OR btrim(t.centro_custo)=r.fabrica),false) valido
 FROM ew_financeiro_interna.rateios_industriais r LEFT JOIN titulos t ON t.id=r.titulo_id
 LEFT JOIN public.liberacoes_corte l ON l.id=r.liberacao_id
 LEFT JOIN public.esquadrias e ON e.empresa_id=r.empresa_id AND e.obra_id=r.obra_id AND e.id=r.esquadria_id
 LEFT JOIN public.obras o ON o.empresa_id=r.empresa_id AND o.id=r.obra_id
 WHERE r.empresa_id=p_empresa_id AND r.estornado_em IS NULL AND r.competencia BETWEEN p_inicio AND p_fim
 ), materiais AS MATERIALIZED (
 SELECT r.obra_id,r.esquadria_id,r.fabrica,r.valor_centavos
 FROM jsonb_to_recordset(v_dre->'reconhecimentos') x(id uuid,valido boolean)
 JOIN ew_financeiro_interna.reconhecimento_material r ON r.empresa_id=p_empresa_id AND r.id=x.id WHERE x.valido
 ), faturamentos AS MATERIALIZED (
 SELECT f.id,f.obra_id,round(f.valor_total*100)::bigint cents
 FROM public.ew_obra_faturamentos f WHERE f.empresa_id=p_empresa_id AND f.categoria='fabricacao' AND f.status='emitido' AND f.cancelado_em IS NULL AND f.data_faturamento BETWEEN p_inicio AND p_fim
 ), linhas AS (
 SELECT f.id doc_id,f.obra_id,i.esquadria_id,e.id item_ok,round(i.valor_total*100)::bigint cents,coalesce(i.area_m2,i.quantidade*e.largura_mm*e.altura_mm/1000000) area
 FROM faturamentos f JOIN public.ew_obra_faturamentos_itens i ON i.empresa_id=p_empresa_id AND i.faturamento_id=f.id LEFT JOIN public.esquadrias e ON e.empresa_id=p_empresa_id AND e.obra_id=f.obra_id AND e.id=i.esquadria_id
 ), docs_ok AS (
 SELECT f.id FROM faturamentos f JOIN linhas l ON l.doc_id=f.id GROUP BY f.id,f.cents HAVING sum(l.cents)=f.cents AND bool_and(l.item_ok IS NOT NULL AND l.cents>0 AND coalesce(l.area,0)>0)
 ), receita_item AS (
 SELECT l.obra_id,l.esquadria_id,sum(l.cents)::bigint receita,sum(l.area) area FROM linhas l JOIN docs_ok k ON k.id=l.doc_id GROUP BY l.obra_id,l.esquadria_id
 UNION ALL SELECT f.obra_id,NULL,sum(f.cents)::bigint,0::numeric FROM faturamentos f WHERE NOT EXISTS(SELECT 1 FROM docs_ok k WHERE k.id=f.id) GROUP BY f.obra_id
 ), por_fabrica AS (
 SELECT fabrica,sum(receita)::bigint receita_centavos,sum(material)::bigint material_centavos,sum(rateio)::bigint rateio_centavos
 FROM (
 SELECT fabrica,faturamento_centavos receita,0::bigint material,0::bigint rateio FROM jsonb_to_recordset(v_gerencial->'fabrica') x(fabrica text,faturamento_centavos bigint)
 UNION ALL SELECT fabrica,0,valor_centavos,0 FROM materiais UNION ALL SELECT fabrica,0,0,valor_centavos FROM rateios WHERE valido
 ) x GROUP BY fabrica
 ), por_obra AS (
 SELECT x.obra_id,o.nome obra,o.codigo,sum(receita)::bigint receita_centavos,sum(material)::bigint material_centavos,sum(rateio)::bigint rateio_centavos
 FROM (SELECT obra_id,cents receita,0::bigint material,0::bigint rateio FROM faturamentos UNION ALL SELECT obra_id,0,valor_centavos,0 FROM materiais UNION ALL SELECT obra_id,0,0,valor_centavos FROM rateios WHERE valido)x
 JOIN public.obras o ON o.empresa_id=p_empresa_id AND o.id=x.obra_id GROUP BY x.obra_id,o.nome,o.codigo
 ), por_item AS (
 SELECT x.obra_id,x.esquadria_id,o.nome obra,e.codigo,sum(receita)::bigint receita_centavos,sum(material)::bigint material_centavos,sum(rateio)::bigint rateio_centavos,sum(area) area_faturada
 FROM (SELECT obra_id,esquadria_id,receita,0::bigint material,0::bigint rateio,area FROM receita_item UNION ALL SELECT obra_id,esquadria_id,0,valor_centavos,0,0 FROM materiais UNION ALL SELECT obra_id,esquadria_id,0,0,valor_centavos,0 FROM rateios WHERE valido)x
 JOIN public.obras o ON o.empresa_id=p_empresa_id AND o.id=x.obra_id LEFT JOIN public.esquadrias e ON e.empresa_id=p_empresa_id AND e.obra_id=x.obra_id AND e.id=x.esquadria_id GROUP BY x.obra_id,x.esquadria_id,o.nome,e.codigo
 ), liberacoes AS (
 SELECT l.id,e.obra_id,e.id esquadria_id,o.nome obra,e.codigo,btrim(l.fabrica) fabrica,l.quantidade,l.data_liberacao
 FROM public.liberacoes_corte l JOIN public.esquadrias e ON e.id=l.esquadria_id AND e.empresa_id=p_empresa_id JOIN public.obras o ON o.empresa_id=e.empresa_id AND o.id=e.obra_id
 WHERE l.cancelado_em IS NULL AND l.tipo_componente='completo' AND l.quantidade>0 AND nullif(btrim(l.fabrica),'') IS NOT NULL AND l.data_liberacao<=(date_trunc('month',p_fim::timestamp)+interval '1 month - 1 day')::date
 ORDER BY l.data_liberacao DESC,l.id LIMIT 500
 )
 SELECT jsonb_build_object('receita_centavos',coalesce((SELECT sum(cents) FROM faturamentos),0),'material_centavos',coalesce((SELECT sum(valor_centavos) FROM materiais),0),
 'industrial_classificado_centavos',coalesce((SELECT sum(valor_centavos) FROM titulos),0),'rateado_centavos',coalesce((SELECT sum(valor_centavos) FROM rateios WHERE valido),0),
 'rateios_pendentes',(SELECT count(*) FROM rateios WHERE NOT valido),'titulos_total',(SELECT count(*) FROM titulos),'itens_total',(SELECT count(*) FROM por_item),
 'titulos',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY competencia,id) FROM (SELECT * FROM titulos ORDER BY competencia,id LIMIT 500)t),'[]'::jsonb),
 'liberacoes',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY data_liberacao DESC,id) FROM liberacoes l),'[]'::jsonb),
 'rateios',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY competencia,id) FROM rateios r),'[]'::jsonb),
 'fabrica',coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY receita_centavos DESC,fabrica NULLS LAST) FROM por_fabrica f),'[]'::jsonb),
 'obras',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY obra,obra_id) FROM por_obra o),'[]'::jsonb),
 'itens',coalesce((SELECT jsonb_agg(to_jsonb(i) ORDER BY obra,codigo NULLS LAST) FROM (SELECT * FROM por_item ORDER BY obra,codigo NULLS LAST,obra_id,esquadria_id LIMIT 500)i),'[]'::jsonb)) INTO v_result;
 RETURN v_result;
END $$;
REVOKE ALL ON ew_financeiro_interna.rateios_industriais FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.ew_rateio_industrial_criar(uuid,uuid,uuid,int,uuid,bigint,text),public.ew_rateio_industrial_estornar(uuid,uuid,uuid,text),public.ew_rateio_industrial_consultar(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_rateio_industrial_criar(uuid,uuid,uuid,int,uuid,bigint,text),public.ew_rateio_industrial_estornar(uuid,uuid,uuid,text),public.ew_rateio_industrial_consultar(uuid,date,date) TO authenticated;
COMMIT;
