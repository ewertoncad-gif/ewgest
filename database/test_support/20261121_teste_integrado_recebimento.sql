-- Executar SOMENTE em ewgest-restauracao-teste.
-- Todos os dados sintéticos desta prova são desfeitos pelo ROLLBACK.
begin;
do $test$
declare
 v_empresa uuid:=gen_random_uuid();
 v_obra uuid:=gen_random_uuid();
 v_user uuid:=gen_random_uuid();
 v_perfil uuid:=gen_random_uuid();
 v_variacao uuid:=gen_random_uuid();
 v_fornecedor uuid:=gen_random_uuid();
 v_nota uuid:=gen_random_uuid();
 v_nota_vidro uuid:=gen_random_uuid();
 v_resp jsonb;v_preco numeric;v_qtd numeric;v_count integer;
 v_captured boolean;
begin
 insert into auth.users(id,aud,role,email)
 values(v_user,'authenticated','authenticated','ewgest-integration-'||v_user::text||'@example.invalid');
 insert into public.empresas(id,nome) values(v_empresa,'EWGEST TESTE DE INTEGRACAO');
 insert into public.obras(id,empresa_id,codigo,nome)
 values(v_obra,v_empresa,'TEST-RECEB','OBRA FICTICIA — TESTE INTEGRADO');
 insert into public.usuarios_empresas(empresa_id,usuario_id,perfil)
 values(v_empresa,v_user,'almoxarife');
 insert into public.ew_obra_orcamento(empresa_id,obra_id,valor_total,
    aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por)
 values(v_empresa,v_obra,1000,700,0,300,0,0,0,v_user);
 insert into public.ew_estoques_locais(empresa_id,obra_id) values(v_empresa,v_obra);
 insert into public.ew_locais_fisicos(empresa_id,nome,ativo)
 values(v_empresa,'GALPAO DE TESTES',true);
 insert into public.ew_fornecedores(id,empresa_id,nome,ativo)
 values(v_fornecedor,v_empresa,'FORNECEDOR TESTE EWGEST',true);
 insert into public.ew_perfis(id,empresa_id,codigo,descricao)
 values(v_perfil,v_empresa,'TESTE6000','Perfil fictício de validação');
 insert into public.ew_materiais_variacoes(id,empresa_id,tipo,perfil_id,ativo)
 values(v_variacao,v_empresa,'perfil',v_perfil,true);
 insert into public.ew_cem_obras_materiais(empresa_id,obra_id,tipo,perfil_id,variacao_id,
   quantidade_prevista,unidade_prevista,barras_planejadas)
 values(v_empresa,v_obra,'perfil',v_perfil,v_variacao,3,'BARRA',
   '[{"comprimento_mm":6000,"quantidade":3}]'::jsonb);
 perform set_config('request.jwt.claim.sub',v_user::text,true);

 v_resp:=public.ew_receber_materiais_almox(v_empresa,v_obra,'aluminio',120,
   'FORNECEDOR TESTE EWGEST','NF-ALU-100',current_date,'Teste de recebimento',
   'GALPAO DE TESTES',
   jsonb_build_array(jsonb_build_object('variacao_id',v_variacao,
    'comprimento_mm',6000,'quantidade',2,'valor_total',120)),v_nota);
 if v_resp->>'ja_registrado'<>'false' then
  raise exception 'Primeiro recebimento deveria criar nota';end if;
 select count(*) into v_count from public.ew_obra_despesas d
 where d.empresa_id=v_empresa and d.obra_id=v_obra and d.categoria='aluminio' and d.valor=120;
 if v_count<>1 then raise exception 'Despesa de alumínio ausente ou duplicada';end if;
 select sum(m.quantidade_delta) into v_qtd from public.ew_estoque_obras_movimentos m
 where m.empresa_id=v_empresa and m.obra_id=v_obra and m.variacao_id=v_variacao and m.local_estoque='GALPAO DE TESTES';
 if v_qtd<>2 then raise exception 'Saldo físico do alumínio deveria ser 2 barras; recebido %',v_qtd;end if;
 select count(*) into v_count from public.ew_nfe_recebimentos n where n.empresa_id=v_empresa and n.obra_id=v_obra;
 if v_count<>1 then raise exception 'Vínculo do item/NF ao estoque ausente';end if;

 v_resp:=public.ew_receber_materiais_almox(v_empresa,v_obra,'aluminio',120,
   'FORNECEDOR TESTE EWGEST','NF-ALU-100',current_date,'Teste de recebimento',
   'GALPAO DE TESTES',
   jsonb_build_array(jsonb_build_object('variacao_id',v_variacao,
    'comprimento_mm',6000,'quantidade',2,'valor_total',120)),v_nota);
 if v_resp->>'ja_registrado'<>'true' then raise exception 'Idempotência não confirmada';end if;
 select count(*) into v_count from public.ew_estoque_obras_movimentos m where m.empresa_id=v_empresa and m.obra_id=v_obra;
 if v_count<>1 then raise exception 'Repetição duplicou movimentos de estoque';end if;

 v_resp:=public.ew_receber_despesa_com_itens_almox(v_empresa,v_obra,'vidros',200,
   'FORNECEDOR TESTE EWGEST','NF-VID-101',current_date,'Vidros recebidos',v_nota_vidro,
   jsonb_build_array(jsonb_build_object('descricao','VIDRO LAMINADO TESTE',
    'unidade','M2','quantidade',2,'valor_total',200)));
 if v_resp->>'sem_estoque_fisico'<>'true' then raise exception 'Vidros devem ser apenas despesa';end if;
 select count(*) into v_count from public.ew_obra_despesas_itens i
 join public.ew_obra_despesas d on d.id=i.despesa_id
 where d.empresa_id=v_empresa and d.obra_id=v_obra and d.categoria='vidros'
   and i.descricao='VIDRO LAMINADO TESTE' and i.quantidade=2 and i.valor_total=200;
 if v_count<>1 then raise exception 'Vidros não discriminados no histórico';end if;
 select count(*) into v_count from public.ew_estoque_obras_movimentos m where m.empresa_id=v_empresa and m.obra_id=v_obra;
 if v_count<>1 then raise exception 'Nota de vidro alterou estoque físico indevidamente';end if;

 v_resp:=public.ew_quantidades_recebidas_obra(v_empresa,v_obra);
 if jsonb_array_length(v_resp)<>1 or (v_resp->0->>'quantidade')::numeric<>2
 then raise exception 'Consulta de quantidades recebidas incorreta';end if;

 v_captured:=false;
 begin
  perform public.ew_receber_materiais_almox(v_empresa,v_obra,'aluminio',120,
   'FORNECEDOR TESTE EWGEST','NF-ALU-100',current_date,'Teste duplicado',
   'GALPAO DE TESTES',
   jsonb_build_array(jsonb_build_object('variacao_id',v_variacao,
    'comprimento_mm',6000,'quantidade',2,'valor_total',120)),gen_random_uuid());
 exception when others then v_captured:=true;end;
 if not v_captured then raise exception 'Nota duplicada com outro UUID foi aceita';end if;

 update public.usuarios_empresas set perfil='administrador'
   where empresa_id=v_empresa and usuario_id=v_user;
 v_captured:=false;
 begin perform public.ew_excluir_cadastro_tecnico_sem_vinculo(v_empresa,'perfil',v_perfil);
 exception when others then v_captured:=true;end;
 if not v_captured then raise exception 'Perfil em uso foi excluído';end if;
 v_captured:=false;
 begin perform public.ew_gerenciar_cadastro_auxiliar(v_empresa,'fornecedor',v_fornecedor,'excluir',null);
 exception when others then v_captured:=true;end;
 if not v_captured then raise exception 'Fornecedor com NF foi excluído';end if;

 update public.usuarios_empresas set perfil='tecnico'
   where empresa_id=v_empresa and usuario_id=v_user;
 v_captured:=false;
 begin
  perform public.ew_receber_despesa_com_itens_almox(v_empresa,v_obra,'vidros',20,
   'FORNECEDOR TESTE EWGEST','NF-BLOQ-999',current_date,'',gen_random_uuid(),
   jsonb_build_array(jsonb_build_object('descricao','TESTE BLOQUEIO',
    'unidade','PC','quantidade',1,'valor_total',20)));
 exception when others then v_captured:=true;end;
 if not v_captured then raise exception 'Usuário sem perfil almoxarife conseguiu registrar';end if;

 raise notice 'PASSOU: alumínio/estoque, vidro/financeiro, idempotência, duplicidade, autorização e vínculos';
end
$test$;
rollback;
