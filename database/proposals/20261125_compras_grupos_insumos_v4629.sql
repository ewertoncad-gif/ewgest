BEGIN;
-- Grupos comerciais dos insumos reutilizam o cadastro existente e NÃO alteram a categoria fiscal.
-- Esta etapa não habilita a compra/recebimento por pedido de insumos genéricos.
CREATE TABLE ew_compras_interna.insumos_grupos (
 empresa_id uuid NOT NULL,
 grupo_id uuid NOT NULL,
 insumo_id uuid NOT NULL,
 criado_por uuid NOT NULL,
 criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,insumo_id),
 FOREIGN KEY(empresa_id,grupo_id) REFERENCES ew_compras_interna.grupos_compra(empresa_id,id),
 FOREIGN KEY(empresa_id,insumo_id) REFERENCES public.ew_insumos_catalogo(empresa_id,id) ON DELETE CASCADE
);
ALTER TABLE ew_compras_interna.insumos_grupos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.insumos_grupos FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_compras_insumos_grupos_listar(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.gerenciar_grupos') THEN RAISE EXCEPTION 'Sem permissão para consultar classificação de insumos.';END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.id,'descricao',i.descricao,'unidade',i.unidade,'categoria',i.categoria,'ativo',i.ativo,'grupo_id',coalesce(m.grupo_id,g.id)) ORDER BY i.descricao,i.unidade),'[]'::jsonb)
 FROM public.ew_insumos_catalogo i LEFT JOIN ew_compras_interna.insumos_grupos m ON m.empresa_id=i.empresa_id AND m.insumo_id=i.id
 LEFT JOIN ew_compras_interna.grupos_compra g ON g.empresa_id=i.empresa_id AND g.codigo=CASE i.categoria WHEN 'vidros' THEN 'VIDROS' ELSE 'DIVERSOS' END
 WHERE i.empresa_id=p_empresa_id);
END;$f$;
CREATE FUNCTION public.ew_compras_insumo_classificar_grupo(p_empresa_id uuid,p_insumo_id uuid,p_grupo_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.gerenciar_grupos') THEN RAISE EXCEPTION 'Sem permissão para classificar insumos.';END IF;
 PERFORM 1 FROM public.ew_insumos_catalogo WHERE empresa_id=p_empresa_id AND id=p_insumo_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Insumo inexistente nesta empresa.';END IF;
 IF p_grupo_id IS NULL THEN DELETE FROM ew_compras_interna.insumos_grupos WHERE empresa_id=p_empresa_id AND insumo_id=p_insumo_id;RETURN;END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_compras_interna.grupos_compra WHERE empresa_id=p_empresa_id AND id=p_grupo_id AND ativo AND codigo NOT IN ('PERFIS','ACESSORIOS')) THEN RAISE EXCEPTION 'Grupo incompatível com insumo não técnico.';END IF;
 INSERT INTO ew_compras_interna.insumos_grupos(empresa_id,grupo_id,insumo_id,criado_por) VALUES(p_empresa_id,p_grupo_id,p_insumo_id,auth.uid())
 ON CONFLICT(empresa_id,insumo_id) DO UPDATE SET grupo_id=excluded.grupo_id,criado_por=excluded.criado_por,criado_em=now();
END;$f$;
REVOKE ALL ON FUNCTION public.ew_compras_insumos_grupos_listar(uuid),public.ew_compras_insumo_classificar_grupo(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_insumos_grupos_listar(uuid),public.ew_compras_insumo_classificar_grupo(uuid,uuid,uuid) TO authenticated;
COMMIT;
