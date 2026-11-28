BEGIN;
CREATE TABLE ew_financeiro_interna.ferramentas(
 empresa_id uuid NOT NULL,id uuid NOT NULL,codigo text NOT NULL,nome text NOT NULL,tipo text NOT NULL CHECK(tipo IN ('MAQUINA','FERRAMENTA','BATERIA','CARREGADOR','MALETA','ACESSORIO')),
 local_id uuid NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(empresa_id,id),UNIQUE(empresa_id,codigo)
);
CREATE TABLE ew_financeiro_interna.maleta_itens(
 empresa_id uuid NOT NULL,maleta_id uuid NOT NULL,item_id uuid NOT NULL,
 PRIMARY KEY(empresa_id,maleta_id,item_id),UNIQUE(empresa_id,item_id),
 FOREIGN KEY(empresa_id,maleta_id) REFERENCES ew_financeiro_interna.ferramentas(empresa_id,id),
 FOREIGN KEY(empresa_id,item_id) REFERENCES ew_financeiro_interna.ferramentas(empresa_id,id),CHECK(maleta_id<>item_id)
);
CREATE TABLE ew_financeiro_interna.ferramentas_entregas(
 empresa_id uuid NOT NULL,id uuid NOT NULL,numero bigint NOT NULL,funcionario_id uuid NOT NULL,funcionario_nome text NOT NULL,matricula text NOT NULL,
 itens jsonb NOT NULL,motivo text NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(empresa_id,id),UNIQUE(empresa_id,numero)
);
CREATE TABLE ew_financeiro_interna.ferramentas_devolucoes(
 empresa_id uuid NOT NULL,id uuid NOT NULL,entrega_id uuid NOT NULL,numero bigint NOT NULL,itens jsonb NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,id),UNIQUE(empresa_id,numero),FOREIGN KEY(empresa_id,entrega_id) REFERENCES ew_financeiro_interna.ferramentas_entregas(empresa_id,id)
);
CREATE TABLE ew_financeiro_interna.ferramentas_custodia(
 empresa_id uuid NOT NULL,entrega_id uuid NOT NULL,item_id uuid NOT NULL,devolucao_id uuid,
 PRIMARY KEY(empresa_id,entrega_id,item_id),FOREIGN KEY(empresa_id,entrega_id) REFERENCES ew_financeiro_interna.ferramentas_entregas(empresa_id,id),
 FOREIGN KEY(empresa_id,item_id) REFERENCES ew_financeiro_interna.ferramentas(empresa_id,id),
 FOREIGN KEY(empresa_id,devolucao_id) REFERENCES ew_financeiro_interna.ferramentas_devolucoes(empresa_id,id)
);
CREATE UNIQUE INDEX ferramenta_custodia_ativa ON ew_financeiro_interna.ferramentas_custodia(empresa_id,item_id) WHERE devolucao_id IS NULL;
ALTER TABLE ew_financeiro_interna.ferramentas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.maleta_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.ferramentas_entregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.ferramentas_devolucoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.ferramentas_custodia ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.ferramentas,ew_financeiro_interna.maleta_itens,ew_financeiro_interna.ferramentas_entregas,ew_financeiro_interna.ferramentas_devolucoes,ew_financeiro_interna.ferramentas_custodia FROM PUBLIC,anon,authenticated;
CREATE FUNCTION ew_financeiro_interna.exigir_ferramentas(p_empresa uuid,p_flag text) RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa,'ferramentas.consultar') OR NOT public.ew_pode(p_empresa,p_flag) THEN RAISE EXCEPTION 'Sem acesso às ferramentas.';END IF;
END $$;
REVOKE ALL ON FUNCTION ew_financeiro_interna.exigir_ferramentas(uuid,text) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_ferramenta_cadastrar(p_empresa_id uuid,p_operacao_id uuid,p_codigo text,p_nome text,p_tipo text,p_local_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a ew_financeiro_interna.ferramentas%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.cadastrar');
 IF p_operacao_id IS NULL OR length(btrim(coalesce(p_codigo,''))) NOT BETWEEN 1 AND 50 OR length(btrim(coalesce(p_nome,''))) NOT BETWEEN 2 AND 150 OR p_tipo IS NULL OR p_tipo NOT IN ('MAQUINA','FERRAMENTA','BATERIA','CARREGADOR','MALETA','ACESSORIO') THEN RAISE EXCEPTION 'Cadastro inválido.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 SELECT * INTO a FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=p_operacao_id;
 IF FOUND THEN
  IF (a.codigo,a.nome,a.tipo,a.local_id) IS DISTINCT FROM (upper(btrim(p_codigo)),btrim(p_nome),p_tipo,p_local_id) THEN RAISE EXCEPTION 'Operação reutilizada.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 PERFORM 1 FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=p_local_id AND ativo FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Local indisponível.';END IF;
 INSERT INTO ew_financeiro_interna.ferramentas(empresa_id,id,codigo,nome,tipo,local_id,criado_por) VALUES(p_empresa_id,p_operacao_id,upper(btrim(p_codigo)),btrim(p_nome),p_tipo,p_local_id,auth.uid());
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE FUNCTION public.ew_ferramenta_compor_maleta(p_empresa_id uuid,p_maleta_id uuid,p_itens uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.cadastrar');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 IF p_itens IS NULL OR cardinality(p_itens)>100 OR array_position(p_itens,NULL) IS NOT NULL OR (SELECT count(DISTINCT i) FROM unnest(p_itens)i)<>cardinality(p_itens) THEN RAISE EXCEPTION 'Composição inválida.';END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=p_maleta_id AND tipo='MALETA') OR EXISTS(SELECT 1 FROM unnest(p_itens)i WHERE NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas f WHERE f.empresa_id=p_empresa_id AND f.id=i AND f.tipo<>'MALETA')) THEN RAISE EXCEPTION 'Maleta ou item inválido.';END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=p_empresa_id AND c.devolucao_id IS NULL AND (c.item_id=p_maleta_id OR c.item_id=ANY(p_itens) OR EXISTS(SELECT 1 FROM ew_financeiro_interna.maleta_itens m WHERE m.empresa_id=c.empresa_id AND m.maleta_id=p_maleta_id AND m.item_id=c.item_id))) THEN RAISE EXCEPTION 'Devolva os componentes antes de alterar a composição.';END IF;
 DELETE FROM ew_financeiro_interna.maleta_itens WHERE empresa_id=p_empresa_id AND maleta_id=p_maleta_id;
 INSERT INTO ew_financeiro_interna.maleta_itens SELECT p_empresa_id,p_maleta_id,i FROM unnest(p_itens)i;
 RETURN jsonb_build_object('ok',true);
END $$;
CREATE FUNCTION public.ew_ferramenta_entregar(p_empresa_id uuid,p_operacao_id uuid,p_funcionario_id uuid,p_itens uuid[],p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE f ew_financeiro_interna.funcionarios_industriais%ROWTYPE; a ew_financeiro_interna.ferramentas_entregas%ROWTYPE;v jsonb;n bigint;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.entregar');
 IF p_operacao_id IS NULL OR p_itens IS NULL OR cardinality(p_itens) NOT BETWEEN 1 AND 100 OR array_position(p_itens,NULL) IS NOT NULL OR (SELECT count(DISTINCT i) FROM unnest(p_itens)i)<>cardinality(p_itens) OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Entrega inválida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 SELECT * INTO a FROM ew_financeiro_interna.ferramentas_entregas WHERE empresa_id=p_empresa_id AND id=p_operacao_id;
 IF FOUND THEN
  IF a.funcionario_id IS DISTINCT FROM p_funcionario_id OR a.motivo IS DISTINCT FROM btrim(p_motivo) OR (SELECT array_agg((x->>'id')::uuid ORDER BY (x->>'id')::uuid) FROM jsonb_array_elements(a.itens)x) IS DISTINCT FROM (SELECT array_agg(i ORDER BY i) FROM unnest(p_itens)i) THEN RAISE EXCEPTION 'Operação reutilizada.';END IF;
  RETURN jsonb_build_object('repetido',true,'numero',a.numero);
 END IF;
 SELECT * INTO f FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=p_empresa_id AND id=p_funcionario_id FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM ew_financeiro_interna.movimentacoes_industriais WHERE empresa_id=p_empresa_id AND tipo='FUNCIONARIO' AND entidade_id=p_funcionario_id AND evento='DESLIGAMENTO') THEN RAISE EXCEPTION 'Funcionário indisponível.';END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_itens)i WHERE NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=i)) OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia WHERE empresa_id=p_empresa_id AND item_id=ANY(p_itens) AND devolucao_id IS NULL) THEN RAISE EXCEPTION 'Item indisponível ou já entregue.';END IF;
 SELECT jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'nome',nome,'tipo',tipo) ORDER BY id) INTO v FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=ANY(p_itens);
 SELECT coalesce(max(numero),0)+1 INTO n FROM ew_financeiro_interna.ferramentas_entregas WHERE empresa_id=p_empresa_id;
 INSERT INTO ew_financeiro_interna.ferramentas_entregas(empresa_id,id,numero,funcionario_id,funcionario_nome,matricula,itens,motivo,criado_por) VALUES(p_empresa_id,p_operacao_id,n,f.id,f.nome,f.matricula,v,btrim(p_motivo),auth.uid());
 INSERT INTO ew_financeiro_interna.ferramentas_custodia(empresa_id,entrega_id,item_id) SELECT p_empresa_id,p_operacao_id,i FROM unnest(p_itens)i;
 RETURN jsonb_build_object('repetido',false,'numero',n);
END $$;
CREATE FUNCTION public.ew_ferramenta_devolver(p_empresa_id uuid,p_operacao_id uuid,p_entrega_id uuid,p_itens jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a ew_financeiro_interna.ferramentas_devolucoes%ROWTYPE;v jsonb;ids uuid[];n bigint;q int;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.devolver');
 IF p_operacao_id IS NULL OR jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Devolução inválida.';END IF;
 SELECT array_agg(id ORDER BY id),jsonb_agg(jsonb_build_object('id',id,'condicao',btrim(condicao)) ORDER BY id) INTO ids,v FROM jsonb_to_recordset(p_itens)x(id uuid,condicao text);
 IF array_position(ids,NULL) IS NOT NULL OR (SELECT count(DISTINCT i) FROM unnest(ids)i)<>cardinality(ids) OR EXISTS(SELECT 1 FROM jsonb_to_recordset(v)x(id uuid,condicao text) WHERE length(coalesce(condicao,'')) NOT BETWEEN 2 AND 300) THEN RAISE EXCEPTION 'Informe condição de cada item.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 SELECT * INTO a FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id AND id=p_operacao_id;
 IF FOUND THEN
  IF a.entrega_id IS DISTINCT FROM p_entrega_id OR a.itens IS DISTINCT FROM v THEN RAISE EXCEPTION 'Operação reutilizada.';END IF;
  RETURN jsonb_build_object('repetido',true,'numero',a.numero);
 END IF;
 SELECT count(*) INTO q FROM ew_financeiro_interna.ferramentas_custodia WHERE empresa_id=p_empresa_id AND entrega_id=p_entrega_id AND item_id=ANY(ids) AND devolucao_id IS NULL;
 IF q<>cardinality(ids) THEN RAISE EXCEPTION 'Item não pertence à entrega ou já devolvido.';END IF;
 SELECT coalesce(max(numero),0)+1 INTO n FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id;
 INSERT INTO ew_financeiro_interna.ferramentas_devolucoes(empresa_id,id,entrega_id,numero,itens,criado_por) VALUES(p_empresa_id,p_operacao_id,p_entrega_id,n,v,auth.uid());
 UPDATE ew_financeiro_interna.ferramentas_custodia SET devolucao_id=p_operacao_id WHERE empresa_id=p_empresa_id AND entrega_id=p_entrega_id AND item_id=ANY(ids) AND devolucao_id IS NULL;
 RETURN jsonb_build_object('repetido',false,'numero',n);
END $$;
CREATE FUNCTION public.ew_ferramentas_consultar(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.consultar');
 SELECT jsonb_build_object(
 'locais',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',nome) ORDER BY nome),'[]') FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND ativo),
 'funcionarios',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.nome,'matricula',f.matricula) ORDER BY f.nome),'[]') FROM ew_financeiro_interna.funcionarios_industriais f WHERE f.empresa_id=p_empresa_id AND NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=f.empresa_id AND m.tipo='FUNCIONARIO' AND m.entidade_id=f.id AND m.evento='DESLIGAMENTO')),
 'itens',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'codigo',f.codigo,'nome',f.nome,'tipo',f.tipo,'local',g.nome,'entrega_id',c.entrega_id,'responsavel',e.funcionario_nome) ORDER BY f.codigo),'[]') FROM ew_financeiro_interna.ferramentas f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.local_id LEFT JOIN ew_financeiro_interna.ferramentas_custodia c ON c.empresa_id=f.empresa_id AND c.item_id=f.id AND c.devolucao_id IS NULL LEFT JOIN ew_financeiro_interna.ferramentas_entregas e ON e.empresa_id=c.empresa_id AND e.id=c.entrega_id WHERE f.empresa_id=p_empresa_id),
 'maletas',(SELECT coalesce(jsonb_agg(jsonb_build_object('maleta_id',maleta_id,'item_id',item_id)),'[]') FROM ew_financeiro_interna.maleta_itens WHERE empresa_id=p_empresa_id),
 'entregas',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'numero',e.numero,'funcionario_nome',e.funcionario_nome,'matricula',e.matricula,'itens',e.itens,'motivo',e.motivo,'criado_em',e.criado_em,'pendentes',(SELECT coalesce(jsonb_agg(c.item_id),'[]') FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=e.empresa_id AND c.entrega_id=e.id AND c.devolucao_id IS NULL)) ORDER BY e.numero DESC),'[]') FROM ew_financeiro_interna.ferramentas_entregas e WHERE e.empresa_id=p_empresa_id),
 'devolucoes',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'numero',numero,'entrega_id',entrega_id,'itens',itens,'criado_em',criado_em) ORDER BY numero DESC),'[]') FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id)) INTO r;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_ferramenta_cadastrar(uuid,uuid,text,text,text,uuid),public.ew_ferramenta_compor_maleta(uuid,uuid,uuid[]),public.ew_ferramenta_entregar(uuid,uuid,uuid,uuid[],text),public.ew_ferramenta_devolver(uuid,uuid,uuid,jsonb),public.ew_ferramentas_consultar(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_ferramenta_cadastrar(uuid,uuid,text,text,text,uuid),public.ew_ferramenta_compor_maleta(uuid,uuid,uuid[]),public.ew_ferramenta_entregar(uuid,uuid,uuid,uuid[],text),public.ew_ferramenta_devolver(uuid,uuid,uuid,jsonb),public.ew_ferramentas_consultar(uuid) TO authenticated;
COMMIT;
