-- EWGEST v46.21 — cancelamento conservador das etapas comerciais.
-- Pré-requisitos: cinco propostas 20261123/24 de compras, estoque e NF.
-- NÃO publicar antes de homologação; histórico nunca é excluído.
begin;

alter table public.ew_compras_solicitacoes
 add column if not exists cancelado_em timestamptz,
 add column if not exists cancelado_por uuid references auth.users(id),
 add column if not exists cancelamento_motivo text,
 add column if not exists cancelamento_operacao_id uuid unique;
alter table public.ew_compras_cotacoes
 add column if not exists status text not null default 'ABERTA',
 add column if not exists cancelado_em timestamptz,
 add column if not exists cancelado_por uuid references auth.users(id),
 add column if not exists cancelamento_motivo text,
 add column if not exists cancelamento_operacao_id uuid unique;
alter table public.ew_compras_cotacoes
 add constraint ew_compras_cotacoes_status_chk check(status in ('ABERTA','CANCELADA'));
alter table public.ew_compras_pedidos
 add column if not exists cancelado_em timestamptz,
 add column if not exists cancelado_por uuid references auth.users(id),
 add column if not exists cancelamento_motivo text,
 add column if not exists cancelamento_operacao_id uuid unique;

create or replace function public.ew_compras_cancelar_solicitacao(
 p_solicitacao_id uuid,p_motivo text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare
 v_s public.ew_compras_solicitacoes%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 perform public.ew_exigir_sessao_atual();
 if auth.uid() is null or p_solicitacao_id is null or p_operacao_id is null
    or char_length(v_motivo) not between 5 and 400
 then raise exception 'Solicitação, identificador e motivo de 5 a 400 caracteres são obrigatórios.';end if;
 select * into v_s from public.ew_compras_solicitacoes
 where id=p_solicitacao_id for update;
 if not found then raise exception 'Solicitação não localizada.';end if;
 if not public.ew_pode(v_s.empresa_id,'compras.solicitar')
 then raise exception 'Sem permissão para cancelar solicitação.';end if;
 if v_s.status='CANCELADA' then
  if v_s.cancelamento_operacao_id=p_operacao_id and v_s.cancelamento_motivo=v_motivo then
   return jsonb_build_object('id',v_s.id,'repetida',true,'cancelada',true);
  end if;
  raise exception 'Esta solicitação já foi cancelada.';end if;
 if v_s.status<>'ABERTA' then
  raise exception 'Solicitação convertida em pedido. Revise a operação comercial original.';end if;
 if exists(select 1 from public.ew_compras_pedidos p where p.solicitacao_id=v_s.id)
 then raise exception 'Já existe pedido histórico para esta solicitação. Não é permitido cancelar por esta rotina.';end if;
 -- Cotações relacionadas são desativadas como consequência auditável, sem apagar preços históricos.
 update public.ew_compras_cotacoes
 set status='CANCELADA',cancelado_em=now(),cancelado_por=auth.uid(),
     cancelamento_motivo=left('Solicitação cancelada: '||v_motivo,400)
 where solicitacao_id=v_s.id and status='ABERTA';
 update public.ew_compras_solicitacoes set status='CANCELADA',cancelado_em=now(),
   cancelado_por=auth.uid(),cancelamento_motivo=v_motivo,cancelamento_operacao_id=p_operacao_id
 where id=v_s.id;
 return jsonb_build_object('id',v_s.id,'cancelada',true,'repetida',false,'estoque_alterado',false);
end;$f$;

create or replace function public.ew_compras_cancelar_cotacao(
 p_cotacao_id uuid,p_motivo text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare
 v_q public.ew_compras_cotacoes%rowtype;
 v_s public.ew_compras_solicitacoes%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 perform public.ew_exigir_sessao_atual();
 if auth.uid() is null or p_cotacao_id is null or p_operacao_id is null
    or char_length(v_motivo) not between 5 and 400
 then raise exception 'Cotação, identificador e motivo de 5 a 400 caracteres são obrigatórios.';end if;
 select * into v_q from public.ew_compras_cotacoes where id=p_cotacao_id;
 if not found then raise exception 'Cotação inexistente.';end if;
 if not public.ew_pode(v_q.empresa_id,'compras.cotar')
 then raise exception 'Sem permissão para cancelar cotação.';end if;
 -- A ordem dos bloqueios é a mesma do pedido e do cancelamento da solicitação:
 -- primeiro a solicitação, depois a cotação. Evita o deadlock clássico.
 select * into v_s from public.ew_compras_solicitacoes
 where id=v_q.solicitacao_id for update;
 if not found then raise exception 'Solicitação da cotação não localizada.';end if;
 select * into v_q from public.ew_compras_cotacoes
 where id=p_cotacao_id for update;
 if v_q.status='CANCELADA' then
  if v_q.cancelamento_operacao_id=p_operacao_id and v_q.cancelamento_motivo=v_motivo then
   return jsonb_build_object('id',v_q.id,'cancelada',true,'repetida',true);
  end if;
  raise exception 'Cotação já cancelada.';end if;
 if v_s.status<>'ABERTA'
 then raise exception 'Solicitação indisponível para revisão de cotação.';end if;
 if exists(select 1 from public.ew_compras_pedidos p
    where p.cotacao_id=v_q.id or p.solicitacao_id=v_s.id)
 then raise exception 'Solicitação já originou pedido; cotação histórica não pode ser cancelada.';end if;
 update public.ew_compras_cotacoes set status='CANCELADA',cancelado_em=now(),
  cancelado_por=auth.uid(),cancelamento_motivo=v_motivo,
  cancelamento_operacao_id=p_operacao_id where id=v_q.id;
 return jsonb_build_object('id',v_q.id,'cancelada',true,'repetida',false,'estoque_alterado',false);
end;$f$;

create or replace function public.ew_compras_cancelar_pedido(
 p_pedido_id uuid,p_motivo text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
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
 -- A verificação inclui histórico já estornado: cancelamento é exclusivo
 -- dos pedidos que jamais geraram entrada física.
 if exists(select 1 from public.ew_compras_recebimentos r where r.pedido_id=v_p.id)
 then raise exception 'Há histórico de recebimento deste pedido, mesmo estornado. Cancelamento direto não permitido.';end if;
 if exists(select 1 from public.ew_compras_nfe_conciliacoes c where c.pedido_id=v_p.id)
  or exists(select 1 from public.ew_compras_notas_empresa n where n.pedido_id=v_p.id)
 then raise exception 'Pedido possui histórico fiscal e não pode ser cancelado diretamente.';end if;
 update public.ew_compras_pedidos set status='CANCELADO',cancelado_em=now(),
  cancelado_por=auth.uid(),cancelamento_motivo=v_motivo,
  cancelamento_operacao_id=p_operacao_id where id=v_p.id;
 -- A solicitação segue PEDIDO_GERADO para não originar outro pedido acidentalmente.
 return jsonb_build_object('id',v_p.id,'cancelado',true,'repetida',false,
   'estoque_alterado',false,'solicitacao_preservada',true);
end;$f$;

-- Pedidos novos não podem ser gerados com uma cotação inativa.
create or replace function public.ew_compras_exigir_cotacao_ativa()
returns trigger language plpgsql security definer set search_path='' as $f$
declare v_status text;v_solic_status text;
begin
 select q.status,s.status into v_status,v_solic_status
 from public.ew_compras_cotacoes q
 join public.ew_compras_solicitacoes s on s.id=q.solicitacao_id
 where q.id=new.cotacao_id and q.empresa_id=new.empresa_id;
 if v_status is distinct from 'ABERTA' or v_solic_status is distinct from 'ABERTA'
 then raise exception 'Cotação cancelada ou solicitação indisponível.';end if;
 return new;
end;$f$;
drop trigger if exists ew_compras_prevenir_pedido_cotacao_cancelada on public.ew_compras_pedidos;
create trigger ew_compras_prevenir_pedido_cotacao_cancelada
 before insert on public.ew_compras_pedidos
 for each row execute function public.ew_compras_exigir_cotacao_ativa();

revoke all on function public.ew_compras_cancelar_solicitacao(uuid,text,uuid),
 public.ew_compras_cancelar_cotacao(uuid,text,uuid),
 public.ew_compras_cancelar_pedido(uuid,text,uuid) from public,anon;
grant execute on function public.ew_compras_cancelar_solicitacao(uuid,text,uuid),
 public.ew_compras_cancelar_cotacao(uuid,text,uuid),
 public.ew_compras_cancelar_pedido(uuid,text,uuid) to authenticated;

commit;
