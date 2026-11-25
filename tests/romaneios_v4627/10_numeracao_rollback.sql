-- Adaptação temporária da restauração antiga, apenas dentro da transação.
CREATE OR REPLACE FUNCTION public.consultar_proximo_romaneio() RETURNS jsonb LANGUAGE sql AS $$select '{}'::jsonb$$;
CREATE OR REPLACE FUNCTION public.adiantar_numero_romaneio(integer,text) RETURNS jsonb LANGUAGE sql AS $$select '{}'::jsonb$$;
-- Aplicar proposta dentro desta transação antes da fixture.
DO $test$
DECLARE e uuid;u uuid;a uuid;b uuid;d uuid;docs uuid[]:=ARRAY[]::uuid[];n text;result jsonb;blocked boolean;j int;stock_before bigint;hist jsonb;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem)
 SELECT k,'Teste',k,1 FROM unnest(ARRAY['romaneios.consultar','romaneios.emitir','romaneios.transferir','relatorios.operacionais']) k ON CONFLICT DO NOTHING;
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
 SELECT e,1,k,true FROM unnest(ARRAY['romaneios.consultar','romaneios.emitir','romaneios.transferir','relatorios.operacionais','romaneios.juntar','romaneios.adiantar_numeracao','romaneios.historico_numeracao']) k ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'Teste numeração A','TESTE-86-A') RETURNING id INTO a;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'Teste numeração B','TESTE-86-B') RETURNING id INTO b;
 IF (public.consultar_proximo_romaneio(e,a)->>'codigo')<>'RM001' THEN RAISE EXCEPTION 'obra A deve iniciar em 001';END IF;
 INSERT INTO public.romaneios(empresa_id,obra_id,chave_operacao,data_saida,motorista,placa,criado_por) VALUES(e,a,gen_random_uuid(),current_date,'Motorista teste','ABC1234',u) RETURNING numero INTO n;
 IF n<>'RM001' THEN RAISE EXCEPTION 'expedição inicial %',n;END IF;
 FOR j IN 2..6 LOOP
 INSERT INTO public.ew_romaneios_transferencia(empresa_id,obra_id,origem_galpao,destino_galpao,criado_por) VALUES(e,a,'AFOGADOS','IMBIRIBEIRA',u) RETURNING id,numero INTO d,n;
 IF n<>ew_romnum_interna.codigo(j) THEN RAISE EXCEPTION 'transferência % esperava %',n,j;END IF;
 docs:=array_append(docs,d);
 END LOOP;
 INSERT INTO public.ew_romaneios_transferencia(empresa_id,obra_id,origem_galpao,destino_galpao,criado_por) VALUES(e,b,'AFOGADOS','IMBIRIBEIRA',u) RETURNING id,numero INTO d,n;
 IF n<>'RM001' THEN RAISE EXCEPTION 'obra B deve iniciar 001, recebido %',n;END IF;
 blocked:=false;BEGIN PERFORM public.ew_romaneios_transferencia_juntar(e,docs[1],ARRAY[d]);EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Somente rascunhos da mesma obra%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'junção entre obras aceita';END IF;
 SELECT count(*) INTO stock_before FROM public.ew_estoque_obras_movimentos;
 result:=public.ew_romaneios_transferencia_juntar(e,docs[5],docs[1:4]);
 IF result->>'numero'<>'RM002' OR result->>'proximo_codigo'<>'RM003' THEN RAISE EXCEPTION 'junção incorreta %',result;END IF;
 IF (SELECT count(*) FROM public.ew_romaneios_transferencia WHERE id=ANY(docs) AND status='AGRUPADO')<>4 THEN RAISE EXCEPTION 'histórico perdido';END IF;
 IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos)<>stock_before THEN RAISE EXCEPTION 'junção alterou estoque';END IF;
 INSERT INTO public.romaneios(empresa_id,obra_id,chave_operacao,data_saida,motorista,placa,criado_por) VALUES(e,a,gen_random_uuid(),current_date,'Motorista teste','ABC1234',u) RETURNING numero INTO n;
 IF n<>'RM003' THEN RAISE EXCEPTION 'reutilização incorreta %',n;END IF;
 UPDATE public.romaneios SET status='cancelado',cancelado_em=now(),cancelado_por=u,motivo_cancelamento='Teste sintético' WHERE empresa_id=e AND obra_id=a AND numero='RM003';
 IF (public.consultar_proximo_romaneio(e,a)->>'codigo')<>'RM004' THEN RAISE EXCEPTION 'cancelado liberou número';END IF;
 PERFORM public.adiantar_numero_romaneio(e,b,999,'Teste de numeração extensa');
 INSERT INTO public.ew_romaneios_transferencia(empresa_id,obra_id,origem_galpao,destino_galpao,criado_por) VALUES(e,b,'AFOGADOS','IMBIRIBEIRA',u) RETURNING numero INTO n;
 IF n<>'RM999' OR (public.consultar_proximo_romaneio(e,b)->>'codigo')<>'RM1000' THEN RAISE EXCEPTION 'erro acima de 999';END IF;
 hist:=public.ew_historico_numeracao_romaneios(e,a,NULL,NULL,0);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(hist) x WHERE x->>'evento'='NUMERO_REUTILIZADO' AND x->>'numero'='RM003') OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(hist) x WHERE x->>'evento'='JUNCAO' AND x->'detalhes'->>'proximo_depois'='3') THEN RAISE EXCEPTION 'histórico insuficiente %',hist;END IF;
 UPDATE public.ew_niveis_permissoes SET permitido=false WHERE empresa_id=e AND nivel=1 AND chave='romaneios.juntar';
 blocked:=false;BEGIN PERFORM public.ew_romaneios_transferencia_juntar(e,docs[1],ARRAY[docs[2]]);EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Sem permissão%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'junção sem flag aceita';END IF;
END;$test$;
SELECT 'PASS: duas obras 001, sequência mista, junção 002-006 -> 002, próximo 003, cancelado reservado, 999->1000, histórico e flags' AS resultado;