BEGIN;
-- v46.29: primeira etapa, catálogo de grupos e compatibilidade fornecedor/grupo.
-- Não aplicar isoladamente em produção: depende do fluxo de cotação por grupo.
CREATE TABLE ew_compras_interna.grupos_compra (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 codigo text NOT NULL CHECK (codigo ~ '^[A-Z][A-Z0-9_]{1,39}$'),
 nome text NOT NULL CHECK (length(btrim(nome)) BETWEEN 2 AND 100),
 ativo boolean NOT NULL DEFAULT true,
 criado_por uuid, criado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,codigo), UNIQUE(empresa_id,id)
);
CREATE UNIQUE INDEX grupos_compra_nome_unico ON ew_compras_interna.grupos_compra(empresa_id,lower(btrim(nome)));
CREATE TABLE ew_compras_interna.fornecedores_grupos (
 empresa_id uuid NOT NULL,
 grupo_id uuid NOT NULL,
 fornecedor_id uuid NOT NULL REFERENCES public.ew_fornecedores(id),
 criado_por uuid NOT NULL, criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,grupo_id,fornecedor_id),
 FOREIGN KEY(empresa_id,grupo_id) REFERENCES ew_compras_interna.grupos_compra(empresa_id,id)
);
CREATE TABLE ew_compras_interna.materiais_grupos (
 empresa_id uuid NOT NULL,
 grupo_id uuid NOT NULL,
 variacao_id uuid NOT NULL REFERENCES public.ew_materiais_variacoes(id),
 criado_por uuid NOT NULL, criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,variacao_id),
 FOREIGN KEY(empresa_id,grupo_id) REFERENCES ew_compras_interna.grupos_compra(empresa_id,id)
);
ALTER TABLE ew_compras_interna.grupos_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_compras_interna.fornecedores_grupos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_compras_interna.materiais_grupos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.grupos_compra,ew_compras_interna.fornecedores_grupos,ew_compras_interna.materiais_grupos FROM PUBLIC,anon,authenticated;

INSERT INTO ew_compras_interna.grupos_compra(empresa_id,codigo,nome)
SELECT e.id,g.codigo,g.nome FROM public.empresas e
CROSS JOIN (VALUES ('PERFIS','Perfis'),('ACESSORIOS','Acessórios'),('VIDROS','Vidros'),('FERRAMENTAS','Ferramentas'),('EPI','EPI'),('DIVERSOS','Diversos')) g(codigo,nome)
ON CONFLICT(empresa_id,codigo) DO NOTHING;
INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem)
VALUES('compras.gerenciar_grupos','Compras','Cadastrar grupos de compra e classificar fornecedores e materiais',47) ON CONFLICT DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT empresa_id,nivel,'compras.gerenciar_grupos',nivel=1 FROM public.ew_niveis_acesso ON CONFLICT DO NOTHING;

CREATE FUNCTION public.ew_compras_grupos_catalogo(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'compras.consultar') OR public.ew_pode(p_empresa_id,'compras.gerenciar_grupos')) THEN RAISE EXCEPTION 'Sem acesso aos grupos de compra.';END IF;
 RETURN jsonb_build_object(
 'grupos',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',g.id,'codigo',g.codigo,'nome',g.nome,'ativo',g.ativo) ORDER BY g.nome),'[]'::jsonb) FROM ew_compras_interna.grupos_compra g WHERE g.empresa_id=p_empresa_id),
 'fornecedores',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.nome,'ativo',f.ativo,'grupos',(SELECT coalesce(jsonb_agg(x.grupo_id ORDER BY x.grupo_id),'[]'::jsonb) FROM ew_compras_interna.fornecedores_grupos x WHERE x.empresa_id=p_empresa_id AND x.fornecedor_id=f.id)) ORDER BY f.nome),'[]'::jsonb) FROM public.ew_fornecedores f WHERE f.empresa_id=p_empresa_id));
END;$f$;
CREATE FUNCTION public.ew_compras_salvar_grupo(p_empresa_id uuid,p_codigo text,p_nome text,p_ativo boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE gid uuid;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.gerenciar_grupos') THEN RAISE EXCEPTION 'Sem permissão para editar grupos.';END IF;
 IF p_codigo IS NULL OR p_codigo !~ '^[A-Z][A-Z0-9_]{1,39}$' OR p_nome IS NULL OR length(btrim(p_nome)) NOT BETWEEN 2 AND 100 OR p_ativo IS NULL THEN RAISE EXCEPTION 'Grupo inválido.';END IF;
 IF NOT p_ativo AND p_codigo IN ('PERFIS','ACESSORIOS') THEN RAISE EXCEPTION 'Grupo padrão de material técnico não pode ser desativado.';END IF;
 INSERT INTO ew_compras_interna.grupos_compra(empresa_id,codigo,nome,ativo,criado_por)
 VALUES(p_empresa_id,p_codigo,btrim(p_nome),p_ativo,auth.uid())
 ON CONFLICT(empresa_id,codigo) DO UPDATE SET nome=excluded.nome,ativo=excluded.ativo RETURNING id INTO gid;
 RETURN gid;
END;$f$;
CREATE FUNCTION public.ew_compras_salvar_grupos_fornecedor(p_empresa_id uuid,p_fornecedor_id uuid,p_grupos uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE ids uuid[]; n int;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.gerenciar_grupos') THEN RAISE EXCEPTION 'Sem permissão para classificar fornecedores.';END IF;
 IF p_grupos IS NULL OR cardinality(p_grupos)>100 OR array_position(p_grupos,NULL) IS NOT NULL THEN RAISE EXCEPTION 'Grupos inválidos.';END IF;
 SELECT coalesce(array_agg(DISTINCT x ORDER BY x),'{}'::uuid[]) INTO ids FROM unnest(p_grupos) x;
 IF cardinality(ids)<>cardinality(p_grupos) THEN RAISE EXCEPTION 'Grupo repetido.';END IF;
 PERFORM 1 FROM public.ew_fornecedores WHERE id=p_fornecedor_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fornecedor inexistente nesta empresa.';END IF;
 SELECT count(*) INTO n FROM ew_compras_interna.grupos_compra WHERE empresa_id=p_empresa_id AND id=ANY(ids) AND ativo;
 IF n<>cardinality(ids) THEN RAISE EXCEPTION 'Grupo inativo ou de outra empresa.';END IF;
 DELETE FROM ew_compras_interna.fornecedores_grupos WHERE empresa_id=p_empresa_id AND fornecedor_id=p_fornecedor_id AND NOT(grupo_id=ANY(ids));
 INSERT INTO ew_compras_interna.fornecedores_grupos(empresa_id,fornecedor_id,grupo_id,criado_por)
 SELECT p_empresa_id,p_fornecedor_id,x,auth.uid() FROM unnest(ids) x ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('fornecedor_id',p_fornecedor_id,'grupos',ids);
END;$f$;
CREATE FUNCTION public.ew_compras_classificar_material(p_empresa_id uuid,p_variacao_id uuid,p_grupo_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.gerenciar_grupos') THEN RAISE EXCEPTION 'Sem permissão para classificar materiais.';END IF;
 PERFORM 1 FROM public.ew_materiais_variacoes WHERE id=p_variacao_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Material inexistente nesta empresa.';END IF;
 IF p_grupo_id IS NULL THEN
  DELETE FROM ew_compras_interna.materiais_grupos WHERE empresa_id=p_empresa_id AND variacao_id=p_variacao_id;
  RETURN;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_compras_interna.grupos_compra WHERE id=p_grupo_id AND empresa_id=p_empresa_id AND ativo) THEN RAISE EXCEPTION 'Grupo inválido.';END IF;
 INSERT INTO ew_compras_interna.materiais_grupos(empresa_id,variacao_id,grupo_id,criado_por)
 VALUES(p_empresa_id,p_variacao_id,p_grupo_id,auth.uid()) ON CONFLICT(empresa_id,variacao_id) DO UPDATE SET grupo_id=excluded.grupo_id,criado_por=excluded.criado_por,criado_em=now();
END;$f$;
-- Prévia read-only; não materializa solicitações-filhas e não altera a demanda.
CREATE FUNCTION public.ew_compras_previa_grupos(p_empresa_id uuid,p_solicitacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
DECLARE s public.ew_compras_solicitacoes%rowtype; result jsonb;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'compras.cotar') AND public.ew_pode(p_empresa_id,'compras.consultar_valores')) THEN RAISE EXCEPTION 'Sem permissão para cotar.';END IF;
 SELECT * INTO s FROM public.ew_compras_solicitacoes WHERE id=p_solicitacao_id AND empresa_id=p_empresa_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitação inexistente nesta empresa.';END IF;
 WITH itens AS (
 SELECT x.item,x.ord,v.id variacao_id,CASE WHEN mg.grupo_id IS NOT NULL THEN mg.grupo_id ELSE base.id END grupo_id
 FROM jsonb_array_elements(s.itens) WITH ORDINALITY x(item,ord)
 LEFT JOIN public.ew_materiais_variacoes v ON v.id=(x.item->>'variacao_id')::uuid AND v.empresa_id=p_empresa_id
 LEFT JOIN ew_compras_interna.materiais_grupos mg ON mg.variacao_id=v.id AND mg.empresa_id=p_empresa_id
 LEFT JOIN ew_compras_interna.grupos_compra base ON base.empresa_id=p_empresa_id AND base.codigo=CASE v.tipo WHEN 'perfil' THEN 'PERFIS' WHEN 'acessorio' THEN 'ACESSORIOS' ELSE NULL END
 ), grupos AS (
 SELECT g.id,g.nome,g.ativo,jsonb_agg(i.item ORDER BY i.ord) itens
 FROM itens i LEFT JOIN ew_compras_interna.grupos_compra g ON g.id=i.grupo_id AND g.empresa_id=p_empresa_id
 GROUP BY g.id,g.nome,g.ativo
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('grupo_id',g.id,'nome',coalesce(g.nome,'Sem classificação'),'ativo',coalesce(g.ativo,false),'itens',g.itens,'fornecedores',
 (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.nome) ORDER BY f.nome),'[]'::jsonb)
 FROM ew_compras_interna.fornecedores_grupos fg JOIN public.ew_fornecedores f ON f.id=fg.fornecedor_id AND f.empresa_id=fg.empresa_id AND f.ativo
 WHERE fg.empresa_id=p_empresa_id AND fg.grupo_id=g.id AND g.ativo)) ORDER BY g.nome),'[]'::jsonb) INTO result FROM grupos g;
 RETURN result;
END;$f$;
REVOKE ALL ON FUNCTION public.ew_compras_grupos_catalogo(uuid),public.ew_compras_salvar_grupo(uuid,text,text,boolean),public.ew_compras_salvar_grupos_fornecedor(uuid,uuid,uuid[]),public.ew_compras_classificar_material(uuid,uuid,uuid),public.ew_compras_previa_grupos(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_grupos_catalogo(uuid),public.ew_compras_salvar_grupo(uuid,text,text,boolean),public.ew_compras_salvar_grupos_fornecedor(uuid,uuid,uuid[]),public.ew_compras_classificar_material(uuid,uuid,uuid),public.ew_compras_previa_grupos(uuid,uuid) TO authenticated;
COMMIT;
