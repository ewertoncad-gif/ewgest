-- APENAS projeto ewgest-restauracao-teste.
-- Snapshot antigo não tem tabelas de liberação; cria o mínimo sem cópia de dados reais.
create table if not exists public.liberacoes_corte (
 id uuid primary key default gen_random_uuid(),
 esquadria_id uuid not null references public.esquadrias(id),
 quantidade integer not null,
 data_liberacao date not null,
 usuario_id uuid,
 fabrica text,
 cancelado_em timestamptz
);
create table if not exists public.ew_planos_liberados(
 id uuid primary key default gen_random_uuid(),
 operacao_id uuid not null unique,
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid not null references public.obras(id),
 esquadria_id uuid not null references public.esquadrias(id),
 liberacao_id uuid not null references public.liberacoes_corte(id),
 fonte text not null,
 arquivo_nome text,
 materiais_confirmados jsonb not null default '[]'::jsonb,
 data_liberacao date not null,
 usuario_id uuid not null references auth.users(id),
 criado_em timestamptz not null default now()
);
create table if not exists public.ew_liberacoes_lotes(
 id uuid primary key default gen_random_uuid(),
 operacao_id uuid not null unique,
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid not null references public.obras(id),
 data_liberacao date not null,
 fabrica text not null,
 arquivo_nome text not null,
 itens_confirmados jsonb not null default '[]'::jsonb,
 materiais_confirmados jsonb not null default '[]'::jsonb,
 criado_por uuid not null references auth.users(id),
 criado_em timestamptz not null default now(),
 cancelado_em timestamptz,
 cancelado_por uuid,
 motivo_cancelamento text
);
alter table public.ew_estoque_obras_movimentos add column if not exists lote_id uuid references public.ew_liberacoes_lotes(id);
alter table public.liberacoes_corte enable row level security;
alter table public.ew_planos_liberados enable row level security;
alter table public.ew_liberacoes_lotes enable row level security;
revoke all on public.liberacoes_corte,public.ew_planos_liberados,public.ew_liberacoes_lotes from anon,authenticated;
-- Apenas stub para o teste isolado do comportamento de baixa técnica, não para produção.
create or replace function public.registrar_liberacao_corte_fabrica(
 p_esquadria_id uuid,p_quantidade integer,p_data_liberacao date,p_fabrica text
) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_esq public.esquadrias%rowtype;v_lib uuid;
begin
 select * into v_esq from public.esquadrias where id=p_esquadria_id for update;
 if not found or p_quantidade<=0 or p_quantidade>v_esq.quantidade-v_esq.qtd_liberada
 then raise exception 'Quantidade indisponível no teste.';end if;
 insert into public.liberacoes_corte(esquadria_id,quantidade,data_liberacao,usuario_id,fabrica)
 values(p_esquadria_id,p_quantidade,p_data_liberacao,auth.uid(),p_fabrica) returning id into v_lib;
 update public.esquadrias set qtd_liberada=qtd_liberada+p_quantidade where id=p_esquadria_id;
 return jsonb_build_object('registro_id',v_lib);
end
$f$;
revoke all on function public.registrar_liberacao_corte_fabrica(uuid,integer,date,text) from public;
grant execute on function public.registrar_liberacao_corte_fabrica(uuid,integer,date,text) to authenticated;
