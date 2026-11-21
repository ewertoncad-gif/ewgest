-- SOMENTE ewgest-restauracao-teste: estrutura ausente no snapshot de homologação.
-- Não aplicar em ewgest-producao.
create table if not exists public.usuarios_login (
 usuario_id uuid primary key references auth.users(id),
 empresa_id uuid not null references public.empresas(id),
 perfil text not null,
 ativo boolean not null default true,
 excluido_em timestamptz,
 nome text,
 login text
);
alter table public.usuarios_login enable row level security;
revoke all on public.usuarios_login from anon,authenticated;
alter table public.ew_estoque_obras_movimentos
 add column if not exists transferencia_id uuid,
 add column if not exists estorno_de_id uuid references public.ew_estoque_obras_movimentos(id),
 add column if not exists criado_em timestamptz not null default now(),
 add column if not exists liberacao_id uuid;
create unique index if not exists ew_estoque_test_estorno_unico
 on public.ew_estoque_obras_movimentos(estorno_de_id)
 where estorno_de_id is not null;
alter table public.ew_nfe_recebimentos
 add column if not exists criado_em timestamptz not null default now();
