-- EWGEST v46.21: conciliação fiscal e prevenção de estoque duplicado.
-- Executar junto das quatro propostas v46.21 na transação de homologação; ROLLBACK.
-- Os dados abaixo são exclusivamente sintéticos.
-- Banco de restauração desatualizado: ajuste transitório da estrutura, revertido no ROLLBACK.
ALTER TABLE public.ew_obra_despesas ADD COLUMN IF NOT EXISTS chave_nfe text;
DO $nfe_test$
DECLARE
 v_uid uuid;v_empresa uuid;v_obra uuid;v_perfil uuid;v_variacao uuid;v_fornecedor uuid;
 v_solic uuid;v_cot uuid;v_pedido uuid;v_receb1 uuid;v_receb2 uuid;
 v_despesa uuid;v_item uuid;v_item_incorreto uuid;v_assoc uuid;
 v_ret jsonb;v_falhou boolean;v_revert_op uuid:=gen_random_uuid();
 v_mov uuid;v_before numeric;v_after numeric;
BEGIN
 SELECT ue.usuario_id,ue.empresa_id INTO STRICT v_uid,v_empresa
 FROM public.usuarios_empresas ue WHERE ue.nivel_acesso=1 LIMIT 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',
  jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 VALUES(v_uid,v_empresa,'administrador',1,'Simulação conciliação fiscal',true);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(v_empresa,'IMBIRIBEIRA');
 INSERT INTO public.obras(empresa_id,nome,codigo)
 VALUES(v_empresa,'OBRA TESTE NF SEM DUPLICIDADE','TESTE-NF-4621') RETURNING id INTO v_obra;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 VALUES(v_empresa,v_obra,v_uid);
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 VALUES(v_empresa,'TESTE-NF-PERFIL','Perfil 6000mm','FAB TESTE') RETURNING id INTO v_perfil;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 VALUES(v_empresa,'perfil',v_perfil,'NATURAL','NATURAL') RETURNING id INTO v_variacao;
 INSERT INTO public.ew_fornecedores(empresa_id,nome)
 VALUES(v_empresa,'FORNECEDOR TESTE NF V4621') RETURNING id INTO v_fornecedor;
 v_ret:=public.ew_compras_criar_solicitacao(v_empresa,v_obra,null,
  jsonb_build_array(jsonb_build_object('chave','EA01','variacao_id',v_variacao,
  'quantidade',4,'unidade','BARRA','comprimento_mm',6000)),
  'Teste conciliação físico-fiscal',gen_random_uuid());
 v_solic:=(v_ret->>'id')::uuid;
 v_ret:=public.ew_compras_criar_cotacao(v_solic,v_fornecedor,
  '[{"chave":"EA01","preco_unitario_centavos":25000}]'::jsonb,gen_random_uuid());
 v_cot:=(v_ret->>'id')::uuid;
 v_ret:=public.ew_compras_criar_pedido(v_cot,gen_random_uuid());
 v_pedido:=(v_ret->>'id')::uuid;
 v_ret:=public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
  '[{"chave":"EA01","quantidade":1}]'::jsonb,gen_random_uuid());
 v_receb1:=(v_ret->>'id')::uuid;
 v_ret:=public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
  '[{"chave":"EA01","quantidade":1}]'::jsonb,gen_random_uuid());
 v_receb2:=(v_ret->>'id')::uuid;
 -- Uma terceira entrega do pedido segue sem nota para testar bloqueio preventivo.
 PERFORM public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
  '[{"chave":"EA01","quantidade":1}]'::jsonb,gen_random_uuid());
 SELECT sum(m.quantidade_delta) INTO v_before FROM public.ew_estoque_obras_movimentos m
 WHERE m.obra_id=v_obra AND m.variacao_id=v_variacao;
 IF v_before<>3 THEN RAISE EXCEPTION 'Estoque pré-conciliação não é 3 barras.';END IF;
 INSERT INTO public.ew_obra_despesas(
  empresa_id,obra_id,categoria,valor,fornecedor,numero_documento,
  origem,chave_nfe,status,observacoes,criado_por,aprovado_por,aprovado_em)
 VALUES(v_empresa,v_obra,'aluminio',500.00,'FORNECEDOR TESTE NF V4621',
  'NF TESTE 0001','nfe_xml',repeat('1',44),'aprovada','Simulação NF somente financeira',
  v_uid,v_uid,now()) RETURNING id INTO v_despesa;
 INSERT INTO public.ew_obra_despesas_itens(
  despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
  valor_unitario,valor_total,perfil_id)
 VALUES(v_despesa,v_empresa,'TESTE-NF-PERFIL','Perfil 6000mm','BARRA',2,250.00,500.00,v_perfil)
 RETURNING id INTO v_item;
 v_ret:=public.ew_compras_vincular_nfe_pedido(v_pedido,v_despesa,
  jsonb_build_array(
    jsonb_build_object('despesa_item_id',v_item,'recebimento_id',v_receb1,'chave','EA01'),
    jsonb_build_object('despesa_item_id',v_item,'recebimento_id',v_receb2,'chave','EA01')
  ),v_revert_op);
 v_assoc:=(v_ret->>'id')::uuid;
 IF (v_ret->>'itens_vinculados')::int<>2 OR (v_ret->>'entrada_fisica_duplicada')::boolean<>false
 THEN RAISE EXCEPTION 'Conciliação não confirmou as duas entradas de pedido.';END IF;
 SELECT sum(m.quantidade_delta) INTO v_after FROM public.ew_estoque_obras_movimentos m
 WHERE m.obra_id=v_obra AND m.variacao_id=v_variacao;
 IF v_after<>v_before THEN RAISE EXCEPTION 'Conciliação alterou o estoque físico.';END IF;
 v_ret:=public.ew_compras_vincular_nfe_pedido(v_pedido,v_despesa,
  jsonb_build_array(
    jsonb_build_object('despesa_item_id',v_item,'recebimento_id',v_receb1,'chave','EA01'),
    jsonb_build_object('despesa_item_id',v_item,'recebimento_id',v_receb2,'chave','EA01')
  ),v_revert_op);
 IF coalesce((v_ret->>'repetida')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Conciliacão idempotente falhou.';END IF;

 -- A nota conciliada não pode reentrar no estoque via registro físico antigo.
 SELECT movimento_obra_id INTO v_mov FROM public.ew_compras_recebimentos_movimentos
 WHERE recebimento_id=v_receb1 AND chave='EA01';
 v_falhou:=false;
 BEGIN
  INSERT INTO public.ew_nfe_recebimentos(
   empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,
   quantidade,local_estoque,movimento_id,usuario_id)
  VALUES(v_empresa,v_obra,v_item,v_variacao,6000,'BARRA',1,'IMBIRIBEIRA',v_mov,v_uid);
 EXCEPTION WHEN others THEN v_falhou:=true;END;
 IF NOT v_falhou THEN RAISE EXCEPTION 'NF vinculada duplicou estoque no fluxo antigo.';END IF;

 -- Outra nota do mesmo fornecedor/material não deve duplicar recebimento por engano.
 INSERT INTO public.ew_obra_despesas_itens(
  despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
  valor_unitario,valor_total,perfil_id)
 VALUES(v_despesa,v_empresa,'TESTE-NF-PERFIL','Perfil duplicado','BARRA',1,250.00,250.00,v_perfil)
 RETURNING id INTO v_item_incorreto;
 v_falhou:=false;
 BEGIN
  INSERT INTO public.ew_nfe_recebimentos(
   empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,
   quantidade,local_estoque,movimento_id,usuario_id)
  VALUES(v_empresa,v_obra,v_item_incorreto,v_variacao,6000,'BARRA',1,'IMBIRIBEIRA',v_mov,v_uid);
 EXCEPTION WHEN others THEN v_falhou:=true;END;
 IF NOT v_falhou THEN RAISE EXCEPTION 'NF do mesmo material/fornecedor não foi bloqueada.';END IF;

 v_falhou:=false;
 BEGIN
  UPDATE public.ew_obra_despesas SET status='cancelada' WHERE id=v_despesa;
 EXCEPTION WHEN others THEN v_falhou:=true;END;
 IF NOT v_falhou THEN RAISE EXCEPTION 'Cancelamento da nota conciliada deveria bloquear.';END IF;
 v_falhou:=false;
 BEGIN
  PERFORM public.ew_compras_estornar_recebimento(
   v_receb1,'Tentativa antes de desvincular nota',gen_random_uuid());
 EXCEPTION WHEN others THEN v_falhou:=true;END;
 IF NOT v_falhou THEN RAISE EXCEPTION 'Estorno físico vinculado à nota deveria bloquear.';END IF;

 v_ret:=public.ew_compras_desvincular_nfe(v_assoc,'Nota com vínculo incorreto - teste',gen_random_uuid());
 IF coalesce((v_ret->>'desvinculada')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Desvincular nota falhou.';END IF;
 v_ret:=public.ew_compras_estornar_recebimento(v_receb1,
  'Estorno após nota ter sido desvinculada',gen_random_uuid());
 IF coalesce((v_ret->>'estornado')::boolean,false) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Estorno após desvinculação falhou.';END IF;
 SELECT coalesce(sum(quantidade_delta),0) INTO v_after
 FROM public.ew_estoque_obras_movimentos m WHERE m.obra_id=v_obra;
 IF v_after<>2 THEN RAISE EXCEPTION 'Estoque após estorno deveria ser 2 barras, encontrado %.',v_after;END IF;
 -- Nota pode ser cancelada após desfazer vínculo; não gera estoque no cancelamento.
 UPDATE public.ew_obra_despesas SET status='cancelada' WHERE id=v_despesa;
 IF (SELECT status FROM public.ew_obra_despesas WHERE id=v_despesa)<>'cancelada'
 THEN RAISE EXCEPTION 'Cancelamento da nota desvinculada falhou.';END IF;

 RAISE NOTICE 'PASS NF: 2 recebimentos 1 NF, sem nova entrada, valores preservados, bloqueios, idempotência e estorno condicionado à desvinculação.';
END;$nfe_test$;
