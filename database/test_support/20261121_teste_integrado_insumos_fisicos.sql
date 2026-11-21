-- EWGEST #34 — execução reversível somente em ewgest-restauracao-teste.
-- Não executar em produção. BEGIN/ROLLBACK deixam zero registros fictícios.
begin;
do $test$
declare
 v_empresa uuid:=gen_random_uuid();v_user uuid:=gen_random_uuid();
 v_obra uuid:=gen_random_uuid();v_destino uuid:=gen_random_uuid();
 v_note_op uuid:=gen_random_uuid();v_note uuid;v_insumo uuid;
 v_transfer1 uuid:=gen_random_uuid();v_transfer2 uuid:=gen_random_uuid();
 v_result jsonb;v_saldo numeric;v_count integer;v_erro boolean;
begin
 insert into auth.users(id,aud,role,email)
 values(v_user,'authenticated','authenticated','ewgest-insumos-'||v_user::text||'@example.invalid');
 insert into public.empresas(id,nome) values(v_empresa,'EMPRESA TESTE INSUMOS EWGEST');
 insert into public.obras(id,empresa_id,codigo,nome)
 values(v_obra,v_empresa,'INS-ORIG','OBRA FICTICIA ORIGEM'),
 (v_destino,v_empresa,'INS-DEST','OBRA FICTICIA DESTINO');
 insert into public.usuarios_empresas(empresa_id,usuario_id,perfil)
 values(v_empresa,v_user,'almoxarife');
 insert into public.ew_obra_orcamento(empresa_id,obra_id,valor_total,
    aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por)
 values(v_empresa,v_obra,1000,0,0,500,500,0,0,v_user);
 insert into public.ew_estoques_locais(empresa_id,obra_id)
 values(v_empresa,v_obra),(v_empresa,v_destino);
 insert into public.ew_locais_fisicos(empresa_id,nome,ativo)
 values(v_empresa,'AFOGADOS',true),(v_empresa,'IMBIRIBEIRA',true);
 insert into public.ew_fornecedores(empresa_id,nome,ativo)
 values(v_empresa,'FORNECEDOR SINTETICO',true);
 perform set_config('request.jwt.claim.sub',v_user::text,true);
 v_result:=public.ew_insumos_receber(v_empresa,v_obra,'vidros',500,
  'FORNECEDOR SINTETICO','NF TESTE VIDROS 101',current_date,'Nota fictícia',
  v_note_op,jsonb_build_array(jsonb_build_object(
   'descricao','VIDRO LAMINADO 8 MM 1000X1000','quantidade',5,
   'unidade','PC','valor_total',500)),'AFOGADOS');
 if v_result->>'estoque_fisico'<>'true' then
  raise exception 'Nota física não reconhecida';end if;
 v_note:=(v_result->>'id')::uuid;
 select id into v_insumo from public.ew_insumos_catalogo
  where empresa_id=v_empresa and categoria='vidros';
 if v_insumo is null then raise exception 'Catálogo não criado';end if;
 v_result:=public.ew_insumos_catalogo_listar(v_empresa);
 if jsonb_array_length(v_result)<>1 then raise exception 'Catálogo não disponível ao almoxarife';end if;
 v_result:=public.ew_insumos_saldos_obra(v_empresa,v_obra);
 if jsonb_array_length(v_result)<>1 or (v_result->0->>'saldo')::numeric<>5
 then raise exception 'Saldos físicos não disponíveis ao almoxarife';end if;
 select sum(quantidade_delta) into v_saldo from public.ew_insumos_movimentos
  where empresa_id=v_empresa and obra_id=v_obra;
 if v_saldo<>5 then raise exception 'Entrada física esperada 5 PC, recebido %',v_saldo;end if;
 select count(*) into v_count from public.ew_obra_despesas_itens
  where despesa_id=v_note and quantidade=5 and valor_total=500;
 if v_count<>1 then raise exception 'Financeiro não recebeu o item físico';end if;
 v_result:=public.ew_insumos_receber(v_empresa,v_obra,'vidros',500,
  'FORNECEDOR SINTETICO','NF TESTE VIDROS 101',current_date,'Nota fictícia',
  v_note_op,jsonb_build_array(jsonb_build_object(
   'descricao','VIDRO LAMINADO 8 MM 1000X1000','quantidade',5,
   'unidade','PC','valor_total',500)),'AFOGADOS');
 if v_result->>'ja_registrado'<>'true' then raise exception 'Idempotência de NF falhou';end if;
 select count(*) into v_count from public.ew_insumos_movimentos where empresa_id=v_empresa;
 if v_count<>1 then raise exception 'Repetição duplicou o estoque';end if;

 v_erro:=false;
 begin
  perform public.ew_insumos_receber(v_empresa,v_obra,'vidros',500,
    'FORNECEDOR SINTETICO','NF TESTE VIDROS 101',current_date,'Nota duplicada',
    gen_random_uuid(),jsonb_build_array(jsonb_build_object(
      'descricao','VIDRO LAMINADO 8 MM 1000X1000','quantidade',5,
      'unidade','PC','valor_total',500)),'AFOGADOS');
 exception when others then v_erro:=true;end;
 if not v_erro then raise exception 'NF duplicada por número foi aceita';end if;

 update public.usuarios_empresas set perfil='administrador'
  where empresa_id=v_empresa and usuario_id=v_user;
 v_result:=public.ew_insumos_transferir(v_empresa,v_obra,v_obra,v_insumo,
   'AFOGADOS','IMBIRIBEIRA',2,'Mudança de galpão',v_transfer1);
 if v_result->>'ja_registrado'<>'false' then raise exception 'Transferência não realizada';end if;
 v_result:=public.ew_insumos_transferir(v_empresa,v_obra,v_destino,v_insumo,
   'IMBIRIBEIRA','IMBIRIBEIRA',1,'Entre obras fictícias',v_transfer2);
 if v_result->>'ja_registrado'<>'false' then raise exception 'Transferência entre obras falhou';end if;
 select coalesce(sum(quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos
  where empresa_id=v_empresa and obra_id=v_destino and local_estoque='IMBIRIBEIRA';
 if v_saldo<>1 then raise exception 'Saldo transferido deveria ser 1';end if;

 v_erro:=false;
 begin
  perform public.ew_insumos_transferir(v_empresa,v_obra,v_destino,v_insumo,
   'IMBIRIBEIRA','IMBIRIBEIRA',100,'Saldo impossível',gen_random_uuid());
 exception when others then v_erro:=true;end;
 if not v_erro then raise exception 'Transferência com saldo insuficiente foi aceita';end if;

 v_erro:=false;
 begin
  perform public.ew_insumos_cancelar_nota(v_empresa,v_note,'Nota a estornar depois da transferência');
 exception when others then v_erro:=true;end;
 if not v_erro then raise exception 'Nota cancelada com estoque fisicamente transferido';end if;
 v_erro:=false;
 begin
  perform public.ew_cancelar_despesa_financeira(v_empresa,v_note,'Motivo teste de bloqueio');
 exception when others then v_erro:=true;end;
 if not v_erro then raise exception 'Cancelamento legado não bloqueou estoque físico';end if;

 v_result:=public.ew_insumos_estornar_transferencia(v_empresa,v_transfer2,'Devolução à origem para cancelar nota');
 v_result:=public.ew_insumos_estornar_transferencia(v_empresa,v_transfer1,'Devolução ao galpão AFOGADOS');
 select coalesce(sum(quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos
  where empresa_id=v_empresa and obra_id=v_obra and local_estoque='AFOGADOS';
 if v_saldo<>5 then raise exception 'Estorno de transferências deveria devolver 5';end if;
 v_result:=public.ew_insumos_cancelar_nota(v_empresa,v_note,'Cancelamento auditável da nota de teste');
 if v_result->>'itens_estornados'<>'1' then raise exception 'Não estornou estoque da NF';end if;
 select coalesce(sum(quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos
  where empresa_id=v_empresa;
 if v_saldo<>0 then raise exception 'Após estornos, saldo total deveria zerar';end if;
 select count(*) into v_count from public.ew_obra_despesas
   where id=v_note and status='cancelada';
 if v_count<>1 then raise exception 'NF não foi cancelada financeiramente';end if;
 v_erro:=false;
 begin perform public.ew_insumo_gerenciar_catalogo(v_empresa,'excluir',v_insumo,null,null,null);
 exception when others then v_erro:=true;end;
 if not v_erro then raise exception 'Exclusão de insumo com histórico não foi bloqueada';end if;
 update public.usuarios_empresas set perfil='tecnico'
  where empresa_id=v_empresa and usuario_id=v_user;
 v_erro:=false;
 begin
 perform public.ew_insumos_receber(v_empresa,v_obra,'outros',10,
  'FORNECEDOR SINTETICO','NF TECNICO BLOQ',current_date,'',
  gen_random_uuid(),jsonb_build_array(jsonb_build_object(
   'descricao','MATERIAL NÃO AUTORIZADO','quantidade',1,
   'unidade','PC','valor_total',10)),'AFOGADOS');
 exception when others then v_erro:=true;end;
 if not v_erro then raise exception 'Perfil técnico conseguiu registrar recebimento';end if;
 raise notice 'PASSOU: NF+estoque, idempotência, transferência, saldo, estorno, acesso e cadastro.';
end
$test$;
rollback;
