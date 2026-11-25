DO $t$ DECLARE u uuid;e uuid;o uuid;p uuid;v uuid;m uuid;rows jsonb;d jsonb; BEGIN
SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE NECESSIDADES','TESTE-NEC-4624') RETURNING id INTO o;
INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por) VALUES(e,o,u);
INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-NEC','Perfil teste','TESTE') RETURNING id INTO p;
INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
INSERT INTO public.ew_cem_obras_materiais(empresa_id,obra_id,tipo,perfil_id,variacao_id,linhas_calculo,quantidade_prevista,unidade_prevista,barras_planejadas) VALUES(e,o,'perfil',p,v,1,999,'CORTE','[{"comprimento_mm":4000,"quantidade":2},{"comprimento_mm":6000,"quantidade":3}]');
INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(e,'AFOGADOS');
INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,o,v,6000,'BARRA',3,'COMPRA',gen_random_uuid(),u,'AFOGADOS') RETURNING id INTO m;
INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,o,v,6000,'BARRA',-2,'SAIDA_MANUAL',gen_random_uuid(),u,'AFOGADOS');
rows:=public.ew_compras_necessidades_obra(e,o);
SELECT x INTO d FROM jsonb_array_elements(rows) x WHERE x->>'comprimento_mm'='6000';
IF (d->>'prevista')::numeric<>3 OR (d->>'fisico')::numeric<>1 OR (d->>'atendida')::numeric<>3 OR (d->>'faltante')::numeric<>0 THEN RAISE EXCEPTION 'Consumo não deve reabrir necessidade: %',d; END IF;
SELECT x INTO d FROM jsonb_array_elements(rows) x WHERE x->>'comprimento_mm'='4000';
IF (d->>'faltante')::numeric<>2 THEN RAISE EXCEPTION 'Medidas não podem se compensar: %',d; END IF;
END $t$;