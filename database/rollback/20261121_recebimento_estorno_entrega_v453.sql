-- EMERGÊNCIA v45.3 — rollback NÃO DESTRUTIVO.
-- Preserva todas as NF-e, entradas, transferências, saídas, liberações e registros
-- de estorno. Não restaurar automaticamente o modo antigo de baixa na liberação:
-- se houver relatórios pendentes, tal reversão desorganizaria o saldo.
-- Aplicar apenas com diagnóstico e responsável autorizado.
begin;
revoke execute on function public.ew_estornar_recebimento_nfe(uuid,uuid,text,uuid) from authenticated;
revoke execute on function public.ew_confirmar_entrega_producao(uuid,uuid,text,uuid,uuid) from authenticated;
revoke execute on function public.ew_liberar_plano_corte_revisado(uuid,integer,date,text,jsonb,text,text,uuid) from authenticated;
revoke execute on function public.ew_liberar_lote_cem(uuid,date,text,jsonb,jsonb,text,uuid) from authenticated;
commit;
-- Reabilitar operações individuais somente após reconciliação do estoque.
-- NÃO remover colunas estornado_em / entregue_em, índices ou histórico.
-- NÃO apagar movimentos de estoque nem repetir baixas antigas.
