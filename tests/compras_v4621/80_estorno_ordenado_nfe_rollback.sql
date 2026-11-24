-- EWGEST v46.21 — estorno ordenado com nota ativa em outro recebimento.
-- Ensaio de banco isolado: executar após as seis propostas SQL em BEGIN / ROLLBACK.
-- Confirma dois recebimentos do mesmo pedido, uma nota fiscal associada a um
-- deles e estorno do outro sem violar o histórico ou os saldos.
ALTER TABLE public.ew_obra_despesas ADD COLUMN IF NOT EXISTS chave_nfe text;

DO $test$
DECLARE
 v_uid uuid;v_emp uuid;v_work uuid;v_profile uuid;v_var uuid;v_supplier uuid;
 v_solic uuid;v_quote uuid;v_order uuid;v_rec_fiscal uuid;v_rec_free uuid;
 v_desp uuid;v_item uuid;v_assoc uuid;
 v_op_free uuid:=gen_random_uuid();v_op_fiscal uuid:=gen_random_uuid();
 v_data jsonb;v_blocked boolean;v_total numeric;
BEGIN
 SELECT ue.usuario_id,ue.empresa_id INTO STRICT v_uid,v_emp
 FROM public.usuarios_empresas ue WHERE ue.nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',
   jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_emp,'administrador',1,'Teste de estorno ordenado e NF',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_emp,'IMBIRIBEIRA');
 INSERT INTO public.obras(empresa_id,nome,codigo)
 VALUES(v_emp,'TESTE ESTORNO NF EWGEST','TESTE-NF-EST-4621') RETURNING id INTO v_work;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(v_emp,v_work,v_uid);
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 VALUES(v_emp,'TESTE-LOCK-PF','Perfil de teste de estorno','FAB TESTE')
 RETURNING id INTO v_profile;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 VALUES(v_emp,'perfil',v_profile,'BRANCO','BRANCO') RETURNING id INTO v_var;
 INSERT INTO public.ew_fornecedores(empresa_id,nome)
 VALUES(v_emp,'FORNECEDOR ORDEM NF ESTORNO TESTE') RETURNING id INTO v_supplier;
 v_data:=public.ew_compras_criar_solicitacao(
  v_emp,v_work,null,jsonb_build_array(jsonb_build_object('chave','1',
   'variacao_id',v_var,'quantidade',3,'unidade','BARRA','comprimento_mm',6000)),
  'Teste de vínculo físico e fiscal',gen_random_uuid());
 v_solic:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_cotacao(v_solic,v_supplier,
  '[{"chave":"1","preco_unitario_centavos":5000}]'::jsonb,gen_random_uuid());
 v_quote:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_pedido(v_quote,gen_random_uuid());
 v_order:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_receber_pedido(v_order,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":1}]'::jsonb,gen_random_uuid());
 v_rec_fiscal:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_receber_pedido(v_order,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":1}]'::jsonb,gen_random_uuid());
 v_rec_free:=(v_data->>'id')::uuid;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_total
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var;
 IF v_total<>2 THEN RAISE EXCEPTION 'Os dois recebimentos devem somar duas barras.';END IF;
 INSERT INTO public.ew_obra_despesas(
   empresa_id,obra_id,categoria,valor,fornecedor,numero_documento,
   origem,chave_nfe,status,observacoes,criado_por,aprovado_por,aprovado_em)
 VALUES(v_emp,v_work,'aluminio',50,
   'FORNECEDOR ORDEM NF ESTORNO TESTE','NF-TESTE-LOCK',
   'nfe_xml',repeat('2',44),'aprovada','Teste de segurança da conciliação',
   v_uid,v_uid,now()) RETURNING id INTO v_desp;
 INSERT INTO public.ew_obra_despesas_itens(
   despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
   valor_unitario,valor_total,perfil_id)
 VALUES(v_desp,v_emp,'TESTE-LOCK-PF','Perfil de teste','BARRA',1,50,50,v_profile)
 RETURNING id INTO v_item;
 v_data:=public.ew_compras_vincular_nfe_pedido(v_order,v_desp,
   jsonb_build_array(jsonb_build_object(
    'despesa_item_id',v_item,'recebimento_id',v_rec_fiscal,'chave','1')),
   gen_random_uuid());
 v_assoc:=(v_data->>'id')::uuid;
 v_blocked:=false;
 BEGIN
  PERFORM public.ew_compras_estornar_recebimento(v_rec_fiscal,
   'Estorno indevido de material com nota ativa',gen_random_uuid());
 EXCEPTION WHEN OTHERS THEN v_blocked:=true;END;
 IF NOT v_blocked THEN RAISE EXCEPTION 'Estorno de recebimento fiscalmente vinculado não foi bloqueado.';END IF;
 v_data:=public.ew_compras_estornar_recebimento(
  v_rec_free,'Estorno do recebimento ainda sem nota',v_op_free);
 IF coalesce((v_data->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Recebimento sem nota não foi estornado.';END IF;
 v_data:=public.ew_compras_estornar_recebimento(
  v_rec_free,'Estorno do recebimento ainda sem nota',v_op_free);
 IF coalesce((v_data->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Reenvio de estorno da mesma operação não foi idempotente.';END IF;
 v_blocked:=false;
 BEGIN
  PERFORM public.ew_compras_estornar_recebimento(v_rec_free,
   'Novo ID para estorno já existente',gen_random_uuid());
 EXCEPTION WHEN OTHERS THEN v_blocked:=true;END;
 IF NOT v_blocked THEN RAISE EXCEPTION 'Novo identificador permitiu estorno duplicado.';END IF;
 IF (SELECT status FROM public.ew_compras_pedidos WHERE id=v_order)<>'PARCIAL'
 THEN RAISE EXCEPTION 'Pedido deveria estar parcial após estorno.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_total
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var;
 IF v_total<>1 THEN RAISE EXCEPTION 'Estorno parcial deixou % barras.',v_total;END IF;
 v_data:=public.ew_compras_desvincular_nfe(v_assoc,
   'Desvincular a nota antes de estornar',gen_random_uuid());
 IF coalesce((v_data->>'desvinculada')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Desvinculação da nota falhou.';END IF;
 v_data:=public.ew_compras_estornar_recebimento(
  v_rec_fiscal,'Estorno após desvinculação fiscal',v_op_fiscal);
 IF coalesce((v_data->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Recebimento desvinculado não foi estornado.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_total
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var;
 IF v_total<>0 THEN RAISE EXCEPTION 'Estorno completo deixou saldo físico %.',v_total;END IF;
 IF (SELECT status FROM public.ew_compras_pedidos WHERE id=v_order)<>'ABERTO'
 THEN RAISE EXCEPTION 'Pedido deveria reabrir após todos os estornos.';END IF;
 IF (SELECT count(*) FROM public.ew_compras_nfe_vinculos
    WHERE conciliacao_id=v_assoc AND desvinculado_em IS NOT NULL)<>1
 THEN RAISE EXCEPTION 'Histórico do vínculo fiscal foi apagado ou ficou ativo.';END IF;
 IF (SELECT count(*) FROM public.ew_compras_recebimentos
   WHERE pedido_id=v_order AND estornado_em IS NOT NULL)<>2
 THEN RAISE EXCEPTION 'Histórico de dois recebimentos estornados foi perdido.';END IF;
 RAISE NOTICE 'PASS: nota bloqueia estorno vinculado; outro recebimento do pedido pode ser estornado, reenvio idempotente, desvinculação permite reversão e saldos zerados.';
END;$test$;
