-- EWGEST #34: catálogo e livro de estoque físico de vidros / outros insumos.
-- Sem migração de saldos históricos: notas anteriores à implantação precisam de
-- inventário inicial conferido, não podem ser convertidas automaticamente.
create table if not exists public.ew_insumos_catalogo (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id) on delete restrict,
 categoria text not null check (categoria in ('vidros','outros')),
 descricao text not null,
 unidade text not null check (unidade in ('PC','UN','M2','MT','KG','CX','CJ','PR')),
 ativo boolean not null default true,
 criado_por uuid references auth.users(id) on delete restrict,
 criado_em timestamptz not null default now(),
 constraint ew_insumos_descricao_valida check (
  char_length(descricao) between 2 and 500 and descricao=upper(btrim(descricao))),
 unique (empresa_id,id),
 unique (empresa_id,categoria,descricao,unidade)
);
create table if not exists public.ew_insumos_movimentos (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null,
 obra_id uuid not null,
 insumo_id uuid not null,
 local_estoque text not null,
 quantidade_delta numeric(16,3) not null check (quantidade_delta<>0),
 origem text not null check (origem in ('RECEBIMENTO','TRANSFERENCIA','ESTORNO')),
 despesa_item_id uuid references public.ew_obra_despesas_itens(id) on delete restrict,
 operacao_id uuid not null,
 transferencia_id uuid,
 estorno_de_id uuid references public.ew_insumos_movimentos(id) on delete restrict,
 observacao text not null default '',
 usuario_id uuid not null references auth.users(id) on delete restrict,
 criado_em timestamptz not null default now(),
 foreign key (empresa_id,obra_id) references public.obras(empresa_id,id) on delete restrict,
 foreign key (empresa_id,insumo_id) references public.ew_insumos_catalogo(empresa_id,id) on delete restrict,
 unique(empresa_id,id),
 constraint ew_insumos_mov_origem_sinal check (
  (origem='RECEBIMENTO' and quantidade_delta>0 and despesa_item_id is not null)
  or (origem in ('TRANSFERENCIA','ESTORNO') and despesa_item_id is null)
 ),
 constraint ew_insumos_mov_local_valido check (char_length(btrim(local_estoque)) between 3 and 80)
);
create unique index if not exists ew_insumo_entrada_item_unico
 on public.ew_insumos_movimentos(despesa_item_id) where origem='RECEBIMENTO';
create unique index if not exists ew_insumo_estorno_unico
 on public.ew_insumos_movimentos(estorno_de_id) where estorno_de_id is not null;
create index if not exists ew_insumo_saldo_local_idx
 on public.ew_insumos_movimentos(empresa_id,obra_id,insumo_id,local_estoque);
create index if not exists ew_insumo_transf_id_idx
 on public.ew_insumos_movimentos(empresa_id,operacao_id);

alter table public.ew_insumos_catalogo enable row level security;
alter table public.ew_insumos_movimentos enable row level security;
-- Nenhuma política pública: leitura e escrita exclusivamente por RPCs autenticadas
-- que conferem empresa, sessão e perfil. A role anon não tem acesso.
revoke all on table public.ew_insumos_catalogo from anon, authenticated;
revoke all on table public.ew_insumos_movimentos from anon, authenticated;

create or replace function public.ew_insumos_catalogo_listar(p_empresa_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid and u.perfil in ('administrador','almoxarife')
 ) then raise exception 'Sem acesso ao catálogo de insumos.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'categoria',c.categoria,'descricao',c.descricao,
  'unidade',c.unidade,'ativo',c.ativo) order by c.categoria,c.descricao,c.unidade),'[]'::jsonb)
 into v_result
 from public.ew_insumos_catalogo c where c.empresa_id=p_empresa_id;
 return v_result;
end
$func$;

create or replace function public.ew_insumos_saldos_obra(p_empresa_id uuid,p_obra_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid and u.perfil in ('administrador','almoxarife')
 ) or not exists(select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id)
 then raise exception 'Sem acesso aos saldos desta obra.';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'insumo_id',s.insumo_id,'categoria',s.categoria,'descricao',s.descricao,
  'unidade',s.unidade,'galpao',s.local_estoque,'saldo',s.saldo)
  order by s.categoria,s.descricao,s.unidade,s.local_estoque),'[]'::jsonb)
 into v_result
 from (
  select m.insumo_id,c.categoria,c.descricao,c.unidade,m.local_estoque,
    sum(m.quantidade_delta) saldo
  from public.ew_insumos_movimentos m join public.ew_insumos_catalogo c
    on c.id=m.insumo_id and c.empresa_id=m.empresa_id
  where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id
  group by m.insumo_id,c.categoria,c.descricao,c.unidade,m.local_estoque
 ) s;
 return v_result;
end
$func$;

create or replace function public.ew_insumo_gerenciar_catalogo(
 p_empresa_id uuid,p_acao text,p_id uuid default null,p_categoria text default null,
 p_descricao text default null,p_unidade text default null
) returns jsonb language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_nome text;v_item public.ew_insumos_catalogo%rowtype;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid and u.perfil='administrador'
 ) then raise exception 'Somente ADM gerencia catálogo de insumos.';end if;
 if p_acao not in ('criar','editar','excluir') then raise exception 'Ação inválida.';end if;
 if p_acao<>'criar' then
  select * into v_item from public.ew_insumos_catalogo where empresa_id=p_empresa_id and id=p_id for update;
  if not found then raise exception 'Cadastro não encontrado nesta empresa.';end if;
  if exists(select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id and m.insumo_id=p_id)
  then raise exception 'Este material possui movimentações/histórico. Não pode editar ou excluir.';end if;
 end if;
 if p_acao='excluir' then
   delete from public.ew_insumos_catalogo where empresa_id=p_empresa_id and id=p_id;
   return jsonb_build_object('excluido',true,'id',p_id);
 end if;
 v_nome:=upper(btrim(pg_catalog.regexp_replace(coalesce(p_descricao,''),'\s+',' ','g')));
 if length(v_nome) not between 2 and 500 or p_categoria not in ('vidros','outros')
  or p_unidade not in ('PC','UN','M2','MT','KG','CX','CJ','PR')
 then raise exception 'Tipo, descrição ou unidade inválidos.';end if;
 if p_acao='criar' then
  insert into public.ew_insumos_catalogo(empresa_id,categoria,descricao,unidade,criado_por)
    values(p_empresa_id,p_categoria,v_nome,p_unidade,v_uid) returning id into p_id;
 else
  update public.ew_insumos_catalogo set categoria=p_categoria,descricao=v_nome,unidade=p_unidade
   where empresa_id=p_empresa_id and id=p_id;
 end if;
 return jsonb_build_object('id',p_id,'acao',p_acao);
exception when unique_violation then
 raise exception 'Este material e unidade já estão cadastrados.';
when foreign_key_violation then
 raise exception 'Cadastro usado por outro registro; exclusão bloqueada.';
end
$func$;

revoke all on function public.ew_insumos_catalogo_listar(uuid) from public;
revoke all on function public.ew_insumos_saldos_obra(uuid,uuid) from public;
revoke all on function public.ew_insumo_gerenciar_catalogo(uuid,text,uuid,text,text,text) from public;
revoke execute on function public.ew_insumos_catalogo_listar(uuid) from anon;
revoke execute on function public.ew_insumos_saldos_obra(uuid,uuid) from anon;
revoke execute on function public.ew_insumo_gerenciar_catalogo(uuid,text,uuid,text,text,text) from anon;
grant execute on function public.ew_insumos_catalogo_listar(uuid) to authenticated;
grant execute on function public.ew_insumos_saldos_obra(uuid,uuid) to authenticated;
grant execute on function public.ew_insumo_gerenciar_catalogo(uuid,text,uuid,text,text,text) to authenticated;
