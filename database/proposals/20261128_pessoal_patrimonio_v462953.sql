-- Cadastros industriais e históricos gerenciais, sem lançamentos financeiros automáticos.
BEGIN;
CREATE TABLE ew_financeiro_interna.funcionarios_industriais(
 empresa_id uuid NOT NULL,id uuid NOT NULL,matricula text NOT NULL,nome text NOT NULL,funcao text NOT NULL,
 galpao_id uuid NOT NULL,admissao date NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,id),UNIQUE(empresa_id,matricula)
);
CREATE TABLE ew_financeiro_interna.folhas_industriais(
 empresa_id uuid NOT NULL,id uuid NOT NULL,galpao_id uuid NOT NULL,competencia date NOT NULL CHECK(extract(day from competencia)=1),
 salarios bigint NOT NULL CHECK(salarios>=0),encargos bigint NOT NULL CHECK(encargos>=0),beneficios bigint NOT NULL CHECK(beneficios>=0),
 referencia text NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 estornado_em timestamptz,estornado_por uuid,estorno_id uuid,estorno_motivo text,PRIMARY KEY(empresa_id,id)
);
CREATE UNIQUE INDEX ew_folha_ativa ON ew_financeiro_interna.folhas_industriais(empresa_id,galpao_id,competencia) WHERE estornado_em IS NULL;
CREATE UNIQUE INDEX ew_folha_estorno ON ew_financeiro_interna.folhas_industriais(empresa_id,estorno_id) WHERE estorno_id IS NOT NULL;
CREATE TABLE ew_financeiro_interna.ativos_industriais(
 empresa_id uuid NOT NULL,id uuid NOT NULL,codigo text NOT NULL,descricao text NOT NULL,galpao_id uuid NOT NULL,
 inicio date NOT NULL CHECK(extract(day from inicio)=1),valor_centavos bigint NOT NULL CHECK(valor_centavos>0),
 residual_centavos bigint NOT NULL CHECK(residual_centavos>=0 AND residual_centavos<=valor_centavos),
 vida_meses int NOT NULL CHECK(vida_meses BETWEEN 1 AND 1200),criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,id),UNIQUE(empresa_id,codigo)
);
CREATE TABLE ew_financeiro_interna.depreciacoes_industriais(
 empresa_id uuid NOT NULL,ativo_id uuid NOT NULL,competencia date NOT NULL,valor_centavos bigint NOT NULL CHECK(valor_centavos>=0),
 operacao_id uuid NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,ativo_id,competencia),UNIQUE(empresa_id,operacao_id)
);
ALTER TABLE ew_financeiro_interna.funcionarios_industriais ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.folhas_industriais ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.ativos_industriais ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.depreciacoes_industriais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.funcionarios_industriais,ew_financeiro_interna.folhas_industriais,ew_financeiro_interna.ativos_industriais,ew_financeiro_interna.depreciacoes_industriais FROM PUBLIC,anon,authenticated;
CREATE FUNCTION ew_financeiro_interna.exigir_pessoal(p_empresa uuid,p_gravar boolean)
RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa,p_gravar,false);
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa,'usuarios.gerenciar') THEN RAISE EXCEPTION 'Sem acesso à gestão de pessoal.';END IF;
END $$;
REVOKE ALL ON FUNCTION ew_financeiro_interna.exigir_pessoal(uuid,boolean) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_industrial_cadastrar(p_empresa_id uuid,p_operacao_id uuid,p_tipo text,p_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE g uuid;d date;cod text;nom text;fun text;a bigint;b bigint;c bigint;vida int;
BEGIN
 IF p_tipo IN ('FUNCIONARIO','FOLHA') THEN PERFORM ew_financeiro_interna.exigir_pessoal(p_empresa_id,true);
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
CREATE FUNCTION public.ew_industrial_depreciar(p_empresa_id uuid,p_operacao_id uuid,p_ativo_id uuid,p_competencia date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a ew_financeiro_interna.ativos_industriais%ROWTYPE;v ew_financeiro_interna.depreciacoes_industriais%ROWTYPE;n int;val bigint;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_competencia IS NULL OR extract(day from p_competencia)<>1 OR p_competencia>date_trunc('month',now() AT TIME ZONE 'America/Recife')::date THEN RAISE EXCEPTION 'Competência inválida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|DEPRECIACAO|'||p_operacao_id::text,0));
 SELECT * INTO v FROM ew_financeiro_interna.depreciacoes_industriais WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF v.ativo_id IS DISTINCT FROM p_ativo_id OR v.competencia IS DISTINCT FROM p_competencia THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
  RETURN jsonb_build_object('repetido',true,'valor_centavos',v.valor_centavos);
 END IF;
 SELECT * INTO a FROM ew_financeiro_interna.ativos_industriais WHERE empresa_id=p_empresa_id AND id=p_ativo_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Ativo indisponível.';END IF;
 n:=(extract(year from p_competencia)::int-extract(year from a.inicio)::int)*12+extract(month from p_competencia)::int-extract(month from a.inicio)::int+1;
 IF n NOT BETWEEN 1 AND a.vida_meses THEN RAISE EXCEPTION 'Competência fora da vida útil.';END IF;
 IF (SELECT count(*) FROM ew_financeiro_interna.depreciacoes_industriais WHERE empresa_id=p_empresa_id AND ativo_id=a.id AND competencia<p_competencia)<>n-1 THEN RAISE EXCEPTION 'Registre as competências anteriores primeiro.';END IF;
 val:=round((a.valor_centavos-a.residual_centavos)::numeric*n/a.vida_meses)-round((a.valor_centavos-a.residual_centavos)::numeric*(n-1)/a.vida_meses);
 INSERT INTO ew_financeiro_interna.depreciacoes_industriais(empresa_id,ativo_id,competencia,valor_centavos,operacao_id,criado_por) VALUES(p_empresa_id,a.id,p_competencia,val,p_operacao_id,auth.uid());
 RETURN jsonb_build_object('repetido',false,'valor_centavos',val);
END $$;
CREATE FUNCTION public.ew_industrial_cadastros_consultar(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;rh boolean;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF auth.uid() IS NULL OR p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Período inválido.';END IF;
 rh:=public.ew_pode(p_empresa_id,'usuarios.gerenciar');
 SELECT jsonb_build_object('pessoal_permitido',rh,
 'funcionarios',CASE WHEN rh THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'matricula',f.matricula,'nome',f.nome,'funcao',f.funcao,'local',g.nome,'admissao',f.admissao) ORDER BY f.nome,f.id),'[]') FROM ew_financeiro_interna.funcionarios_industriais f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.galpao_id WHERE f.empresa_id=p_empresa_id) ELSE '[]'::jsonb END,
 'folhas',CASE WHEN rh THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'local',g.nome,'competencia',f.competencia,'salarios',f.salarios,'encargos',f.encargos,'beneficios',f.beneficios,'referencia',f.referencia,'estornado_em',f.estornado_em,'estorno_motivo',f.estorno_motivo) ORDER BY f.competencia DESC,f.id),'[]') FROM ew_financeiro_interna.folhas_industriais f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.galpao_id WHERE f.empresa_id=p_empresa_id AND f.competencia BETWEEN date_trunc('month',p_inicio::timestamp)::date AND p_fim) ELSE '[]'::jsonb END,
 'ativos',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'codigo',a.codigo,'descricao',a.descricao,'local',g.nome,'inicio',a.inicio,'valor_centavos',a.valor_centavos,'residual_centavos',a.residual_centavos,'vida_meses',a.vida_meses,'depreciado_centavos',coalesce(d.total,0),'meses',coalesce(d.meses,0)) ORDER BY a.codigo),'[]') FROM ew_financeiro_interna.ativos_industriais a LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=a.empresa_id AND g.id=a.galpao_id LEFT JOIN LATERAL(SELECT sum(valor_centavos) total,count(*) meses FROM ew_financeiro_interna.depreciacoes_industriais d WHERE d.empresa_id=a.empresa_id AND d.ativo_id=a.id)d ON true WHERE a.empresa_id=p_empresa_id),
 'depreciacoes',(SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',a.codigo,'local',g.nome,'competencia',d.competencia,'valor_centavos',d.valor_centavos) ORDER BY d.competencia DESC,a.codigo),'[]') FROM ew_financeiro_interna.depreciacoes_industriais d JOIN ew_financeiro_interna.ativos_industriais a ON a.empresa_id=d.empresa_id AND a.id=d.ativo_id LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=a.empresa_id AND g.id=a.galpao_id WHERE d.empresa_id=p_empresa_id AND d.competencia BETWEEN date_trunc('month',p_inicio::timestamp)::date AND p_fim)) INTO r;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_industrial_cadastrar(uuid,uuid,text,jsonb),public.ew_industrial_depreciar(uuid,uuid,uuid,date),public.ew_industrial_cadastros_consultar(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_industrial_cadastrar(uuid,uuid,text,jsonb),public.ew_industrial_depreciar(uuid,uuid,uuid,date),public.ew_industrial_cadastros_consultar(uuid,date,date) TO authenticated;
COMMIT;
