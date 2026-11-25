BEGIN;
-- Proposta de catálogo versionado; não ativa a nova expedição automaticamente.
-- Permissões novas, sem alterar flags existentes.
INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES
 ('cadastros.composicao_consultar','Cadastros','Consultar composição de expedição',36),
 ('cadastros.composicao_editar','Cadastros','Cadastrar/alterar composição de expedição e aplicar a similares',37)
ON CONFLICT(chave) DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT n.empresa_id,n.nivel,c.chave,
 CASE WHEN n.nivel=1 THEN true WHEN n.nivel=8 THEN false
 WHEN c.chave='cadastros.composicao_consultar' THEN coalesce(pc.permitido,false)
 ELSE coalesce(pc.permitido,false) AND coalesce(pe.permitido,false) AND n.nivel IN (2,3) END
FROM public.ew_niveis_acesso n
CROSS JOIN (VALUES ('cadastros.composicao_consultar'),('cadastros.composicao_editar')) c(chave)
LEFT JOIN public.ew_niveis_permissoes pc ON pc.empresa_id=n.empresa_id AND pc.nivel=n.nivel AND pc.chave='cadastros.consultar'
LEFT JOIN public.ew_niveis_permissoes pe ON pe.empresa_id=n.empresa_id AND pe.nivel=n.nivel AND pe.chave='cadastros.editar'
ON CONFLICT(empresa_id,nivel,chave) DO NOTHING;
CREATE SCHEMA IF NOT EXISTS ew_expedicao_interna;
REVOKE ALL ON SCHEMA ew_expedicao_interna FROM PUBLIC,anon,authenticated;
CREATE TABLE ew_expedicao_interna.revisoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 tipologia_id uuid NOT NULL REFERENCES public.tipologias(id) ON DELETE RESTRICT,
 revisao integer NOT NULL CHECK (revisao>0),
 partes jsonb NOT NULL CHECK (jsonb_typeof(partes)='array'),
 operacao_id uuid NOT NULL,
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,tipologia_id,revisao),
 UNIQUE(empresa_id,tipologia_id,operacao_id)
);
ALTER TABLE ew_expedicao_interna.revisoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_expedicao_interna.revisoes FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_listar_composicoes_expedicao(p_empresa_id uuid,p_tipologias uuid[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'cadastros.consultar') OR NOT public.ew_pode(p_empresa_id,'cadastros.composicao_consultar') THEN RAISE EXCEPTION 'Sem permissão de cadastro.'; END IF;
 IF p_tipologias IS NULL OR cardinality(p_tipologias) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Consulte de 1 a 200 tipologias.'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM (
  SELECT DISTINCT ON (v.tipologia_id) v.tipologia_id,v.id AS revisao_id,v.revisao,v.partes
  FROM ew_expedicao_interna.revisoes v JOIN public.tipologias t ON t.id=v.tipologia_id AND t.empresa_id=v.empresa_id
  WHERE v.empresa_id=p_empresa_id AND v.tipologia_id=ANY(p_tipologias)
  ORDER BY v.tipologia_id,v.revisao DESC
 ) r);
END;$f$;

CREATE OR REPLACE FUNCTION public.ew_salvar_composicoes_expedicao(p_empresa_id uuid,p_alvos jsonb,p_partes jsonb,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE u uuid:=auth.uid(); x jsonb; p jsonb; alvo uuid; anterior uuid; atual uuid; versao integer; total integer:=0;
 n integer; ids text[]:=ARRAY[]::text[]; nomes text[]:=ARRAY[]::text[]; alvos uuid[]:=ARRAY[]::uuid[];
 resultado jsonb:='[]'::jsonb; normalizadas jsonb:='[]'::jsonb; peso integer; qtd integer; nome text; chave text; pid text;
 existente ew_expedicao_interna.revisoes%rowtype; repeticoes integer;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF u IS NULL OR NOT public.ew_pode(p_empresa_id,'cadastros.editar') OR NOT public.ew_pode(p_empresa_id,'cadastros.consultar') OR NOT public.ew_pode(p_empresa_id,'cadastros.composicao_consultar') OR NOT public.ew_pode(p_empresa_id,'cadastros.composicao_editar') THEN RAISE EXCEPTION 'Sem permissão para editar composições.'; END IF;
 IF p_operacao_id IS NULL OR jsonb_typeof(p_partes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_partes) NOT BETWEEN 1 AND 30
 OR jsonb_typeof(p_alvos) IS DISTINCT FROM 'array' OR jsonb_array_length(p_alvos) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Informe componentes e tipologias válidos.'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements(p_partes) LOOP
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR jsonb_typeof(p->'peso') IS DISTINCT FROM 'number'
   OR jsonb_typeof(p->'quantidade') IS DISTINCT FROM 'number' OR jsonb_typeof(p->'id') IS DISTINCT FROM 'string'
   OR jsonb_typeof(p->'nome') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Componente inválido.'; END IF;
  pid:=btrim(p->>'id'); nome:=btrim(p->>'nome'); chave:=upper(regexp_replace(nome,'[[:space:]]+',' ','g'));
  IF length(pid) NOT BETWEEN 1 AND 80 OR length(nome) NOT BETWEEN 1 AND 100 OR pid=ANY(ids) OR chave=ANY(nomes)
   OR (p->>'quantidade')::numeric NOT BETWEEN 1 AND 100 OR (p->>'peso')::numeric NOT BETWEEN 1 AND 10000
   OR trunc((p->>'quantidade')::numeric)<>(p->>'quantidade')::numeric OR trunc((p->>'peso')::numeric)<>(p->>'peso')::numeric
  THEN RAISE EXCEPTION 'Componente repetido, quantidade ou percentual inválido.'; END IF;
  qtd:=(p->>'quantidade')::integer; peso:=(p->>'peso')::integer;
  ids:=array_append(ids,pid); nomes:=array_append(nomes,chave); total:=total+peso;
  normalizadas:=normalizadas||jsonb_build_array(jsonb_build_object('id',pid,'nome',nome,'quantidade',qtd,'peso',peso));
 END LOOP;
 IF total<>10000 THEN RAISE EXCEPTION 'Os percentuais precisam somar 100%%.'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_alvos) LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' OR NOT (x ? 'revisao_id') OR jsonb_typeof(x->'tipologia_id') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Seleção de tipologia inválida.'; END IF;
  alvo:=(x->>'tipologia_id')::uuid;
  IF alvo IS NULL OR alvo=ANY(alvos) THEN RAISE EXCEPTION 'Tipologia repetida.'; END IF;
  alvos:=array_append(alvos,alvo);
 END LOOP;
 -- Serializar salvamento em lote na empresa; conferir todas as revisões antes de gravar.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_empresa_id::text,842625));
 PERFORM 1 FROM public.tipologias WHERE empresa_id=p_empresa_id AND id=ANY(alvos) AND NOT provisoria ORDER BY id FOR UPDATE;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>cardinality(alvos) THEN RAISE EXCEPTION 'Tipologia provisória, inexistente ou de outra empresa.'; END IF;
 SELECT count(*) INTO repeticoes FROM ew_expedicao_interna.revisoes WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF repeticoes>0 THEN
  IF repeticoes<>cardinality(alvos) OR EXISTS(SELECT 1 FROM ew_expedicao_interna.revisoes WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id AND (NOT tipologia_id=ANY(alvos) OR partes<>normalizadas OR criado_por<>u))
  THEN RAISE EXCEPTION 'Identificador de operação reutilizado.'; END IF;
  RETURN (SELECT jsonb_agg(jsonb_build_object('tipologia_id',tipologia_id,'revisao_id',id,'revisao',revisao)) FROM ew_expedicao_interna.revisoes WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id);
 END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_alvos) LOOP
  alvo:=(x->>'tipologia_id')::uuid; anterior:=(x->>'revisao_id')::uuid;
  SELECT id,revisao INTO atual,versao FROM ew_expedicao_interna.revisoes WHERE empresa_id=p_empresa_id AND tipologia_id=alvo ORDER BY revisao DESC LIMIT 1;
  IF atual IS DISTINCT FROM anterior THEN RAISE EXCEPTION 'Composição alterada por outro usuário. Atualize e confira antes de salvar.'; END IF;
  INSERT INTO ew_expedicao_interna.revisoes(empresa_id,tipologia_id,revisao,partes,operacao_id,criado_por)
  VALUES(p_empresa_id,alvo,coalesce(versao,0)+1,normalizadas,p_operacao_id,u) RETURNING * INTO existente;
  resultado:=resultado||jsonb_build_array(jsonb_build_object('tipologia_id',alvo,'revisao_id',existente.id,'revisao',existente.revisao));
 END LOOP;
 RETURN resultado;
END;$f$;
REVOKE ALL ON FUNCTION public.ew_listar_composicoes_expedicao(uuid,uuid[]),public.ew_salvar_composicoes_expedicao(uuid,jsonb,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_listar_composicoes_expedicao(uuid,uuid[]),public.ew_salvar_composicoes_expedicao(uuid,jsonb,jsonb,uuid) TO authenticated;
COMMIT;
