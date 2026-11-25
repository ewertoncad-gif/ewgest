-- Executar no ambiente isolado após a proposta, dentro de BEGIN/ROLLBACK; fixture requer usuário de teste e cadastros sintéticos.
DO $test$
DECLARE u uuid;e uuid;a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();op uuid:=gen_random_uuid();p jsonb:='[{"id":"marco","nome":"Marco","quantidade":1,"peso":5000},{"id":"folha","nome":"Folha","quantidade":1,"peso":4000},{"id":"vidro","nome":"Vidro do peitoril","quantidade":1,"peso":1000}]'; targets jsonb; r jsonb; r2 jsonb; blocked boolean; rev uuid;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES ('cadastros.consultar','Cadastros','Consultar',1),('cadastros.editar','Cadastros','Editar',2) ON CONFLICT(chave) DO NOTHING;
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido) VALUES(e,1,'cadastros.consultar',true),(e,1,'cadastros.editar',true) ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.tipologias(id,empresa_id,codigo,descricao,provisoria) VALUES(a,e,'TESTE-84-A','MAXIM AR COM PEITORIL - LINHA A',false),(b,e,'TESTE-84-B','MAXIM AR COM PEITORIL - LINHA B',false);
 targets:=jsonb_build_array(jsonb_build_object('tipologia_id',a,'revisao_id',null),jsonb_build_object('tipologia_id',b,'revisao_id',null));
 r:=public.ew_salvar_composicoes_expedicao(e,targets,p,op);
 IF jsonb_array_length(r)<>2 THEN RAISE EXCEPTION 'falha lote'; END IF;
 r2:=public.ew_salvar_composicoes_expedicao(e,targets,p,op);
 IF jsonb_array_length(r2)<>2 OR (SELECT count(*) FROM ew_expedicao_interna.revisoes WHERE operacao_id=op)<>2 THEN RAISE EXCEPTION 'falha idempotencia'; END IF;
 blocked:=false;BEGIN PERFORM public.ew_salvar_composicoes_expedicao(e,targets,p,gen_random_uuid()); EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Composição alterada%' THEN RAISE; END IF; blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'falha revisão concorrente';END IF;
 blocked:=false;BEGIN PERFORM public.ew_salvar_composicoes_expedicao(e,targets,p-2,gen_random_uuid()); EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Os percentuais%' THEN RAISE; END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'falha soma';END IF;
 SELECT id INTO rev FROM ew_expedicao_interna.revisoes WHERE tipologia_id=a;
 PERFORM public.ew_salvar_composicoes_expedicao(e,jsonb_build_array(jsonb_build_object('tipologia_id',a,'revisao_id',rev)),p,gen_random_uuid());
 IF (SELECT count(*) FROM ew_expedicao_interna.revisoes WHERE tipologia_id=a)<>2 OR jsonb_array_length(public.ew_listar_composicoes_expedicao(e,ARRAY[a,b]))<>2 THEN RAISE EXCEPTION 'falha revisões';END IF;
END $test$;
SELECT 'PASS catálogo: lote, retry, conflito, soma, revisão imutável' AS resultado;