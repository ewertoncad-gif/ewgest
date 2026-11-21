-- TESTE INTEGRADO REVERSÍVEL — somente projeto ewgest-restauracao-teste.
begin;
do $test$
declare
 v_user uuid:=gen_random_uuid();v_empresa uuid:=gen_random_uuid();v_obra uuid:=gen_random_uuid();
 v_perfil uuid:=gen_random_uuid();v_variacao uuid:=gen_random_uuid();
 v_esq1 uuid:=gen_random_uuid();v_esq2 uuid:=gen_random_uuid();
 v_plano uuid;v_lote uuid;v_result jsonb;v_pend jsonb;
 v_mat jsonb;v_saldo numeric;v_qt integer;v_block boolean;
 v_op_entrega uuid:=gen_random_uuid();
begin
 insert into auth.users(id,aud,role,email)
 values(v_user,'authenticated','authenticated','ewgest-entrega-'||v_user::text||'@example.invalid');
 insert into public.empresas(id,nome) values(v_empresa,'EMPRESA TESTE ENTREGA');
 insert into public.obras(id,empresa_id,codigo,nome)
 values(v_obra,v_empresa,'LIB-01','OBRA FICTICIA ENTREGA');
 insert into public.usuarios_empresas(empresa_id,usuario_id,perfil)
 values(v_empresa,v_user,'tecnico');
 insert into public.usuarios_login(usuario_id,empresa_id,perfil,ativo,login,nome)
 values(v_user,v_empresa,'tecnico',true,'tecnico-teste','TÉCNICO TESTE');
 insert into public.esquadrias(id,empresa_id,obra_id,codigo,descricao,
  largura_mm,altura_mm,quantidade,qtd_liberada,qtd_fabricada)
 values(v_esq1,v_empresa,v_obra,'EA1','JANELA TESTE',1000,1000,1,0,0),
 (v_esq2,v_empresa,v_obra,'EA2','JANELA TESTE',1000,1000,1,0,0);
 insert into public.ew_estoques_locais(empresa_id,obra_id) values(v_empresa,v_obra);
 insert into public.ew_locais_fisicos(empresa_id,nome,ativo) values(v_empresa,'AFOGADOS',true);
 insert into public.ew_perfis(id,empresa_id,codigo,descricao) values(v_perfil,v_empresa,'GN096','FOLHA COLADA');
 insert into public.ew_materiais_variacoes(id,empresa_id,tipo,perfil_id,ativo)
 values(v_variacao,v_empresa,'perfil',v_perfil,true);
 perform set_config('request.jwt.claim.sub',v_user::text,true);
 v_mat:=jsonb_build_array(jsonb_build_object('variacao_id',v_variacao,'comprimento_mm',6000,
  'unidade','BARRA','quantidade',2,'local_estoque','AFOGADOS'));
 v_result:=public.ew_liberar_plano_corte_revisado(
  v_esq1,1,current_date,'AFOGADOS',v_mat,'MANUAL','RELATORIO-1',gen_random_uuid());
 v_plano:=(v_result->>'plano_id')::uuid;
 if (v_result->>'linhas_baixadas')::integer<>0 then
   raise exception 'Liberação técnica alterou estoque.';end if;
 select count(*) into v_qt from public.ew_estoque_obras_movimentos where obra_id=v_obra;
 if v_qt<>0 then raise exception 'Movimento inserido antes da entrega física';end if;
 -- Segundo relatório, geração em lote CEM.
 v_result:=public.ew_liberar_lote_cem(
  v_obra,current_date,'AFOGADOS',
  jsonb_build_array(jsonb_build_object('esquadria_id',v_esq2,'quantidade',1)),
  jsonb_build_array(jsonb_build_object('variacao_id',v_variacao,'comprimento_mm',6000,
   'unidade','BARRA','quantidade',1,'local_estoque','AFOGADOS')),
  'OBRA-LIB-01.zip',gen_random_uuid());
 v_lote:=(v_result->>'lote_id')::uuid;
 if (v_result->>'linhas_baixadas')::integer<>0 then
  raise exception 'Liberação CEM em lote alterou estoque';end if;
 update public.usuarios_empresas set perfil='almoxarife' where empresa_id=v_empresa and usuario_id=v_user;
 update public.usuarios_login set perfil='almoxarife' where empresa_id=v_empresa and usuario_id=v_user;
 v_pend:=public.ew_entregas_pendentes_producao(v_empresa,v_obra);
 if jsonb_array_length(v_pend)<>2 then raise exception 'Deveria haver 2 relatórios pendentes: %',v_pend;end if;
 -- Sem material disponível: não baixar, manter pendente.
 v_block:=false;
 begin
  perform public.ew_confirmar_entrega_producao(v_empresa,v_obra,'PLANO',v_plano,gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Entrega sem saldo foi aceita';end if;
 -- Recebimento físico da nota; agora saldo disponível 3 barras.
 insert into public.ew_estoque_obras_movimentos(
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque
 ) values(v_empresa,v_obra,v_variacao,6000,'BARRA',3,'COMPRA',gen_random_uuid(),
  'ENTRADA FISICA PARA TESTE',v_user,'AFOGADOS');
 v_result:=public.ew_confirmar_entrega_producao(v_empresa,v_obra,'PLANO',v_plano,v_op_entrega);
 if v_result->>'repetida'<>'false' then raise exception 'Entrega plano não realizada';end if;
 v_result:=public.ew_confirmar_entrega_producao(v_empresa,v_obra,'PLANO',v_plano,v_op_entrega);
 if v_result->>'repetida'<>'true' then raise exception 'Entrega duplicou ao repetir UUID';end if;
 v_block:=false;
 begin
  perform public.ew_confirmar_entrega_producao(v_empresa,v_obra,'PLANO',v_plano,gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Relatório já entregue foi baixado duas vezes';end if;
 v_result:=public.ew_confirmar_entrega_producao(v_empresa,v_obra,'LOTE',v_lote,gen_random_uuid());
 if v_result->>'repetida'<>'false' then raise exception 'Entrega lote não realizada';end if;
 select count(*) into v_qt from public.ew_estoque_obras_movimentos m where m.empresa_id=v_empresa
  and m.obra_id=v_obra and m.quantidade_delta<0
  and m.origem in ('PLANO_CORTE','PLANO_CORTE_LOTE');
 if v_qt<>2 then raise exception 'Duas linhas de baixa física esperadas';end if;
 select sum(quantidade_delta) into v_saldo from public.ew_estoque_obras_movimentos
  where empresa_id=v_empresa and obra_id=v_obra;
 if v_saldo<>0 then raise exception 'Saldo deveria ser zero após as duas entregas, obtido %',v_saldo;end if;
 v_pend:=public.ew_entregas_pendentes_producao(v_empresa,v_obra);
 if jsonb_array_length(v_pend)<>0 then raise exception 'Relatórios entregues continuam como pendentes';end if;
 -- Um técnico não pode confirmar a entrega no lugar do almoxarife.
 update public.usuarios_empresas set perfil='tecnico' where empresa_id=v_empresa and usuario_id=v_user;
 v_block:=false;
 begin
  perform public.ew_confirmar_entrega_producao(v_empresa,v_obra,'LOTE',v_lote,gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Técnico teve acesso a confirmação de almoxarifado';end if;
 raise notice 'PASSOU: liberar sem baixa, relatórios pendentes, entrega com saldo, bloqueio de duplicidade, fábrica CEM e controle de acesso.';
end $test$;
rollback;