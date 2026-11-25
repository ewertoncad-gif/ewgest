-- EWGEST: permite cancelar pedido somente após estorno integral e regularização fiscal.
CREATE OR REPLACE FUNCTION public.ew_compras_cancelar_pedido(p_pedido_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_p public.ew_compras_pedidos%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 perform public.ew_exigir_sessao_atual();
 if auth.uid() is null or p_pedido_id is null or p_operacao_id is null
    or char_length(v_motivo) not between 5 and 400
 then raise exception 'Pedido, identificador e motivo de 5 a 400 caracteres são obrigatórios.';end if;
 select * into v_p from public.ew_compras_pedidos where id=p_pedido_id for update;
 if not found then raise exception 'Pedido não localizado.';end if;
 if not public.ew_pode(v_p.empresa_id,'compras.pedir')
 then raise exception 'Sem permissão para cancelar pedido.';end if;
 if v_p.status='CANCELADO' then
  if v_p.cancelamento_operacao_id=p_operacao_id and v_p.cancelamento_motivo=v_motivo then
   return jsonb_build_object('id',v_p.id,'cancelado',true,'repetida',true);
  end if;
  raise exception 'Pedido já cancelado.';end if;
 if v_p.status<>'ABERTO' then
  raise exception 'Pedido já iniciou recebimento ou foi concluído. Cancelamento comercial direto bloqueado.';end if;
 -- Histórico estornado é preservado, mas não constitui uma obrigação ativa.
 if exists(select 1 from public.ew_compras_recebimentos r where r.pedido_id=v_p.id and r.empresa_id=v_p.empresa_id and r.estornado_em is null)
 then raise exception 'Estorne todos os recebimentos ativos antes de cancelar o pedido.';end if;
 if exists(select 1 from public.ew_compras_nfe_conciliacoes c where c.pedido_id=v_p.id and c.empresa_id=v_p.empresa_id and c.desvinculado_em is null)
  or exists(select 1 from public.ew_compras_notas_empresa n where n.pedido_id=v_p.id and n.empresa_id=v_p.empresa_id and n.status<>'CANCELADA')
 then raise exception 'Regularize as notas fiscais e conciliações ativas antes de cancelar o pedido.';end if;
 update public.ew_compras_pedidos set status='CANCELADO',cancelado_em=now(),
  cancelado_por=auth.uid(),cancelamento_motivo=v_motivo,
  cancelamento_operacao_id=p_operacao_id where id=v_p.id;
 -- A solicitação segue PEDIDO_GERADO para não originar outro pedido acidentalmente.
 return jsonb_build_object('id',v_p.id,'cancelado',true,'repetida',false,
   'estoque_alterado',false,'solicitacao_preservada',true);
end;$function$;
