-- EWGEST: integridade entre arquivamento e compras. Sem apagar histórico.
CREATE OR REPLACE FUNCTION public.ew_inspecionar_reversao_obra(p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_obra public.obras%rowtype;v_uid uuid:=auth.uid();
 v_n_esq int;v_lib int;v_lib_cancel int;v_lotes int;v_planos int;
 v_rom int;v_rom_cancel int;v_saida int;v_saida_cancel int;
 v_mov int;v_mov_abertos int;v_fabr int;v_liberadas int;v_refs int;
 v_saldos int;v_insumos_saldos int;v_conciliadas int:=0;v_conciliadas_nf int:=0;v_motivos text[]:=array[]::text[];
begin
 perform public.ew_exigir_sessao_atual();
 select * into v_obra from public.obras where id=p_obra_id;
 if not found then raise exception 'Obra não encontrada.';end if;
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.empresa_id=v_obra.empresa_id and ue.usuario_id=v_uid
   and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
   and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem conferir reversões.';end if;
 select count(*),coalesce(sum(e.qtd_liberada),0),coalesce(sum(e.qtd_fabricada),0)
 into v_n_esq,v_liberadas,v_fabr from public.esquadrias e where e.obra_id=p_obra_id;
 select count(*) filter(where l.cancelado_em is null),
 count(*) filter(where l.cancelado_em is not null)
 into v_lib,v_lib_cancel from public.liberacoes_corte l
 join public.esquadrias e on e.id=l.esquadria_id where e.obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
 where obra_id=p_obra_id and cancelado_em is null;
 select count(*) into v_planos from public.ew_planos_liberados p
 left join public.liberacoes_corte l on l.id=p.liberacao_id
 where p.obra_id=p_obra_id and (l.id is null or l.cancelado_em is null);
 select count(*) filter(where status<>'cancelado'),
 count(*) filter(where status='cancelado')
 into v_rom,v_rom_cancel from public.romaneios where obra_id=p_obra_id;
 select count(*) filter(where s.cancelado_em is null),
 count(*) filter(where s.cancelado_em is not null)
 into v_saida,v_saida_cancel from public.saidas_producao s
 join public.esquadrias e on e.id=s.esquadria_id where e.obra_id=p_obra_id;
 select count(*),
 count(*) filter(where m.origem<>'ESTORNO' and m.estorno_de_id is null
  and not exists(select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id))
 into v_mov,v_mov_abertos from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id;
 select count(*) into v_saldos from (
  select m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
  from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
  group by 1,2,3,4 having sum(m.quantidade_delta)<>0
 ) saldo;
 select count(*) into v_insumos_saldos from (
  select m.insumo_id,m.local_estoque from public.ew_insumos_movimentos m
  where m.empresa_id=v_obra.empresa_id and m.obra_id=p_obra_id
  group by m.insumo_id,m.local_estoque having sum(m.quantidade_delta)<>0
 ) x;
 select count(*) into v_refs from (
  select a.id from public.classificacoes_tipologias_auditoria a
   join public.esquadrias e on e.id=a.esquadria_referencia_id
   where e.obra_id=p_obra_id and a.obra_id<>p_obra_id
  union all
  select r.id from public.esquadrias_descricoes_revisoes r
   join public.esquadrias e on e.id=r.esquadria_referencia_id
   where e.obra_id=p_obra_id and r.obra_id<>p_obra_id
 ) xs;
 -- Transferências internas históricas ficam conciliadas quando todas as NF-e
 -- físicas foram estornadas e o saldo em cada galpão já é exatamente zero.
 v_conciliadas_nf:=public.ew_transferencias_nfe_conciliadas(p_obra_id);
 v_conciliadas:=v_conciliadas_nf;
 IF v_conciliadas=0 THEN
  v_conciliadas:=public.ew_transferencias_internas_conciliadas(p_obra_id);
 END IF;
 IF v_conciliadas>0 AND v_conciliadas=v_mov_abertos THEN
  v_mov_abertos:=0;
 ELSE
  v_conciliadas:=0;v_conciliadas_nf:=0;
 END IF;
 if v_rom>0 then v_motivos:=array_append(v_motivos,'Cancele todos os romaneios emitidos.');end if;
 if v_saida>0 then v_motivos:=array_append(v_motivos,'Estorne todas as saídas de produção ainda ativas.');end if;
 if v_lib>0 or v_lotes>0 or v_planos>0 or v_liberadas>0 then
  v_motivos:=array_append(v_motivos,'Cancele as liberações para corte e seus lotes.');end if;
 if v_fabr>0 then v_motivos:=array_append(v_motivos,'Existem quantidades fabricadas a conciliar.');end if;
 if v_mov_abertos>0 or v_saldos>0 then
  v_motivos:=array_append(v_motivos,'Estorne as movimentações do estoque e confira saldo zero por material e galpão.');end if;
 if v_insumos_saldos>0 then v_motivos:=array_append(v_motivos,
  'Estorne ou transfira todo o estoque de vidros e outros insumos antes de arquivar a obra.');end if;
 if v_refs>0 then v_motivos:=array_append(v_motivos,'Há referências vinculadas a outra obra.');end if;
 if exists(select 1 from public.ew_compras_solicitacoes s where s.empresa_id=v_obra.empresa_id and s.obra_id=p_obra_id and s.status='ABERTA') then
  v_motivos:=array_append(v_motivos,'Cancele as solicitações de compra abertas (e suas cotações) antes de excluir a obra.');end if;
 if exists(select 1 from public.ew_compras_pedidos p where p.empresa_id=v_obra.empresa_id and p.obra_id=p_obra_id and p.status<>'CANCELADO') then
  v_motivos:=array_append(v_motivos,'Estorne os recebimentos e cancele os pedidos de compra antes de excluir a obra.');end if;
 if exists(select 1 from public.ew_compras_recebimentos r join public.ew_compras_pedidos p on p.id=r.pedido_id and p.empresa_id=r.empresa_id where p.empresa_id=v_obra.empresa_id and p.obra_id=p_obra_id and r.estornado_em is null) then
  v_motivos:=array_append(v_motivos,'Estorne os recebimentos por pedido ainda ativos.');end if;
 if v_obra.arquivada_em is not null then
  v_motivos:=array_append(v_motivos,'Esta obra já foi retirada do acompanhamento ativo.');end if;
 return jsonb_build_object(
 'obra_id',v_obra.id,'nome',v_obra.nome,'codigo',v_obra.codigo,'motivos',to_jsonb(v_motivos),
 'permitido',cardinality(v_motivos)=0,'arquivada_em',v_obra.arquivada_em,
 'resumo',jsonb_build_object(
  'esquadrias',v_n_esq,'liberacoes',v_lib,'liberacoes_canceladas',v_lib_cancel,
  'unidades_liberadas',v_liberadas,'fabricadas',v_fabr,'lotes_cem',v_lotes,
  'planos_liberados',v_planos,'romaneios',v_rom,'romaneios_cancelados',v_rom_cancel,
  'saidas_producao',v_saida,'saidas_canceladas',v_saida_cancel,
  'movimentos_estoque',v_mov,'movimentos_pendentes',v_mov_abertos,
  'transferencias_nfe_conciliadas',v_conciliadas_nf,
  'transferencias_conciliadas',v_conciliadas,
  'saldos_nao_zerados',v_saldos,'saldos_insumos_nao_zerados',v_insumos_saldos,
  'referencias_externas',v_refs));
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_compras_pedidos_resumo(p_empresa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_precos boolean;v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not(public.ew_pode(p_empresa_id,'compras.consultar') or
        public.ew_pode(p_empresa_id,'compras.receber'))
 then raise exception 'Sem permissão para consultar pedidos.';end if;
 v_precos:=public.ew_pode(p_empresa_id,'compras.consultar_valores');
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'numero',p.numero,'empresa_id',p.empresa_id,
  'solicitacao_id',p.solicitacao_id,'cotacao_id',p.cotacao_id,
  'fornecedor_id',p.fornecedor_id,'obra_id',p.obra_id,
  'local_empresa_id',p.local_empresa_id,
  'itens',case when v_precos then p.itens else
   (select coalesce(jsonb_agg(i.value - 'preco_unitario_centavos'),'[]'::jsonb)
    from jsonb_array_elements(p.itens) i(value)) end,
  'total_centavos',case when v_precos then p.total_centavos else null end,
  'status',p.status,'criado_em',p.criado_em
 ) order by p.criado_em desc),'[]'::jsonb)
 into v_result from public.ew_compras_pedidos p where p.empresa_id=p_empresa_id and (p.obra_id is null or exists(select 1 from public.obras o where o.id=p.obra_id and o.empresa_id=p.empresa_id and o.arquivada_em is null));
 return v_result;
end;$function$;

-- Serializa novas compras com a exclusão e rejeita destinos arquivados.
create or replace function ew_compras_interna.proteger_destino_obra() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_obra uuid; v_empresa uuid:=new.empresa_id;
begin
 if tg_table_name='ew_compras_cotacoes' then
  select s.obra_id into v_obra from public.ew_compras_solicitacoes s where s.id=new.solicitacao_id and s.empresa_id=v_empresa;
 elsif tg_table_name='ew_compras_recebimentos' then
  select p.obra_id into v_obra from public.ew_compras_pedidos p where p.id=new.pedido_id and p.empresa_id=v_empresa;
 else v_obra:=new.obra_id;
 end if;
 if v_obra is not null then
  perform 1 from public.obras o where o.id=v_obra and o.empresa_id=v_empresa and o.arquivada_em is null for share;
  if not found then raise exception 'Obra excluída ou indisponível para compras.'; end if;
 end if;
 return new;
end;$$;
revoke all on function ew_compras_interna.proteger_destino_obra() from public,anon,authenticated;
create trigger ew_compras_destino_obra_ativo before insert on public.ew_compras_solicitacoes for each row execute function ew_compras_interna.proteger_destino_obra();
create trigger ew_compras_destino_obra_ativo before insert on public.ew_compras_cotacoes for each row execute function ew_compras_interna.proteger_destino_obra();
create trigger ew_compras_destino_obra_ativo before insert on public.ew_compras_pedidos for each row execute function ew_compras_interna.proteger_destino_obra();
create trigger ew_compras_destino_obra_ativo before insert on public.ew_compras_recebimentos for each row execute function ew_compras_interna.proteger_destino_obra();

-- Defesa adicional, inclusive para outras rotinas de arquivamento.
create or replace function ew_compras_interna.proteger_arquivamento() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if old.arquivada_em is null and new.arquivada_em is not null then
  if exists(select 1 from public.ew_compras_solicitacoes s where s.obra_id=old.id and s.empresa_id=old.empresa_id and s.status='ABERTA')
  or exists(select 1 from public.ew_compras_pedidos p where p.obra_id=old.id and p.empresa_id=old.empresa_id and p.status<>'CANCELADO')
  or exists(select 1 from public.ew_compras_recebimentos r join public.ew_compras_pedidos p on p.id=r.pedido_id and p.empresa_id=r.empresa_id where p.obra_id=old.id and p.empresa_id=old.empresa_id and r.estornado_em is null)
  then raise exception 'Compras pendentes: cancele solicitações e pedidos e estorne os recebimentos antes de excluir a obra.';end if;
 end if;
 return new;
end;$$;
revoke all on function ew_compras_interna.proteger_arquivamento() from public,anon,authenticated;
create trigger ew_compras_proteger_arquivamento before update of arquivada_em on public.obras for each row execute function ew_compras_interna.proteger_arquivamento();

-- Políticas restritivas: histórico arquivado não aparece nas consultas operacionais.
-- Mantém as permissões originais; a função interna não é uma RPC pública.
create or replace function ew_compras_interna.destino_visivel(p_empresa uuid,p_obra uuid,p_solicitacao uuid,p_pedido uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare v_obra uuid:=p_obra;
begin
 if auth.uid() is null or not (public.ew_pode(p_empresa,'compras.consultar') or public.ew_pode(p_empresa,'compras.consultar_valores') or public.ew_pode(p_empresa,'compras.receber')) then return false;end if;
 if p_solicitacao is not null then
  select s.obra_id into v_obra from public.ew_compras_solicitacoes s where s.id=p_solicitacao and s.empresa_id=p_empresa;
  if not found then return false;end if;
 elsif p_pedido is not null then
  select p.obra_id into v_obra from public.ew_compras_pedidos p where p.id=p_pedido and p.empresa_id=p_empresa;
  if not found then return false;end if;
 end if;
 return v_obra is null or exists(select 1 from public.obras o where o.id=v_obra and o.empresa_id=p_empresa and o.arquivada_em is null);
end;$$;
revoke all on function ew_compras_interna.destino_visivel(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function ew_compras_interna.destino_visivel(uuid,uuid,uuid,uuid) to authenticated;
create policy ew_compras_obra_ativa on public.ew_compras_solicitacoes as restrictive for select to authenticated using (ew_compras_interna.destino_visivel(empresa_id,obra_id,null,null));
create policy ew_compras_obra_ativa on public.ew_compras_cotacoes as restrictive for select to authenticated using (ew_compras_interna.destino_visivel(empresa_id,null,solicitacao_id,null));
create policy ew_compras_obra_ativa on public.ew_compras_pedidos as restrictive for select to authenticated using (ew_compras_interna.destino_visivel(empresa_id,obra_id,null,null));
create policy ew_compras_obra_ativa on public.ew_compras_recebimentos as restrictive for select to authenticated using (ew_compras_interna.destino_visivel(empresa_id,null,null,pedido_id));

-- Reconcilia somente solicitações da obra de treinamento já arquivada, sem compras.
-- Cancelar um agrupamento pode reabrir as origens; repetir até encerrar todas.
do $$
declare x record;
begin
 loop
  select s.id,o.arquivada_por,o.arquivada_em into x
  from public.ew_compras_solicitacoes s join public.obras o on o.id=s.obra_id and o.empresa_id=s.empresa_id
  where o.codigo='TESTE-TREINAMENTO' and o.nome='ESSENCE CONSTRUÇÕES' and o.arquivada_em is not null
    and o.arquivada_por is not null and s.status='ABERTA'
    and not exists(select 1 from public.ew_compras_pedidos p where p.obra_id=o.id and p.empresa_id=o.empresa_id)
    and not exists(select 1 from public.ew_compras_cotacoes c join public.ew_compras_solicitacoes a on a.id=c.solicitacao_id where a.obra_id=o.id and a.empresa_id=o.empresa_id)
  order by s.id limit 1 for update of s;
  exit when not found;
  update public.ew_compras_solicitacoes set status='CANCELADA',cancelado_em=now(),cancelado_por=x.arquivada_por,
  cancelamento_motivo='Reconciliação de solicitação da obra de treinamento já excluída.',cancelamento_operacao_id=gen_random_uuid()
  where id=x.id;
 end loop;
end;$$;
