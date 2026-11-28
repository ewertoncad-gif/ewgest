BEGIN;
INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES ('ferramentas.ocorrencias','Ferramentas','Registrar manutenção, avarias e extravios',50),('ferramentas.estornar','Ferramentas','Estornar romaneios de ferramentas',60) ON CONFLICT(chave) DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido) SELECT n.empresa_id,n.nivel,c.chave,n.nivel=1 OR (n.nivel=4 AND c.chave='ferramentas.ocorrencias') FROM public.ew_niveis_acesso n CROSS JOIN public.ew_permissoes_catalogo c WHERE c.chave IN ('ferramentas.ocorrencias','ferramentas.estornar') ON CONFLICT(empresa_id,nivel,chave) DO NOTHING;
ALTER TABLE ew_financeiro_interna.ferramentas ADD COLUMN estado text NOT NULL DEFAULT 'DISPONIVEL' CHECK(estado IN ('DISPONIVEL','AVARIADA','MANUTENCAO','EXTRAVIADA','CONFERIR'));
-- Devoluções antigas não tinham estado estruturado: exigir conferência antes de reentregar.
UPDATE ew_financeiro_interna.ferramentas f SET estado='CONFERIR' WHERE EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=f.empresa_id AND c.item_id=f.id AND c.devolucao_id IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=f.empresa_id AND c.item_id=f.id AND c.devolucao_id IS NULL);
ALTER TABLE ew_financeiro_interna.ferramentas_entregas ADD COLUMN estornado_em timestamptz,ADD COLUMN estornado_por uuid,ADD COLUMN estorno_motivo text,ADD COLUMN estorno_id uuid;
ALTER TABLE ew_financeiro_interna.ferramentas_devolucoes ADD COLUMN estornado_em timestamptz,ADD COLUMN estornado_por uuid,ADD COLUMN estorno_motivo text,ADD COLUMN estorno_id uuid;
ALTER TABLE ew_financeiro_interna.ferramentas_custodia ADD COLUMN estornado_em timestamptz;
DROP INDEX ew_financeiro_interna.ferramenta_custodia_ativa;
CREATE UNIQUE INDEX ferramenta_custodia_ativa ON ew_financeiro_interna.ferramentas_custodia(empresa_id,item_id) WHERE devolucao_id IS NULL AND estornado_em IS NULL;
CREATE UNIQUE INDEX ferramenta_entrega_estorno ON ew_financeiro_interna.ferramentas_entregas(empresa_id,estorno_id) WHERE estorno_id IS NOT NULL;
CREATE UNIQUE INDEX ferramenta_devolucao_estorno ON ew_financeiro_interna.ferramentas_devolucoes(empresa_id,estorno_id) WHERE estorno_id IS NOT NULL;
CREATE TABLE ew_financeiro_interna.ferramentas_ocorrencias(empresa_id uuid NOT NULL,operacao_id uuid NOT NULL,item_id uuid NOT NULL,estado_anterior text NOT NULL,estado_novo text NOT NULL,motivo text NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),tipo text NOT NULL,PRIMARY KEY(empresa_id,operacao_id,item_id));
ALTER TABLE ew_financeiro_interna.ferramentas_ocorrencias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.ferramentas_ocorrencias FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.ew_ferramenta_entregar(p_empresa_id uuid,p_operacao_id uuid,p_funcionario_id uuid,p_itens uuid[],p_motivo text)
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
 IF EXISTS(SELECT 1 FROM unnest(p_itens)i WHERE NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=i AND estado='DISPONIVEL')) OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia WHERE empresa_id=p_empresa_id AND item_id=ANY(p_itens) AND devolucao_id IS NULL AND estornado_em IS NULL) THEN RAISE EXCEPTION 'Item indisponível ou já entregue.';END IF;
 SELECT jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'nome',nome,'tipo',tipo) ORDER BY id) INTO v FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=ANY(p_itens);
 SELECT coalesce(max(numero),0)+1 INTO n FROM ew_financeiro_interna.ferramentas_entregas WHERE empresa_id=p_empresa_id;
 INSERT INTO ew_financeiro_interna.ferramentas_entregas(empresa_id,id,numero,funcionario_id,funcionario_nome,matricula,itens,motivo,criado_por) VALUES(p_empresa_id,p_operacao_id,n,f.id,f.nome,f.matricula,v,btrim(p_motivo),auth.uid());
 INSERT INTO ew_financeiro_interna.ferramentas_custodia(empresa_id,entrega_id,item_id) SELECT p_empresa_id,p_operacao_id,i FROM unnest(p_itens)i;
 RETURN jsonb_build_object('repetido',false,'numero',n);
END $$;
CREATE OR REPLACE FUNCTION public.ew_ferramenta_devolver(p_empresa_id uuid,p_operacao_id uuid,p_entrega_id uuid,p_itens jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a ew_financeiro_interna.ferramentas_devolucoes%ROWTYPE;v jsonb;ids uuid[];n bigint;q int;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.devolver');
 IF p_operacao_id IS NULL OR jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Devolução inválida.';END IF;
 SELECT array_agg(id ORDER BY id),jsonb_agg(jsonb_build_object('id',id,'condicao',btrim(condicao),'estado',coalesce(estado,'CONFERIR')) ORDER BY id) INTO ids,v FROM jsonb_to_recordset(p_itens)x(id uuid,condicao text,estado text);
 IF array_position(ids,NULL) IS NOT NULL OR (SELECT count(DISTINCT i) FROM unnest(ids)i)<>cardinality(ids) OR EXISTS(SELECT 1 FROM jsonb_to_recordset(v)x(id uuid,condicao text,estado text) WHERE length(coalesce(condicao,'')) NOT BETWEEN 2 AND 300 OR estado NOT IN ('DISPONIVEL','AVARIADA','MANUTENCAO','CONFERIR')) THEN RAISE EXCEPTION 'Informe condição de cada item.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 SELECT * INTO a FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id AND id=p_operacao_id;
 IF FOUND THEN
  IF a.entrega_id IS DISTINCT FROM p_entrega_id OR a.itens IS DISTINCT FROM v THEN RAISE EXCEPTION 'Operação reutilizada.';END IF;
  RETURN jsonb_build_object('repetido',true,'numero',a.numero);
 END IF;
 SELECT count(*) INTO q FROM ew_financeiro_interna.ferramentas_custodia WHERE empresa_id=p_empresa_id AND entrega_id=p_entrega_id AND item_id=ANY(ids) AND devolucao_id IS NULL AND estornado_em IS NULL;
 IF q<>cardinality(ids) THEN RAISE EXCEPTION 'Item não pertence à entrega ou já devolvido.';END IF;
 SELECT coalesce(max(numero),0)+1 INTO n FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id;
 INSERT INTO ew_financeiro_interna.ferramentas_devolucoes(empresa_id,id,entrega_id,numero,itens,criado_por) VALUES(p_empresa_id,p_operacao_id,p_entrega_id,n,v,auth.uid());
 UPDATE ew_financeiro_interna.ferramentas_custodia SET devolucao_id=p_operacao_id WHERE empresa_id=p_empresa_id AND entrega_id=p_entrega_id AND item_id=ANY(ids) AND devolucao_id IS NULL AND estornado_em IS NULL;
 INSERT INTO ew_financeiro_interna.ferramentas_ocorrencias(empresa_id,operacao_id,item_id,estado_anterior,estado_novo,motivo,criado_por,tipo) SELECT p_empresa_id,p_operacao_id,f.id,f.estado,x.estado,x.condicao,auth.uid(),'DEVOLUCAO' FROM jsonb_to_recordset(v)x(id uuid,condicao text,estado text) JOIN ew_financeiro_interna.ferramentas f ON f.empresa_id=p_empresa_id AND f.id=x.id;
 UPDATE ew_financeiro_interna.ferramentas f SET estado=x.estado FROM jsonb_to_recordset(v)x(id uuid,estado text) WHERE f.empresa_id=p_empresa_id AND f.id=x.id;
 RETURN jsonb_build_object('repetido',false,'numero',n);
END $$;
CREATE OR REPLACE FUNCTION public.ew_ferramenta_compor_maleta(p_empresa_id uuid,p_maleta_id uuid,p_itens uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.cadastrar');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 IF p_itens IS NULL OR cardinality(p_itens)>100 OR array_position(p_itens,NULL) IS NOT NULL OR (SELECT count(DISTINCT i) FROM unnest(p_itens)i)<>cardinality(p_itens) THEN RAISE EXCEPTION 'Composição inválida.';END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=p_maleta_id AND tipo='MALETA') OR EXISTS(SELECT 1 FROM unnest(p_itens)i WHERE NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas f WHERE f.empresa_id=p_empresa_id AND f.id=i AND f.tipo<>'MALETA')) THEN RAISE EXCEPTION 'Maleta ou item inválido.';END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=p_empresa_id AND c.devolucao_id IS NULL AND c.estornado_em IS NULL AND (c.item_id=p_maleta_id OR c.item_id=ANY(p_itens) OR EXISTS(SELECT 1 FROM ew_financeiro_interna.maleta_itens m WHERE m.empresa_id=c.empresa_id AND m.maleta_id=p_maleta_id AND m.item_id=c.item_id))) THEN RAISE EXCEPTION 'Devolva os componentes antes de alterar a composição.';END IF;
 DELETE FROM ew_financeiro_interna.maleta_itens WHERE empresa_id=p_empresa_id AND maleta_id=p_maleta_id;
 INSERT INTO ew_financeiro_interna.maleta_itens SELECT p_empresa_id,p_maleta_id,i FROM unnest(p_itens)i;
 RETURN jsonb_build_object('ok',true);
END $$;
CREATE OR REPLACE FUNCTION public.ew_ferramentas_consultar(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.consultar');
 SELECT jsonb_build_object(
 'locais',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',nome) ORDER BY nome),'[]') FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND ativo),
 'funcionarios',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.nome,'matricula',f.matricula) ORDER BY f.nome),'[]') FROM ew_financeiro_interna.funcionarios_industriais f WHERE f.empresa_id=p_empresa_id AND NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=f.empresa_id AND m.tipo='FUNCIONARIO' AND m.entidade_id=f.id AND m.evento='DESLIGAMENTO')),
 'itens',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'codigo',f.codigo,'nome',f.nome,'tipo',f.tipo,'estado',f.estado,'local',g.nome,'entrega_id',c.entrega_id,'responsavel',e.funcionario_nome) ORDER BY f.codigo),'[]') FROM ew_financeiro_interna.ferramentas f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.local_id LEFT JOIN ew_financeiro_interna.ferramentas_custodia c ON c.empresa_id=f.empresa_id AND c.item_id=f.id AND c.devolucao_id IS NULL AND c.estornado_em IS NULL LEFT JOIN ew_financeiro_interna.ferramentas_entregas e ON e.empresa_id=c.empresa_id AND e.id=c.entrega_id WHERE f.empresa_id=p_empresa_id),
 'maletas',(SELECT coalesce(jsonb_agg(jsonb_build_object('maleta_id',maleta_id,'item_id',item_id)),'[]') FROM ew_financeiro_interna.maleta_itens WHERE empresa_id=p_empresa_id),
 'entregas',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'numero',e.numero,'funcionario_nome',e.funcionario_nome,'matricula',e.matricula,'itens',e.itens,'motivo',e.motivo,'estornado_em',e.estornado_em,'criado_em',e.criado_em,'pendentes',(SELECT coalesce(jsonb_agg(c.item_id),'[]') FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=e.empresa_id AND c.entrega_id=e.id AND c.devolucao_id IS NULL AND c.estornado_em IS NULL)) ORDER BY e.numero DESC),'[]') FROM ew_financeiro_interna.ferramentas_entregas e WHERE e.empresa_id=p_empresa_id),
 'devolucoes',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'numero',numero,'entrega_id',entrega_id,'itens',itens,'estornado_em',estornado_em,'criado_em',criado_em) ORDER BY numero DESC),'[]') FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id), 'ocorrencias',(SELECT coalesce(jsonb_agg(jsonb_build_object('item_id',o.item_id,'estado_anterior',o.estado_anterior,'estado_novo',o.estado_novo,'motivo',o.motivo,'criado_em',o.criado_em,'tipo',o.tipo) ORDER BY o.criado_em DESC),'[]') FROM ew_financeiro_interna.ferramentas_ocorrencias o WHERE o.empresa_id=p_empresa_id)) INTO r;
 RETURN r;
END $$;
CREATE FUNCTION public.ew_ferramenta_ocorrencia(p_empresa_id uuid,p_operacao_id uuid,p_item_id uuid,p_estado text,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE f ew_financeiro_interna.ferramentas%ROWTYPE;o ew_financeiro_interna.ferramentas_ocorrencias%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.ocorrencias');
 IF p_operacao_id IS NULL OR p_estado IS NULL OR p_estado NOT IN ('DISPONIVEL','AVARIADA','MANUTENCAO','EXTRAVIADA','CONFERIR') OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Ocorrência inválida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 SELECT * INTO o FROM ew_financeiro_interna.ferramentas_ocorrencias WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id AND item_id=p_item_id;
 IF FOUND THEN
 IF o.tipo<>'MANUAL' OR o.estado_novo<>p_estado OR o.motivo<>btrim(p_motivo) THEN RAISE EXCEPTION 'Operação reutilizada.';END IF;
 RETURN jsonb_build_object('repetido',true);END IF;
 SELECT * INTO f FROM ew_financeiro_interna.ferramentas WHERE empresa_id=p_empresa_id AND id=p_item_id FOR UPDATE;
 IF NOT FOUND OR f.estado=p_estado THEN RAISE EXCEPTION 'Item indisponível ou estado inalterado.';END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=p_empresa_id AND c.item_id=f.id AND c.devolucao_id IS NULL AND c.estornado_em IS NULL) AND p_estado<>'EXTRAVIADA' THEN RAISE EXCEPTION 'Registre a devolução física antes de mudar a condição.';END IF;
 INSERT INTO ew_financeiro_interna.ferramentas_ocorrencias(empresa_id,operacao_id,item_id,estado_anterior,estado_novo,motivo,criado_por,tipo) VALUES(p_empresa_id,p_operacao_id,f.id,f.estado,p_estado,btrim(p_motivo),auth.uid(),'MANUAL');
 UPDATE ew_financeiro_interna.ferramentas SET estado=p_estado WHERE empresa_id=p_empresa_id AND id=f.id;
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE FUNCTION public.ew_ferramenta_estornar(p_empresa_id uuid,p_operacao_id uuid,p_tipo text,p_romaneio_id uuid,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE e ew_financeiro_interna.ferramentas_entregas%ROWTYPE;d ew_financeiro_interna.ferramentas_devolucoes%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_ferramentas(p_empresa_id,'ferramentas.estornar');
 IF p_operacao_id IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('ENTREGA','DEVOLUCAO') OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Estorno inválido.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FERRAMENTAS',0));
 IF p_tipo='ENTREGA' THEN
 SELECT * INTO e FROM ew_financeiro_interna.ferramentas_entregas WHERE empresa_id=p_empresa_id AND id=p_romaneio_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Entrega indisponível.';END IF;
 IF e.estorno_id=p_operacao_id AND e.estorno_motivo=btrim(p_motivo) THEN RETURN jsonb_build_object('repetido',true);END IF;
 IF e.estornado_em IS NOT NULL OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id AND entrega_id=e.id AND estornado_em IS NULL) OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c JOIN ew_financeiro_interna.ferramentas f ON f.empresa_id=c.empresa_id AND f.id=c.item_id WHERE c.empresa_id=p_empresa_id AND c.entrega_id=e.id AND (c.devolucao_id IS NOT NULL OR f.estado<>'DISPONIVEL')) THEN RAISE EXCEPTION 'Desfaça devoluções e confira ocorrências antes de estornar.';END IF;
 UPDATE ew_financeiro_interna.ferramentas_custodia SET estornado_em=now() WHERE empresa_id=p_empresa_id AND entrega_id=e.id;
 UPDATE ew_financeiro_interna.ferramentas_entregas SET estornado_em=now(),estornado_por=auth.uid(),estorno_motivo=btrim(p_motivo),estorno_id=p_operacao_id WHERE empresa_id=p_empresa_id AND id=e.id;
 ELSE
 SELECT * INTO d FROM ew_financeiro_interna.ferramentas_devolucoes WHERE empresa_id=p_empresa_id AND id=p_romaneio_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Devolução indisponível.';END IF;
 IF d.estorno_id=p_operacao_id AND d.estorno_motivo=btrim(p_motivo) THEN RETURN jsonb_build_object('repetido',true);END IF;
 IF d.estornado_em IS NOT NULL OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia c WHERE c.empresa_id=p_empresa_id AND c.devolucao_id=d.id AND (EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_custodia z WHERE z.empresa_id=c.empresa_id AND z.item_id=c.item_id AND z.entrega_id<>c.entrega_id AND z.estornado_em IS NULL AND (z.devolucao_id IS NULL OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_entregas ee WHERE ee.empresa_id=z.empresa_id AND ee.id=z.entrega_id AND ee.criado_em>=d.criado_em))) OR NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_ocorrencias o WHERE o.empresa_id=c.empresa_id AND o.item_id=c.item_id AND o.operacao_id=d.id AND o.tipo='DEVOLUCAO') OR EXISTS(SELECT 1 FROM ew_financeiro_interna.ferramentas_ocorrencias o JOIN ew_financeiro_interna.ferramentas_ocorrencias original ON original.empresa_id=o.empresa_id AND original.item_id=o.item_id AND original.operacao_id=d.id WHERE o.empresa_id=c.empresa_id AND o.item_id=c.item_id AND o.criado_em>original.criado_em))) THEN RAISE EXCEPTION 'Devolução com movimentação posterior ou sem histórico de condição; conferência necessária.';END IF;
 UPDATE ew_financeiro_interna.ferramentas f SET estado=o.estado_anterior FROM ew_financeiro_interna.ferramentas_ocorrencias o WHERE f.empresa_id=p_empresa_id AND o.empresa_id=f.empresa_id AND o.item_id=f.id AND o.operacao_id=d.id AND o.tipo='DEVOLUCAO';
 UPDATE ew_financeiro_interna.ferramentas_custodia SET devolucao_id=NULL WHERE empresa_id=p_empresa_id AND devolucao_id=d.id;
 UPDATE ew_financeiro_interna.ferramentas_devolucoes SET estornado_em=now(),estornado_por=auth.uid(),estorno_motivo=btrim(p_motivo),estorno_id=p_operacao_id WHERE empresa_id=p_empresa_id AND id=d.id;
 END IF;
 RETURN jsonb_build_object('repetido',false);
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_ferramenta_ocorrencia(uuid,uuid,uuid,text,text),public.ew_ferramenta_estornar(uuid,uuid,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_ferramenta_ocorrencia(uuid,uuid,uuid,text,text),public.ew_ferramenta_estornar(uuid,uuid,text,uuid,text) TO authenticated;
COMMIT;