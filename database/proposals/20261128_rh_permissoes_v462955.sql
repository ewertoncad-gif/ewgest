BEGIN;
INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES ('rh.consultar','RH','Consultar funcionários e horas',10),
('rh.funcionarios','RH','Cadastrar e movimentar funcionários',20),
('rh.horas','RH','Registrar horas-homem',30),
('rh.estornar_horas','RH','Estornar horas-homem',40),
('rh.folha','RH','Consultar e registrar folha gerencial',50),
('rh.estornar_folha','RH','Estornar folha gerencial',60),
('ferramentas.consultar','Ferramentas','Consultar ferramentas e termos',10),
('ferramentas.cadastrar','Ferramentas','Cadastrar ferramentas, máquinas e maletas',20),
('ferramentas.entregar','Ferramentas','Entregar ferramentas',30),
('ferramentas.devolver','Ferramentas','Receber devoluções',40) ON CONFLICT(chave) DO NOTHING;
-- Não promove níveis de usuários existentes; o RH 08 é habilitado apenas onde ainda não há usuários nesse nível.
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT n.empresa_id,n.nivel,c.chave,
 n.nivel=1 OR (n.nivel=4 AND c.chave LIKE 'ferramentas.%') OR (n.nivel=8 AND c.chave LIKE 'rh.%' AND NOT EXISTS(SELECT 1 FROM public.usuarios_empresas u WHERE u.empresa_id=n.empresa_id AND u.nivel_acesso=8))
FROM public.ew_niveis_acesso n CROSS JOIN public.ew_permissoes_catalogo c WHERE c.chave LIKE 'rh.%' OR c.chave LIKE 'ferramentas.%'
ON CONFLICT(empresa_id,nivel,chave) DO NOTHING;
UPDATE public.ew_niveis_acesso SET nome='RH' WHERE nivel=8 AND NOT EXISTS(SELECT 1 FROM public.usuarios_empresas u WHERE u.empresa_id=ew_niveis_acesso.empresa_id AND u.nivel_acesso=8);
CREATE FUNCTION ew_financeiro_interna.exigir_rh(p_empresa uuid,p_flag text)
RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa,'rh.consultar') OR NOT public.ew_pode(p_empresa,p_flag) THEN RAISE EXCEPTION 'Sem acesso ao RH.';END IF;
END $$;
REVOKE ALL ON FUNCTION ew_financeiro_interna.exigir_rh(uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.ew_industrial_cadastrar(p_empresa_id uuid,p_operacao_id uuid,p_tipo text,p_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE g uuid;d date;cod text;nom text;fun text;a bigint;b bigint;c bigint;vida int;
BEGIN
 IF p_tipo='FUNCIONARIO' THEN PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.funcionarios');
 ELSIF p_tipo='FOLHA' THEN PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.folha');
 ELSE PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);END IF;
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('FUNCIONARIO','FOLHA','ATIVO') OR jsonb_typeof(p_dados) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Cadastro inválido.';END IF;
 g:=(p_dados->>'galpao_id')::uuid;
 PERFORM 1 FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=g AND ativo FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Local ativo indisponível.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|CAD_INDUSTRIAL|'||p_operacao_id::text,0));
 d:=(p_dados->>'data')::date;
 IF d IS NULL OR d>(now() AT TIME ZONE 'America/Recife')::date THEN RAISE EXCEPTION 'Data inválida.';END IF;
 IF p_tipo='FUNCIONARIO' THEN
  cod:=upper(btrim(coalesce(p_dados->>'codigo','')));nom:=btrim(coalesce(p_dados->>'nome',''));fun:=btrim(coalesce(p_dados->>'funcao',''));
  IF length(cod) NOT BETWEEN 1 AND 50 OR length(nom) NOT BETWEEN 2 AND 150 OR length(fun) NOT BETWEEN 2 AND 100 THEN RAISE EXCEPTION 'Dados de funcionário inválidos.';END IF;
  IF EXISTS(SELECT 1 FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=p_empresa_id AND id=p_operacao_id) THEN
   IF NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=p_empresa_id AND id=p_operacao_id AND matricula=cod AND nome=nom AND funcao=fun AND galpao_id=g AND admissao=d) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
   RETURN jsonb_build_object('repetido',true);
  END IF;
  INSERT INTO ew_financeiro_interna.funcionarios_industriais(empresa_id,id,matricula,nome,funcao,galpao_id,admissao,criado_por) VALUES(p_empresa_id,p_operacao_id,cod,nom,fun,g,d,auth.uid());
 ELSIF p_tipo='FOLHA' THEN
  a:=(p_dados->>'salarios')::bigint;b:=(p_dados->>'encargos')::bigint;c:=(p_dados->>'beneficios')::bigint;nom:=btrim(coalesce(p_dados->>'referencia',''));
  IF a IS NULL OR b IS NULL OR c IS NULL OR least(a,b,c)<0 OR greatest(a,b,c)>100000000000000 OR length(nom) NOT BETWEEN 5 AND 300 OR extract(day from d)<>1 THEN RAISE EXCEPTION 'Folha gerencial inválida.';END IF;
  IF EXISTS(SELECT 1 FROM ew_financeiro_interna.folhas_industriais WHERE empresa_id=p_empresa_id AND id=p_operacao_id) THEN
   IF NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.folhas_industriais WHERE empresa_id=p_empresa_id AND id=p_operacao_id AND galpao_id=g AND competencia=d AND salarios=a AND encargos=b AND beneficios=c AND referencia=nom) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
   RETURN jsonb_build_object('repetido',true);
  END IF;
  INSERT INTO ew_financeiro_interna.folhas_industriais(empresa_id,id,galpao_id,competencia,salarios,encargos,beneficios,referencia,criado_por) VALUES(p_empresa_id,p_operacao_id,g,d,a,b,c,nom,auth.uid());
 ELSE
  cod:=upper(btrim(coalesce(p_dados->>'codigo','')));nom:=btrim(coalesce(p_dados->>'nome',''));a:=(p_dados->>'valor')::bigint;b:=(p_dados->>'residual')::bigint;vida:=(p_dados->>'vida')::int;
  IF length(cod) NOT BETWEEN 1 AND 50 OR length(nom) NOT BETWEEN 2 AND 150 OR a IS NULL OR b IS NULL OR vida IS NULL OR a NOT BETWEEN 1 AND 100000000000000 OR b NOT BETWEEN 0 AND a OR vida NOT BETWEEN 1 AND 1200 OR extract(day from d)<>1 THEN RAISE EXCEPTION 'Ativo inválido.';END IF;
  IF EXISTS(SELECT 1 FROM ew_financeiro_interna.ativos_industriais WHERE empresa_id=p_empresa_id AND id=p_operacao_id) THEN
   IF NOT EXISTS(SELECT 1 FROM ew_financeiro_interna.ativos_industriais WHERE empresa_id=p_empresa_id AND id=p_operacao_id AND codigo=cod AND descricao=nom AND galpao_id=g AND inicio=d AND valor_centavos=a AND residual_centavos=b AND vida_meses=vida) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
   RETURN jsonb_build_object('repetido',true);
  END IF;
  INSERT INTO ew_financeiro_interna.ativos_industriais(empresa_id,id,codigo,descricao,galpao_id,inicio,valor_centavos,residual_centavos,vida_meses,criado_por) VALUES(p_empresa_id,p_operacao_id,cod,nom,g,d,a,b,vida,auth.uid());
 END IF;
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE OR REPLACE FUNCTION public.ew_industrial_estornar_folha(p_empresa_id uuid,p_operacao_id uuid,p_folha_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE f ew_financeiro_interna.folhas_industriais%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.folha');
 PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.estornar_folha');
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Justificativa inválida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|FOLHA_ESTORNO|'||p_operacao_id::text,0));
 SELECT * INTO f FROM ew_financeiro_interna.folhas_industriais WHERE empresa_id=p_empresa_id AND estorno_id=p_operacao_id;
 IF FOUND THEN
  IF f.id IS DISTINCT FROM p_folha_id OR f.estorno_motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 UPDATE ew_financeiro_interna.folhas_industriais SET estornado_em=now(),estornado_por=auth.uid(),estorno_id=p_operacao_id,estorno_motivo=btrim(p_motivo) WHERE empresa_id=p_empresa_id AND id=p_folha_id AND estornado_em IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Folha ativa indisponível.';END IF;
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE OR REPLACE FUNCTION public.ew_industrial_movimentar(p_empresa_id uuid,p_operacao_id uuid,p_tipo text,p_entidade_id uuid,p_evento text,p_data date,p_destino_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE m ew_financeiro_interna.movimentacoes_industriais%ROWTYPE;g uuid;inicio date;
BEGIN
 IF p_tipo='FUNCIONARIO' THEN PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.funcionarios');
 ELSE PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);END IF;
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('FUNCIONARIO','ATIVO') OR p_evento IS NULL OR p_evento NOT IN ('TRANSFERENCIA','DESLIGAMENTO') OR p_data IS NULL OR p_data>(now() AT TIME ZONE 'America/Recife')::date OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Movimentação inválida.';END IF;
 IF p_tipo='ATIVO' AND (p_evento<>'TRANSFERENCIA' OR extract(day from p_data)<>1) THEN RAISE EXCEPTION 'Transferência patrimonial somente no primeiro dia da competência.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|MOV_INDUSTRIAL|'||p_operacao_id::text,0));
 SELECT * INTO m FROM ew_financeiro_interna.movimentacoes_industriais WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF m.tipo IS DISTINCT FROM p_tipo OR m.entidade_id IS DISTINCT FROM p_entidade_id OR m.evento IS DISTINCT FROM p_evento OR m.data_evento IS DISTINCT FROM p_data OR m.destino_id IS DISTINCT FROM p_destino_id OR m.motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 IF p_tipo='FUNCIONARIO' THEN
  SELECT galpao_id,admissao INTO g,inicio FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=p_empresa_id AND id=p_entidade_id FOR UPDATE;
 ELSE
  SELECT a.galpao_id,a.inicio INTO g,inicio FROM ew_financeiro_interna.ativos_industriais a WHERE a.empresa_id=p_empresa_id AND a.id=p_entidade_id FOR UPDATE;
 END IF;
 IF NOT FOUND OR p_data<inicio THEN RAISE EXCEPTION 'Cadastro ou data indisponível.';END IF;
 SELECT * INTO m FROM ew_financeiro_interna.movimentacoes_industriais WHERE empresa_id=p_empresa_id AND tipo=p_tipo AND entidade_id=p_entidade_id ORDER BY data_evento DESC LIMIT 1;
 IF FOUND THEN
  IF m.evento='DESLIGAMENTO' OR p_data<=m.data_evento THEN RAISE EXCEPTION 'Histórico encerrado ou data fora de sequência.';END IF;
  g:=m.destino_id;
 END IF;
 IF p_tipo='ATIVO' AND EXISTS(SELECT 1 FROM ew_financeiro_interna.depreciacoes_industriais WHERE empresa_id=p_empresa_id AND ativo_id=p_entidade_id AND competencia>=p_data) THEN RAISE EXCEPTION 'Competência já depreciada; não é permitido alterar seu local histórico.';END IF;
 IF p_evento='TRANSFERENCIA' THEN
  IF p_destino_id IS NULL OR p_destino_id=g THEN RAISE EXCEPTION 'Escolha outro local.';END IF;
  PERFORM 1 FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=p_destino_id AND ativo FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Destino indisponível.';END IF;
 ELSIF p_destino_id IS NOT NULL THEN RAISE EXCEPTION 'Desligamento não possui destino.';END IF;
 INSERT INTO ew_financeiro_interna.movimentacoes_industriais(empresa_id,operacao_id,tipo,entidade_id,evento,data_evento,origem_id,destino_id,motivo,criado_por) VALUES(p_empresa_id,p_operacao_id,p_tipo,p_entidade_id,p_evento,p_data,g,p_destino_id,btrim(p_motivo),auth.uid());
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE OR REPLACE FUNCTION public.ew_industrial_registrar_horas(p_empresa_id uuid,p_operacao_id uuid,p_galpao_id uuid,p_data date,p_minutos bigint,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE h ew_financeiro_interna.horas_industriais%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.horas');
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_data IS NULL OR p_data>(now() AT TIME ZONE 'America/Recife')::date OR p_minutos IS NULL OR p_minutos NOT BETWEEN 0 AND 10000000 OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Dados de horas inválidos.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|HORAS|'||p_operacao_id::text,0));
 SELECT * INTO h FROM ew_financeiro_interna.horas_industriais WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF h.galpao_id IS DISTINCT FROM p_galpao_id OR h.data_trabalho IS DISTINCT FROM p_data OR h.minutos IS DISTINCT FROM p_minutos OR h.motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Identificador já utilizado.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 PERFORM 1 FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=p_galpao_id AND ativo FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Local ativo indisponível.';END IF;
 INSERT INTO ew_financeiro_interna.horas_industriais(empresa_id,operacao_id,galpao_id,data_trabalho,minutos,motivo,criado_por) VALUES(p_empresa_id,p_operacao_id,p_galpao_id,p_data,p_minutos,btrim(p_motivo),auth.uid());
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE OR REPLACE FUNCTION public.ew_industrial_estornar_horas(p_empresa_id uuid,p_operacao_id uuid,p_registro_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE h ew_financeiro_interna.horas_industriais%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.estornar_horas');
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Informe justificativa válida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|HORAS_ESTORNO|'||p_operacao_id::text,0));
 SELECT * INTO h FROM ew_financeiro_interna.horas_industriais WHERE empresa_id=p_empresa_id AND estorno_operacao_id=p_operacao_id;
 IF FOUND THEN
  IF h.operacao_id IS DISTINCT FROM p_registro_id OR h.estorno_motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Identificador já utilizado.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 UPDATE ew_financeiro_interna.horas_industriais SET estornado_em=now(),estornado_por=auth.uid(),estorno_operacao_id=p_operacao_id,estorno_motivo=btrim(p_motivo) WHERE empresa_id=p_empresa_id AND operacao_id=p_registro_id AND estornado_em IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registro ativo indisponível.';END IF;
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE FUNCTION public.ew_rh_consultar(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_rh(p_empresa_id,'rh.consultar');
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Período inválido.';END IF;
 SELECT jsonb_build_object(
 'locais',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',nome) ORDER BY nome),'[]') FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND ativo),
 'funcionarios',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'matricula',f.matricula,'nome',f.nome,'funcao',f.funcao,'admissao',f.admissao,'local',g.nome,'desligado_em',CASE WHEN m.evento='DESLIGAMENTO' THEN m.data_evento END) ORDER BY f.nome,f.id),'[]') FROM ew_financeiro_interna.funcionarios_industriais f LEFT JOIN LATERAL(SELECT evento,data_evento,origem_id,destino_id FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=f.empresa_id AND m.tipo='FUNCIONARIO' AND m.entidade_id=f.id ORDER BY data_evento DESC LIMIT 1)m ON true LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=coalesce(m.destino_id,m.origem_id,f.galpao_id) WHERE f.empresa_id=p_empresa_id),
 'horas',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',h.operacao_id,'local',g.nome,'data',h.data_trabalho,'minutos',h.minutos,'motivo',h.motivo,'estornado_em',h.estornado_em) ORDER BY h.data_trabalho DESC,h.operacao_id),'[]') FROM ew_financeiro_interna.horas_industriais h LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=h.empresa_id AND g.id=h.galpao_id WHERE h.empresa_id=p_empresa_id AND h.data_trabalho BETWEEN p_inicio AND p_fim),
 'folhas',CASE WHEN public.ew_pode(p_empresa_id,'rh.folha') THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'local',g.nome,'competencia',f.competencia,'salarios',f.salarios,'encargos',f.encargos,'beneficios',f.beneficios,'referencia',f.referencia,'estornado_em',f.estornado_em) ORDER BY f.competencia DESC,f.id),'[]') FROM ew_financeiro_interna.folhas_industriais f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.galpao_id WHERE f.empresa_id=p_empresa_id AND f.competencia BETWEEN date_trunc('month',p_inicio::timestamp)::date AND p_fim) ELSE '[]'::jsonb END) INTO r;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_rh_consultar(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_rh_consultar(uuid,date,date) TO authenticated;
COMMIT;
