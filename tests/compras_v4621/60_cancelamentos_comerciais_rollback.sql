-- EWGEST v46.21: cancelamentos comerciais preservam auditoria sem estoque alterado.
-- Executar APÓS seis propostas v46.21, no mesmo BEGIN e ROLLBACK.
alter table public.ew_fornecedores add column if not exists criado_por uuid references auth.users(id);

DO $commercial$
declare
 v_uid uuid;v_emp uuid;v_work uuid;v_perf uuid;v_var uuid;v_supplier uuid;
 v_solic1 uuid;v_quote1 uuid;v_quote2 uuid;v_solic2 uuid;v_quote3 uuid;v_order2 uuid;
 v_solic3 uuid;v_quote4 uuid;v_order3 uuid;v_recv uuid;
 v_r jsonb;v_items jsonb;v_price jsonb;
 v_op uuid:=gen_random_uuid();v_failed boolean;v_movements integer;
begin
 select usuario_id,empresa_id into strict v_uid,v_emp from public.usuarios_empresas
 where nivel_acesso=1 limit 1;
 perform pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 perform pg_catalog.set_config('request.jwt.claims',
   jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 insert into public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 values(v_uid,v_emp,'administrador',1,'Teste cancelamentos comerciais',true);
 insert into public.ew_locais_fisicos(empresa_id,nome) values(v_emp,'IMBIRIBEIRA');
 insert into public.obras(empresa_id,nome,codigo)
 values(v_emp,'TESTE CANCELAMENTO COMPRAS','TESTE-CANCEL-4621') returning id into v_work;
 insert into public.ew_estoques_locais(empresa_id,obra_id,criado_por)
 values(v_emp,v_work,v_uid);
 insert into public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 values(v_emp,'TESTE-CANCEL-PF','Perfil de ensaio comercial','FAB TESTE') returning id into v_perf;
 insert into public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 values(v_emp,'perfil',v_perf,'NATURAL','NATURAL') returning id into v_var;
 insert into public.ew_fornecedores(empresa_id,nome,criado_por)
 values(v_emp,'FORNECEDOR TESTE CANCELAMENTOS',v_uid) returning id into v_supplier;
 v_items:=jsonb_build_array(jsonb_build_object(
    'chave','1','variacao_id',v_var,'quantidade',2,'unidade','BARRA','comprimento_mm',6000));
 v_price:='[{"chave":"1","preco_unitario_centavos":10000}]'::jsonb;

 -- Solicitação com duas cotações: cancelar uma, impedir pedido,
 -- cancelar solicitação e invalidar cotação restante.
 v_r:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,
    'Ensaio de solicitação e cotações',gen_random_uuid());
 v_solic1:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_criar_cotacao(v_solic1,v_supplier,v_price,gen_random_uuid());
 v_quote1:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_criar_cotacao(v_solic1,v_supplier,v_price,gen_random_uuid());
 v_quote2:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_cancelar_cotacao(v_quote1,'Cotação rejeitada no teste',v_op);
 if (v_r->>'cancelada')::boolean is distinct from true
 then raise exception 'Cancelamento da cotação falhou.';end if;
 v_r:=public.ew_compras_cancelar_cotacao(v_quote1,'Cotação rejeitada no teste',v_op);
 if (v_r->>'repetida')::boolean is distinct from true
 then raise exception 'Reenvio da mesma cotação cancelada deveria ser idempotente.';end if;
 v_failed:=false;
 begin perform public.ew_compras_criar_pedido(v_quote1,gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Pedido aceitou cotação cancelada.';end if;
 v_r:=public.ew_compras_cancelar_solicitacao(v_solic1,
     'Necessidade de materiais cancelada',gen_random_uuid());
 if (select status from public.ew_compras_solicitacoes where id=v_solic1)<>'CANCELADA'
 or (select status from public.ew_compras_cotacoes where id=v_quote2)<>'CANCELADA'
 then raise exception 'Solicitação e cotação aberta não foram canceladas juntas.';end if;
 v_failed:=false;
 begin perform public.ew_compras_criar_pedido(v_quote2,gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Cotação de solicitação cancelada gerou pedido.';end if;

 -- Pedido nunca recebido: cancelar sem movimentar estoque.
 v_r:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,
    'Compra que não será entregue',gen_random_uuid());
 v_solic2:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_criar_cotacao(v_solic2,v_supplier,v_price,gen_random_uuid());
 v_quote3:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_criar_pedido(v_quote3,gen_random_uuid());
 v_order2:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_cancelar_pedido(v_order2,'Compra desistida antes da entrega',v_op);
 if (v_r->>'cancelado')::boolean is distinct from true
 then raise exception 'Pedido sem recebimento não foi cancelado.';end if;
 v_r:=public.ew_compras_cancelar_pedido(v_order2,'Compra desistida antes da entrega',v_op);
 if (v_r->>'repetida')::boolean is distinct from true
 then raise exception 'Reenvio de pedido cancelado não foi idempotente.';end if;
 if (select status from public.ew_compras_solicitacoes where id=v_solic2)<>'PEDIDO_GERADO'
 then raise exception 'Pedido cancelado liberou solicitação para gerar outro pedido.';end if;
 v_failed:=false;
 begin perform public.ew_compras_receber_pedido(v_order2,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":1}]'::jsonb,gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Pedido cancelado foi recebido fisicamente.';end if;

 -- Pedido já recebido, ainda que o recebimento tenha sido estornado:
 -- não permitir cancelamento direto (há histórico físico).
 v_r:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,
    'Pedido com movimento físico de teste',gen_random_uuid());
 v_solic3:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_criar_cotacao(v_solic3,v_supplier,v_price,gen_random_uuid());
 v_quote4:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_criar_pedido(v_quote4,gen_random_uuid());
 v_order3:=(v_r->>'id')::uuid;
 v_r:=public.ew_compras_receber_pedido(v_order3,'IMBIRIBEIRA',
  '[{"chave":"1","quantidade":1}]'::jsonb,gen_random_uuid());
 v_recv:=(v_r->>'id')::uuid;
 v_failed:=false;
 begin perform public.ew_compras_cancelar_pedido(v_order3,
 'Cancelar pedido parcialmente recebido',gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Pedido com recebimento parcial foi cancelado.';end if;
 perform public.ew_compras_estornar_recebimento(v_recv,
   'Devolver material que ainda não foi usado',gen_random_uuid());
 v_failed:=false;
 begin perform public.ew_compras_cancelar_pedido(v_order3,
 'Histórico de recebimento foi estornado',gen_random_uuid());
 exception when others then v_failed:=true;end;
 if not v_failed then raise exception 'Pedido com movimento histórico estornado foi cancelado.';end if;
 select count(*) into v_movements from public.ew_estoque_obras_movimentos
 where obra_id=v_work;
 if v_movements<>2 then raise exception 'Esperados entrada e estorno, encontrados %.',v_movements;end if;
 if (select coalesce(sum(quantidade_delta),0) from public.ew_estoque_obras_movimentos
 where obra_id=v_work)<>0
 then raise exception 'Cancelamentos alteraram saldo físico indevidamente.';end if;
 raise notice 'PASS: cancelamentos, cotação invalidada, recebimento bloqueado, histórico, justificativas e estoque zerado.';
end;$commercial$;
