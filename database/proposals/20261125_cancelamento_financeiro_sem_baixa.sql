-- A flag de estorno físico só é exigida quando há movimento físico de insumos.
CREATE OR REPLACE FUNCTION public.ew_insumos_cancelar_nota(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_despesa public.ew_obra_despesas%rowtype;
 v_linha public.ew_insumos_movimentos%rowtype;v_saldo numeric;v_op uuid:=gen_random_uuid();
 v_count integer:=0;
begin
 IF NOT public.ew_pode(p_empresa_id,'financeiro.cancelar_despesas') THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: financeiro.cancelar_despesas'; END IF;
 PERFORM public.ew_exigir_permissao('financeiro.cancelar_despesas');
 perform public.ew_exigir_sessao_atual();
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400
 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 select * into v_despesa from public.ew_obra_despesas d
  where d.id=p_despesa_id and d.empresa_id=p_empresa_id for update;
 if not found or v_despesa.status<>'aprovada' then
  raise exception 'Nota inexistente ou já cancelada.';end if;
 if exists(select 1 from public.ew_insumos_movimentos m join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id and i.empresa_id=m.empresa_id where i.despesa_id=p_despesa_id and m.empresa_id=p_empresa_id and m.origem='RECEBIMENTO')
 and not public.ew_pode(p_empresa_id,'estoque.estornar') then
 raise exception 'PERMISSAO_NEGADA: estoque.estornar — nota possui entrada física de insumos.';end if;
 if exists(select 1 from public.ew_nfe_recebimentos r join public.ew_obra_despesas_itens i on i.id=r.despesa_item_id and i.empresa_id=r.empresa_id where i.despesa_id=p_despesa_id and r.empresa_id=p_empresa_id and r.estornado_em is null)
 then raise exception 'Esta nota possui materiais recebidos. Estorne as entradas de estoque antes de cancelar a despesa.';end if;
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
$function$;
