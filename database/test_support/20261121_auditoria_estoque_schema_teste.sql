-- SOMENTE projeto de testes: auditoria ausente no snapshot antigo.
create table if not exists public.ew_auditoria_operacoes(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid,
 obra_nome text not null default '',
 obra_codigo text,
 usuario_id uuid not null references auth.users(id),
 acao text not null,
 referencia_id uuid,
 operacao_id uuid,
 motivo text not null default '',
 detalhes jsonb not null default '{}'::jsonb,
 criado_em timestamptz not null default now()
);
alter table public.ew_auditoria_operacoes enable row level security;
revoke all on public.ew_auditoria_operacoes from anon, authenticated;