-- SOMENTE ambiente ewgest-restauracao-teste. NÃO APLICAR EM PRODUÇÃO.
-- Reconstitui estrutura ausente do snapshot de testes, sem copiar registros reais.
create table if not exists public.ew_fornecedores (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 nome text not null,
 ativo boolean not null default true
);
create unique index if not exists ew_fornecedores_teste_unq_nome on public.ew_fornecedores(empresa_id,nome);
alter table public.ew_fornecedores enable row level security;
drop policy if exists ew_fornecedores_teste_pertence on public.ew_fornecedores;
create policy ew_fornecedores_teste_pertence on public.ew_fornecedores for select to authenticated
 using(exists(select 1 from public.usuarios_empresas ue
  where ue.usuario_id=(select auth.uid()) and ue.empresa_id=ew_fornecedores.empresa_id));

create table if not exists public.ew_cem_obras_materiais (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid not null references public.obras(id),
 tipo text not null check(tipo in ('perfil','acessorio')),
 perfil_id uuid references public.ew_perfis(id),
 acessorio_id uuid references public.ew_acessorios(id),
 variacao_id uuid not null references public.ew_materiais_variacoes(id),
 linhas_calculo integer not null default 0,
 quantidade_prevista numeric,
 unidade_prevista text,
 comprimento_total_m numeric,
 barras_planejadas jsonb check(barras_planejadas is null or jsonb_typeof(barras_planejadas)='array'),
 unique (empresa_id,obra_id,variacao_id)
);
alter table public.ew_cem_obras_materiais enable row level security;
drop policy if exists ew_cem_obras_materiais_teste_pertence on public.ew_cem_obras_materiais;
create policy ew_cem_obras_materiais_teste_pertence on public.ew_cem_obras_materiais for select to authenticated
 using(exists(select 1 from public.usuarios_empresas ue
  where ue.usuario_id=(select auth.uid()) and ue.empresa_id=ew_cem_obras_materiais.empresa_id));

create table if not exists public.ew_materiais_alias(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 tipo text,
 perfil_id uuid references public.ew_perfis(id),
 acessorio_id uuid references public.ew_acessorios(id),
 fabricante text,
 codigo_alternativo text
);
alter table public.ew_materiais_alias enable row level security;
-- Sem grant de leitura por cliente: o fixture só serve à checagem interna.

create table if not exists public.ew_estoque_movimentacoes(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 variacao_id uuid not null references public.ew_materiais_variacoes(id),
 quantidade_delta numeric
);
alter table public.ew_estoque_movimentacoes enable row level security;

create table if not exists public.fabricantes(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 nome text not null
);
alter table public.fabricantes enable row level security;

create table if not exists public.tipologias(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 codigo text not null,
 descricao text not null,
 fabricante text,
 tipologia_principal_id uuid references public.tipologias(id)
);
alter table public.tipologias enable row level security;

alter table public.usuarios_empresas drop constraint if exists usuarios_empresas_perfil_check;
alter table public.usuarios_empresas add constraint usuarios_empresas_perfil_check check(
 perfil in ('administrador','gerenciador','supervisor','tecnico','consulta','almoxarife')
);
