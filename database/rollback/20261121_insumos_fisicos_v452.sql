-- EWGEST #34: rollback emergencial NÃO DESTRUTIVO da v45.2.
-- Preserva notas, movimentos, catálogo, histórico e saldos físicos.
-- Aplicar somente em emergência, com autorização e diagnóstico.
-- Reverter a interface via PR/commit no GitHub; não apagar tabelas com lançamentos.
begin;
revoke execute on function public.ew_insumos_receber(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb,text) from authenticated;
revoke execute on function public.ew_insumos_transferir(uuid,uuid,uuid,uuid,text,text,numeric,text,uuid) from authenticated;
revoke execute on function public.ew_insumos_estornar_transferencia(uuid,uuid,text) from authenticated;
revoke execute on function public.ew_insumos_cancelar_nota(uuid,uuid,text) from authenticated;
revoke execute on function public.ew_insumo_gerenciar_catalogo(uuid,text,uuid,text,text,text) from authenticated;
-- Consultas permanecem disponíveis até resolver o incidente.
commit;
-- NÃO dar DROP nas tabelas ew_insumos_catalogo e ew_insumos_movimentos.
-- Para reativar após correção revisada, restaurar GRANT EXECUTE individualmente.
