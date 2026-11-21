-- EWGEST #34: transferências e estornos físicos de vidros/insumos.
-- Operações sem impacto financeiro novo, com trilha e bloqueio de saldo negativo.
create or replace function public.ew_insumos_transferir(
 p_empresa_id uuid,p_origem_obra_id uuid,p_destino_obra_id uuid,
 p_insumo_id uuid,p_origem_local text,p_destino_local text,
 p_quantidade numeric,p_observacao text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_saldo numeric;v_qtd integer;v_transfer uuid:=gen_random_uuid();
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and u.perfil='administrador')
 then raise exception 'Somente ADM transfere estes materiais.';end if;
 if p_operacao_id is null or p_origem_obra_id is null or p_destino_obra_id is null
  or p_insumo_id is null or (p_origem_obra_id=p_destino_obra_id and v_origem=v_destino)
  or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
  or p_quantidade<>round(p_quantidade,3) or length(coalesce(p_observacao,''))>400
 then raise exception 'Transferência inválida.';end if;
 if not exists(select 1 from public.ew_insumos_catalogo c where c.id=p_insumo_id
    and c.empresa_id=p_empresa_id and c.ativo)
 then raise exception 'Material não pertence à empresa ou está inativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_origem and l.ativo)
 or not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_destino and l.ativo)
 then raise exception 'Galpão de origem/destino inválido.';end if;
 if not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_origem_obra_id and l.excluido_em is null)
 or not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_destino_obra_id and l.excluido_em is null)
 then raise exception 'Obras com estoque ativo são obrigatórias.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,9011));
 select count(*) into v_qtd from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.origem='TRANSFERENCIA';
 if v_qtd>0 then
   if v_qtd<>2 or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_origem_obra_id and m.local_estoque=v_origem
     and m.quantidade_delta=-p_quantidade
   ) or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_destino_obra_id and m.local_estoque=v_destino
     and m.quantidade_delta=p_quantidade
   ) then raise exception 'Operação já utilizada em outra transferência.';end if;
   return jsonb_build_object('ja_registrado',true);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_origem_obra_id::text||'|'||
   p_insumo_id::text||'|'||v_origem,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo
 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
  and m.obra_id=p_origem_obra_id and m.insumo_id=p_insumo_id
  and m.local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente na origem. Disponível: %',v_saldo;end if;
 insert into public.ew_insumos_movimentos(
   empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
   operacao_id,transferencia_id,observacao,usuario_id
 ) values
 (p_empresa_id,p_origem_obra_id,p_insumo_id,v_origem,-p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid),
 (p_empresa_id,p_destino_obra_id,p_insumo_id,v_destino,p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid);
 return jsonb_build_object('transferencia_id',v_transfer,'ja_registrado',false);
end
$func$;

create or replace function public.ew_insumos_estornar_transferencia(
 p_empresa_id uuid,p_transferencia_operacao_id uuid,p_motivo text
) returns jsonb language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();v_saida public.ew_insumos_movimentos%rowtype;
 v_entrada public.ew_insumos_movimentos%rowtype;v_total integer;
 v_saldo numeric;v_op uuid:=gen_random_uuid();
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente ADM pode estornar transferências.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400 or p_transferencia_operacao_id is null
 then raise exception 'Informe motivo de 5 a 400 caracteres e operação válida.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_transferencia_operacao_id::text,9011));
 select count(*) into v_total from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_transferencia_operacao_id
   and m.origem='TRANSFERENCIA';
 if v_total<>2 then raise exception 'Transferência original não encontrada ou incompleta.';end if;
 select * into v_saida from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 for update;
 select * into v_entrada from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta>0 for update;
 if v_saida.id is null or v_entrada.id is null or v_saida.insumo_id<>v_entrada.insumo_id
    or v_saida.quantidade_delta<>-v_entrada.quantidade_delta
 then raise exception 'Movimentos da transferência não conferem.';end if;
 if exists(select 1 from public.ew_insumos_movimentos m where m.estorno_de_id in (v_saida.id,v_entrada.id))
 then raise exception 'Transferência já estornada.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||v_entrada.obra_id::text||'|'||
   v_entrada.insumo_id::text||'|'||v_entrada.local_estoque,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_entrada.obra_id
   and m.insumo_id=v_entrada.insumo_id and m.local_estoque=v_entrada.local_estoque;
 if v_saldo<v_entrada.quantidade_delta then
  raise exception 'Estorno bloqueado: destino já utilizou/transferiu parte do material.';end if;
 insert into public.ew_insumos_movimentos(
  empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
  origem,operacao_id,estorno_de_id,observacao,usuario_id
 ) values
 (p_empresa_id,v_entrada.obra_id,v_entrada.insumo_id,v_entrada.local_estoque,
  -v_entrada.quantidade_delta,'ESTORNO',v_op,v_entrada.id,btrim(p_motivo),v_uid),
 (p_empresa_id,v_saida.obra_id,v_saida.insumo_id,v_saida.local_estoque,
  -v_saida.quantidade_delta,'ESTORNO',v_op,v_saida.id,btrim(p_motivo),v_uid);
 return jsonb_build_object('estornado',true,'operacao_estorno',v_op);
end
$func$;

create or replace function public.ew_insumos_cancelar_nota(
 p_empresa_id uuid,p_despesa_id uuid,p_motivo text
) returns jsonb language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();v_despesa public.ew_obra_despesas%rowtype;
 v_linha public.ew_insumos_movimentos%rowtype;v_saldo numeric;v_op uuid:=gen_random_uuid();
 v_count integer:=0;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
  where u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente ADM pode cancelar nota.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400
 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 select * into v_despesa from public.ew_obra_despesas d
  where d.id=p_despesa_id and d.empresa_id=p_empresa_id for update;
 if not found or v_despesa.status<>'aprovada' then
  raise exception 'Nota inexistente ou já cancelada.';end if;
 for v_linha in select m.* from public.ew_insumos_movimentos m
  join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
  where i.despesa_id=p_despesa_id and m.empresa_id=p_empresa_id and m.origem='RECEBIMENTO'
  order by m.obra_id,m.insumo_id,m.local_estoque,m.id
 loop
  v_count:=v_count+1;
  if exists(select 1 from public.ew_insumos_movimentos x where x.estorno_de_id=v_linha.id)
  then raise exception 'Este recebimento já possui estorno de estoque.';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_empresa_id::text||'|'||v_linha.obra_id::text||'|'||
    v_linha.insumo_id::text||'|'||v_linha.local_estoque,9012));
  select coalesce(sum(x.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos x
    where x.empresa_id=p_empresa_id and x.obra_id=v_linha.obra_id
     and x.insumo_id=v_linha.insumo_id and x.local_estoque=v_linha.local_estoque;
  if v_saldo<v_linha.quantidade_delta then
   raise exception 'Não é possível cancelar: o saldo recebido foi transferido/utilizado. Estorne primeiro os movimentos.';
  end if;
  insert into public.ew_insumos_movimentos(
    empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
    operacao_id,estorno_de_id,observacao,usuario_id
  ) values(p_empresa_id,v_linha.obra_id,v_linha.insumo_id,v_linha.local_estoque,
    -v_linha.quantidade_delta,'ESTORNO',v_op,v_linha.id,btrim(p_motivo),v_uid);
 end loop;
 if v_count=0 then
  -- Nota da v45.1, que registrava apenas custos. Não inventar um estorno físico.
  return public.ew_cancelar_despesa_financeira(p_empresa_id,p_despesa_id,p_motivo);
 end if;
 update public.ew_obra_despesas set status='cancelada',cancelado_por=v_uid,
  cancelado_em=now(),observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 where empresa_id=p_empresa_id and id=p_despesa_id;
 return jsonb_build_object('cancelada',true,'itens_estornados',v_count,'operacao_estorno',v_op);
end
$func$;

revoke all on function public.ew_insumos_transferir(uuid,uuid,uuid,uuid,text,text,numeric,text,uuid) from public;
revoke all on function public.ew_insumos_estornar_transferencia(uuid,uuid,text) from public;
revoke all on function public.ew_insumos_cancelar_nota(uuid,uuid,text) from public;
revoke execute on function public.ew_insumos_transferir(uuid,uuid,uuid,uuid,text,text,numeric,text,uuid) from anon;
revoke execute on function public.ew_insumos_estornar_transferencia(uuid,uuid,text) from anon;
revoke execute on function public.ew_insumos_cancelar_nota(uuid,uuid,text) from anon;
grant execute on function public.ew_insumos_transferir(uuid,uuid,uuid,uuid,text,text,numeric,text,uuid) to authenticated;
grant execute on function public.ew_insumos_estornar_transferencia(uuid,uuid,text) to authenticated;
grant execute on function public.ew_insumos_cancelar_nota(uuid,uuid,text) to authenticated;
