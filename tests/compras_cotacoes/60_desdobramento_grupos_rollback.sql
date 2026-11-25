-- Executar na restauração com dependências v46.21/v46.28 e proposta v46.29, em transação revertida.
DO $t$
DECLARE u uuid;e uuid;o uuid;p uuid;a uuid;v uuid;va uuid;fp uuid;fa uuid;fb uuid;s uuid;gp uuid;ga uuid;gt uuid;r jsonb;it jsonb;blocked boolean;sp uuid;sa uuid;qp uuid;qa uuid;pp uuid;pa uuid;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
 SELECT e,1,k,true FROM unnest(ARRAY['compras.solicitar','compras.consultar','compras.cotar','compras.consultar_valores','compras.gerenciar_grupos','compras.pedir','compras.aprovar_pedido','compras.replicar_cotacao']) k ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE 90','TESTE-90-GRUPOS') RETURNING id INTO o;
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-90-P','Perfil','Teste') RETURNING id INTO p;
 INSERT INTO public.ew_acessorios(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-90-A','Acessório','Teste') RETURNING id INTO a;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,acessorio_id,cor,acabamento) VALUES(e,'acessorio',a,'PRETO','PRETO') RETURNING id INTO va;
 INSERT INTO public.ew_fornecedores(empresa_id,nome) VALUES(e,'Fornecedor teste perfil 90') RETURNING id INTO fp;
 INSERT INTO public.ew_fornecedores(empresa_id,nome) VALUES(e,'Fornecedor teste acessório 90') RETURNING id INTO fa;
 INSERT INTO public.ew_fornecedores(empresa_id,nome) VALUES(e,'Fornecedor teste ambos 90') RETURNING id INTO fb;
 SELECT id INTO STRICT gp FROM ew_compras_interna.grupos_compra WHERE empresa_id=e AND codigo='PERFIS';
 SELECT id INTO STRICT ga FROM ew_compras_interna.grupos_compra WHERE empresa_id=e AND codigo='ACESSORIOS';
 PERFORM public.ew_compras_salvar_grupos_fornecedor(e,fp,ARRAY[gp]);
 PERFORM public.ew_compras_salvar_grupos_fornecedor(e,fa,ARRAY[ga]);
 PERFORM public.ew_compras_salvar_grupos_fornecedor(e,fb,ARRAY[gp,ga]);
 it:=jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v,'quantidade',1,'unidade','BARRA','comprimento_mm',6000),jsonb_build_object('chave','2','variacao_id',va,'quantidade',1,'unidade','PC','comprimento_mm',null));
 r:=public.ew_compras_criar_solicitacao(e,o,null,it,'Teste',gen_random_uuid());s:=(r->>'id')::uuid;
 r:=public.ew_compras_previa_grupos(e,s);
 IF jsonb_array_length(r)<>2 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'grupo_id'=gp::text AND jsonb_array_length(x->'itens')=1 AND x->'itens'->0->>'chave'='1' AND x->'fornecedores' @> jsonb_build_array(jsonb_build_object('id',fp),jsonb_build_object('id',fb)) AND NOT x->'fornecedores' @> jsonb_build_array(jsonb_build_object('id',fa))) THEN RAISE EXCEPTION 'Perfis não isolados %',r; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'grupo_id'=ga::text AND x->'itens'->0->>'chave'='2' AND x->'fornecedores' @> jsonb_build_array(jsonb_build_object('id',fa),jsonb_build_object('id',fb)) AND NOT x->'fornecedores' @> jsonb_build_array(jsonb_build_object('id',fp))) THEN RAISE EXCEPTION 'Acessórios não isolados %',r;END IF;
 gt:=public.ew_compras_salvar_grupo(e,'TESTE90','Grupo teste 90',true);
 PERFORM public.ew_compras_classificar_material(e,va,gt);
 r:=public.ew_compras_previa_grupos(e,s);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'grupo_id'=gt::text AND x->'itens'->0->>'chave'='2' AND jsonb_array_length(x->'fornecedores')=0) THEN RAISE EXCEPTION 'Classificação configurável inválida';END IF;
 PERFORM public.ew_compras_classificar_material(e,va,null);
 IF (SELECT count(*) FROM public.ew_compras_solicitacoes WHERE obra_id=o)<>1 THEN RAISE EXCEPTION 'Duplicação da solicitação';END IF;
 blocked:=false;BEGIN PERFORM public.ew_compras_salvar_grupos_fornecedor(e,fa,ARRAY[gen_random_uuid()]);EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Grupo inativo%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'Grupo inválido aceito';END IF;
 IF has_function_privilege('anon','public.ew_compras_previa_grupos(uuid,uuid)','EXECUTE') OR has_table_privilege('authenticated','ew_compras_interna.fornecedores_grupos','SELECT') THEN RAISE EXCEPTION 'Acesso direto indevido';END IF;

 PERFORM public.ew_compras_desdobrar_grupos(e,s,gen_random_uuid());
 PERFORM public.ew_compras_desdobrar_grupos(e,s,gen_random_uuid());
 r:=public.ew_compras_grupos_desdobrados(e);
 SELECT (x->>'filha_id')::uuid INTO STRICT sp FROM jsonb_array_elements(r) x WHERE x->>'solicitacao_id'=s::text AND x->>'grupo_id'=gp::text;
 SELECT (x->>'filha_id')::uuid INTO STRICT sa FROM jsonb_array_elements(r) x WHERE x->>'solicitacao_id'=s::text AND x->>'grupo_id'=ga::text;
 IF (SELECT status FROM public.ew_compras_solicitacoes WHERE id=s)<>'DESDOBRADA' OR (SELECT count(*) FROM public.ew_compras_solicitacoes WHERE obra_id=o)<>3 THEN RAISE EXCEPTION 'Desdobramento duplicado';END IF;
 blocked:=false;BEGIN PERFORM public.ew_compras_criar_cotacao(sp,fa,'[{"chave":"1","preco_unitario_centavos":10000}]',gen_random_uuid());EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Fornecedor não atende%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'Fornecedor incompatível aceito';END IF;
 blocked:=false;BEGIN PERFORM public.ew_compras_replicar_cotacao(e,sp,ARRAY[fp,fa]);EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Fornecedor não atende%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked OR EXISTS(SELECT 1 FROM ew_compras_interna.convites WHERE solicitacao_id=sp) THEN RAISE EXCEPTION 'Convites incompatíveis registrados';END IF;
 PERFORM public.ew_compras_replicar_cotacao(e,sp,ARRAY[fp,fb]);
 r:=public.ew_compras_criar_cotacao(sp,fp,'[{"chave":"1","preco_unitario_centavos":10000}]',gen_random_uuid());qp:=(r->>'id')::uuid;
 r:=public.ew_compras_criar_pedido(qp,gen_random_uuid());pp:=(r->>'id')::uuid;
 IF (SELECT status FROM public.ew_compras_solicitacoes WHERE id=sa)<>'ABERTA' THEN RAISE EXCEPTION 'Pedido de perfil encerrou acessório';END IF;
 r:=public.ew_compras_criar_cotacao(sa,fa,'[{"chave":"2","preco_unitario_centavos":2000}]',gen_random_uuid());qa:=(r->>'id')::uuid;
 r:=public.ew_compras_criar_pedido(qa,gen_random_uuid());pa:=(r->>'id')::uuid;
 IF (SELECT sum(total_centavos) FROM public.ew_compras_pedidos WHERE id IN (pp,pa))<>12000 THEN RAISE EXCEPTION 'Total incorreto';END IF;
END;$t$;
SELECT 'PASS: desdobramento, bloqueio de fornecedores incompatíveis, dois pedidos independentes e total preservado' AS resultado;
