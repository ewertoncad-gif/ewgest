
-- Saídas lançadas manualmente, sem romaneio, também precisam de reversão documentada.
alter table public.ew_auditoria_operacoes drop constraint if exists ew_auditoria_operacoes_acao_check;
alter table public.ew_auditoria_operacoes add constraint ew_auditoria_operacoes_acao_check
 check (acao in ('CANCELAR_ROMANEIO','CANCELAR_SAIDAS_AVULSAS',
 'CANCELAR_LIBERACOES','ESTORNAR_ESTOQUE','ARQUIVAR_OBRA'));

create or replace function public.ew_cancelar_saidas_avulsas_obra(
 p_obra_id uuid,p_motivo text
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_total int;v_details jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 10 and 400 then raise exception 'Motivo obrigatório de 10 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas ue join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_ob.empresa_id
  and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
  and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Sem permissão para cancelar saídas avulsas.';end if;
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 if exists(select 1 from public.romaneios r where r.obra_id=p_obra_id and r.status<>'cancelado')
 then raise exception 'Cancele os romaneios antes de estornar saídas avulsas.';end if;
 -- Não permitir operação aqui sobre saída ligada a qualquer romaneio.
 if exists(select 1 from public.saidas_producao s
  join public.esquadrias e on e.id=s.esquadria_id
  where e.obra_id=p_obra_id and s.cancelado_em is null
  and exists(select 1 from public.romaneios_itens ri where ri.saida_producao_id=s.id))
 then raise exception 'Existem saídas vinculadas a romaneios com estorno pendente. Solicite conferência técnica.';end if;
 select count(*),coalesce(jsonb_agg(jsonb_build_object('id',s.id,'esquadria_id',s.esquadria_id,
  'tipo',s.tipo,'quantidade',s.quantidade,'data_saida',s.data_saida,
  'registrada_em',s.registrada_em,'usuario_original',s.usuario_id)),'[]'::jsonb)
 into v_total,v_details
 from public.saidas_producao s join public.esquadrias e on e.id=s.esquadria_id
 where e.obra_id=p_obra_id and s.cancelado_em is null;
 update public.saidas_producao s set cancelado_em=now(),cancelado_por=v_uid
 from public.esquadrias e
 where s.esquadria_id=e.id and e.obra_id=p_obra_id and s.cancelado_em is null;
 if v_total>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_SAIDAS_AVULSAS',
   v_motivo,jsonb_build_object('saidas_canceladas',v_total,'saidas_originais',v_details));
 end if;
 return jsonb_build_object('canceladas',v_total,'historico_preservado',true);
end;$$;
revoke all on function public.ew_cancelar_saidas_avulsas_obra(uuid,text) from public,anon;
grant execute on function public.ew_cancelar_saidas_avulsas_obra(uuid,text) to authenticated;
