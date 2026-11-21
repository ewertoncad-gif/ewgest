-- EWGEST #38 — documentos técnicos liberados aguardam a ENTREGA FÍSICA.
-- Nenhum valor de compra, orçamento ou faturamento é retornado ao almoxarife.
create or replace function public.ew_entregas_pendentes_producao(
 p_empresa_id uuid,p_obra_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
  where u.usuario_id=v_uid and u.empresa_id=p_empresa_id
  and u.perfil in ('administrador','almoxarife'))
 then raise exception 'Sem permissão para consultar entregas à produção.';end if;
 if not exists(select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
   and o.arquivada_em is null)
 then raise exception 'Obra não encontrada ou arquivada.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'tipo',x.tipo,'id',x.id,'data',x.data_liberacao,'fabrica',x.fabrica,
  'codigo',x.codigo,'arquivo',x.arquivo_nome,'materiais',x.materiais
 ) order by x.data_liberacao desc,x.id),'[]'::jsonb) into v_result
 from (
  select 'PLANO'::text tipo,p.id,p.data_liberacao,l.fabrica,
   e.codigo,p.arquivo_nome,p.materiais_confirmados materiais
  from public.ew_planos_liberados p
   join public.liberacoes_corte l on l.id=p.liberacao_id and l.cancelado_em is null
   join public.esquadrias e on e.id=p.esquadria_id
  where p.empresa_id=p_empresa_id and p.obra_id=p_obra_id and p.entregue_em is null
   and jsonb_typeof(p.materiais_confirmados)='array'
   and jsonb_array_length(p.materiais_confirmados)>0
   and not exists(select 1 from public.ew_estoque_obras_movimentos m
     where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.liberacao_id=p.liberacao_id and m.origem='PLANO_CORTE')
  union all
  select 'LOTE'::text tipo,l.id,l.data_liberacao,l.fabrica,
   'LOTE CEM'::text codigo,l.arquivo_nome,l.materiais_confirmados materiais
  from public.ew_liberacoes_lotes l
  where l.empresa_id=p_empresa_id and l.obra_id=p_obra_id and l.cancelado_em is null
   and l.entregue_em is null and jsonb_typeof(l.materiais_confirmados)='array'
   and jsonb_array_length(l.materiais_confirmados)>0
   and not exists(select 1 from public.ew_estoque_obras_movimentos m
     where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.lote_id=l.id and m.origem='PLANO_CORTE_LOTE')
 ) x;
 return v_result;
end
$fn$;

create or replace function public.ew_confirmar_entrega_producao(
 p_empresa_id uuid,p_obra_id uuid,p_tipo text,p_referencia_id uuid,
 p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
 v_uid uuid:=auth.uid();
 v_plano public.ew_planos_liberados%rowtype;v_lote public.ew_liberacoes_lotes%rowtype;
 v_materiais jsonb;v_item jsonb;
 v_var uuid;v_length integer;v_unit text;v_qty numeric;v_local text;
 v_stock numeric;v_tp text;v_n integer:=0;v_liberacao uuid;v_lote_id uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_referencia_id is null
  or p_operacao_id is null or p_tipo not in ('PLANO','LOTE')
  or not exists(select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
   and u.empresa_id=p_empresa_id and u.perfil in ('administrador','almoxarife'))
 then raise exception 'Sem permissão para baixar materiais da produção.';end if;
 if not exists(select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
   and o.arquivada_em is null)
 then raise exception 'Obra não encontrada ou arquivada.';end if;
 if not exists(select 1 from public.ew_estoques_locais l where l.empresa_id=p_empresa_id
   and l.obra_id=p_obra_id and l.excluido_em is null)
 then raise exception 'Estoque desta obra não está ativo.';end if;
 -- Bloqueio estável entre tentativas simultâneas de entrega do mesmo relatório.
 perform pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(p_tipo||'|'||p_referencia_id::text,773428));
 if p_tipo='PLANO' then
  select * into v_plano from public.ew_planos_liberados p
   where p.empresa_id=p_empresa_id and p.obra_id=p_obra_id
    and p.id=p_referencia_id for update;
  if not found or not exists(select 1 from public.liberacoes_corte l
    where l.id=v_plano.liberacao_id and l.cancelado_em is null)
  then raise exception 'Liberação não encontrada ou cancelada.';end if;
  if v_plano.entregue_em is not null then
   if v_plano.entrega_operacao_id=p_operacao_id then
    return jsonb_build_object('repetida',true,'referencia_id',p_referencia_id);end if;
   raise exception 'Este relatório já teve baixa física. Não duplique a entrega.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
    where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.liberacao_id=v_plano.liberacao_id and m.origem='PLANO_CORTE')
   then raise exception 'Liberação antiga já movimentou estoque. Não executar nova baixa.';end if;
  v_materiais:=v_plano.materiais_confirmados;
  v_liberacao:=v_plano.liberacao_id;
 else
  select * into v_lote from public.ew_liberacoes_lotes l
   where l.empresa_id=p_empresa_id and l.obra_id=p_obra_id
    and l.id=p_referencia_id for update;
  if not found or v_lote.cancelado_em is not null
   then raise exception 'Lote de liberação não encontrado ou cancelado.';end if;
  if v_lote.entregue_em is not null then
   if v_lote.entrega_operacao_id=p_operacao_id then
    return jsonb_build_object('repetida',true,'referencia_id',p_referencia_id);end if;
   raise exception 'Este lote já teve baixa física. Não repita a entrega.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
    where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.lote_id=v_lote.id and m.origem='PLANO_CORTE_LOTE')
   then raise exception 'Lote antigo já movimentou estoque. Não executar nova baixa.';end if;
  v_materiais:=v_lote.materiais_confirmados;v_lote_id:=v_lote.id;
 end if;
 if jsonb_typeof(v_materiais) is distinct from 'array'
   or jsonb_array_length(v_materiais) not between 1 and 250
 then raise exception 'Relatório não possui materiais pendentes de entrega.';end if;
 -- Locks no MESMO escopo das rotinas atuais, sempre em ordem, evitando concorrência
 -- com transferências, estorno de NF e baixas de outras liberações.
 for v_item in select value from jsonb_array_elements(v_materiais)
  order by value->>'variacao_id',value->>'comprimento_mm',value->>'unidade' loop
   if jsonb_typeof(v_item)<>'object' then raise exception 'Linha inválida do relatório.';end if;
   v_var:=(v_item->>'variacao_id')::uuid;
   v_length:=nullif(v_item->>'comprimento_mm','')::integer;
   v_unit:=v_item->>'unidade';
   v_local:=upper(btrim(coalesce(v_item->>'local_estoque','')));
   v_qty:=(v_item->>'quantidade')::numeric;
   select tipo into v_tp from public.ew_materiais_variacoes v
    where v.id=v_var and v.empresa_id=p_empresa_id;
   if v_tp is null or v_qty is null or v_qty<=0 or v_qty>1000000
      or (v_tp='perfil' and (v_unit<>'BARRA' or v_length not between 100 and 20000
          or v_qty<>trunc(v_qty)))
      or (v_tp='acessorio' and (v_length is not null
          or v_unit not in ('PC','PR','CJ','MT','KG','UN')
          or v_qty<>round(v_qty,3)))
   then raise exception 'Material ou quantidade inválidos no relatório de liberação.';end if;
   if not exists(select 1 from public.ew_locais_fisicos f
     where f.empresa_id=p_empresa_id and f.nome=v_local and f.ativo)
   then raise exception 'Galpão original do relatório está inativo. Concilie antes da entrega.';end if;
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_obra_id::text||'|'||v_var::text||'|'||coalesce(v_length::text,'-')||'|'||v_unit,34777));
   select coalesce(sum(m.quantidade_delta),0) into v_stock
    from public.ew_estoque_obras_movimentos m
    where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
     and m.variacao_id=v_var and m.comprimento_mm is not distinct from v_length
     and m.unidade=v_unit and m.local_estoque=v_local;
   if v_stock<v_qty then raise exception
    'Entrega bloqueada: saldo insuficiente de % no galpão %. Disponível % %, necessário % %.',
    v_var,v_local,v_stock,v_unit,v_qty,v_unit;end if;
 end loop;
 -- Todos os saldos foram validados. A transação inteira reverte se qualquer
 -- linha de movimentação falhar; nunca entrega pela metade.
 for v_item in select value from jsonb_array_elements(v_materiais) loop
   v_var:=(v_item->>'variacao_id')::uuid;
   v_length:=nullif(v_item->>'comprimento_mm','')::integer;
   v_unit:=v_item->>'unidade';v_local:=upper(btrim(v_item->>'local_estoque'));
   v_qty:=(v_item->>'quantidade')::numeric;
   insert into public.ew_estoque_obras_movimentos
    (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
     origem,liberacao_id,lote_id,operacao_id,observacao,usuario_id,local_estoque)
   values(p_empresa_id,p_obra_id,v_var,v_length,v_unit,-v_qty,
    case when p_tipo='PLANO' then 'PLANO_CORTE' else 'PLANO_CORTE_LOTE' end,
    v_liberacao,v_lote_id,gen_random_uuid(),
    'Material entregue pelo almoxarife à produção — liberação '||p_referencia_id::text,
    v_uid,v_local);
   v_n:=v_n+1;
 end loop;
 if p_tipo='PLANO' then
   update public.ew_planos_liberados
   set entregue_em=now(),entregue_por=v_uid,entrega_operacao_id=p_operacao_id
   where id=p_referencia_id and empresa_id=p_empresa_id;
 else
   update public.ew_liberacoes_lotes
   set entregue_em=now(),entregue_por=v_uid,entrega_operacao_id=p_operacao_id
   where id=p_referencia_id and empresa_id=p_empresa_id;
 end if;
 return jsonb_build_object('repetida',false,'linhas_baixadas',v_n,
  'obra_id',p_obra_id,'tipo',p_tipo,'referencia_id',p_referencia_id);
end
$fn$;

revoke all on function public.ew_entregas_pendentes_producao(uuid,uuid) from public;
revoke execute on function public.ew_entregas_pendentes_producao(uuid,uuid) from anon;
grant execute on function public.ew_entregas_pendentes_producao(uuid,uuid) to authenticated;
revoke all on function public.ew_confirmar_entrega_producao(uuid,uuid,text,uuid,uuid) from public;
revoke execute on function public.ew_confirmar_entrega_producao(uuid,uuid,text,uuid,uuid) from anon;
grant execute on function public.ew_confirmar_entrega_producao(uuid,uuid,text,uuid,uuid) to authenticated;
