-- EWGEST v45.4 — rollback nao destrutivo.
-- Remove apenas a automacao de novos romaneios e acesso da interface.
-- Preserva numeros, documentos, vinculos, auditorias e movimentacoes de estoque.
begin;
drop trigger if exists ew_gera_romaneio_transferencia on public.ew_estoque_obras_movimentos;
revoke execute on function public.ew_romaneios_transferencia_listar(uuid) from authenticated,anon;
revoke execute on function public.ew_romaneio_transferencia_salvar(uuid,uuid,date,text,text,text,jsonb) from authenticated,anon;
revoke execute on function public.ew_romaneios_transferencia_juntar(uuid,uuid,uuid[]) from authenticated,anon;
revoke execute on function public.ew_romaneio_transferencia_emitir(uuid,uuid) from authenticated,anon;
commit;
