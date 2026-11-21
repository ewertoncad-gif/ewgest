-- Rollback das funções novas da issue #31 (não reverte lançamentos de notas/estoque).
-- Usar somente após inspeção de dependências e autorização na instância correspondente.
drop function if exists public.ew_quantidades_recebidas_obra(uuid,uuid);
drop function if exists public.ew_receber_despesa_almox(uuid,uuid,text,numeric,text,text,date,text,uuid);
drop function if exists public.ew_receber_materiais_almox(uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid);
drop function if exists public.ew_gerenciar_cadastro_auxiliar(uuid,text,uuid,text,text);

-- Funções adicionais da v45.1: usar somente após conferir dependências.
drop function if exists public.ew_receber_despesa_com_itens_almox(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb);
drop function if exists public.ew_excluir_cadastro_tecnico_sem_vinculo(uuid,text,uuid);
drop function if exists public.ew_renomear_fabricante_sem_vinculo(uuid,uuid,text);
