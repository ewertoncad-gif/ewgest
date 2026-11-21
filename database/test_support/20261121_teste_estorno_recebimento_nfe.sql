-- EWGEST #38: prova reversível estorno de NF após transferência de galpão.
-- Executar SOMENTE em ewgest-restauracao-teste. Não deixar dados fictícios.
begin;
do $test$
declare
 v_user uuid:=gen_random_uuid();v_empresa uuid:=gen_random_uuid();v_obra uuid:=gen_random_uuid();
 v_perfil uuid:=gen_random_uuid();v_variacao uuid:=gen_random_uuid();v_despesa uuid:=gen_random_uuid();
 v_item uuid:=gen_random_uuid();v_recebimento uuid:=gen_random_uuid();v_compra uuid:=gen_random_uuid();
 v_op uuid:=gen_random_uuid();v_result jsonb;v_saldo numeric;v_n integer;v_block boolean;
 v_compra2 uuid:=gen_random_uuid();v_rec2 uuid:=gen_random_uuid();
begin
 insert into auth.users(id,aud,role,email) values
   (v_user,'authenticated','authenticated','estorno-teste-'||v_user::text||'@example.invalid');
 insert into public.empresas(id,nome) values(v_empresa,'EMPRESA HOMOLOGACAO ESTORNO');
 insert into public.obras(id,empresa_id,codigo,nome)
 values(v_obra,v_empresa,'EST-NF-01','OBRA ESTORNO NF FICTICIA');
 insert into public.usuarios_empresas(empresa_id,usuario_id,perfil)
 values(v_empresa,v_user,'administrador');
 insert into public.usuarios_login(usuario_id,empresa_id,perfil,ativo,login,nome)
 values(v_user,v_empresa,'administrador',true,'admin-estorno-teste','ADM ESTORNO');
 insert into public.ew_perfis(id,empresa_id,codigo,descricao)
 values(v_perfil,v_empresa,'GN096','FOLHA COLADA');
 insert into public.ew_materiais_variacoes(id,empresa_id,tipo,perfil_id,ativo)
 values(v_variacao,v_empresa,'perfil',v_perfil,true);
 insert into public.ew_obra_despesas(
 id,empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,
 data_documento,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id
 ) values(v_despesa,v_empresa,v_obra,'aluminio',100,'nfe_xml','FORNECEDOR FICTICIO',
 'NF-123',current_date,'aprovada','',v_user,v_user,now(),gen_random_uuid());
 insert into public.ew_obra_despesas_itens(
  id,despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
  valor_unitario,valor_total,perfil_id
 ) values(v_item,v_despesa,v_empresa,'GN096','FOLHA COLADA','BARRA',3,33.333333,100,v_perfil);
 insert into public.ew_estoque_obras_movimentos(
 id,empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
 origem,operacao_id,observacao,usuario_id,local_estoque
 ) values(v_compra,v_empresa,v_obra,v_variacao,6000,'BARRA',3,'COMPRA',
 gen_random_uuid(),'NF FICTICIA',v_user,'AFOGADOS');
 insert into public.ew_nfe_recebimentos(
  id,empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,
  unidade,quantidade,local_estoque,movimento_id,usuario_id
 ) values(v_recebimento,v_empresa,v_obra,v_item,v_variacao,6000,
  'BARRA',3,'AFOGADOS',v_compra,v_user);
 perform set_config('request.jwt.claim.sub',v_user::text,true);
 insert into public.ew_estoque_obras_movimentos(
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,transferencia_id
 ) values
 (v_empresa,v_obra,v_variacao,6000,'BARRA',-2,'TRANSFERENCIA',gen_random_uuid(),'Saiu do galpão',v_user,'AFOGADOS',gen_random_uuid()),
 (v_empresa,v_obra,v_variacao,6000,'BARRA',2,'TRANSFERENCIA',gen_random_uuid(),'Chegou no outro galpão',v_user,'IMBIRIBEIRA',gen_random_uuid());
 v_result:=public.ew_estornar_recebimento_nfe(v_empresa,v_recebimento,
   'Material devolvido ao fornecedor',v_op);
 if v_result->>'ja_estornado'<>'false'
 then raise exception 'Primeiro estorno não foi concluído';end if;
 select count(*) into v_n from public.ew_estoque_obras_movimentos
 where empresa_id=v_empresa and origem='ESTORNO' and quantidade_delta<0;
 if v_n<>2 then raise exception 'Estorno deveria debitar os dois galpões, recebido %',v_n;end if;
 select sum(quantidade_delta) into v_saldo from public.ew_estoque_obras_movimentos
 where empresa_id=v_empresa and obra_id=v_obra;
 if v_saldo<>0 then raise exception 'Saldo final deveria ser zero, recebido %',v_saldo;end if;
 v_result:=public.ew_quantidades_recebidas_obra(v_empresa,v_obra);
 if jsonb_array_length(v_result)<>0 then
  raise exception 'Quantidades recebidas não deveriam incluir entrada já estornada';end if;
 v_block:=false;
 begin
  perform public.ew_estornar_movimento_obra(
    v_obra,v_compra,'Tentativa de estorno genérico indevido',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Estorno genérico permitiu apagar entrada de NF-e';end if;
 v_result:=public.ew_estornar_recebimento_nfe(v_empresa,v_recebimento,
   'Material devolvido ao fornecedor',v_op);
 if v_result->>'ja_estornado'<>'true' then raise exception 'Idempotência de estorno falhou';end if;
 if not exists(select 1 from public.ew_obra_despesas where id=v_despesa and status='aprovada')
 then raise exception 'Nota financeira não foi preservada';end if;

 -- Reentrada do item após estorno permitido, histórico original permanece.
 insert into public.ew_estoque_obras_movimentos(
 id,empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
 origem,operacao_id,observacao,usuario_id,local_estoque)
 values(v_compra2,v_empresa,v_obra,v_variacao,6000,'BARRA',2,'COMPRA',gen_random_uuid(),'NF corrigida',v_user,'AFOGADOS');
 insert into public.ew_nfe_recebimentos(
 id,empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,
 unidade,quantidade,local_estoque,movimento_id,usuario_id)
 values(v_rec2,v_empresa,v_obra,v_item,v_variacao,6000,'BARRA',2,'AFOGADOS',v_compra2,v_user);
 insert into public.ew_estoque_obras_movimentos(
 empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
 origem,operacao_id,observacao,usuario_id,local_estoque)
 values(v_empresa,v_obra,v_variacao,6000,'BARRA',-1,'SAIDA_MANUAL',
 gen_random_uuid(),'ENTREGA À PRODUÇÃO',v_user,'AFOGADOS');
 v_block:=false;
 begin
  perform public.ew_estornar_recebimento_nfe(v_empresa,v_rec2,
   'Recebimento já consumido',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'NF consumida pôde ser estornada indevidamente';end if;
 update public.usuarios_empresas set perfil='tecnico' where empresa_id=v_empresa and usuario_id=v_user;
 update public.usuarios_login set perfil='tecnico' where empresa_id=v_empresa and usuario_id=v_user;
 v_block:=false;
 begin perform public.ew_estornar_recebimento_nfe(v_empresa,v_rec2,
  'Acesso de técnico não permitido',gen_random_uuid());
 exception when others then v_block:=true;end;
 if not v_block then raise exception 'Técnico conseguiu estornar entrada física';end if;
 raise notice 'PASSOU: estorno com transferência entre galpões, sem saldo negativo, NF preservada, idempotência, bloqueio de consumo e permissão.';
end
$test$;
rollback;
