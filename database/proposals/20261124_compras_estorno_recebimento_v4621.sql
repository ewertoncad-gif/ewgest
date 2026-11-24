-- EWGEST v46.21: estorno conservador e rastreável de recebimento por pedido.
-- Aplicar SOMENTE após 20261123_compras_locais_estoque_v4621.sql, em homologação.
-- Não há exclusões físicas. Toda operação é atômica.
begin;

alter table public.ew_compras_recebimentos add column if not exists estorno_detalhes jsonb;

create or replace function public.ew_compras_estornar_recebimento(
 p_recebimento_id uuid,p_motivo text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare
 v_uid uuid:=auth.uid();
 v_rec public.ew_compras_recebimentos%rowtype;
 v_ped public.ew_compras_pedidos%rowtype;
 v_vinc record;
 v_mov_obra public.ew_estoque_obras_movimentos%rowtype;
 v_mov_emp public.ew_compras_estoque_empresa%rowtype;
 v_original_id uuid;
 v_q numeric;v_saldo numeric;
 v_n integer:=0;v_motivo text:=btrim(coalesce(p_motivo,''));
 v_detalhes jsonb:='[]'::jsonb;v_ja numeric;v_item jsonb;
 v_nenhum boolean:=true;v_completo boolean:=true;v_estado text;
 v_op_uuid uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_recebimento_id is null or p_operacao_id is null then
  raise exception 'Sessão, recebimento ou operação inválida.';
 end if;
 if char_length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo entre 5 e 400 caracteres.';
 end if;
 -- Leitura preliminar sem lock apenas para descobrir o pedido.
 -- Todas as operações que mexem no pedido/nota/recebimento obtêm locks na
 -- ordem PEDIDO → RECEBIMENTO, evitando inversão com a conciliação fiscal.
 select * into v_rec from public.ew_compras_recebimentos r
 where r.id=p_recebimento_id;
 if not found then raise exception 'Recebimento não encontrado.';end if;
 if not (public.ew_pode(v_rec.empresa_id,'estoque.estornar')
         and public.ew_pode(v_rec.empresa_id,'compras.receber')) then
  raise exception 'Sem permissão para estornar pedido recebido.';
 end if;
 select * into v_ped from public.ew_compras_pedidos
 where id=v_rec.pedido_id for update;
 if not found or v_ped.empresa_id<>v_rec.empresa_id or v_ped.status='CANCELADO'
 then raise exception 'Pedido do recebimento está indisponível.';end if;
 -- Releitura obrigatória COM lock: a consulta preliminar pode estar obsoleta
 -- caso outro estorno/recebimento tenha confirmado sua transação.
 select * into v_rec from public.ew_compras_recebimentos r
 where r.id=p_recebimento_id for update;
 if not found or v_rec.pedido_id<>v_ped.id or v_rec.empresa_id<>v_ped.empresa_id
 then raise exception 'Vínculo do recebimento com o pedido mudou.';end if;
 if v_rec.estornado_em is not null then
  if v_rec.estorno_operacao_id=p_operacao_id then
   return jsonb_build_object('id',v_rec.id,'repetida',true,'ja_estornado',true);
  end if;
  raise exception 'Recebimento já estornado anteriormente.';
 end if;
 if exists(select 1 from public.ew_compras_recebimentos r
   where r.estorno_operacao_id=p_operacao_id and r.id<>v_rec.id)
 then raise exception 'Identificador de estorno já utilizado.';end if;

 select count(*) into v_n from public.ew_compras_recebimentos_movimentos
 where recebimento_id=v_rec.id and empresa_id=v_rec.empresa_id;
 if v_n<>jsonb_array_length(v_rec.itens)
 then raise exception 'Vínculo físico incompleto. Nada foi estornado.';end if;
 v_n:=0;

 -- Ordem determinística para evitar inversões na aquisição de locks.
 for v_vinc in select * from public.ew_compras_recebimentos_movimentos
   where recebimento_id=v_rec.id and empresa_id=v_rec.empresa_id
   order by (select item->>'variacao_id' from jsonb_array_elements(v_ped.itens) item
      where item->>'chave'=ew_compras_recebimentos_movimentos.chave),
    (select coalesce(item->>'comprimento_mm','-') from jsonb_array_elements(v_ped.itens) item
      where item->>'chave'=ew_compras_recebimentos_movimentos.chave),
    (select item->>'unidade' from jsonb_array_elements(v_ped.itens) item
      where item->>'chave'=ew_compras_recebimentos_movimentos.chave), chave
 loop
  select (item->>'quantidade')::numeric into v_q
  from jsonb_array_elements(v_rec.itens) item
  where item->>'chave'=v_vinc.chave;
  if v_q is null or v_q<=0 then raise exception 'Linha de recebimento inconsistente.';end if;
  if v_ped.obra_id is not null then
   if v_vinc.movimento_empresa_id is not null or v_vinc.movimento_obra_id is null
   then raise exception 'Vínculo de obra inválido.';end if;
   select * into v_mov_obra from public.ew_estoque_obras_movimentos
   where id=v_vinc.movimento_obra_id for update;
   if not found or v_mov_obra.empresa_id<>v_rec.empresa_id or
      v_mov_obra.obra_id<>v_ped.obra_id or v_mov_obra.origem<>'COMPRA' or
      v_mov_obra.quantidade_delta<>v_q or v_mov_obra.local_estoque<>v_rec.galpao
   then raise exception 'Movimentação de entrada da obra inconsistente.';end if;
   if exists(select 1 from public.ew_estoque_obras_movimentos m
    where m.estorno_de_id=v_mov_obra.id)
   then raise exception 'Entrada já possui estorno no estoque.';end if;

   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_mov_obra.obra_id::text||'|'||v_mov_obra.variacao_id::text||'|'||
    coalesce(v_mov_obra.comprimento_mm::text,'-')||'|'||v_mov_obra.unidade,34777));

   -- Bloqueio conservador: mesmo com saldo suficiente, não estornar
   -- se houve QUALQUER saída posterior do mesmo item no mesmo galpão.
   -- Transferências e consumo podem depender desta entrada.
   if exists(select 1 from public.ew_estoque_obras_movimentos m
     where m.empresa_id=v_rec.empresa_id and m.obra_id=v_mov_obra.obra_id
       and m.variacao_id=v_mov_obra.variacao_id
       and m.comprimento_mm is not distinct from v_mov_obra.comprimento_mm
       and m.unidade=v_mov_obra.unidade and m.local_estoque=v_mov_obra.local_estoque
       and m.quantidade_delta<0 and m.origem<>'ESTORNO' and m.criado_em>=v_mov_obra.criado_em
       and not exists(select 1 from public.ew_estoque_obras_movimentos rev where rev.estorno_de_id=m.id))
   then raise exception 'Existe saída/transferência posterior neste galpão. Desfaça dependências antes do estorno.';end if;

   select coalesce(sum(m.quantidade_delta),0) into v_saldo
   from public.ew_estoque_obras_movimentos m
   where m.empresa_id=v_rec.empresa_id and m.obra_id=v_mov_obra.obra_id
     and m.variacao_id=v_mov_obra.variacao_id
     and m.comprimento_mm is not distinct from v_mov_obra.comprimento_mm
     and m.unidade=v_mov_obra.unidade and m.local_estoque=v_mov_obra.local_estoque;
   if v_saldo<v_q then raise exception 'Saldo físico insuficiente para estorno: %.',v_saldo;end if;
   insert into public.ew_estoque_obras_movimentos(
    empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
    origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
   values(v_rec.empresa_id,v_ped.obra_id,v_mov_obra.variacao_id,
    v_mov_obra.comprimento_mm,v_mov_obra.unidade,-v_q,
    'ESTORNO',gen_random_uuid(),left('Estorno pedido #'||v_ped.numero||': '||v_motivo,500),
    v_uid,v_mov_obra.local_estoque,v_mov_obra.id) returning id into v_original_id;
  else
   if v_vinc.movimento_obra_id is not null or v_vinc.movimento_empresa_id is null
   then raise exception 'Vínculo de estoque da empresa inválido.';end if;
   select * into v_mov_emp from public.ew_compras_estoque_empresa
   where id=v_vinc.movimento_empresa_id for update;
   if not found or v_mov_emp.empresa_id<>v_rec.empresa_id or
     v_mov_emp.local_empresa_id<>v_ped.local_empresa_id or
     v_mov_emp.origem<>'RECEBIMENTO_PEDIDO' or
     v_mov_emp.recebimento_id<>v_rec.id or v_mov_emp.quantidade_delta<>v_q or
     v_mov_emp.galpao<>v_rec.galpao
   then raise exception 'Movimentação original da empresa inconsistente.';end if;
   if exists(select 1 from public.ew_compras_estoque_empresa m
     where m.estorno_de_id=v_mov_emp.id)
   then raise exception 'Entrada empresarial já foi estornada.';end if;
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'COMPRA_EMPRESA|'||v_mov_emp.local_empresa_id::text||'|'||
    v_mov_emp.variacao_id::text||'|'||
    coalesce(v_mov_emp.comprimento_mm::text,'-')||'|'||v_mov_emp.unidade,34777));

   if exists(select 1 from public.ew_compras_estoque_empresa m
     where m.empresa_id=v_rec.empresa_id and m.local_empresa_id=v_mov_emp.local_empresa_id
       and m.variacao_id=v_mov_emp.variacao_id
       and m.comprimento_mm is not distinct from v_mov_emp.comprimento_mm
       and m.unidade=v_mov_emp.unidade and m.galpao=v_mov_emp.galpao
       and m.quantidade_delta<0 and m.origem not in ('ESTORNO_PEDIDO','ESTORNO_TRANSFERENCIA')
       and m.criado_em>=v_mov_emp.criado_em
       and not exists(select 1 from public.ew_compras_estoque_empresa rev where rev.estorno_de_id=m.id))
   then raise exception 'Existe transferência ou saída posterior. Desfaça dependências antes do estorno.';end if;
   select coalesce(sum(m.quantidade_delta),0) into v_saldo
   from public.ew_compras_estoque_empresa m
   where m.empresa_id=v_rec.empresa_id and m.local_empresa_id=v_mov_emp.local_empresa_id
     and m.variacao_id=v_mov_emp.variacao_id
     and m.comprimento_mm is not distinct from v_mov_emp.comprimento_mm
     and m.unidade=v_mov_emp.unidade and m.galpao=v_mov_emp.galpao;
   if v_saldo<v_q then raise exception 'Saldo físico da empresa insuficiente para estorno.';end if;
   insert into public.ew_compras_estoque_empresa(
    empresa_id,local_empresa_id,variacao_id,galpao,unidade,
    comprimento_mm,quantidade_delta,origem,estorno_de_id)
   values(v_rec.empresa_id,v_ped.local_empresa_id,v_mov_emp.variacao_id,
    v_mov_emp.galpao,v_mov_emp.unidade,v_mov_emp.comprimento_mm,-v_q,
    'ESTORNO_PEDIDO',v_mov_emp.id) returning id into v_original_id;
  end if;
  v_n:=v_n+1;
  v_detalhes:=v_detalhes||jsonb_build_array(jsonb_build_object(
    'chave',v_vinc.chave,'quantidade',v_q,'movimento_estorno_id',v_original_id));
 end loop;

 update public.ew_compras_recebimentos set
  estornado_em=now(),estornado_por=v_uid,estorno_motivo=v_motivo,
  estorno_operacao_id=p_operacao_id,estorno_detalhes=v_detalhes
 where id=v_rec.id;

 -- Reabrir o saldo do pedido, ignorando apenas os recebimentos estornados.
 for v_item in select value from jsonb_array_elements(v_ped.itens) loop
  select coalesce(sum((entry.value->>'quantidade')::numeric),0) into v_ja
  from public.ew_compras_recebimentos r
  cross join lateral jsonb_array_elements(r.itens) entry(value)
  where r.pedido_id=v_ped.id and r.estornado_em is null
     and entry.value->>'chave'=v_item->>'chave';
  if v_ja>0 then v_nenhum:=false;end if;
  if v_ja<(v_item->>'quantidade')::numeric then v_completo:=false;end if;
 end loop;
 v_estado:=case when v_nenhum then 'ABERTO' when v_completo then 'CONCLUIDO' else 'PARCIAL' end;
 update public.ew_compras_pedidos set status=v_estado where id=v_ped.id;
 return jsonb_build_object('id',v_rec.id,'repetida',false,'estornado',true,
  'movimentos_estornados',v_n,'pedido_status',v_estado,'historico_preservado',true);
end;$f$;

revoke all on function public.ew_compras_estornar_recebimento(uuid,text,uuid) from public,anon;
grant execute on function public.ew_compras_estornar_recebimento(uuid,text,uuid) to authenticated;
commit;
