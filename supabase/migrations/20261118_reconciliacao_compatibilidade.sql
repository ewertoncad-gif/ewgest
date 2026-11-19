
-- Compatibilidade com versões anteriores: impedir qualquer exclusão física por RPC legado.
create or replace function public.ew_verificar_exclusao_obra(p_obra_id uuid)
returns jsonb language sql security definer set search_path to '' as $$
 select public.ew_inspecionar_reversao_obra(p_obra_id);
$$;
create or replace function public.ew_excluir_obra_sem_operacoes(
 p_obra_id uuid,p_confirmacao text,p_motivo text,p_operacao_id uuid
) returns jsonb language sql security definer set search_path to '' as $$
 select public.ew_arquivar_obra_reconciliada(p_obra_id,p_confirmacao,p_motivo,p_operacao_id);
$$;
revoke all on function public.ew_verificar_exclusao_obra(uuid) from public,anon;
grant execute on function public.ew_verificar_exclusao_obra(uuid) to authenticated;
revoke all on function public.ew_excluir_obra_sem_operacoes(uuid,text,text,uuid) from public,anon;
grant execute on function public.ew_excluir_obra_sem_operacoes(uuid,text,text,uuid) to authenticated;
