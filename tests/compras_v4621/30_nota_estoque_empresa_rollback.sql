-- EWGEST v46.21: teste de nota fiscal de estoque próprio da empresa.
-- Somente com BEGIN/migrações/ROLLBACK em ewgest-restauracao-teste.
DO $empresa_test$
DECLARE
 v_uid uuid;v_empresa uuid;v_local uuid;v_perfil uuid;v_var uuid;v_fornecedor uuid;
 v_solic uuid;v_cot uuid;v_pedido uuid;v_rec1 uuid;v_rec2 uuid;v_nota uuid;
 v_note_op uuid:=gen_random_uuid();v_result jsonb;v_saldo numeric;v_antes numeric;
 v_total bigint;v_failed boolean;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT v_uid,v_empresa
 FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_empresa,'administrador',1,'Teste fiscal estoque empresa',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_empresa,'AFOGADOS');
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 VALUES(v_empresa,'TESTE-EMP-6000','Perfil 6m empresa teste','FAB TESTE')
 RETURNING id INTO v_perfil;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 VALUES(v_empresa,'perfil',v_perfil,'BRANCO','BRANCO') RETURNING id INTO v_var;
 INSERT INTO public.ew_fornecedores(empresa_id,nome)
 VALUES(v_empresa,'FORNECEDOR EMPRESA TESTE') RETURNING id INTO v_fornecedor;
 v_result:=public.ew_compras_criar_local_empresa(v_empresa,'ESTOQUE EMPRESA FISCAL TESTE');
 v_local:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_solicitacao(v_empresa,null,v_local,
   jsonb_build_array(jsonb_build_object('chave','X01','variacao_id',v_var,'quantidade',4,
    'unidade','BARRA','comprimento_mm',6000)),
   'Teste fiscal de estoque sem obra',gen_random_uuid());
 v_solic:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_cotacao(v_solic,v_fornecedor,
   '[{"chave":"X01","preco_unitario_centavos":5000}]'::jsonb,gen_random_uuid());
 v_cot:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_pedido(v_cot,gen_random_uuid());
 v_pedido:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_receber_pedido(v_pedido,'AFOGADOS',
  '[{"chave":"X01","quantidade":1}]'::jsonb,gen_random_uuid());
 v_rec1:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_receber_pedido(v_pedido,'AFOGADOS',
  '[{"chave":"X01","quantidade":1}]'::jsonb,gen_random_uuid());
 v_rec2:=(v_result->>'id')::uuid;
 SELECT sum(m.quantidade_delta) INTO v_antes FROM public.ew_compras_estoque_empresa m
 WHERE m.local_empresa_id=v_local;
 IF v_antes<>2 THEN RAISE EXCEPTION 'Saldo físico deveria ser 2 barras.';END IF;
 v_result:=public.ew_compras_registrar_nota_empresa(
  v_pedido,'NF-EMP-0001',current_date,null,10000,
  jsonb_build_array(
   jsonb_build_object('recebimento_id',v_rec1,'chave','X01','valor_total_centavos',4000),
   jsonb_build_object('recebimento_id',v_rec2,'chave','X01','valor_total_centavos',6000)
  ),'Nota empresarial de teste',v_note_op);
 v_nota:=(v_result->>'id')::uuid;
 IF coalesce((v_result->>'novo_movimento_fisico')::boolean,true) IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Registro da nota criou novo estoque.';END IF;
 SELECT sum(m.quantidade_delta) INTO v_saldo FROM public.ew_compras_estoque_empresa m
 WHERE m.local_empresa_id=v_local;
 IF v_saldo<>v_antes THEN RAISE EXCEPTION 'Nota alterou saldo físico empresarial.';END IF;
 SELECT sum(valor_total_centavos) INTO v_total FROM public.ew_compras_notas_empresa_itens
 WHERE nota_id=v_nota;
 IF v_total<>10000 THEN RAISE EXCEPTION 'Soma dos custos empresariais errada.';END IF;
 v_result:=public.ew_compras_registrar_nota_empresa(
  v_pedido,'NF-EMP-0001',current_date,null,10000,
  jsonb_build_array(
   jsonb_build_object('recebimento_id',v_rec1,'chave','X01','valor_total_centavos',4000),
   jsonb_build_object('recebimento_id',v_rec2,'chave','X01','valor_total_centavos',6000)
  ),'Reenvio da mesma operação',v_note_op);
 IF coalesce((v_result->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Registro fiscal repetido não foi idempotente.';END IF;
 v_failed:=false;
 BEGIN
  PERFORM public.ew_compras_registrar_nota_empresa(
   v_pedido,'NF-EMP-0002',current_date,null,4000,
   jsonb_build_array(jsonb_build_object('recebimento_id',v_rec1,'chave','X01','valor_total_centavos',4000)),
   '',gen_random_uuid());
 EXCEPTION WHEN others THEN v_failed:=true;END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Recebimento foi faturado em duas notas ativas.';END IF;
 v_failed:=false;
 BEGIN
  PERFORM public.ew_compras_estornar_recebimento(
   v_rec1,'Estorno de nota empresarial ainda ativa',gen_random_uuid());
 EXCEPTION WHEN others THEN v_failed:=true;END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Estorno físico ignorou nota empresarial ativa.';END IF;
 v_result:=public.ew_compras_cancelar_nota_empresa(
  v_nota,'Nota empresarial cancelada para teste',gen_random_uuid());
 IF coalesce((v_result->>'movimento_fisico_alterado')::boolean,true) IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Cancelamento da nota alterou estoque.';END IF;
 SELECT count(*) INTO v_total FROM public.ew_compras_notas_empresa
 WHERE status='ATIVA' AND local_empresa_id=v_local;
 IF v_total<>0 THEN RAISE EXCEPTION 'Custo empresarial não foi retirado das notas ativas.';END IF;
 v_result:=public.ew_compras_estornar_recebimento(
  v_rec1,'Recebimento após cancelamento de nota empresarial',gen_random_uuid());
 IF coalesce((v_result->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Estorno do recebimento após nota cancelada falhou.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_saldo
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_local;
 IF v_saldo<>1 THEN RAISE EXCEPTION 'Após estorno deveria sobrar 1 barra, saldo %.',v_saldo;END IF;
 RAISE NOTICE 'PASS nota empresarial: custo sem obra, sem estoque duplo, NF parcial, duplicidade bloqueada, cancelamento fiscal e estorno.';
END;$empresa_test$;
