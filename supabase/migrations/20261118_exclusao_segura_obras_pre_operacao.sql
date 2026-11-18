
-- Excluir e reimportar uma obra somente ANTES de iniciar operações.
-- Preserva cadastros gerais e rejeita qualquer liberação, saída, romaneio ou movimento
-- de estoque, inclusive aqueles cancelados ou estornados.
create table if not exists public.ew_obras_exclusoes_historico (
 id uuid primary key default gen_random_uuid(),
 operacao_id uuid not null unique,
 empresa_id uuid not null references public.empresas(id),
 obra_excluida_id uuid not null,
 obra_nome text not null,
 obra_codigo text,
 motivo text not null,
 resumo jsonb not null,
 excluido_por uuid not null references auth.users(id),
 excluido_em timestamptz not null default now()
);
create index if not exists ew_obras_exclusoes_empresa_data
 on public.ew_obras_exclusoes_historico(empresa_id,excluido_em desc);
alter table public.ew_obras_exclusoes_historico enable row level security;
revoke all on public.ew_obras_exclusoes_historico from public,anon,authenticated;
grant select on public.ew_obras_exclusoes_historico to authenticated;
create policy "ADM e Gerenciador consultam exclusoes de sua empresa"
on public.ew_obras_exclusoes_historico for select to authenticated using (
  public.ew_sessao_eh_atual() and exists (
   select 1 from public.usuarios_empresas ue join public.usuarios_login ul
    on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
   where ue.usuario_id=(select auth.uid()) and ue.empresa_id=ew_obras_exclusoes_historico.empresa_id
    and ue.perfil in ('administrador','gerenciador') and ul.ativo and ul.excluido_em is null
  )
);

create or replace function public.ew_verificar_exclusao_obra(p_obra_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_obra public.obras%rowtype;v_uid uuid:=auth.uid();
 v_liberacoes integer;v_qtd_liberada integer;v_qtd_fabricada integer;
 v_lotes integer;v_planos integer;v_romaneios integer;v_itens_romaneio integer;
 v_saidas integer;v_movimentos integer;v_esquadrias integer;v_referencias_externas integer;
 v_estoques integer;v_cem integer;v_motivos text[]:=array[]::text[];
begin
 perform public.ew_exigir_sessao_atual();
 if p_obra_id is null then raise exception 'Selecione uma obra.';end if;
 select * into v_obra from public.obras where id=p_obra_id;
 if not found then raise exception 'Obra não encontrada no banco.';end if;
 if v_uid is null or not exists (
   select 1 from public.usuarios_empresas ue join public.usuarios_login ul
     on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
   where ue.usuario_id=v_uid and ue.empresa_id=v_obra.empresa_id
     and ue.perfil in ('administrador','gerenciador')
     and ul.perfil=ue.perfil and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem gerenciar exclusão de obras.';end if;
 select count(*) into v_esquadrias from public.esquadrias e where e.obra_id=p_obra_id;
 select count(*) into v_liberacoes from public.liberacoes_corte l
   join public.esquadrias e on e.id=l.esquadria_id where e.obra_id=p_obra_id;
 select coalesce(sum(e.qtd_liberada),0),coalesce(sum(e.qtd_fabricada),0)
 into v_qtd_liberada,v_qtd_fabricada from public.esquadrias e where e.obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes where obra_id=p_obra_id;
 select count(*) into v_planos from public.ew_planos_liberados where obra_id=p_obra_id;
 select count(*) into v_romaneios from public.romaneios where obra_id=p_obra_id;
 select count(*) into v_itens_romaneio from public.romaneios_itens ri
  join public.esquadrias e on ri.esquadria_id=e.id where e.obra_id=p_obra_id;
 select count(*) into v_saidas from public.saidas_producao s
  join public.esquadrias e on s.esquadria_id=e.id where e.obra_id=p_obra_id;
 select count(*) into v_movimentos from public.ew_estoque_obras_movimentos where obra_id=p_obra_id;
 select count(*) into v_referencias_externas from (
  select a.id from public.classificacoes_tipologias_auditoria a
   join public.esquadrias e on e.id=a.esquadria_referencia_id
   where e.obra_id=p_obra_id and a.obra_id<>p_obra_id
  union all
  select r.id from public.esquadrias_descricoes_revisoes r
   join public.esquadrias e on e.id=r.esquadria_referencia_id
   where e.obra_id=p_obra_id and r.obra_id<>p_obra_id
 ) x;
 select count(*) into v_estoques from public.ew_estoques_locais where obra_id=p_obra_id;
 select count(*) into v_cem from public.ew_cem_obras_materiais where obra_id=p_obra_id;
 if v_liberacoes>0 or v_lotes>0 or v_planos>0 or v_qtd_liberada>0
   then v_motivos:=array_append(v_motivos,'A obra tem liberações para corte registradas.');end if;
 if v_qtd_fabricada>0 or v_saidas>0
   then v_motivos:=array_append(v_motivos,'A obra tem fabricação ou saída de produção registrada.');end if;
 if v_romaneios>0 or v_itens_romaneio>0
   then v_motivos:=array_append(v_motivos,'A obra tem romaneios (inclusive cancelados).');end if;
 if v_movimentos>0
   then v_motivos:=array_append(v_motivos,'A obra tem movimentações de estoque (inclusive ajustes ou estornos).');end if;
 if v_referencias_externas>0
   then v_motivos:=array_append(v_motivos,'Há registros de outras obras vinculados às esquadrias desta obra.');end if;
 return jsonb_build_object(
   'permitido',cardinality(v_motivos)=0,
   'obra_id',v_obra.id,'nome',v_obra.nome,'codigo',v_obra.codigo,
   'motivos',to_jsonb(v_motivos),
   'resumo',jsonb_build_object('esquadrias',v_esquadrias,'liberacoes',v_liberacoes,
      'unidades_liberadas',v_qtd_liberada,'fabricadas',v_qtd_fabricada,
      'lotes_cem',v_lotes,'planos_liberados',v_planos,
      'saidas_producao',v_saidas,'romaneios',v_romaneios,
      'itens_romaneio',v_itens_romaneio,'movimentos_estoque',v_movimentos,
      'estoques_cadastrados',v_estoques,'materiais_espelho_cem',v_cem,
      'referencias_externas',v_referencias_externas)
 );
end;$$;
revoke all on function public.ew_verificar_exclusao_obra(uuid) from public,anon;
grant execute on function public.ew_verificar_exclusao_obra(uuid) to authenticated;

create or replace function public.ew_excluir_obra_sem_operacoes(
 p_obra_id uuid,p_confirmacao text,p_motivo text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_obra public.obras%rowtype;v_ver jsonb;
 v_codigo text;v_motivo text:=btrim(coalesce(p_motivo,''));v_reg public.ew_obras_exclusoes_historico%rowtype;
 v_afetadas integer;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_obra_id is null or p_operacao_id is null then
   raise exception 'Usuário, obra ou identificador inválido.';end if;
 if char_length(v_motivo) not between 8 and 300
   then raise exception 'Informe um motivo de 8 a 300 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_reg from public.ew_obras_exclusoes_historico
  where operacao_id=p_operacao_id;
 if found then
   if v_reg.obra_excluida_id<>p_obra_id or v_reg.excluido_por<>v_uid then
      raise exception 'Este identificador já foi usado em outra operação.';end if;
   return jsonb_build_object('excluida',true,'repetida',true,'nome',v_reg.obra_nome,
      'codigo',v_reg.obra_codigo,'resumo',v_reg.resumo);
 end if;
 select * into v_obra from public.obras where id=p_obra_id for update;
 if not found then raise exception 'Obra não encontrada: ela pode já ter sido removida.';end if;
 -- Bloqueia alterações nas esquadrias enquanto confere as dependências.
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 v_ver:=public.ew_verificar_exclusao_obra(p_obra_id);
 if not (v_ver->>'permitido')::boolean then
   raise exception 'EXCLUSAO_BLOQUEADA: %',array_to_string(
     array(select jsonb_array_elements_text(v_ver->'motivos')), ' ');
 end if;
 v_codigo:=coalesce(nullif(btrim(v_obra.codigo),''),v_obra.nome);
 if upper(btrim(coalesce(p_confirmacao,'')))<>upper(v_codigo) then
   raise exception 'Confirmação incorreta: digite exatamente o código da obra.';end if;

 -- Apaga somente dados vinculados à obra, nunca os bancos mestres.
 delete from public.esquadrias_saida_config c using public.esquadrias e
  where c.esquadria_id=e.id and e.obra_id=p_obra_id;
 delete from public.classificacoes_tipologias_auditoria where obra_id=p_obra_id;
 delete from public.esquadrias_descricoes_revisoes where obra_id=p_obra_id;
 delete from public.ew_cem_importacoes_materiais where obra_id=p_obra_id;
 delete from public.ew_cem_obras_materiais where obra_id=p_obra_id;
 delete from public.ew_estoque_importacoes_cem where obra_id=p_obra_id;
 delete from public.ew_estoques_locais where obra_id=p_obra_id;
 delete from public.esquadrias where obra_id=p_obra_id;
 delete from public.obras where id=p_obra_id;
 get diagnostics v_afetadas=row_count;
 if v_afetadas<>1 then raise exception 'Falha ao excluir obra. Operação cancelada.';end if;
 insert into public.ew_obras_exclusoes_historico
 (operacao_id,empresa_id,obra_excluida_id,obra_nome,obra_codigo,motivo,resumo,excluido_por)
 values(p_operacao_id,v_obra.empresa_id,p_obra_id,v_obra.nome,v_obra.codigo,
    v_motivo,v_ver->'resumo',v_uid);
 return jsonb_build_object('excluida',true,'repetida',false,'nome',v_obra.nome,
  'codigo',v_obra.codigo,'resumo',v_ver->'resumo');
end;$$;
revoke all on function public.ew_excluir_obra_sem_operacoes(uuid,text,text,uuid) from public,anon;
grant execute on function public.ew_excluir_obra_sem_operacoes(uuid,text,text,uuid) to authenticated;
