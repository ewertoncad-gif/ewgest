
-- Consulta de pendências: o passado permanece, somente operações ATIVAS bloqueiam.
create or replace function public.ew_inspecionar_reversao_obra(p_obra_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_obra public.obras%rowtype;v_uid uuid:=auth.uid();
 v_n_esq int;v_lib int;v_lib_cancel int;v_lotes int;v_planos int;
 v_rom int;v_rom_cancel int;v_saida int;v_saida_cancel int;
 v_mov int;v_mov_abertos int;v_fabr int;v_liberadas int;v_refs int;
 v_saldos int;v_motivos text[]:=array[]::text[];
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
 count(*) filter(where m.estorno_de_id is null
  and not exists(select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id))
 into v_mov,v_mov_abertos from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id;
 select count(*) into v_saldos from (
  select m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
  from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
  group by 1,2,3,4 having sum(m.quantidade_delta)<>0
 ) saldo;
 select count(*) into v_refs from (
  select a.id from public.classificacoes_tipologias_auditoria a
   join public.esquadrias e on e.id=a.esquadria_referencia_id
   where e.obra_id=p_obra_id and a.obra_id<>p_obra_id
  union all
  select r.id from public.esquadrias_descricoes_revisoes r
   join public.esquadrias e on e.id=r.esquadria_referencia_id
   where e.obra_id=p_obra_id and r.obra_id<>p_obra_id
 ) xs;
 if v_rom>0 then v_motivos:=array_append(v_motivos,'Cancele todos os romaneios emitidos.');end if;
 if v_saida>0 then v_motivos:=array_append(v_motivos,'Estorne todas as saídas de produção ainda ativas.');end if;
 if v_lib>0 or v_lotes>0 or v_planos>0 or v_liberadas>0 then
  v_motivos:=array_append(v_motivos,'Cancele as liberações para corte e seus lotes.');end if;
 if v_fabr>0 then v_motivos:=array_append(v_motivos,'Existem quantidades fabricadas a conciliar.');end if;
 if v_mov_abertos>0 or v_saldos>0 then
  v_motivos:=array_append(v_motivos,'Estorne as movimentações do estoque e confira saldo zero por material e galpão.');end if;
 if v_refs>0 then v_motivos:=array_append(v_motivos,'Há referências vinculadas a outra obra.');end if;
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
  'saldos_nao_zerados',v_saldos,'referencias_externas',v_refs));
end;$$;
revoke all on function public.ew_inspecionar_reversao_obra(uuid) from public,anon;
grant execute on function public.ew_inspecionar_reversao_obra(uuid) to authenticated;

-- Operador cancela TODOS os registros ativos de liberação após anular saídas.
-- Este ato NÃO "apaga" lançamentos antigos, apenas desativa e registra autoria.
create or replace function public.ew_cancelar_liberacoes_obra(p_obra_id uuid,p_motivo text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_e record;
 v_qtd integer;v_ativas integer;v_lotes integer;v_motivo text:=btrim(coalesce(p_motivo,''));v_liberacoes jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 10 and 400 then raise exception 'Informe o motivo, de 10 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u join public.usuarios_login ul
   on ul.usuario_id=u.usuario_id and ul.empresa_id=u.empresa_id
  where u.usuario_id=v_uid and u.empresa_id=v_ob.empresa_id
   and u.perfil in ('administrador','gerenciador') and ul.perfil=u.perfil and ul.ativo
   and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem cancelar liberações.';end if;
 perform 1 from public.esquadrias where obra_id=p_obra_id order by id for update;
 if exists (select 1 from public.romaneios where obra_id=p_obra_id and status<>'cancelado')
  then raise exception 'Cancele os romaneios emitidos antes das liberações.';end if;
 if exists(select 1 from public.saidas_producao s join public.esquadrias e
    on e.id=s.esquadria_id where e.obra_id=p_obra_id and s.cancelado_em is null)
  then raise exception 'Existem saídas de produção ativas. Estorne-as primeiro.';end if;
 if exists(select 1 from public.esquadrias where obra_id=p_obra_id and qtd_fabricada<>0)
  then raise exception 'Existem quantidades fabricadas que precisam ser conciliadas.';end if;
 -- Confere consistência acumulada ANTES de qualquer alteração.
 for v_e in
  select e.id,e.codigo,e.qtd_liberada,coalesce(sum(l.quantidade)
    filter(where l.cancelado_em is null),0)::integer as ativos
  from public.esquadrias e left join public.liberacoes_corte l on l.esquadria_id=e.id
  where e.obra_id=p_obra_id group by e.id,e.codigo,e.qtd_liberada
 loop
  if v_e.qtd_liberada<>v_e.ativos then
   raise exception 'Saldo de liberação inconsistente para %. Solicite conferência técnica.',v_e.codigo;
  end if;
 end loop;
 select count(*),coalesce(sum(l.quantidade),0) into v_ativas,v_qtd
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'esquadria',e.codigo,
  'quantidade',l.quantidade,'liberado_em',l.registrada_em,'liberado_por',l.usuario_id)),
  '[]'::jsonb) into v_liberacoes
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 update public.liberacoes_corte l set cancelado_em=now(),cancelado_por=v_uid,motivo_cancelamento=v_motivo
 from public.esquadrias e where l.esquadria_id=e.id and e.obra_id=p_obra_id
 and l.cancelado_em is null;
 update public.esquadrias set qtd_liberada=0 where obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
  where obra_id=p_obra_id and cancelado_em is null;
 update public.ew_liberacoes_lotes set cancelado_em=now(),cancelado_por=v_uid,
  motivo_cancelamento=v_motivo where obra_id=p_obra_id and cancelado_em is null;
 if v_ativas>0 or v_lotes>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_LIBERACOES',v_motivo,
   jsonb_build_object('registros',v_ativas,'quantidade',v_qtd,'lotes',v_lotes,
    'liberacoes_originais',v_liberacoes,
    'estoque','Baixas de materiais ainda precisam de estorno separado'));
 end if;
 return jsonb_build_object('canceladas',v_ativas,'unidades',v_qtd,'lotes',v_lotes,
  'estoque_pendente',true,'historico_preservado',true);
end;$$;
revoke all on function public.ew_cancelar_liberacoes_obra(uuid,text) from public,anon;
grant execute on function public.ew_cancelar_liberacoes_obra(uuid,text) to authenticated;
