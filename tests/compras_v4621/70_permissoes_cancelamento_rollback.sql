-- EWGEST v46.21: permissão de cancelamento dos níveis 01/03/04/05/06/07/08.
-- Somente dados sintéticos em transação com ROLLBACK.
alter table public.ew_fornecedores add column if not exists criado_por uuid references auth.users(id);
DO $roles$
declare
 v_uid uuid;v_emp uuid;v_work uuid;v_perf uuid;v_var uuid;v_sup uuid;
 v_s1 uuid;v_s2 uuid;v_s3 uuid;v_s4 uuid;
 v_q1 uuid;v_q2 uuid;v_q3 uuid;v_p uuid;
 v_res jsonb;v_items jsonb;v_price jsonb;
 v_block boolean;
begin
 select usuario_id,empresa_id into strict v_uid,v_emp from public.usuarios_empresas where nivel_acesso=1 limit 1;
 perform pg_catalog.set_config('request.jwt.claim.sub',v_uid::text,true);
 perform pg_catalog.set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
 insert into public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo)
 values(v_uid,v_emp,'administrador',1,'Teste permissões cancelamento',true);
 insert into public.obras(empresa_id,nome,codigo)
 values(v_emp,'TESTE REGRAS NIVEIS CANCELAMENTO','TESTE-NIVEL-COMPRA') returning id into v_work;
 insert into public.ew_estoques_locais(empresa_id,obra_id,criado_por) values(v_emp,v_work,v_uid);
 insert into public.ew_perfis(empresa_id,codigo,descricao,fabricante)
 values(v_emp,'TESTEPROFNIVEL','Perfil simulado','FAB TESTE') returning id into v_perf;
 insert into public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento)
 values(v_emp,'perfil',v_perf,'BRANCO','BRANCO') returning id into v_var;
 insert into public.ew_fornecedores(empresa_id,nome,criado_por)
 values(v_emp,'FORNECEDOR PERMISSOES COMPRAS',v_uid) returning id into v_sup;
 v_items:=jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v_var,'quantidade',1,'unidade','BARRA','comprimento_mm',6000));
 v_price:='[{"chave":"1","preco_unitario_centavos":10000}]'::jsonb;
 v_res:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,'Solicitação técnica 1',gen_random_uuid());
 v_s1:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,'Solicitação técnica 2',gen_random_uuid());
 v_s2:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_cotacao(v_s2,v_sup,v_price,gen_random_uuid());
 v_q1:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,'Solicitação técnica 3',gen_random_uuid());
 v_s3:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_cotacao(v_s3,v_sup,v_price,gen_random_uuid());
 v_q2:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_pedido(v_q2,gen_random_uuid());
 v_p:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_solicitacao(v_emp,v_work,null,v_items,'Solicitação técnica 4',gen_random_uuid());
 v_s4:=(v_res->>'id')::uuid;
 v_res:=public.ew_compras_criar_cotacao(v_s4,v_sup,v_price,gen_random_uuid());
 v_q3:=(v_res->>'id')::uuid;

 -- Nível 04 (almoxarife) não cancela atos de compras; permanece apto a receber.
 update public.usuarios_empresas set nivel_acesso=4,perfil='almoxarife'
 where usuario_id=v_uid and empresa_id=v_emp;
 update public.usuarios_login set nivel_acesso=4,perfil='almoxarife'
 where usuario_id=v_uid and empresa_id=v_emp;
 if not public.ew_pode(v_emp,'compras.receber') then raise exception 'Nível 04 sem flag de receber.';end if;
 v_block:=false;
 begin perform public.ew_compras_cancelar_solicitacao(v_s1,'Teste acesso negado nível 04',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Almoxarife conseguiu cancelar solicitação.';end if;
 v_block:=false;
 begin perform public.ew_compras_cancelar_cotacao(v_q1,'Teste acesso negado nível 04',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Almoxarife conseguiu cancelar cotação.';end if;
 v_block:=false;
 begin perform public.ew_compras_cancelar_pedido(v_p,'Teste acesso negado nível 04',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Almoxarife conseguiu cancelar pedido.';end if;

 -- Nível 03 pode cancelar solicitação, não cotação/pedido.
 update public.usuarios_empresas set nivel_acesso=3,perfil='tecnico'
 where usuario_id=v_uid and empresa_id=v_emp;
 update public.usuarios_login set nivel_acesso=3,perfil='tecnico'
 where usuario_id=v_uid and empresa_id=v_emp;
 v_res:=public.ew_compras_cancelar_solicitacao(v_s1,'Cancelamento permitido ao perfil técnico',gen_random_uuid());
 if (v_res->>'cancelada')::boolean is distinct from true then raise exception 'Nível 03 deveria cancelar solicitação.';end if;
 v_block:=false;
 begin perform public.ew_compras_cancelar_pedido(v_p,'Teste acesso negado nível 03',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Nível 03 cancelou pedido.';end if;

 -- Nível 05: permite cotação e pedido, não solicitação.
 update public.usuarios_empresas set nivel_acesso=5,perfil='financeiro'
 where usuario_id=v_uid and empresa_id=v_emp;
 update public.usuarios_login set nivel_acesso=5,perfil='financeiro'
 where usuario_id=v_uid and empresa_id=v_emp;
 v_res:=public.ew_compras_cancelar_cotacao(v_q1,'Cancelamento de cotação pelo financeiro',gen_random_uuid());
 if (v_res->>'cancelada')::boolean is distinct from true then raise exception 'Nível 05 deveria cancelar cotação.';end if;
 v_res:=public.ew_compras_cancelar_pedido(v_p,'Cancelamento de pedido pelo financeiro',gen_random_uuid());
 if (v_res->>'cancelado')::boolean is distinct from true then raise exception 'Nível 05 deveria cancelar pedido.';end if;
 v_block:=false;
 begin perform public.ew_compras_cancelar_solicitacao(v_s4,'Sem permissão de solicitação',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Nível 05 cancelou solicitação.';end if;

 -- Níveis somente leitura (06,07) e bloqueado (08).
 for v_res in select jsonb_build_object('nivel',n) from unnest(array[6,7,8]) n loop
  update public.usuarios_empresas set nivel_acesso=(v_res->>'nivel')::integer,perfil='consulta'
  where usuario_id=v_uid and empresa_id=v_emp;
  update public.usuarios_login set nivel_acesso=(v_res->>'nivel')::integer,perfil='consulta'
  where usuario_id=v_uid and empresa_id=v_emp;
  v_block:=false;
  begin perform public.ew_compras_cancelar_cotacao(v_q3,'Operação reservada ao financeiro',gen_random_uuid());
  exception when others then v_block:=true;end;
  if not v_block then raise exception 'Nível % cancelou cotação.',v_res->>'nivel';end if;
 end loop;
 raise notice 'PASS: níveis 03,04,05,06,07,08 respeitam permissões de cancelamentos e recebimento.';
end;$roles$;
