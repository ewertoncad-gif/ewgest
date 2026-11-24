-- EWGEST v46.21 | PROPOSTA (não aplicada em produção)
-- Compras: solicitação -> cotação -> pedido -> recebimento físico parcial.
-- Estoque da empresa sem obra em ledger separado. Não duplica despesas NF-e.
-- Pré-requisito: homologar estorno, conciliação NF e transferências antes de publicar.
begin;

insert into public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) values
 ('compras.consultar','Compras','Consultar solicitações, cotações e pedidos',29),
 ('compras.solicitar','Compras','Criar solicitações de compras',30),
 ('compras.cotar','Compras','Registrar cotações',31),
 ('compras.pedir','Compras','Emitir pedidos de compra',32),
 ('compras.receber','Compras','Receber pedidos no estoque',33),
 ('estoque.gerenciar_locais','Estoque','Cadastrar locais de estoque da empresa',34),
 ('compras.consultar_valores','Compras','Consultar valores e cotações de fornecedores',35)
on conflict (chave) do nothing;

insert into public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
select n.empresa_id,n.nivel,p.chave,
 case when n.nivel in (1,2) then true
      when p.chave='compras.consultar' and n.nivel in (3,4,5,6,7) then true
      when p.chave='compras.solicitar' and n.nivel=3 then true
      when p.chave='compras.receber' and n.nivel=4 then true
      when p.chave in ('compras.cotar','compras.pedir','compras.consultar_valores') and n.nivel=5 then true
      else false end
from public.ew_niveis_acesso n
join public.ew_permissoes_catalogo p on p.chave in
 ('compras.consultar','compras.solicitar','compras.cotar','compras.pedir','compras.receber','estoque.gerenciar_locais','compras.consultar_valores')
on conflict (empresa_id,nivel,chave) do nothing;

create table if not exists public.ew_compras_locais_empresa(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 nome text not null check(length(btrim(nome)) between 3 and 100),
 ativo boolean not null default true,
 criado_em timestamptz not null default now(),
 criado_por uuid not null references auth.users(id)
);
create unique index if not exists ew_compras_local_empresa_nome_uk
 on public.ew_compras_locais_empresa(empresa_id,upper(btrim(nome)));

create table if not exists public.ew_compras_solicitacoes(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid references public.obras(id),
 local_empresa_id uuid references public.ew_compras_locais_empresa(id),
 operacao_id uuid not null unique,
 status text not null default 'ABERTA' check(status in ('ABERTA','PEDIDO_GERADO','CANCELADA')),
 itens jsonb not null check(jsonb_typeof(itens)='array'),
 observacoes text not null default '',
 criado_em timestamptz not null default now(),
 criado_por uuid not null references auth.users(id),
 constraint ew_compras_solic_destino check((obra_id is null) <> (local_empresa_id is null))
);
create index if not exists ew_compras_solic_emp_idx on public.ew_compras_solicitacoes(empresa_id,criado_em desc);

create table if not exists public.ew_compras_cotacoes(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 solicitacao_id uuid not null references public.ew_compras_solicitacoes(id),
 fornecedor_id uuid not null references public.ew_fornecedores(id),
 operacao_id uuid not null unique,
 itens jsonb not null check(jsonb_typeof(itens)='array'),
 total_centavos bigint not null check(total_centavos>=0),
 criado_em timestamptz not null default now(),
 criado_por uuid not null references auth.users(id)
);
create index if not exists ew_compras_cot_solic_idx on public.ew_compras_cotacoes(solicitacao_id);

create table if not exists public.ew_compras_pedidos(
 id uuid primary key default gen_random_uuid(),
 numero bigint generated always as identity unique,
 empresa_id uuid not null references public.empresas(id),
 solicitacao_id uuid not null unique references public.ew_compras_solicitacoes(id),
 cotacao_id uuid not null unique references public.ew_compras_cotacoes(id),
 fornecedor_id uuid not null references public.ew_fornecedores(id),
 obra_id uuid references public.obras(id),
 local_empresa_id uuid references public.ew_compras_locais_empresa(id),
 operacao_id uuid not null unique,
 itens jsonb not null check(jsonb_typeof(itens)='array'),
 total_centavos bigint not null check(total_centavos>=0),
 status text not null default 'ABERTO' check(status in ('ABERTO','PARCIAL','CONCLUIDO','CANCELADO')),
 criado_em timestamptz not null default now(),
 criado_por uuid not null references auth.users(id),
 constraint ew_compras_pedido_destino check((obra_id is null) <> (local_empresa_id is null))
);
create index if not exists ew_compras_pedido_emp_idx on public.ew_compras_pedidos(empresa_id,criado_em desc);

create table if not exists public.ew_compras_recebimentos(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 pedido_id uuid not null references public.ew_compras_pedidos(id),
 galpao text not null,
 operacao_id uuid not null unique,
 itens jsonb not null check(jsonb_typeof(itens)='array'),
 criado_em timestamptz not null default now(),
 criado_por uuid not null references auth.users(id),
 estornado_em timestamptz,
 estornado_por uuid references auth.users(id),
 estorno_motivo text,
 estorno_operacao_id uuid unique
);
create index if not exists ew_compras_receb_pedido_idx on public.ew_compras_recebimentos(pedido_id);

-- Ledger isolado dos locais independentes da empresa, sem obra fictícia.
-- O ledger da obra permanece ew_estoque_obras_movimentos (origem='COMPRA').
create table if not exists public.ew_compras_estoque_empresa(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 local_empresa_id uuid not null references public.ew_compras_locais_empresa(id),
 recebimento_id uuid references public.ew_compras_recebimentos(id),
 chave text,
 variacao_id uuid not null references public.ew_materiais_variacoes(id),
 galpao text not null,
 unidade text not null,
 comprimento_mm integer,
 quantidade_delta numeric(16,3) not null check(quantidade_delta<>0),
 origem text not null default 'RECEBIMENTO_PEDIDO' check(origem in ('RECEBIMENTO_PEDIDO','ESTORNO_PEDIDO','TRANSFERENCIA','ESTORNO_TRANSFERENCIA')),
 operacao_id uuid not null unique default gen_random_uuid(),
 transferencia_id uuid,
 estorno_de_id uuid unique references public.ew_compras_estoque_empresa(id),
 criado_em timestamptz not null default now(),
 unique(recebimento_id,chave),
 constraint ew_compras_empresa_origem check((origem='RECEBIMENTO_PEDIDO' and recebimento_id is not null and chave is not null and quantidade_delta>0)
   or (origem<>'RECEBIMENTO_PEDIDO' and recebimento_id is null and chave is null)),
 constraint ew_compras_empresa_origem_estorno check((origem in ('ESTORNO_PEDIDO','ESTORNO_TRANSFERENCIA'))=(estorno_de_id is not null)),
 constraint ew_compras_empresa_comprimento check(
   (unidade='BARRA' and comprimento_mm between 100 and 20000 and quantidade_delta=trunc(quantidade_delta))
   or (unidade<>'BARRA' and comprimento_mm is null))
);
create index if not exists ew_compras_estoque_empresa_idx
 on public.ew_compras_estoque_empresa(empresa_id,local_empresa_id,galpao,variacao_id);

-- Uma linha de recebimento deve apontar exatamente para um movimento físico.
create table if not exists public.ew_compras_recebimentos_movimentos(
 empresa_id uuid not null references public.empresas(id),
 recebimento_id uuid not null references public.ew_compras_recebimentos(id),
 chave text not null,
 movimento_obra_id uuid unique references public.ew_estoque_obras_movimentos(id),
 movimento_empresa_id uuid unique references public.ew_compras_estoque_empresa(id),
 primary key (recebimento_id,chave),
 constraint ew_compras_vinculo_exclusivo check((movimento_obra_id is null)<>(movimento_empresa_id is null))
);
create index if not exists ew_compras_vinculos_emp_idx
 on public.ew_compras_recebimentos_movimentos(empresa_id,recebimento_id);

alter table public.ew_compras_locais_empresa enable row level security;
alter table public.ew_compras_solicitacoes enable row level security;
alter table public.ew_compras_cotacoes enable row level security;
alter table public.ew_compras_pedidos enable row level security;
alter table public.ew_compras_recebimentos enable row level security;
alter table public.ew_compras_estoque_empresa enable row level security;
alter table public.ew_compras_recebimentos_movimentos enable row level security;

create policy "ew_compras_locais_leitura" on public.ew_compras_locais_empresa
 for select to authenticated using
 (public.ew_pode(empresa_id,'estoque.consultar') or public.ew_pode(empresa_id,'compras.consultar'));
create policy "ew_compras_solic_leitura" on public.ew_compras_solicitacoes
 for select to authenticated using(public.ew_pode(empresa_id,'compras.consultar'));
create policy "ew_compras_cot_leitura" on public.ew_compras_cotacoes
 for select to authenticated using(public.ew_pode(empresa_id,'compras.consultar_valores'));
create policy "ew_compras_pedido_leitura" on public.ew_compras_pedidos
 for select to authenticated using(public.ew_pode(empresa_id,'compras.consultar_valores'));
create policy "ew_compras_receb_leitura" on public.ew_compras_recebimentos
 for select to authenticated using(public.ew_pode(empresa_id,'compras.consultar') or public.ew_pode(empresa_id,'compras.receber'));
create policy "ew_compras_estoque_leitura" on public.ew_compras_estoque_empresa
 for select to authenticated using(public.ew_pode(empresa_id,'estoque.consultar'));
create policy "ew_compras_vinculos_leitura" on public.ew_compras_recebimentos_movimentos
 for select to authenticated using(public.ew_pode(empresa_id,'compras.consultar') or public.ew_pode(empresa_id,'compras.receber'));

grant select on public.ew_compras_locais_empresa,public.ew_compras_solicitacoes,
 public.ew_compras_cotacoes,public.ew_compras_pedidos,public.ew_compras_recebimentos,
 public.ew_compras_estoque_empresa,public.ew_compras_recebimentos_movimentos to authenticated;
revoke insert,update,delete on public.ew_compras_locais_empresa,public.ew_compras_solicitacoes,
 public.ew_compras_cotacoes,public.ew_compras_pedidos,public.ew_compras_recebimentos,
 public.ew_compras_estoque_empresa,public.ew_compras_recebimentos_movimentos from anon,authenticated;

create or replace function public.ew_compras_criar_local_empresa(p_empresa_id uuid,p_nome text)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_id uuid;v_nome text:=upper(btrim(coalesce(p_nome,'')));
begin
 perform public.ew_exigir_sessao_atual();
 if not public.ew_pode(p_empresa_id,'estoque.gerenciar_locais')
 then raise exception 'Sem permissão para cadastrar locais de estoque.';end if;
 if length(v_nome) not between 3 and 100 then raise exception 'Nome inválido.';end if;
 insert into public.ew_compras_locais_empresa(empresa_id,nome,criado_por)
 values(p_empresa_id,v_nome,auth.uid()) returning id into v_id;
 return jsonb_build_object('id',v_id,'nome',v_nome);
end;$f$;

create or replace function public.ew_compras_criar_solicitacao(
 p_empresa_id uuid,p_obra_id uuid,p_local_empresa_id uuid,p_itens jsonb,p_observacoes text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_item jsonb;v_id uuid;v_prev public.ew_compras_solicitacoes%rowtype;v_var public.ew_materiais_variacoes%rowtype;
 v_q numeric;v_unit text;v_length integer;v_key text;v_seen text[]:=array[]::text[];v_clean jsonb:='[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not public.ew_pode(p_empresa_id,'compras.solicitar') then raise exception 'Sem permissão para solicitar.';end if;
 if p_operacao_id is null then raise exception 'Identificador da operação obrigatório.';end if;
 -- Isolar a tentativa idempotente por operação e por empresa.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'COMPRAS_SOLIC|'||p_operacao_id::text,38640));
 select * into v_prev from public.ew_compras_solicitacoes where operacao_id=p_operacao_id;
 if found then
  if v_prev.empresa_id<>p_empresa_id OR
     v_prev.obra_id IS DISTINCT FROM p_obra_id OR
     v_prev.local_empresa_id IS DISTINCT FROM p_local_empresa_id OR
     v_prev.itens IS DISTINCT FROM p_itens OR
     v_prev.observacoes IS DISTINCT FROM left(coalesce(p_observacoes,''),600)
  then raise exception 'Identificador de solicitação usado anteriormente para outros dados.';end if;
  return jsonb_build_object('id',v_prev.id,'repetida',true);
 end if;
 if (p_obra_id is null)=(p_local_empresa_id is null) then raise exception 'Escolha obra ou local da empresa.';end if;
 if p_obra_id is not null and not exists(
  select 1 from public.obras where id=p_obra_id and empresa_id=p_empresa_id and arquivada_em is null)
 then raise exception 'Obra inexistente ou arquivada.';end if;
 if p_local_empresa_id is not null and not exists(
  select 1 from public.ew_compras_locais_empresa where id=p_local_empresa_id and empresa_id=p_empresa_id and ativo)
 then raise exception 'Local de estoque inválido.';end if;
 if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens)<1 or jsonb_array_length(p_itens)>200
 then raise exception 'Informe de 1 a 200 itens.';end if;
 for v_item in select value from jsonb_array_elements(p_itens) loop
  v_key:=btrim(v_item->>'chave');
  if length(v_key)<1 or length(v_key)>30 or v_key=any(v_seen)
  then raise exception 'Identificador de linha repetido ou inválido.';end if;
  v_seen:=array_append(v_seen,v_key);
  select * into v_var from public.ew_materiais_variacoes
  where id=(v_item->>'variacao_id')::uuid and empresa_id=p_empresa_id and ativo;
  if not found then raise exception 'Material fora do catálogo da empresa.';end if;
  v_q:=(v_item->>'quantidade')::numeric;v_unit:=upper(btrim(v_item->>'unidade'));
  v_length:=nullif(v_item->>'comprimento_mm','')::integer;
  if v_q is null or v_q<=0 or v_q>1000000 or
    v_unit not in ('BARRA','PC','PR','CJ','UN','MT','KG') or
    (v_var.tipo='perfil' and (v_unit<>'BARRA' or v_length not between 100 and 20000)) or
    (v_var.tipo<>'perfil' and (v_unit='BARRA' or v_length is not null)) or
    (v_var.tipo='acessorio' and v_unit<>coalesce((select upper(btrim(a.unidade_item))
      from public.ew_acessorios a where a.id=v_var.acessorio_id and a.empresa_id=p_empresa_id),'')) or
    (v_unit in ('BARRA','MT','PC','PR','CJ','UN') and v_q<>trunc(v_q)) or v_q<>round(v_q,3)
  then raise exception 'Quantidade, unidade ou barra inválida.';end if;
  v_clean:=v_clean||jsonb_build_array(jsonb_build_object('chave',v_key,
   'variacao_id',v_var.id,'quantidade',v_q,'unidade',v_unit,'comprimento_mm',v_length));
 end loop;
 insert into public.ew_compras_solicitacoes
  (empresa_id,obra_id,local_empresa_id,operacao_id,itens,observacoes,criado_por)
 values(p_empresa_id,p_obra_id,p_local_empresa_id,p_operacao_id,v_clean,left(coalesce(p_observacoes,''),600),auth.uid())
 returning id into v_id;
 return jsonb_build_object('id',v_id,'repetida',false);
end;$f$;

create or replace function public.ew_compras_criar_cotacao(
 p_solicitacao_id uuid,p_fornecedor_id uuid,p_precos jsonb,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_s public.ew_compras_solicitacoes%rowtype;v_prev public.ew_compras_cotacoes%rowtype;
 v_i jsonb;v_price jsonb;v_old_prices jsonb;v_new_prices jsonb;
 v_id uuid;v_value bigint;v_total bigint:=0;v_items jsonb:='[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Operação inválida.';end if;
 select * into v_s from public.ew_compras_solicitacoes where id=p_solicitacao_id;
 if not found then raise exception 'Solicitação não encontrada.';end if;
 if not public.ew_pode(v_s.empresa_id,'compras.cotar') then raise exception 'Sem permissão para cotar.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'COMPRAS_COTACAO|'||p_operacao_id::text,38640));
 select * into v_prev from public.ew_compras_cotacoes where operacao_id=p_operacao_id;
 if found then
  select jsonb_agg(jsonb_build_object('chave',x.value->>'chave',
    'preco_unitario_centavos',(x.value->>'preco_unitario_centavos')::bigint)
    order by x.value->>'chave') into v_old_prices
  from jsonb_array_elements(v_prev.itens) x;
  select jsonb_agg(jsonb_build_object('chave',x.value->>'chave',
    'preco_unitario_centavos',(x.value->>'preco_unitario_centavos')::bigint)
    order by x.value->>'chave') into v_new_prices
  from jsonb_array_elements(p_precos) x;
  if v_prev.empresa_id<>v_s.empresa_id OR v_prev.solicitacao_id<>v_s.id
    OR v_prev.fornecedor_id<>p_fornecedor_id OR v_old_prices IS DISTINCT FROM v_new_prices
  then raise exception 'Identificador de cotação usado anteriormente para outros dados.';end if;
  return jsonb_build_object('id',v_prev.id,'total_centavos',v_prev.total_centavos,'repetida',true);
 end if;
 if v_s.status<>'ABERTA' then raise exception 'Solicitação indisponível.';end if;
 if not exists(select 1 from public.ew_fornecedores
 where id=p_fornecedor_id and empresa_id=v_s.empresa_id and ativo) then raise exception 'Fornecedor inválido.';end if;
 if jsonb_typeof(p_precos) is distinct from 'array' or jsonb_array_length(p_precos)<>jsonb_array_length(v_s.itens)
 then raise exception 'Cotação deve ter preço para cada item.';end if;
 for v_i in select value from jsonb_array_elements(v_s.itens) loop
  select value into v_price from jsonb_array_elements(p_precos) where value->>'chave'=v_i->>'chave';
  if not found then raise exception 'Falta preço de item da solicitação.';end if;
  v_value:=(v_price->>'preco_unitario_centavos')::bigint;
  if v_value is null or v_value<0 or v_value>100000000000 then raise exception 'Preço inválido.';end if;
  v_total:=v_total+round((v_i->>'quantidade')::numeric*v_value)::bigint;
  v_items:=v_items||jsonb_build_array(v_i||jsonb_build_object('preco_unitario_centavos',v_value));
 end loop;
 insert into public.ew_compras_cotacoes(empresa_id,solicitacao_id,fornecedor_id,operacao_id,itens,total_centavos,criado_por)
 values(v_s.empresa_id,v_s.id,p_fornecedor_id,p_operacao_id,v_items,v_total,auth.uid()) returning id into v_id;
 return jsonb_build_object('id',v_id,'total_centavos',v_total);
end;$f$;

create or replace function public.ew_compras_criar_pedido(p_cotacao_id uuid,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_q public.ew_compras_cotacoes%rowtype;v_s public.ew_compras_solicitacoes%rowtype;
 v_prev public.ew_compras_pedidos%rowtype;v_id uuid;v_numero bigint;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Operação inválida.';end if;
 select * into v_q from public.ew_compras_cotacoes where id=p_cotacao_id;
 if not found then raise exception 'Cotação não encontrada.';end if;
 select * into v_s from public.ew_compras_solicitacoes where id=v_q.solicitacao_id for update;
 if not found then raise exception 'Solicitação da cotação não encontrada.';end if;
 if not public.ew_pode(v_s.empresa_id,'compras.pedir') then raise exception 'Sem permissão para pedidos.';end if;
 select * into v_prev from public.ew_compras_pedidos where operacao_id=p_operacao_id;
 if found then
  if v_prev.empresa_id<>v_s.empresa_id OR v_prev.cotacao_id<>v_q.id
  then raise exception 'Identificador de pedido usado anteriormente para outra cotação.';end if;
  return jsonb_build_object('id',v_prev.id,'numero',v_prev.numero,'repetida',true);
 end if;
 if v_s.status<>'ABERTA' then raise exception 'Solicitação já convertida ou cancelada.';end if;
 insert into public.ew_compras_pedidos(empresa_id,solicitacao_id,cotacao_id,fornecedor_id,
  obra_id,local_empresa_id,operacao_id,itens,total_centavos,criado_por)
 values(v_q.empresa_id,v_s.id,v_q.id,v_q.fornecedor_id,v_s.obra_id,v_s.local_empresa_id,
  p_operacao_id,v_q.itens,v_q.total_centavos,auth.uid()) returning id,numero into v_id,v_numero;
 update public.ew_compras_solicitacoes set status='PEDIDO_GERADO' where id=v_s.id;
 return jsonb_build_object('id',v_id,'numero',v_numero,'repetida',false);
end;$f$;

create or replace function public.ew_compras_receber_pedido(
 p_pedido_id uuid,p_galpao text,p_itens jsonb,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_p public.ew_compras_pedidos%rowtype;v_rec public.ew_compras_recebimentos%rowtype;
 v_id uuid;v_i jsonb;v_original jsonb;
 v_chave text;v_seen text[]:=array[]::text[];v_q numeric;v_total numeric;
 v_ja numeric;v_clean jsonb:='[]'::jsonb;v_all boolean:=true;v_movimento uuid;
 v_galpao text:=upper(btrim(coalesce(p_galpao,'')));
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Operação inválida.';end if;
 -- Bloqueio no pedido ANTES da verificação de duplicidade. Duas sessões usando
 -- o mesmo ID esperam sua vez e a segunda observa a primeira após o COMMIT.
 select * into v_p from public.ew_compras_pedidos where id=p_pedido_id for update;
 if not found then raise exception 'Pedido não encontrado.';end if;
 if not public.ew_pode(v_p.empresa_id,'compras.receber') or not public.ew_pode(v_p.empresa_id,'estoque.receber')
 then raise exception 'Sem permissão para receber pedidos.';end if;
 select * into v_rec from public.ew_compras_recebimentos where operacao_id=p_operacao_id;
 if found then
  if v_rec.empresa_id<>v_p.empresa_id or v_rec.pedido_id<>v_p.id
    or v_rec.galpao<>upper(btrim(coalesce(p_galpao,'')))
    or v_rec.itens IS DISTINCT FROM p_itens
  then raise exception 'Identificador de recebimento reutilizado com outro pedido, galpão ou itens.';end if;
  return jsonb_build_object('id',v_rec.id,'pedido_id',v_p.id,'repetida',true,
    'estornado',v_rec.estornado_em IS NOT NULL);
 end if;
 if v_p.status in ('CANCELADO','CONCLUIDO') then raise exception 'Pedido indisponível.';end if;
 if not public.ew_pode(v_p.empresa_id,'compras.receber') or not public.ew_pode(v_p.empresa_id,'estoque.receber')
 then raise exception 'Sem permissão para receber pedidos.';end if;
 if not exists(select 1 from public.ew_locais_fisicos
 where empresa_id=v_p.empresa_id and nome=v_galpao and ativo)
 then raise exception 'Galpão inválido.';end if;
 if v_p.obra_id is not null and not exists(select 1 from public.obras
 where id=v_p.obra_id and empresa_id=v_p.empresa_id and arquivada_em is null)
 then raise exception 'Obra arquivada ou inexistente.';end if;
 if v_p.local_empresa_id is not null and not exists(select 1 from public.ew_compras_locais_empresa
 where id=v_p.local_empresa_id and empresa_id=v_p.empresa_id and ativo)
 then raise exception 'Local empresarial inativo ou inválido.';end if;
 -- Uma obra verdadeira recebe um cadastro de estoque se ainda não possuía um.
 if v_p.obra_id is not null then
  insert into public.ew_estoques_locais(empresa_id,obra_id,criado_por)
  values(v_p.empresa_id,v_p.obra_id,auth.uid())
  on conflict (empresa_id,obra_id) do nothing;
  if not exists(select 1 from public.ew_estoques_locais
   where empresa_id=v_p.empresa_id and obra_id=v_p.obra_id and excluido_em is null)
  then raise exception 'Estoque da obra encontra-se arquivado.';end if;
 end if;
 if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) not between 1 and 200
 then raise exception 'Informe itens recebidos.';end if;
 for v_i in select value from jsonb_array_elements(p_itens) loop
  v_chave:=v_i->>'chave';v_q:=(v_i->>'quantidade')::numeric;
  if v_chave is null or v_chave=any(v_seen) then raise exception 'Item de recebimento duplicado.';end if;
  v_seen:=array_append(v_seen,v_chave);
  select value into v_original from jsonb_array_elements(v_p.itens) where value->>'chave'=v_chave;
  if not found then raise exception 'Item não pertence ao pedido.';end if;
  v_total:=(v_original->>'quantidade')::numeric;
  select coalesce(sum((u.value->>'quantidade')::numeric),0) into v_ja
  from public.ew_compras_recebimentos r
  cross join lateral jsonb_array_elements(r.itens) u(value)
  where r.pedido_id=v_p.id and r.estornado_em is null and u.value->>'chave'=v_chave;
  if v_q is null or v_q<=0 or v_q>v_total-v_ja or v_q>1000000 or
     ((v_original->>'unidade') in ('BARRA','MT','PC','PR','CJ','UN') and v_q<>trunc(v_q)) or v_q<>round(v_q,3)
  then raise exception 'Quantidade inválida. Item %, pendente %.',v_chave,v_total-v_ja;end if;
  v_clean:=v_clean||jsonb_build_array(jsonb_build_object('chave',v_chave,'quantidade',v_q));
 end loop;
 -- Adquirir todos os locks físicos em ordem global antes de inserir movimentos.
 -- A ordem da seleção na interface não deve definir a ordem das travas.
 for v_original in
  select original.value from jsonb_array_elements(v_p.itens) original(value)
  where original.value->>'chave'=any(v_seen)
  order by (original.value->>'variacao_id'),coalesce(original.value->>'comprimento_mm','-'),(original.value->>'unidade')
 loop
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   case when v_p.obra_id is not null then v_p.obra_id::text
    else 'COMPRA_EMPRESA|'||v_p.local_empresa_id::text end||'|'||
   (v_original->>'variacao_id')||'|'||coalesce(v_original->>'comprimento_mm','-')||'|'||
   (v_original->>'unidade'),34777));
 end loop;
 insert into public.ew_compras_recebimentos(empresa_id,pedido_id,galpao,operacao_id,itens,criado_por)
 values(v_p.empresa_id,v_p.id,v_galpao,p_operacao_id,v_clean,auth.uid()) returning id into v_id;
 for v_i in select value from jsonb_array_elements(v_clean) loop
  v_chave:=v_i->>'chave';v_q:=(v_i->>'quantidade')::numeric;
  select value into v_original from jsonb_array_elements(v_p.itens) where value->>'chave'=v_chave;
  if v_p.obra_id is not null then
   -- Lock físico já adquirido antes da criação dos movimentos.
   -- Se este fornecedor e material já deram entrada por NF-e, não repetir
   -- automaticamente a entrada em estoque via pedido.
   if exists(select 1 from public.ew_nfe_recebimentos n
     join public.ew_obra_despesas_itens di on di.id=n.despesa_item_id
     join public.ew_obra_despesas d on d.id=di.despesa_id
     join public.ew_fornecedores f on f.id=v_p.fornecedor_id
     where n.empresa_id=v_p.empresa_id and n.obra_id=v_p.obra_id
       and n.estornado_em is null and d.status='aprovada'
       and lower(btrim(d.fornecedor))=lower(btrim(f.nome))
       and n.variacao_id=(v_original->>'variacao_id')::uuid
       and n.comprimento_mm is not distinct from (v_original->>'comprimento_mm')::integer
       and n.unidade=v_original->>'unidade')
   then raise exception
    'Este material e fornecedor já possuem entrada física por nota na obra. Concilie o recebimento anterior antes de receber por pedido.';
   end if;
   insert into public.ew_estoque_obras_movimentos(
    empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
    origem,operacao_id,observacao,usuario_id,local_estoque)
   values(v_p.empresa_id,v_p.obra_id,(v_original->>'variacao_id')::uuid,
    (v_original->>'comprimento_mm')::integer,v_original->>'unidade',v_q,
    'COMPRA',gen_random_uuid(),'Recebimento físico do pedido #'||v_p.numero||' · comprovante '||v_id,
    auth.uid(),v_galpao)
   returning id into v_movimento;
  else
   insert into public.ew_compras_estoque_empresa(
    empresa_id,local_empresa_id,recebimento_id,chave,variacao_id,galpao,unidade,comprimento_mm,quantidade_delta)
   values(v_p.empresa_id,v_p.local_empresa_id,v_id,v_chave,(v_original->>'variacao_id')::uuid,
     v_galpao,v_original->>'unidade',(v_original->>'comprimento_mm')::integer,v_q)
   returning id into v_movimento;
  end if;
  insert into public.ew_compras_recebimentos_movimentos(
   empresa_id,recebimento_id,chave,movimento_obra_id,movimento_empresa_id)
  values(v_p.empresa_id,v_id,v_chave,
   case when v_p.obra_id is not null then v_movimento else null end,
   case when v_p.local_empresa_id is not null then v_movimento else null end);
 end loop;
 for v_original in select value from jsonb_array_elements(v_p.itens) loop
  select coalesce(sum((u.value->>'quantidade')::numeric),0) into v_ja
  from public.ew_compras_recebimentos r cross join lateral jsonb_array_elements(r.itens) u(value)
  where r.pedido_id=v_p.id and r.estornado_em is null and u.value->>'chave'=v_original->>'chave';
  if v_ja < (v_original->>'quantidade')::numeric then v_all:=false;end if;
 end loop;
 update public.ew_compras_pedidos set status=case when v_all then 'CONCLUIDO' else 'PARCIAL' end where id=v_p.id;
 return jsonb_build_object('id',v_id,'pedido_id',v_p.id,'status',case when v_all then 'CONCLUIDO' else 'PARCIAL' end,'repetida',false);
end;$f$;


-- Listagem reduzida para quem recebe pedidos: sem custo unitário ou total.
-- Leitura direta de cotações/pedidos exige compras.consultar_valores.
create or replace function public.ew_compras_pedidos_resumo(p_empresa_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_precos boolean;v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if not(public.ew_pode(p_empresa_id,'compras.consultar') or
        public.ew_pode(p_empresa_id,'compras.receber'))
 then raise exception 'Sem permissão para consultar pedidos.';end if;
 v_precos:=public.ew_pode(p_empresa_id,'compras.consultar_valores');
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'numero',p.numero,'empresa_id',p.empresa_id,
  'solicitacao_id',p.solicitacao_id,'cotacao_id',p.cotacao_id,
  'fornecedor_id',p.fornecedor_id,'obra_id',p.obra_id,
  'local_empresa_id',p.local_empresa_id,
  'itens',case when v_precos then p.itens else
   (select coalesce(jsonb_agg(i.value - 'preco_unitario_centavos'),'[]'::jsonb)
    from jsonb_array_elements(p.itens) i(value)) end,
  'total_centavos',case when v_precos then p.total_centavos else null end,
  'status',p.status,'criado_em',p.criado_em
 ) order by p.criado_em desc),'[]'::jsonb)
 into v_result from public.ew_compras_pedidos p where p.empresa_id=p_empresa_id;
 return v_result;
end;$f$;

revoke all on function public.ew_compras_pedidos_resumo(uuid) from public,anon;
grant execute on function public.ew_compras_pedidos_resumo(uuid) to authenticated;

revoke all on function public.ew_compras_criar_local_empresa(uuid,text),
 public.ew_compras_criar_solicitacao(uuid,uuid,uuid,jsonb,text,uuid),
 public.ew_compras_criar_cotacao(uuid,uuid,jsonb,uuid),
 public.ew_compras_criar_pedido(uuid,uuid),
 public.ew_compras_receber_pedido(uuid,text,jsonb,uuid) from public,anon;
grant execute on function public.ew_compras_criar_local_empresa(uuid,text),
 public.ew_compras_criar_solicitacao(uuid,uuid,uuid,jsonb,text,uuid),
 public.ew_compras_criar_cotacao(uuid,uuid,jsonb,uuid),
 public.ew_compras_criar_pedido(uuid,uuid),
 public.ew_compras_receber_pedido(uuid,text,jsonb,uuid) to authenticated;

commit;
