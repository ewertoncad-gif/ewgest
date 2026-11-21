-- Rollback das funções novas da issue #31 (não reverte lançamentos de notas/estoque).
-- Usar somente após inspeção de dependências e autorização na instância correspondente.
drop function if exists public.ew_quantidades_recebidas_obra(uuid,uuid);
drop function if exists public.ew_receber_despesa_almox(uuid,uuid,text,numeric,text,text,date,text,uuid);
drop function if exists public.ew_receber_materiais_almox(uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid);
drop function if exists public.ew_gerenciar_cadastro_auxiliar(uuid,text,uuid,text,text);
