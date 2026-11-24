-- EWGEST v46.21: duas transferências consecutivas para a MESMA obra,
-- estornos na ordem reversa, depois estorno do recebimento da empresa.
-- Prova que estornos negativos não são considerados saídas de consumo.
-- Executar somente com BEGIN / ROLLBACK em ewgest-restauracao-teste.
DO $test$
DECLARE
 v_uid uuid;v_emp uuid;v_local uuid;v_work uuid;v_profile uuid;v_var uuid;
 v_supplier uuid;v_solic uuid;v_quote uuid;v_order uuid;v_receipt uuid;
 v_trans1 uuid;v_trans2 uuid;v_data jsonb;
 v_qty_work numeric;v_qty_company numeric;
 v_reverse1 uuid:=gen_random_uuid();
BEGIN
 SELECT ue.usuario_id,ue.empresa_id INTO STRICT v_uid,v_emp
 FROM public.usuarios_empresas ue WHERE ue.nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',
   jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_emp,'administrador',1,'Teste de transferências encadeadas',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_emp,'IMBIRIBEIRA');
 INSERT INTO public.obras(empresa_id,nome,codigo)
 VALUES(v_emp,'TESTE DESTINO DUPLO','TESTE-TRANS-90') RETURNING id INTO v_work;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(v_emp,v_work,v_uid);
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 VALUES(v_emp,'TESTE-90','Perfil de teste de transferências','FAB TESTE')
 RETURNING id INTO v_profile;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 VALUES(v_emp,'perfil',v_profile,'NATURAL','NATURAL') RETURNING id INTO v_var;
 INSERT INTO public.ew_fornecedores(empresa_id,nome)
 VALUES(v_emp,'FORNECEDOR TESTE 90') RETURNING id INTO v_supplier;
 v_data:=public.ew_compras_criar_local_empresa(v_emp,'ESTOQUE EMPRESA TESTE 90');
 v_local:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_solicitacao(v_emp,null,v_local,
  jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v_var,
   'quantidade',2,'unidade','BARRA','comprimento_mm',6000)),
  'Estoque de origem de duas transferências',gen_random_uuid());
 v_solic:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_cotacao(v_solic,v_supplier,
   '[{"chave":"1","preco_unitario_centavos":20000}]'::jsonb,gen_random_uuid());
 v_quote:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_pedido(v_quote,gen_random_uuid());
 v_order:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_receber_pedido(v_order,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":2}]'::jsonb,gen_random_uuid());
 v_receipt:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_transferir_locais(
  v_emp,'EMPRESA',v_local,'OBRA',v_work,
  v_var,6000,'BARRA',1,'IMBIRIBEIRA','IMBIRIBEIRA',
  'Primeira transferência independente',gen_random_uuid());
 v_trans1:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_transferir_locais(
  v_emp,'EMPRESA',v_local,'OBRA',v_work,
  v_var,6000,'BARRA',1,'IMBIRIBEIRA','IMBIRIBEIRA',
  'Segunda transferência independente',gen_random_uuid());
 v_trans2:=(v_data->>'id')::uuid;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_qty_work
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_qty_company
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_local;
 IF v_qty_work<>2 OR v_qty_company<>0
 THEN RAISE EXCEPTION 'Antes da reversão esperadas 2 barras na obra e zero na empresa.';END IF;

 -- Estorno da transferência mais nova cria um movimento negativo de
 -- ESTORNO na mesma obra. Esse estorno NÃO pode bloquear a mais antiga.
 v_data:=public.ew_compras_estornar_transferencia(
  v_trans2,'Desfazer a segunda transferência',gen_random_uuid());
 IF coalesce((v_data->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Segunda transferência não foi estornada.';END IF;
 v_data:=public.ew_compras_estornar_transferencia(
  v_trans1,'Desfazer a primeira transferência',v_reverse1);
 IF coalesce((v_data->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Primeira transferência foi bloqueada por estorno anterior.';END IF;
 v_data:=public.ew_compras_estornar_transferencia(
  v_trans1,'Desfazer a primeira transferência',v_reverse1);
 IF coalesce((v_data->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Reenvio do estorno não foi idempotente.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_qty_work
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_qty_company
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_local;
 IF v_qty_work<>0 OR v_qty_company<>2
 THEN RAISE EXCEPTION 'Após estorno esperadas 0 barras na obra e 2 na empresa: %, %.',
  v_qty_work,v_qty_company;END IF;

 -- Agora não há consumo físico, apenas saídas já desfeitas e estornos.
 v_data:=public.ew_compras_estornar_recebimento(
  v_receipt,'Devolver recebimento após estornar transferências',gen_random_uuid());
 IF coalesce((v_data->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Recebimento empresarial sem uso foi bloqueado indevidamente.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_qty_work
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_qty_company
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_local;
 IF v_qty_work<>0 OR v_qty_company<>0
 THEN RAISE EXCEPTION 'Saldos deveriam zerar após todos os estornos, obra %, empresa %.',
  v_qty_work,v_qty_company;END IF;
 IF (SELECT count(*) FROM public.ew_compras_transferencias
  WHERE id IN(v_trans1,v_trans2) AND estornado_em IS NOT NULL)<>2
 THEN RAISE EXCEPTION 'As transferências históricas deveriam estar estornadas.';END IF;
 RAISE NOTICE 'PASS: duas transferências para mesmo destino estornadas em ordem inversa, idempotência e recebimento original revertido; saldo total zero.';
END;$test$;
