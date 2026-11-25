-- Na restauração: BEGIN; proposta base compras; trecho de cancelamentos até antes de ew_compras_cancelar_cotacao; proposta agrupamento; este teste; ROLLBACK. Retirar BEGIN/COMMIT internos.
DO $test$
DECLARE e uuid;u uuid;o uuid;o2 uuid;p uuid;v uuid;s1 uuid;s2 uuid;s3 uuid;g uuid;op uuid:=gen_random_uuid();r jsonb;blocked boolean;itens jsonb;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
 SELECT e,1,k,true FROM unnest(ARRAY['compras.solicitar','compras.consultar','compras.cotar','compras.consultar_valores','compras.agrupar']) k ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'Teste A','TESTE-88-A') RETURNING id INTO o;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'Teste B','TESTE-88-B') RETURNING id INTO o2;
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-88-P','Perfil teste','Teste') RETURNING id INTO p;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
 itens:=jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v,'unidade','BARRA','comprimento_mm',6000,'quantidade',2));
 r:=public.ew_compras_criar_solicitacao(e,o,null,itens,'A',gen_random_uuid());s1:=(r->>'id')::uuid;
 r:=public.ew_compras_criar_solicitacao(e,o,null,itens,'B',gen_random_uuid());s2:=(r->>'id')::uuid;
 r:=public.ew_compras_criar_solicitacao(e,o2,null,itens,'C',gen_random_uuid());s3:=(r->>'id')::uuid;
 blocked:=false;BEGIN PERFORM public.ew_compras_agrupar_solicitacoes(e,o,ARRAY[s1,s3],gen_random_uuid());EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Somente solicitações%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'agrupou obras distintas';END IF;
 r:=public.ew_compras_agrupar_solicitacoes(e,o,ARRAY[s1,s2],op);g:=(r->>'id')::uuid;
 IF (SELECT (s.itens->0->>'quantidade')::numeric FROM public.ew_compras_solicitacoes s WHERE id=g)<>4 THEN RAISE EXCEPTION 'soma errada';END IF;
 IF (SELECT count(*) FROM public.ew_compras_solicitacoes WHERE agrupada_em=g AND status='AGRUPADA')<>2 THEN RAISE EXCEPTION 'origens não preservadas';END IF;
 r:=public.ew_compras_agrupar_solicitacoes(e,o,ARRAY[s2,s1],op);IF NOT (r->>'repetida')::boolean THEN RAISE EXCEPTION 'retry errado';END IF;
 blocked:=false;BEGIN PERFORM public.ew_compras_agrupar_solicitacoes(e,o,ARRAY[s1,s2],gen_random_uuid());EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Somente solicitações%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'agrupamento duplicado';END IF;
 PERFORM public.ew_compras_cancelar_solicitacao(g,'Teste cancelamento grupo',gen_random_uuid());
 IF (SELECT count(*) FROM public.ew_compras_solicitacoes WHERE id=ANY(ARRAY[s1,s2]) AND status='ABERTA' AND agrupada_em IS NULL)<>2 THEN RAISE EXCEPTION 'origens não restauradas';END IF;
 IF (SELECT count(*) FROM ew_compras_interna.agrupamentos WHERE solicitacao_id=g)<>1 THEN RAISE EXCEPTION 'histórico perdido';END IF;
END;$test$;
SELECT 'PASS: consolidação, soma, isolamento por obra, idempotência, duplicidade, cancelamento e histórico' AS resultado;