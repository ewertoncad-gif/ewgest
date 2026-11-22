-- Teste executado só no PostgreSQL 17 descartável do GitHub Actions.
\set ON_ERROR_STOP on
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
CREATE FUNCTION public.test_mov(
 w uuid, q numeric, src text, loc text, op uuid DEFAULT NULL,
 reverse_of uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE x uuid;
BEGIN
 INSERT INTO public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,local_estoque,transferencia_id,estorno_de_id,usuario_id)
 VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',w,
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',6000,'BARRA',
 q,src,loc,op,reverse_of,'11111111-1111-4111-8111-111111111111')
 RETURNING id INTO x;
 RETURN x;
END $$;

-- Constantes fictícias: obra A, B e C no mesmo cadastro da empresa A.
DO $case1$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 op uuid:='aaaa0001-0000-4000-8000-000000000001';
 rev uuid:='bbbb0001-0000-4000-8000-000000000001';
 res jsonb; balance numeric;
BEGIN
 PERFORM public.test_mov(a,3,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-3,'TRANSFERENCIA','AFOGADOS',op);
 PERFORM public.test_mov(b,3,'TRANSFERENCIA','IMBIRIBEIRA',op);
 PERFORM public.test_mov(b,-3,'TRANSFERENCIA','IMBIRIBEIRA','aaaa0002-0000-4000-8000-000000000002');
 PERFORM public.test_mov(b,3,'TRANSFERENCIA','AFOGADOS','aaaa0002-0000-4000-8000-000000000002');
 res:=public.ew_estornar_transferencia_entre_obras(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Devolução sem uso após mudar galpão',rev);
 IF res->>'galpao_da_retirada'<>'AFOGADOS' OR (res->>'estornados')::int<>2
 THEN RAISE EXCEPTION 'Caso1: não devolveu de galpão alternativo: %',res; END IF;
 SELECT sum(quantidade_delta) INTO balance FROM public.ew_estoque_obras_movimentos
 WHERE obra_id=b AND local_estoque='AFOGADOS';
 IF balance<>0 THEN RAISE EXCEPTION 'Caso1: saldo incorreto destino AFOGADOS %',balance;END IF;
 IF (public.ew_estornar_transferencia_entre_obras(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Devolução sem uso após mudar galpão',rev)->>'repetida')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Caso1: retry deve ser idempotente';END IF;
END $case1$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case2$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 op uuid:='aaaa0003-0000-4000-8000-000000000003';
 consume uuid;err text;
BEGIN
 PERFORM public.test_mov(a,3,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-3,'TRANSFERENCIA','AFOGADOS',op);
 PERFORM public.test_mov(b,3,'TRANSFERENCIA','IMBIRIBEIRA',op);
 consume:=public.test_mov(b,-1,'PLANO_CORTE_LOTE','IMBIRIBEIRA');
 PERFORM public.test_mov(b,1,'COMPRA','IMBIRIBEIRA');
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Não pode devolver material fabricado',gen_random_uuid());
  RAISE EXCEPTION 'Caso2: consumo ativo foi aceito indevidamente';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%material consumido%' THEN RAISE;END IF;
 END;
 PERFORM public.test_mov(b,1,'ESTORNO','IMBIRIBEIRA',NULL,consume);
 PERFORM public.ew_estornar_transferencia_entre_obras(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Baixa fabricada devidamente estornada',gen_random_uuid());
END $case2$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case3$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 c uuid:='aaaaaaaa-0000-4000-8000-000000000003';
 op uuid:='aaaa0004-0000-4000-8000-000000000004';
 later uuid:='aaaa0005-0000-4000-8000-000000000005';
 debit uuid;credit uuid;err text;
BEGIN
 PERFORM public.test_mov(a,2,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-2,'TRANSFERENCIA','AFOGADOS',op);
 PERFORM public.test_mov(b,2,'TRANSFERENCIA','IMBIRIBEIRA',op);
 debit:=public.test_mov(b,-1,'TRANSFERENCIA','IMBIRIBEIRA',later);
 credit:=public.test_mov(c,1,'TRANSFERENCIA','IMBIRIBEIRA',later);
 PERFORM public.test_mov(b,1,'ABERTURA','IMBIRIBEIRA');
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Transferência original ainda em cadeia',gen_random_uuid());
  RAISE EXCEPTION 'Caso3: transferência encadeada não bloqueada';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%enviado posteriormente para outra obra%' THEN RAISE;END IF;
 END;
 PERFORM public.test_mov(b,1,'ESTORNO','IMBIRIBEIRA',NULL,debit);
 PERFORM public.test_mov(c,-1,'ESTORNO','IMBIRIBEIRA',NULL,credit);
 PERFORM public.ew_estornar_transferencia_entre_obras(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Transferência seguinte já revertida',gen_random_uuid());
END $case3$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case4$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 op uuid:='aaaa0006-0000-4000-8000-000000000006';err text;
BEGIN
 PERFORM public.test_mov(a,1,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-1,'TRANSFERENCIA','AFOGADOS',op);
 PERFORM public.test_mov(b,1,'TRANSFERENCIA','IMBIRIBEIRA',op);
 INSERT INTO public._blockers VALUES(b,'Cancele todos os romaneios emitidos.');
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Romaneio ainda não cancelado',gen_random_uuid());
  RAISE EXCEPTION 'Caso4: romaneio não bloqueou retorno';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%pendências na obra de destino%' THEN RAISE;END IF;
 END;
 DELETE FROM public._blockers;
 PERFORM public.ew_estornar_transferencia_entre_obras(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Romaneio cancelado, saída revertida',gen_random_uuid());
END $case4$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case5$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 original uuid;res jsonb;v numeric;
BEGIN
 original:=public.test_mov(a,2,'IMPORTACAO_CEM','AFOGADOS');
 PERFORM public.test_mov(a,-2,'TRANSFERENCIA','AFOGADOS','aaaa0007-0000-4000-8000-000000000007');
 PERFORM public.test_mov(a,2,'TRANSFERENCIA','IMBIRIBEIRA','aaaa0007-0000-4000-8000-000000000007');
 res:=public.ew_estornar_movimento_obra(a,original,'Desfazer entrada sem consumir',gen_random_uuid());
 IF (res->>'estornados')::int<>1 THEN RAISE EXCEPTION 'Caso5: estorno de entrada não gerado';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v FROM public.ew_estoque_obras_movimentos
 WHERE obra_id=a AND local_estoque='IMBIRIBEIRA';
 IF v<>0 THEN RAISE EXCEPTION 'Caso5: estoque não zerou no galpão atual'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos
  WHERE estorno_de_id=original AND local_estoque='IMBIRIBEIRA')
 THEN RAISE EXCEPTION 'Caso5: estorno não registra galpão real';END IF;
END $case5$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case6$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 src uuid;consume uuid;err text;
BEGIN
 src:=public.test_mov(a,1,'ABERTURA','AFOGADOS');
 consume:=public.test_mov(a,-1,'PLANO_CORTE','AFOGADOS');
 PERFORM public.test_mov(a,1,'ABERTURA','AFOGADOS');
 BEGIN
  PERFORM public.ew_estornar_movimento_obra(a,src,'Não pode devolver material consumido',gen_random_uuid());
  RAISE EXCEPTION 'Caso6: consumo não bloqueou devolução';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Material consumido%' THEN RAISE;END IF;
 END;
 PERFORM public.test_mov(a,1,'ESTORNO','AFOGADOS',NULL,consume);
 PERFORM public.ew_estornar_movimento_obra(a,src,'Material de fabricação revertido',gen_random_uuid());
END $case6$;

TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case7$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 op uuid:='aaaa0008-0000-4000-8000-000000000008';
 rev uuid:='eeee0008-0000-4000-8000-000000000008';
 r jsonb;v numeric;
BEGIN
 PERFORM public.test_mov(a,2,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-2,'TRANSFERENCIA','AFOGADOS',op);
 PERFORM public.test_mov(b,2,'TRANSFERENCIA','IMBIRIBEIRA',op);
 PERFORM public.test_mov(b,-1,'TRANSFERENCIA','IMBIRIBEIRA','aaaa0009-0000-4000-8000-000000000009');
 PERFORM public.test_mov(b,1,'TRANSFERENCIA','AFOGADOS','aaaa0009-0000-4000-8000-000000000009');
 r:=public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,
   'Quantidades divididas por galpão sem consumo',rev);
 IF (r->>'estornados')::int<>3 OR jsonb_array_length(r->'parcelas')<>2 THEN
   RAISE EXCEPTION 'Caso7: estorno deveria ter 2 parcelas + 1 devolução: %',r;END IF;
 IF (SELECT count(*) FROM public.ew_estornos_parcelas WHERE operacao_id=rev)<>3 THEN
   RAISE EXCEPTION 'Caso7: vínculos auditáveis incompletos'; END IF;
 IF (SELECT sum(quantidade) FROM public.ew_estornos_parcelas
     WHERE operacao_id=rev AND obra_id=b)<>2 THEN
   RAISE EXCEPTION 'Caso7: parcelas da obra destino não somam a transferência';END IF;
 IF (SELECT count(DISTINCT local_estoque) FROM public.ew_estornos_parcelas
     WHERE operacao_id=rev AND obra_id=b)<>2 THEN
   RAISE EXCEPTION 'Caso7: galpões de origem física não foram registrados';END IF;
 IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos WHERE
    transferencia_id=rev AND origem='ESTORNO' AND estorno_de_id IS NULL)<>1 THEN
   RAISE EXCEPTION 'Caso7: apenas a parcela adicional deve ficar sem link direto';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v FROM public.ew_estoque_obras_movimentos WHERE obra_id=b;
 IF v<>0 THEN RAISE EXCEPTION 'Caso7: obra destino não zerou: %',v;END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v FROM public.ew_estoque_obras_movimentos WHERE obra_id=a;
 IF v<>2 THEN RAISE EXCEPTION 'Caso7: origem não recuperou a quantidade: %',v;END IF;
 r:=public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,
   'Quantidades divididas por galpão sem consumo',rev);
 IF (r->>'repetida')::boolean IS DISTINCT FROM true OR
    (r->>'estornados')::int<>3 THEN
   RAISE EXCEPTION 'Caso7: retry deve voltar idempotente com três movimentos: %',r;END IF;
 IF (SELECT count(*) FROM public.ew_estoque_obras_movimentos WHERE
    transferencia_id=rev AND origem='ESTORNO')<>3 THEN
   RAISE EXCEPTION 'Caso7: retry duplicou lançamentos';END IF;
END $case7$;

-- Saldo total insuficiente nunca pode criar parcelas parciais.
TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case8$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 op uuid:='aaaa0010-0000-4000-8000-000000000010';
 rev uuid:='eeee0010-0000-4000-8000-000000000010';
 err text;
BEGIN
 PERFORM public.test_mov(a,3,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-3,'TRANSFERENCIA','AFOGADOS',op);
 PERFORM public.test_mov(b,3,'TRANSFERENCIA','IMBIRIBEIRA',op);
 PERFORM public.test_mov(b,-1,'TRANSFERENCIA','IMBIRIBEIRA','aaaa0011-0000-4000-8000-000000000011');
 PERFORM public.test_mov(b,1,'TRANSFERENCIA','AFOGADOS','aaaa0011-0000-4000-8000-000000000011');
 -- Simula uma saída não documentada que deixou menos de 3 barras, sem
 -- mascarar o problema por compras posteriores.
 PERFORM public.test_mov(b,-2,'ESTORNO','IMBIRIBEIRA');
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,
   'Quantidade indisponível na obra destino',rev);
  RAISE EXCEPTION 'Caso8: estornou além do saldo disponível';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Saldo insuficiente%' THEN RAISE;END IF;
 END;
 IF EXISTS(SELECT 1 FROM public.ew_estornos_parcelas WHERE operacao_id=rev) OR
    EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos WHERE transferencia_id=rev)
 THEN RAISE EXCEPTION 'Caso8: operação rejeitada não pode deixar movimentações';END IF;
END $case8$;

-- Entrada que foi distribuída entre dois galpões: duas contrapartidas
-- com uma única operação, cada parcela com vínculo próprio.
TRUNCATE public.ew_auditoria_operacoes,public.ew_estornos_parcelas,public.ew_nfe_recebimentos,public.ew_estoque_obras_movimentos,public._blockers;
DO $case9$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 origem uuid;rev uuid:='cccc0012-0000-4000-8000-000000000012';
 r jsonb;extra uuid;err text;
BEGIN
 origem:=public.test_mov(a,2,'ABERTURA','AFOGADOS');
 PERFORM public.test_mov(a,-1,'TRANSFERENCIA','AFOGADOS','aaaa0012-0000-4000-8000-000000000012');
 PERFORM public.test_mov(a,1,'TRANSFERENCIA','IMBIRIBEIRA','aaaa0012-0000-4000-8000-000000000012');
 r:=public.ew_estornar_movimento_obra(a,origem,'Reverter entrada disponível em dois galpões',rev);
 IF (r->>'estornados')::int<>2 OR
    (SELECT count(*) FROM public.ew_estornos_parcelas WHERE operacao_id=rev)<>2
 THEN RAISE EXCEPTION 'Caso9: estorno de entrada dividido incorreto: %',r;END IF;
 IF (SELECT count(*) FROM public.ew_estornos_parcelas
   WHERE operacao_id=rev AND movimento_original_id=origem)<>2
 THEN RAISE EXCEPTION 'Caso9: parcelas não vinculadas ao lançamento original';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=a
    GROUP BY m.local_estoque HAVING sum(m.quantidade_delta)<>0)
 THEN RAISE EXCEPTION 'Caso9: sobrou saldo em um dos galpões';END IF;
 IF public.ew_transferencias_internas_conciliadas(a)<>2 THEN
  RAISE EXCEPTION 'Caso9: duas pernas históricas internas deveriam estar conciliadas.';
 END IF;
 SELECT m.id INTO extra FROM public.ew_estornos_parcelas p
 JOIN public.ew_estoque_obras_movimentos m ON m.id=p.movimento_estorno_id
 WHERE p.operacao_id=rev AND m.estorno_de_id IS NULL;
 IF extra IS NULL THEN RAISE EXCEPTION 'Caso9: parcela adicional inexistente';END IF;
 BEGIN
  PERFORM public.ew_estornar_movimento_obra(a,extra,'Não pode estornar uma contrapartida',gen_random_uuid());
  RAISE EXCEPTION 'Caso9: permitiu estorno da contrapartida';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%Contrapartida de estorno%' THEN RAISE;END IF;
 END;
 r:=public.ew_estornar_movimento_obra(a,origem,'Reverter entrada disponível em dois galpões',rev);
 IF (r->>'repetida')::boolean IS DISTINCT FROM true OR (r->>'estornados')::int<>2
 THEN RAISE EXCEPTION 'Caso9: retry da entrada não é idempotente';END IF;
 BEGIN
  PERFORM public.ew_estornar_movimento_obra(a,origem,'Tentar estornar pela segunda vez',gen_random_uuid());
  RAISE EXCEPTION 'Caso9: duplo estorno com nova operação';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE '%já foi estornada%' THEN RAISE;END IF;
 END;
END $case9$;

-- Isolamento empresarial e perfil de autorização.
DO $security$
DECLARE a uuid:='aaaaaaaa-0000-4000-8000-000000000001';
 b uuid:='aaaaaaaa-0000-4000-8000-000000000002';
 op uuid:='aaaa0008-0000-4000-8000-000000000008';err text;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Almox não pode fazer o estorno',gen_random_uuid());
  RAISE EXCEPTION 'Segurança: almoxarife aceito indevidamente';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE 'Somente ADM%' THEN RAISE;END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',op,'Outro administrador de outra empresa',gen_random_uuid());
  RAISE EXCEPTION 'Segurança: admin de outra empresa aceito indevidamente';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE 'Somente ADM%' THEN RAISE;END IF;
 END;
END $security$;

-- Perfil ADM sem login ativo não autoriza estorno, mesmo com vínculo
-- em usuarios_empresas e JWT de uma sessão anteriormente autenticada.
DO $security_inactive$
DECLARE adm uuid:='11111111-1111-4111-8111-111111111111';
 empresa uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 op uuid:='aaaa0008-0000-4000-8000-000000000008';
 err text;antes int;apos int;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',adm::text,false);
 SELECT count(*) INTO antes FROM public.ew_estoque_obras_movimentos;
 UPDATE public.usuarios_login SET ativo=false
 WHERE usuario_id=adm AND empresa_id=empresa;
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   empresa,op,'Login ADM desativado deve impedir estorno',gen_random_uuid());
  RAISE EXCEPTION 'Segurança: login ADM inativo foi aceito';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE 'Somente ADM%' THEN RAISE; END IF;
 END;
 UPDATE public.usuarios_login SET ativo=true,excluido_em=now()
 WHERE usuario_id=adm AND empresa_id=empresa;
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   empresa,op,'Login ADM excluído deve impedir estorno',gen_random_uuid());
  RAISE EXCEPTION 'Segurança: login ADM excluído foi aceito';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE 'Somente ADM%' THEN RAISE; END IF;
 END;
 UPDATE public.usuarios_login SET excluido_em=NULL,perfil='almoxarife'
 WHERE usuario_id=adm AND empresa_id=empresa;
 BEGIN
  PERFORM public.ew_estornar_transferencia_entre_obras(
   empresa,op,'Perfil divergente deve impedir estorno',gen_random_uuid());
  RAISE EXCEPTION 'Segurança: perfis divergentes foram aceitos';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  IF err NOT LIKE 'Somente ADM%' THEN RAISE; END IF;
 END;
 UPDATE public.usuarios_login SET perfil='administrador'
 WHERE usuario_id=adm AND empresa_id=empresa;
 SELECT count(*) INTO apos FROM public.ew_estoque_obras_movimentos;
 IF antes<>apos THEN RAISE EXCEPTION 'Segurança: tentativa negada modificou estoque';END IF;
END $security_inactive$;

SELECT 'OK v46.15: galpão alternativo, consumo, romaneio, cadeia entre obras, entrada e usuário, login ativo/perfil' AS resultado;
