
-- Estoque por galpão: preserva registros históricos como IMBIRIBEIRA.
create table if not exists public.ew_locais_fisicos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  nome text not null check (char_length(btrim(nome)) between 3 and 80 and nome=upper(btrim(nome))),
  ativo boolean not null default true,
  criado_por uuid references auth.users(id),
  criado_em timestamptz not null default now(),
  unique(empresa_id,nome)
);
insert into public.ew_locais_fisicos(empresa_id,nome)
select e.id, t.nome from public.empresas e cross join (values ('IMBIRIBEIRA'),('AFOGADOS')) as t(nome)
on conflict (empresa_id,nome) do nothing;
alter table public.ew_locais_fisicos enable row level security;
create policy "Equipe consulta galpoes da empresa" on public.ew_locais_fisicos
for select to authenticated using (exists (
 select 1 from public.usuarios_empresas ue
 where ue.empresa_id=ew_locais_fisicos.empresa_id and ue.usuario_id=(select auth.uid())));
create policy "ADM cadastra galpoes" on public.ew_locais_fisicos
for insert to authenticated with check (criado_por=(select auth.uid()) and exists (
 select 1 from public.usuarios_empresas ue where ue.empresa_id=ew_locais_fisicos.empresa_id
 and ue.usuario_id=(select auth.uid()) and ue.perfil='administrador'));
grant select,insert on public.ew_locais_fisicos to authenticated;

alter table public.ew_estoque_obras_movimentos
  add column if not exists local_estoque text not null default 'IMBIRIBEIRA',
  add column if not exists transferencia_id uuid,
  add column if not exists lote_id uuid;
alter table public.ew_estoque_obras_movimentos drop constraint if exists ew_estoque_origem_check;
alter table public.ew_estoque_obras_movimentos add constraint ew_estoque_origem_check
 check (origem in ('ABERTURA','COMPRA','SAIDA_MANUAL','AJUSTE','PLANO_CORTE','IMPORTACAO_CEM','TRANSFERENCIA','PLANO_CORTE_LOTE'));
create index if not exists ew_estoque_local_saldo_idx on public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,local_estoque,variacao_id,comprimento_mm,unidade);
create index if not exists ew_estoque_transferencia_idx on public.ew_estoque_obras_movimentos(transferencia_id) where transferencia_id is not null;

create table if not exists public.ew_liberacoes_lotes (
 id uuid primary key default gen_random_uuid(),
 operacao_id uuid not null unique,
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid not null references public.obras(id),
 data_liberacao date not null,
 fabrica text not null,
 arquivo_nome text not null,
 itens_confirmados jsonb not null,
 materiais_confirmados jsonb not null,
 criado_por uuid not null references auth.users(id),
 criado_em timestamptz not null default now()
);
alter table public.ew_liberacoes_lotes enable row level security;
create policy "Equipe consulta lotes da empresa" on public.ew_liberacoes_lotes
 for select to authenticated using (exists (
 select 1 from public.usuarios_empresas ue where ue.empresa_id=ew_liberacoes_lotes.empresa_id
 and ue.usuario_id=(select auth.uid())));
grant select on public.ew_liberacoes_lotes to authenticated;
alter table public.ew_estoque_obras_movimentos
 add constraint ew_estoque_lote_vinculo check (origem<>'PLANO_CORTE_LOTE' or lote_id is not null);
alter table public.ew_estoque_obras_movimentos
 add constraint ew_estoque_lote_fk foreign key(lote_id) references public.ew_liberacoes_lotes(id);

-- Movimento dirigido ao galpão. Verifica saldo local sem alterar a assinatura antiga.
create or replace function public.ew_movimentar_estoque_obra_local(
 p_empresa_id uuid,p_obra_id uuid,p_variacao_id uuid,p_comprimento_mm integer,
 p_unidade text,p_quantidade numeric,p_origem text,p_observacao text,p_operacao_id uuid,p_local_estoque text
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_saldo numeric;v_result jsonb;
begin
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where
   u.empresa_id=p_empresa_id and u.usuario_id=v_uid and u.perfil='administrador')
 then raise exception 'Somente o ADM pode movimentar estoque.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=p_empresa_id
   and l.nome=v_local and l.ativo)
 then raise exception 'Selecione um local de estoque válido.';end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.usuario_id=v_uid)
 then return jsonb_build_object('repetida',true);end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||p_variacao_id::text||'|'||coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade,34777));
 if p_quantidade<0 then
   select coalesce(sum(quantidade_delta),0) into v_saldo
   from public.ew_estoque_obras_movimentos where empresa_id=p_empresa_id and obra_id=p_obra_id
   and variacao_id=p_variacao_id and comprimento_mm is not distinct from p_comprimento_mm
   and unidade=p_unidade and local_estoque=v_local;
   if v_saldo+p_quantidade<0 then
     raise exception 'Saldo insuficiente em %: disponível % %.',v_local,v_saldo,p_unidade;
   end if;
 end if;
 v_result:=public.ew_movimentar_estoque_obra(p_empresa_id,p_obra_id,p_variacao_id,
   p_comprimento_mm,p_unidade,p_quantidade,p_origem,p_observacao,p_operacao_id);
 if not coalesce((v_result->>'repetida')::boolean,false) then
   update public.ew_estoque_obras_movimentos set local_estoque=v_local
   where id=(v_result->>'id')::uuid;
 end if;
 return v_result||jsonb_build_object('local_estoque',v_local);
end;$$;
revoke all on function public.ew_movimentar_estoque_obra_local(uuid,uuid,uuid,integer,text,numeric,text,text,uuid,text) from public,anon;
grant execute on function public.ew_movimentar_estoque_obra_local(uuid,uuid,uuid,integer,text,numeric,text,text,uuid,text) to authenticated;

-- Materiais novos registrados pelo cadastro manual também guardam o galpão.
create or replace function public.ew_cadastrar_material_manual_estoque_local(
 p_empresa_id uuid,p_obra_id uuid,p_tipo text,p_codigo text,p_descricao text,p_fabricante text,
 p_acabamento text,p_cor text,p_comprimento_mm integer,p_unidade text,p_quantidade numeric,
 p_origem text,p_observacao text,p_operacao_id uuid,p_local_estoque text
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_result jsonb;
begin
 if v_uid is null or not exists(select 1 from public.usuarios_empresas ue where
 ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ue.perfil='administrador')
 then raise exception 'Somente ADM pode cadastrar materiais.';end if;
 if not exists(select 1 from public.ew_locais_fisicos where empresa_id=p_empresa_id and nome=v_local and ativo)
 then raise exception 'Local de estoque inválido.';end if;
 v_result:=public.ew_cadastrar_material_manual_estoque(p_empresa_id,p_obra_id,p_tipo,p_codigo,
  p_descricao,p_fabricante,p_acabamento,p_cor,p_comprimento_mm,p_unidade,p_quantidade,
  p_origem,p_observacao,p_operacao_id);
 if not coalesce((v_result->>'repetida')::boolean,false) then
  update public.ew_estoque_obras_movimentos set local_estoque=v_local
  where empresa_id=p_empresa_id and operacao_id=p_operacao_id and usuario_id=v_uid;
 end if;
 return v_result||jsonb_build_object('local_estoque',v_local);
end;$$;
revoke all on function public.ew_cadastrar_material_manual_estoque_local(uuid,uuid,text,text,text,text,text,text,integer,text,numeric,text,text,uuid,text) from public,anon;
grant execute on function public.ew_cadastrar_material_manual_estoque_local(uuid,uuid,text,text,text,text,text,text,integer,text,numeric,text,text,uuid,text) to authenticated;

-- Transferência interna: um lançamento negativo e outro positivo na mesma transação.
create or replace function public.ew_transferir_estoque_obra(
 p_empresa_id uuid,p_obra_id uuid,p_variacao_id uuid,p_comprimento_mm integer,
 p_unidade text,p_quantidade numeric,p_origem_local text,p_destino_local text,
 p_observacao text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_tipo text;v_saldo numeric;
begin
 if v_uid is null or p_operacao_id is null or not exists(select 1 from public.usuarios_empresas ue
   where ue.empresa_id=p_empresa_id and ue.usuario_id=v_uid and ue.perfil='administrador')
 then raise exception 'Somente ADM pode transferir estoque.';end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos where transferencia_id=p_operacao_id and empresa_id=p_empresa_id)
 then return jsonb_build_object('repetida',true);end if;
 if v_origem=v_destino or not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_origem and ativo)
   or not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_destino and ativo)
 then raise exception 'Selecione galpões de origem e destino diferentes e válidos.';end if;
 if not exists(select 1 from public.ew_estoques_locais where empresa_id=p_empresa_id
   and obra_id=p_obra_id and excluido_em is null)
 then raise exception 'Estoque da obra arquivado ou inexistente.';end if;
 select tipo into v_tipo from public.ew_materiais_variacoes where id=p_variacao_id
   and empresa_id=p_empresa_id and ativo;
 if v_tipo is null or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
   or (v_tipo='perfil' and (p_unidade<>'BARRA' or p_comprimento_mm not between 100 and 20000
     or p_quantidade<>trunc(p_quantidade)))
   or (v_tipo='acessorio' and (p_comprimento_mm is not null or p_unidade not in ('PC','PR','CJ','MT','KG','UN')))
 then raise exception 'Material, comprimento ou quantidade inválidos.';end if;
 if char_length(btrim(coalesce(p_observacao,'')))<5 then raise exception 'Informe motivo da transferência.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_obra_id::text||'|'||p_variacao_id::text||'|'||coalesce(p_comprimento_mm::text,'-')||'|'||p_unidade,34777));
 select coalesce(sum(quantidade_delta),0) into v_saldo
 from public.ew_estoque_obras_movimentos where empresa_id=p_empresa_id and obra_id=p_obra_id
 and variacao_id=p_variacao_id and comprimento_mm is not distinct from p_comprimento_mm
 and unidade=p_unidade and local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente no galpão %. Disponível % %.',v_origem,v_saldo,p_unidade;end if;
 insert into public.ew_estoque_obras_movimentos
 (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,
  operacao_id,observacao,usuario_id,local_estoque,transferencia_id)
 values
 (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,-p_quantidade,'TRANSFERENCIA',
  gen_random_uuid(),p_observacao,v_uid,v_origem,p_operacao_id),
 (p_empresa_id,p_obra_id,p_variacao_id,p_comprimento_mm,p_unidade,p_quantidade,'TRANSFERENCIA',
  gen_random_uuid(),p_observacao,v_uid,v_destino,p_operacao_id);
 return jsonb_build_object('repetida',false,'origem',v_origem,'destino',v_destino,'quantidade',p_quantidade);
end;$$;
revoke all on function public.ew_transferir_estoque_obra(uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid) from public,anon;
grant execute on function public.ew_transferir_estoque_obra(uuid,uuid,uuid,integer,text,numeric,text,text,text,uuid) to authenticated;
