-- Executar apenas em transação revertida, no ambiente de testes.
DO $test$ DECLARE u uuid;e uuid;a uuid;c uuid;b uuid;p uuid;v uuid;r jsonb; BEGIN
SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
r:=public.ew_criar_obra_estoque(e,'LOCAL MANUAL TESTE',''); a:=(r->>'id')::uuid;
INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'OBRA TESTE CEM','CEM-TESTE-120') RETURNING id INTO b;
r:=public.ew_compras_criar_local_empresa(e,'EMPRESA TESTE 120'); c:=(r->>'id')::uuid;
IF public.ew_local_estoque_motivo(e,'OBRA',a) IS NOT NULL OR public.ew_local_estoque_motivo(e,'OBRA',b) IS NULL OR public.ew_local_estoque_motivo(e,'EMPRESA',c) IS NOT NULL THEN RAISE EXCEPTION 'Classificação incorreta'; END IF;
BEGIN PERFORM public.ew_excluir_cadastro_local_estoque(e,'OBRA',b,'Teste proteção CEM'); RAISE EXCEPTION 'FALHA proteção'; EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Vinculado a obra%' THEN RAISE; END IF; END;
INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-120','Perfil teste','TESTE') RETURNING id INTO p;
INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(e,'AFOGADOS');
INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,a,v,6000,'BARRA',1,'ABERTURA',gen_random_uuid(),u,'AFOGADOS');
BEGIN PERFORM public.ew_excluir_cadastro_local_estoque(e,'OBRA',a,'Teste saldo não zero'); RAISE EXCEPTION 'FALHA saldo'; EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Possui saldo%' THEN RAISE; END IF; END;
INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,a,v,6000,'BARRA',-1,'AJUSTE',gen_random_uuid(),u,'AFOGADOS');
PERFORM public.ew_excluir_cadastro_local_estoque(e,'OBRA',a,'Teste exclusão manual');
PERFORM public.ew_excluir_cadastro_local_estoque(e,'EMPRESA',c,'Teste exclusão empresa');
IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos WHERE obra_id=a)<>2 OR EXISTS(SELECT 1 FROM public.obras WHERE id=a AND arquivada_em IS NULL) OR EXISTS(SELECT 1 FROM public.ew_compras_locais_empresa WHERE id=c AND ativo) THEN RAISE EXCEPTION 'Exclusão ou histórico incorretos'; END IF;
BEGIN INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,a,v,6000,'BARRA',1,'ABERTURA',gen_random_uuid(),u,'AFOGADOS'); RAISE EXCEPTION 'FALHA local excluído'; EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Local manual excluído%' THEN RAISE; END IF; END;
END $test$;