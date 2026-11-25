DO $t$
DECLARE u uuid;e uuid;i uuid;g uuid;d uuid;r jsonb;blocked boolean;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido) VALUES(e,1,'compras.gerenciar_grupos',true) ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.ew_insumos_catalogo(empresa_id,categoria,descricao,unidade,criado_por) VALUES(e,'outros','TESTE EPI V4629','PC',u) RETURNING id INTO i;
 SELECT id INTO STRICT g FROM ew_compras_interna.grupos_compra WHERE empresa_id=e AND codigo='EPI';
 SELECT id INTO STRICT d FROM ew_compras_interna.grupos_compra WHERE empresa_id=e AND codigo='DIVERSOS';
 r:=public.ew_compras_insumos_grupos_listar(e);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'id'=i::text AND x->>'grupo_id'=d::text) THEN RAISE EXCEPTION 'Padrão incorreto';END IF;
 PERFORM public.ew_compras_insumo_classificar_grupo(e,i,g);
 r:=public.ew_compras_insumos_grupos_listar(e);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'id'=i::text AND x->>'grupo_id'=g::text AND x->>'categoria'='outros') THEN RAISE EXCEPTION 'Classificação incorreta';END IF;
 IF (SELECT categoria FROM public.ew_insumos_catalogo WHERE id=i)<>'outros' THEN RAISE EXCEPTION 'Categoria financeira alterada';END IF;
 blocked:=false;BEGIN PERFORM public.ew_compras_insumo_classificar_grupo(e,i,gen_random_uuid());EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Grupo incompatível%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'Grupo inválido aceito';END IF;
 IF has_table_privilege('authenticated','ew_compras_interna.insumos_grupos','SELECT') OR has_function_privilege('anon','public.ew_compras_insumos_grupos_listar(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Privilégio indevido';END IF;
END;$t$;
SELECT 'PASS: classificação EPI, padrão Diversos, categoria fiscal preservada, grupo inválido bloqueado e acesso protegido' AS resultado;
