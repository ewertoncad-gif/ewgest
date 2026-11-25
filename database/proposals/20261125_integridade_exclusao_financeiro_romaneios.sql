-- EWGEST: extensão da proteção de exclusão ao financeiro e aos romaneios de transferência.
-- Preserva registros históricos; emissão/cancelamento fiscal externo não é realizado aqui.
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
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=v_obra.empresa_id and d.obra_id=p_obra_id and d.status<>'cancelada') then
  v_motivos:=array_append(v_motivos,'Cancele as despesas e notas fiscais ainda ativas no Financeiro antes de excluir a obra.');end if;
 if exists(select 1 from public.ew_obra_faturamentos f where f.empresa_id=v_obra.empresa_id and f.obra_id=p_obra_id and f.status<>'cancelado') then
  v_motivos:=array_append(v_motivos,'Cancele os faturamentos ainda emitidos antes de excluir a obra.');end if;
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
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_arquivamento()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if old.arquivada_em is null and new.arquivada_em is not null then
  if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=old.empresa_id and d.obra_id=old.id and d.status<>'cancelada')
  or exists(select 1 from public.ew_obra_faturamentos f where f.empresa_id=old.empresa_id and f.obra_id=old.id and f.status<>'cancelado')
  then raise exception 'Financeiro pendente: cancele despesas e faturamentos antes de excluir a obra.';end if;

  if exists(select 1 from public.ew_compras_solicitacoes s where s.obra_id=old.id and s.empresa_id=old.empresa_id and s.status='ABERTA')
  or exists(select 1 from public.ew_compras_pedidos p where p.obra_id=old.id and p.empresa_id=old.empresa_id and p.status<>'CANCELADO')
  or exists(select 1 from public.ew_compras_recebimentos r join public.ew_compras_pedidos p on p.id=r.pedido_id and p.empresa_id=r.empresa_id where p.obra_id=old.id and p.empresa_id=old.empresa_id and r.estornado_em is null)
  then raise exception 'Compras pendentes: cancele solicitações e pedidos e estorne os recebimentos antes de excluir a obra.';end if;
 end if;
 return new;
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_romaneios_transferencia_listar(p_empresa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not exists(select 1 from public.usuarios_empresas ue
 join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
 where ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ul.ativo and ul.excluido_em is null
 and ue.perfil in ('administrador','gerenciador','supervisor','almoxarife'))
 then raise exception 'Sem acesso aos romaneios desta empresa.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',d.id,'numero',d.numero,'obra_id',d.obra_id,
   'origem',d.origem_galpao,'destino',d.destino_galpao,'data',d.data_saida,
   'motorista',d.motorista,'placa',d.placa,'observacoes',d.observacoes,
   'status',d.status,'agrupado_em',d.agrupado_em,'criado_em',d.criado_em,
   'itens',coalesce((select jsonb_agg(jsonb_build_object(
     'id',i.id,'tipo',i.tipo,'transferencia_id',i.transferencia_id,
     'origem_obra_id',i.obra_origem_id,'destino_obra_id',i.obra_destino_id,
     'codigo',i.codigo,'descricao',i.descricao,'quantidade',i.quantidade,
     'unidade',i.unidade,'comprimento_mm',i.comprimento_mm,'cor',i.cor,
     'estornado', (i.tipo='TRANSFERENCIA' and exists(
        select 1 from public.ew_estoque_obras_movimentos e
        where e.estorno_de_id in (i.movimento_saida_id,i.movimento_entrada_id))))
     order by i.criado_em,i.id) from public.ew_romaneios_transferencia_itens i
     where i.documento_id=d.id),'[]'::jsonb)
 ) order by d.criado_em desc),'[]'::jsonb) into v_result
 from public.ew_romaneios_transferencia d where d.empresa_id=p_empresa_id and exists(select 1 from public.obras o where o.id=d.obra_id and o.empresa_id=d.empresa_id and o.arquivada_em is null);
 return coalesce(v_result,'[]'::jsonb);
end;$function$;

create or replace function ew_compras_interna.proteger_obra_financeiro_romaneio() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Permitir regularização por cancelamento de documentos legados, sem reabrir operações.
 if tg_op='UPDATE' and ((tg_table_name='ew_obra_despesas' and new.status='cancelada')
   or (tg_table_name='ew_obra_faturamentos' and new.status='cancelado')
   or (tg_table_name='ew_romaneios_transferencia' and new.status='CANCELADO'))
   and new.obra_id=old.obra_id and new.empresa_id=old.empresa_id and old.status is distinct from new.status then return new;end if;
 perform 1 from public.obras o where o.id=new.obra_id and o.empresa_id=new.empresa_id and o.arquivada_em is null for share;
 if not found then raise exception 'Obra excluída ou indisponível para esta operação.';end if;
 return new;
end;$$;
revoke all on function ew_compras_interna.proteger_obra_financeiro_romaneio() from public,anon,authenticated;
create trigger ew_destino_obra_ativa_guard before insert or update on public.ew_obra_despesas for each row execute function ew_compras_interna.proteger_obra_financeiro_romaneio();
create trigger ew_destino_obra_ativa_guard before insert or update on public.ew_obra_faturamentos for each row execute function ew_compras_interna.proteger_obra_financeiro_romaneio();
create trigger ew_destino_obra_ativa_guard before insert or update on public.ew_romaneios_transferencia for each row execute function ew_compras_interna.proteger_obra_financeiro_romaneio();
