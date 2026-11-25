-- Execute only in rollback on restored test DB.
DO $test$ DECLARE u uuid;e uuid;o uuid;a uuid;b uuid;ra uuid;rb uuid;rr uuid;r jsonb; BEGIN
SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE ESTORNO LIB','TESTE-LIB-4624') RETURNING id INTO o;
INSERT INTO public.esquadrias(empresa_id,obra_id,codigo,descricao,largura_mm,altura_mm,quantidade,qtd_liberada) VALUES(e,o,'EA1','JANELA 2 FOLHAS',1200,1000,5,2) RETURNING id INTO a;
INSERT INTO public.esquadrias(empresa_id,obra_id,codigo,descricao,largura_mm,altura_mm,quantidade,qtd_liberada) VALUES(e,o,'EA2','JANELA 2 FOLHAS',1200,1000,5,1) RETURNING id INTO b;
INSERT INTO public.liberacoes_corte(esquadria_id,quantidade,data_liberacao,usuario_id,fabrica,tipo_componente) VALUES(a,2,current_date,u,'AFOGADOS','completo') RETURNING id INTO ra;
INSERT INTO public.liberacoes_corte(esquadria_id,quantidade,data_liberacao,usuario_id,fabrica,tipo_componente) VALUES(b,1,current_date,u,'AFOGADOS','completo') RETURNING id INTO rb;
INSERT INTO public.romaneios(empresa_id,obra_id,numero,chave_operacao,data_saida,motorista,placa,criado_por) VALUES(e,o,'RMTEST4624',gen_random_uuid(),current_date,'TESTE','ABC1234',u) RETURNING id INTO rr;
INSERT INTO public.romaneios_itens(romaneio_id,sequencia,natureza,esquadria_id,quantidade) VALUES(rr,1,'esquadria',b,1);
IF public.ew_motivo_estorno_liberacao(ra) IS NOT NULL OR public.ew_motivo_estorno_liberacao(rb) NOT LIKE 'Existe romaneio%' THEN RAISE EXCEPTION 'Bloqueio deve considerar somente esquadria correspondente'; END IF;
BEGIN PERFORM public.ew_estornar_liberacao_individual(rb,'Teste bloqueio romaneio'); RAISE EXCEPTION 'FALHA: estorno indevido'; EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Existe romaneio%' THEN RAISE; END IF; END;
r:=public.ew_estornar_liberacao_individual(ra,'Teste estorno permitido');
IF (r->>'qtd_liberada')::int<>0 OR (SELECT qtd_liberada FROM public.esquadrias WHERE id=b)<>1 OR NOT EXISTS(SELECT 1 FROM public.liberacoes_corte WHERE id=ra AND cancelado_em IS NOT NULL) THEN RAISE EXCEPTION 'Contadores ou histórico incorretos'; END IF;
END $test$;