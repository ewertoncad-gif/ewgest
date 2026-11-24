-- EWGEST v46.21: MT inteiro (invariante legado) e KG fracionado até 3 casas.
-- Barras, peças e MT permanecem inteiros, KG admite frações com três decimais.
-- Executar somente em transação única seguida de ROLLBACK.
DO $test$
DECLARE
 v_uid uuid;v_emp uuid;v_work uuid;v_loc uuid;
 v_acc_mt uuid;v_acc_kg uuid;v_var_mt uuid;v_var_kg uuid;
 v_solic uuid;v_quote uuid;v_order uuid;v_rec uuid;v_supplier uuid;
 v_trans_mt uuid;v_trans_kg uuid;v_data jsonb;
 v_company_mt numeric;v_company_kg numeric;v_work_mt numeric;v_work_kg numeric;v_reject boolean;
BEGIN
 SELECT ue.usuario_id,ue.empresa_id INTO STRICT v_uid,v_emp
 FROM public.usuarios_empresas ue WHERE ue.nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',
  jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_emp,'administrador',1,'Teste MT e KG fracionados',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_emp,'IMBIRIBEIRA');
 INSERT INTO public.obras(empresa_id,nome,codigo)
 VALUES(v_emp,'OBRA TESTE FRAÇÕES','TESTE-MTKG-4621') RETURNING id INTO v_work;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(v_emp,v_work,v_uid);
 INSERT INTO public.ew_acessorios(empresa_id,codigo,descricao,fabricante,unidade_item)
 VALUES(v_emp,'TESTE-MT-4621','Fita de vedação por metro','FAB TESTE','MT')
 RETURNING id INTO v_acc_mt;
 INSERT INTO public.ew_acessorios(empresa_id,codigo,descricao,fabricante,unidade_item)
 VALUES(v_emp,'TESTE-KG-4621','Insumo por quilograma','FAB TESTE','KG')
 RETURNING id INTO v_acc_kg;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,acessorio_id,cor,acabamento)
 VALUES(v_emp,'acessorio',v_acc_mt,'PRETO','PRETO') RETURNING id INTO v_var_mt;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,acessorio_id,cor,acabamento)
 VALUES(v_emp,'acessorio',v_acc_kg,'NATURAL','NATURAL') RETURNING id INTO v_var_kg;
 INSERT INTO public.ew_fornecedores(empresa_id,nome)
 VALUES(v_emp,'FORNECEDOR TESTE FRACIONADO') RETURNING id INTO v_supplier;
 v_data:=public.ew_compras_criar_local_empresa(v_emp,'ESTOQUE EMPRESA FRACIONADO TESTE');
 v_loc:=(v_data->>'id')::uuid;
 -- Quantidade de MT fracionada não pode ser aceita no cadastro.
 v_reject:=false;
 BEGIN
  PERFORM public.ew_compras_criar_solicitacao(v_emp,null,v_loc,
   jsonb_build_array(jsonb_build_object('chave','mt','variacao_id',v_var_mt,
     'quantidade',0.500,'unidade','MT','comprimento_mm',null)),
   'Valor com precisão inválida',gen_random_uuid());
 EXCEPTION WHEN OTHERS THEN v_reject:=true;END;
 IF NOT v_reject THEN RAISE EXCEPTION 'Compras aceitou fração de MT proibida pelo estoque legado.';END IF;

 v_data:=public.ew_compras_criar_solicitacao(v_emp,null,v_loc,
  jsonb_build_array(
    jsonb_build_object('chave','mt','variacao_id',v_var_mt,
      'quantidade',2,'unidade','MT','comprimento_mm',null),
    jsonb_build_object('chave','kg','variacao_id',v_var_kg,
      'quantidade',2.250,'unidade','KG','comprimento_mm',null)),
  'Compra com MT inteiro e KG fracionado',gen_random_uuid());
 v_solic:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_cotacao(v_solic,v_supplier,
  '[{"chave":"mt","preco_unitario_centavos":10000},{"chave":"kg","preco_unitario_centavos":20000}]'::jsonb,
  gen_random_uuid());
 v_quote:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_criar_pedido(v_quote,gen_random_uuid());
 v_order:=(v_data->>'id')::uuid;
 -- Entrada física com MT inteiro e KG fracionado (vários itens no mesmo recebimento).
 v_data:=public.ew_compras_receber_pedido(v_order,'IMBIRIBEIRA',
  '[{"chave":"mt","quantidade":1},{"chave":"kg","quantidade":0.725}]'::jsonb,gen_random_uuid());
 v_rec:=(v_data->>'id')::uuid;
 IF (SELECT status FROM public.ew_compras_pedidos WHERE id=v_order)<>'PARCIAL'
 THEN RAISE EXCEPTION 'Pedido fracionado deveria permanecer parcial.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_company_mt
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_loc AND variacao_id=v_var_mt;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_company_kg
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_loc AND variacao_id=v_var_kg;
 IF v_company_mt<>1 OR v_company_kg<>0.725
 THEN RAISE EXCEPTION 'Entrada fracionada incorreta: % MT e % KG.',v_company_mt,v_company_kg;END IF;
 v_reject:=false;
 BEGIN
  PERFORM public.ew_compras_transferir_locais(v_emp,'EMPRESA',v_loc,'OBRA',v_work,
   v_var_kg,null,'KG',0.0005,'IMBIRIBEIRA','IMBIRIBEIRA',
   'Tentativa fracionária inválida',gen_random_uuid());
 EXCEPTION WHEN OTHERS THEN v_reject:=true;END;
 IF NOT v_reject THEN RAISE EXCEPTION 'Transferência aceitou quatro casas decimais.';END IF;

 v_data:=public.ew_compras_transferir_locais(v_emp,'EMPRESA',v_loc,'OBRA',v_work,
  v_var_mt,null,'MT',1,'IMBIRIBEIRA','IMBIRIBEIRA',
  'Transferência de fita por metro',gen_random_uuid());
 v_trans_mt:=(v_data->>'id')::uuid;
 v_data:=public.ew_compras_transferir_locais(v_emp,'EMPRESA',v_loc,'OBRA',v_work,
  v_var_kg,null,'KG',0.250,'IMBIRIBEIRA','IMBIRIBEIRA',
  'Transferência de material por quilo',gen_random_uuid());
 v_trans_kg:=(v_data->>'id')::uuid;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_work_mt
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var_mt;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_work_kg
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var_kg;
 IF v_work_mt<>1 OR v_work_kg<>0.250
 THEN RAISE EXCEPTION 'Obra recebeu frações incorretas, % MT e % KG.',v_work_mt,v_work_kg;END IF;

 -- Antes de reverter a transferência, o recebimento precisa bloquear estorno.
 v_reject:=false;
 BEGIN
  PERFORM public.ew_compras_estornar_recebimento(v_rec,
   'Recebimento ainda transferido à obra',gen_random_uuid());
 EXCEPTION WHEN OTHERS THEN v_reject:=true;END;
 IF NOT v_reject THEN RAISE EXCEPTION 'Recebimento fracionado com transferência foi estornado indevidamente.';END IF;
 PERFORM public.ew_compras_estornar_transferencia(
  v_trans_mt,'Reversão do envio de fita',gen_random_uuid());
 PERFORM public.ew_compras_estornar_transferencia(
  v_trans_kg,'Reversão do envio do insumo em KG',gen_random_uuid());
 v_data:=public.ew_compras_estornar_recebimento(
  v_rec,'Estornar após retorno dos materiais',gen_random_uuid());
 IF coalesce((v_data->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Recebimento fracionado não foi estornado.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_company_mt
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_loc AND variacao_id=v_var_mt;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_company_kg
 FROM public.ew_compras_estoque_empresa WHERE local_empresa_id=v_loc AND variacao_id=v_var_kg;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_work_mt
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var_mt;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_work_kg
 FROM public.ew_estoque_obras_movimentos WHERE obra_id=v_work AND variacao_id=v_var_kg;
 IF v_company_mt<>0 OR v_company_kg<>0 OR v_work_mt<>0 OR v_work_kg<>0
 THEN RAISE EXCEPTION 'Saldo não zerou: empresa % MT / % KG, obra % MT / % KG.',
    v_company_mt,v_company_kg,v_work_mt,v_work_kg;END IF;
 RAISE NOTICE 'PASS: MT inteiro preservado, KG com três decimais, recebimento parcial, transferências, bloqueio com consumo, estornos e saldo zero.';
END;$test$;
