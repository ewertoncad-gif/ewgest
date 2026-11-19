
alter table public.ew_auditoria_operacoes add column if not exists operacao_id uuid;
create unique index if not exists ew_auditoria_operacoes_unica on public.ew_auditoria_operacoes(operacao_id)
 where operacao_id is not null;

-- Registra contrapartida de cada movimento: transferência terá duas contrapartidas.
-- Os saldos ficam zero por material, comprimento, unidade e galpão;
-- NENHUM movimento original é apagado.
create or replace function public.ew_estornar_estoque_obra(
 p_obra_id uuid,p_motivo text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Identificador de operação obrigatório.';end if;
 if length(v_motivo) not between 10 and 400 then
  raise exception 'Informe motivo de 10 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 v_status:=public.ew_inspecionar_reversao_obra(p_obra_id);
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao<>'ESTORNAR_ESTOQUE' or v_audit.obra_id<>p_obra_id or v_audit.usuario_id<>v_uid
   then raise exception 'Identificador de operação já utilizado.';end if;
  return jsonb_build_object('repetida',true,'estornados',
    v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 if (v_status->'resumo'->>'romaneios')::int>0
   or (v_status->'resumo'->>'saidas_producao')::int>0
   or (v_status->'resumo'->>'liberacoes')::int>0
   or (v_status->'resumo'->>'lotes_cem')::int>0
   or (v_status->'resumo'->>'planos_liberados')::int>0
   or (v_status->'resumo'->>'unidades_liberadas')::int>0
   or (v_status->'resumo'->>'fabricadas')::int>0
 then raise exception 'Cancele romaneios, saídas e liberações antes de estornar o estoque.';end if;
 perform 1 from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id order by m.id for update;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
   group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
   having sum(m.quantidade_delta)<0) then
  raise exception 'Saldo negativo em galpão. Concilie o estoque antes do estorno.';end if;
 -- Registra em detalhes cada movimento que será revertido.
 select count(*),
  coalesce(jsonb_agg(jsonb_build_object('id',m.id,'origem',m.origem,
   'quantidade',m.quantidade_delta,'local',m.local_estoque,
   'unidade',m.unidade,'comprimento_mm',m.comprimento_mm,
   'variacao_id',m.variacao_id,'criado_em',m.criado_em,'usuario_original',m.usuario_id)),
   '[]'::jsonb)
 into v_n,v_originais from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if v_n=0 then
  if (v_status->'resumo'->>'saldos_nao_zerados')::int>0 then
   raise exception 'Não existem movimentos pendentes, mas há saldos diferentes de zero.';end if;
  return jsonb_build_object('repetida',false,'estornados',0,'historico_preservado',true);
 end if;
 insert into public.ew_estoque_obras_movimentos (
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
 select m.empresa_id,m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,
  -m.quantidade_delta,'ESTORNO',gen_random_uuid(),left('Estorno para reimportação: '||v_motivo,500),
  v_uid,m.local_estoque,m.id
 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if exists(select 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
 group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
 having sum(m.quantidade_delta)<>0) then
  raise exception 'A operação não zerou todos os saldos. Nenhum estorno foi confirmado.';end if;
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_operacao_id,v_motivo,jsonb_build_object('movimentos_estornados',v_n,
   'movimentos_originais',v_originais));
 return jsonb_build_object('repetida',false,'estornados',v_n,'historico_preservado',true);
end;$$;
revoke all on function public.ew_estornar_estoque_obra(uuid,text,uuid) from public,anon;
grant execute on function public.ew_estornar_estoque_obra(uuid,text,uuid) to authenticated;

-- Remover da lista operacional mantendo TODAS as dependências para auditoria.
create or replace function public.ew_arquivar_obra_reconciliada(
 p_obra_id uuid,p_confirmacao text,p_motivo text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_ver jsonb;
 v_record public.ew_obras_exclusoes_historico%rowtype;v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 perform public.ew_exigir_sessao_atual();
 if p_obra_id is null or p_operacao_id is null then raise exception 'Obra e operação obrigatórias.';end if;
 if length(v_motivo) not between 10 and 400 then
  raise exception 'Informe motivo de 10 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_record from public.ew_obras_exclusoes_historico where operacao_id=p_operacao_id;
 if found then
  if v_record.obra_excluida_id<>p_obra_id or v_record.excluido_por<>v_uid
   then raise exception 'Identificador já usado em outra operação.';end if;
  return jsonb_build_object('excluida',true,'repetida',true,'nome',v_record.obra_nome);
 end if;
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra já arquivada ou não encontrada.';end if;
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 v_ver:=public.ew_inspecionar_reversao_obra(p_obra_id);
 if not (v_ver->>'permitido')::boolean then raise exception
  'ARQUIVAMENTO_BLOQUEADO: %',
  array_to_string(array(select jsonb_array_elements_text(v_ver->'motivos')),' ');
 end if;
 if upper(btrim(coalesce(p_confirmacao,'')))<>upper(coalesce(nullif(btrim(v_ob.codigo),''),v_ob.nome))
 then raise exception 'Confirmação incorreta. Digite o código da obra.';end if;
 update public.obras set arquivada_em=now(),arquivada_por=v_uid,motivo_arquivamento=v_motivo
 where id=p_obra_id and arquivada_em is null;
 insert into public.ew_obras_exclusoes_historico
  (operacao_id,empresa_id,obra_excluida_id,obra_nome,obra_codigo,motivo,resumo,excluido_por)
 values(p_operacao_id,v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,
  left(v_motivo,300),v_ver->'resumo',v_uid);
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ARQUIVAR_OBRA',
  p_operacao_id,v_motivo,jsonb_build_object(
   'resumo',v_ver->'resumo','cadastros_gerais_preservados',true,
   'historico_operacional_preservado',true));
 return jsonb_build_object('excluida',true,'repetida',false,
  'nome',v_ob.nome,'codigo',v_ob.codigo,'historico_preservado',true);
end;$$;
revoke all on function public.ew_arquivar_obra_reconciliada(uuid,text,text,uuid) from public,anon;
grant execute on function public.ew_arquivar_obra_reconciliada(uuid,text,text,uuid) to authenticated;
