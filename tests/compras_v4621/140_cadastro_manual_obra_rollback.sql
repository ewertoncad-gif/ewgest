DO $t$ DECLARE u uuid;e uuid;o uuid:=gen_random_uuid();r jsonb; BEGIN
SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
r:=public.ew_cadastrar_obra_manual(e,'OBRA MANUAL TESTE','','CLIENTE TESTE',current_date,o);
IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=o AND cadastro_manual AND codigo LIKE 'OBR-%') OR NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais WHERE obra_id=o) THEN RAISE EXCEPTION 'Cadastro incompleto'; END IF;
r:=public.ew_cadastrar_obra_manual(e,'OBRA MANUAL TESTE','','CLIENTE TESTE',current_date,o);
IF NOT (r->>'repetida')::boolean THEN RAISE EXCEPTION 'Idempotência falhou'; END IF;
BEGIN PERFORM public.ew_cadastrar_obra_manual(e,'OBRA MANUAL TESTE','','',null,gen_random_uuid()); RAISE EXCEPTION 'FALHA duplicidade'; EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Já existe obra%' THEN RAISE; END IF; END;
END $t$;