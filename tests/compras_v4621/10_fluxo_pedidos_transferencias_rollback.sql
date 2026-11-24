-- EWGEST v46.21 | teste funcional transacional com dados sintéticos.
-- Executar APENAS em ewgest-restauracao-teste DEPOIS das três propostas v46.21,
-- na MESMA transação iniciada com BEGIN e finalizada com ROLLBACK.
-- Nunca aplicar isoladamente à produção.
-- Harmonização temporária de estrutura do ensaio (ROLLBACK ao final).
alter table public.ew_fornecedores add column if not exists criado_por uuid references auth.users(id);
DO $test$
DECLARE
 v_user uuid;v_empresa uuid;
 v_loc uuid;v_work uuid;v_profile uuid;v_var uuid;v_supplier uuid;
 v_solic uuid;v_cot uuid;v_pedido uuid;v_rec uuid;v_transfer uuid;
 v_solic_obra uuid;v_cot_obra uuid;v_pedido_obra uuid;v_rec_obra uuid;
 v_receber_op uuid:=gen_random_uuid();
 v_result jsonb;v_failed boolean;v_saldo numeric;v_status text;
 v_subtot bigint;
BEGIN
 select ue.usuario_id,ue.empresa_id into strict v_user,v_empresa
 from public.usuarios_empresas ue where ue.nivel_acesso=1 limit 1;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',v_user::text,true);
 PERFORM pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
 if auth.uid() is distinct from v_user then raise exception 'JWT de teste não foi simulado.';end if;
 insert into public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 values(v_user,v_empresa,'administrador',1,'Teste rollback v46.21',true);
 if not public.ew_pode(v_empresa,'compras.receber')
 or not public.ew_pode(v_empresa,'estoque.transferir_obras')
 or not public.ew_pode(v_empresa,'estoque.estornar')
 then raise exception 'Permissões v46.21 não funcionaram no ambiente de teste.';end if;

 insert into public.ew_locais_fisicos(empresa_id,nome)
 values(v_empresa,'IMBIRIBEIRA'),(v_empresa,'AFOGADOS');
 insert into public.obras(empresa_id,nome,codigo)
 values(v_empresa,'TESTE OBRA COMPRAS V46.21','TESTE-OBRA-COMPRA')
 returning id into v_work;
 insert into public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 values(v_empresa,v_work,v_user);
 insert into public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 values(v_empresa,'TESTEF001','Perfil teste compra - 6m','FABRICANTE TESTE')
 returning id into v_profile;
 insert into public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 values(v_empresa,'perfil',v_profile,'NATURAL','NATURAL')
 returning id into v_var;
 insert into public.ew_fornecedores(empresa_id,nome,criado_por)
 values(v_empresa,'FORNECEDOR TESTE V46.21',v_user) returning id into v_supplier;

 v_result:=public.ew_compras_criar_local_empresa(v_empresa,'ESTOQUE EMPRESA TESTE V4621');
 v_loc:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_solicitacao(v_empresa,null,v_loc,
  jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v_var,
   'quantidade',4,'unidade','BARRA','comprimento_mm',6000)),
  'Solicitação de teste com rollback',gen_random_uuid());
 v_solic:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_cotacao(v_solic,v_supplier,
  '[{"chave":"1","preco_unitario_centavos":12345}]'::jsonb,gen_random_uuid());
 v_cot:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_pedido(v_cot,gen_random_uuid());
 v_pedido:=(v_result->>'id')::uuid;

 v_result:=public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":2}]'::jsonb,v_receber_op);
 v_rec:=(v_result->>'id')::uuid;
 if (select status from public.ew_compras_pedidos where id=v_pedido)<>'PARCIAL'
 then raise exception 'Pedido deveria estar PARCIAL.';end if;
 if (select count(*) from public.ew_compras_recebimentos_movimentos where recebimento_id=v_rec)<>1
 then raise exception 'Recebimento sem vínculo físico exato.';end if;
 v_result:=public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":2}]'::jsonb,v_receber_op);
 if coalesce((v_result->>'repetida')::boolean,false)<>true
 then raise exception 'Recebimento duplicado não foi idempotente.';end if;
 if (select count(*) from public.ew_compras_estoque_empresa where recebimento_id=v_rec)<>1
 then raise exception 'Repetição duplicou o movimento de estoque.';end if;

 -- Saldo restante de 2: tentar receber 3 deve FALHAR por limite do pedido.
 v_failed:=false;
 begin
  perform public.ew_compras_receber_pedido(v_pedido,'IMBIRIBEIRA',
   '[{"chave":"1","quantidade":3}]'::jsonb,gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Recebimento acima do saldo foi aceito.';end if;

 v_result:=public.ew_compras_transferir_locais(
  v_empresa,'EMPRESA',v_loc,'OBRA',v_work,
  v_var,6000,'BARRA',1,'IMBIRIBEIRA','AFOGADOS',
  'Teste transferência empresa para obra',gen_random_uuid());
 v_transfer:=(v_result->>'id')::uuid;
 if (select count(*) from public.ew_compras_transferencias where id=v_transfer)<>1
 then raise exception 'Transferência não gerou histórico.';end if;
 v_failed:=false;
 begin
  perform public.ew_compras_estornar_recebimento(
    v_rec,'Estorno proibido: material já transferido',gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Estorno permitiu retirar entrada transferida.';end if;

 v_result:=public.ew_compras_estornar_transferencia(
    v_transfer,'Devolução de teste sem consumo',gen_random_uuid());
 if coalesce((v_result->>'estornado')::boolean,false)<>true
 then raise exception 'Estorno de transferência falhou.';end if;
 v_result:=public.ew_compras_estornar_recebimento(
    v_rec,'Recebimento devolvido após retorno do material',gen_random_uuid());
 if coalesce((v_result->>'estornado')::boolean,false)<>true
 then raise exception 'Estorno de recebimento após devolução falhou.';end if;

 select coalesce(sum(quantidade_delta),0) into v_saldo
 from public.ew_compras_estoque_empresa where local_empresa_id=v_loc;
 if v_saldo<>0 then raise exception 'Saldo da empresa após estornos: %.',v_saldo;end if;
 select coalesce(sum(quantidade_delta),0) into v_saldo
 from public.ew_estoque_obras_movimentos where obra_id=v_work;
 if v_saldo<>0 then raise exception 'Saldo da obra após estornos: %.',v_saldo;end if;
 select status into v_status from public.ew_compras_pedidos where id=v_pedido;
 if v_status<>'ABERTO' then raise exception 'Estorno não reabriu pedido: %.',v_status;end if;

 -- Segundo destino: receber diretamente em obra e estornar sem transferências.
 v_result:=public.ew_compras_criar_solicitacao(v_empresa,v_work,null,
   jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v_var,
   'quantidade',3,'unidade','BARRA','comprimento_mm',6000)),
   'Solicitação teste obra',gen_random_uuid());
 v_solic_obra:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_cotacao(v_solic_obra,v_supplier,
   '[{"chave":"1","preco_unitario_centavos":10000}]'::jsonb,gen_random_uuid());
 v_cot_obra:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_criar_pedido(v_cot_obra,gen_random_uuid());
 v_pedido_obra:=(v_result->>'id')::uuid;
 v_result:=public.ew_compras_receber_pedido(v_pedido_obra,'IMBIRIBEIRA',
   '[{"chave":"1","quantidade":1}]'::jsonb,gen_random_uuid());
 v_rec_obra:=(v_result->>'id')::uuid;
 if (select count(*) from public.ew_compras_recebimentos_movimentos
    where recebimento_id=v_rec_obra and movimento_obra_id is not null)<>1
 then raise exception 'Entrada da obra sem vínculo físico.';end if;
 v_result:=public.ew_compras_estornar_recebimento(
  v_rec_obra,'Recebimento não utilizado em obra',gen_random_uuid());
 if coalesce((v_result->>'estornado')::boolean,false)<>true
 then raise exception 'Estorno da obra não retornou confirmação.';end if;
 select coalesce(sum(quantidade_delta),0) into v_saldo
 from public.ew_estoque_obras_movimentos where obra_id=v_work;
 if v_saldo<>0 then raise exception 'Saldo da obra não zerou após estorno.';end if;

 -- Cotações/preços só podem ser mostrados a quem tiver a flag financeira.
 v_result:=public.ew_compras_pedidos_resumo(v_empresa);
 if jsonb_typeof(v_result)<>'array' or
   not exists(select 1 from jsonb_array_elements(v_result) p
    where p->>'id'=v_pedido::text and (p->>'total_centavos')::bigint>0)
 then raise exception 'Administrador deveria consultar preços dos pedidos.';end if;
 update public.usuarios_empresas set perfil='almoxarife',nivel_acesso=4
 where usuario_id=v_user and empresa_id=v_empresa;
 update public.usuarios_login set perfil='almoxarife',nivel_acesso=4
 where usuario_id=v_user and empresa_id=v_empresa;
 if public.ew_pode(v_empresa,'compras.consultar_valores') or
    not public.ew_pode(v_empresa,'compras.receber')
 then raise exception 'Matriz de privacidade do almoxarifado inválida.';end if;
 v_result:=public.ew_compras_pedidos_resumo(v_empresa);
 if exists(select 1 from jsonb_array_elements(v_result) p
   where p->>'total_centavos' is not null)
 or exists(select 1 from jsonb_array_elements(v_result) p
     cross join lateral jsonb_array_elements(p->'itens') i(value)
     where i.value ? 'preco_unitario_centavos')
 then raise exception 'Preço de fornecedor foi exposto ao almoxarifado.';end if;
 raise notice 'PASS: fluxo com recebimento parcial, idempotência, limites, transferência, estorno, saldos zerados e preços ocultos por nível.';

END;
$test$;
