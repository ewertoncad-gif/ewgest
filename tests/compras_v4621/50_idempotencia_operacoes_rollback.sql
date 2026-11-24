-- EWGEST v46.21: idempotência e prevenção de reutilização de IDs com dados diferentes.
-- Executar após todas as propostas v46.21 no mesmo BEGIN/ROLLBACK em restauração-teste.
DO $test$
DECLARE
 v_uid uuid;v_empresa uuid;v_obra uuid;v_perfil uuid;v_var uuid;v_supplier uuid;
 v_solic uuid;v_quote uuid;v_pedido uuid;v_rec uuid;
 v_op_solic uuid:=gen_random_uuid();v_op_quote uuid:=gen_random_uuid();
 v_op_pedido uuid:=gen_random_uuid();v_op_rec uuid:=gen_random_uuid();
 v_itens jsonb;v_precos jsonb;v_result jsonb;
 v_bloqueou boolean;v_saldo numeric;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT v_uid,v_empresa
 FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_empresa,'administrador',1,'Teste idempotência compras',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_empresa,'IMBIRIBEIRA');
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(v_empresa,'TESTE IDEMPOTENCIA','TESTE-IDEM-COMPRA')
 RETURNING id INTO v_obra;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(v_empresa,v_obra,v_uid);
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 VALUES(v_empresa,'IDEM-P001','Perfil teste idempotência','FABRICANTE TESTE')
 RETURNING id INTO v_perfil;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 VALUES(v_empresa,'perfil',v_perfil,'NATURAL','NATURAL') RETURNING id INTO v_var;
 INSERT INTO public.ew_fornecedores(empresa_id,nome)
 VALUES(v_empresa,'FORNECEDOR TESTE IDEMPOTENCIA') RETURNING id INTO v_supplier;
 v_itens:=jsonb_build_array(jsonb_build_object('chave','A','variacao_id',v_var,
   'quantidade',2,'unidade','BARRA','comprimento_mm',6000));
 v_precos:='[{"chave":"A","preco_unitario_centavos":10000}]'::jsonb;
 v_result:=public.ew_compras_criar_solicitacao(
   v_empresa,v_obra,null,v_itens,'Solicitação idempotente',v_op_solic);
 v_solic:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_solicitacao(
   v_empresa,v_obra,null,v_itens,'Solicitação idempotente',v_op_solic);
 IF coalesce((v_result->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Repetição idêntica da solicitação não foi reconhecida.';END IF;
 v_bloqueou:=false;
 BEGIN
  PERFORM public.ew_compras_criar_solicitacao(v_empresa,v_obra,null,
    jsonb_build_array(jsonb_build_object('chave','A','variacao_id',v_var,
      'quantidade',3,'unidade','BARRA','comprimento_mm',6000)),
    'Solicitação idempotente',v_op_solic);
 EXCEPTION WHEN others THEN v_bloqueou:=true;END;
 IF NOT v_bloqueou THEN RAISE EXCEPTION 'Operação de solicitação aceitou dados diferentes.';END IF;

 v_result:=public.ew_compras_criar_cotacao(v_solic,v_supplier,v_precos,v_op_quote);
 v_quote:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_cotacao(v_solic,v_supplier,v_precos,v_op_quote);
 IF coalesce((v_result->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Repetição idêntica de cotação não foi reconhecida.';END IF;
 v_bloqueou:=false;
 BEGIN
  PERFORM public.ew_compras_criar_cotacao(
   v_solic,v_supplier,'[{"chave":"A","preco_unitario_centavos":20000}]'::jsonb,v_op_quote);
 EXCEPTION WHEN others THEN v_bloqueou:=true;END;
 IF NOT v_bloqueou THEN RAISE EXCEPTION 'Preço diferente foi aceito na mesma operação.';END IF;

 v_result:=public.ew_compras_criar_pedido(v_quote,v_op_pedido);
 v_pedido:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_pedido(v_quote,v_op_pedido);
 IF coalesce((v_result->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Pedido repetido não foi reconhecido.';END IF;
 v_result:=public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
   '[{"chave":"A","quantidade":2}]'::jsonb,v_op_rec);
 v_rec:=(v_result->>'id')::uuid;
 IF (SELECT status FROM public.ew_compras_pedidos WHERE id=v_pedido)<>'CONCLUIDO'
 THEN RAISE EXCEPTION 'Pedido deveria estar concluído.';END IF;
 v_result:=public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
   '[{"chave":"A","quantidade":2}]'::jsonb,v_op_rec);
 IF coalesce((v_result->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Recebimento já concluído não foi idempotente.';END IF;
 v_bloqueou:=false;
 BEGIN
  PERFORM public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
   '[{"chave":"A","quantidade":1}]'::jsonb,v_op_rec);
 EXCEPTION WHEN others THEN v_bloqueou:=true;END;
 IF NOT v_bloqueou THEN RAISE EXCEPTION 'Recebimento aceitou quantidade diferente no mesmo ID.';END IF;
 SELECT coalesce(sum(m.quantidade_delta),0) INTO v_saldo
 FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=v_obra AND m.variacao_id=v_var;
 IF v_saldo<>2 THEN RAISE EXCEPTION 'ID repetido duplicou saldo, encontrado %.',v_saldo;END IF;
 IF (SELECT count(*) FROM public.ew_compras_solicitacoes WHERE operacao_id=v_op_solic)<>1 OR
  (SELECT count(*) FROM public.ew_compras_cotacoes WHERE operacao_id=v_op_quote)<>1 OR
  (SELECT count(*) FROM public.ew_compras_pedidos WHERE operacao_id=v_op_pedido)<>1 OR
  (SELECT count(*) FROM public.ew_compras_recebimentos WHERE operacao_id=v_op_rec)<>1
 THEN RAISE EXCEPTION 'Operações repetidas criaram registros duplicados.';END IF;
 RAISE NOTICE 'PASS: solicitação, cotação, pedido e recebimento rejeitam IDs reutilizados com dados diferentes, saldo físico único.';
END;
$test$;
