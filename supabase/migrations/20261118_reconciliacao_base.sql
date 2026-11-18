-- Reversão auditável: nenhum evento histórico é removido.
alter table public.obras add column if not exists arquivada_em timestamptz;
alter table public.obras add column if not exists arquivada_por uuid references auth.users(id);
alter table public.obras add column if not exists motivo_arquivamento text;
create index if not exists obras_ativas_empresa on public.obras(empresa_id,nome) where arquivada_em is null;
alter table public.liberacoes_corte add column if not exists cancelado_em timestamptz;
alter table public.liberacoes_corte add column if not exists cancelado_por uuid references auth.users(id);
alter table public.liberacoes_corte add column if not exists motivo_cancelamento text;
alter table public.ew_liberacoes_lotes add column if not exists cancelado_em timestamptz;
alter table public.ew_liberacoes_lotes add column if not exists cancelado_por uuid references auth.users(id);
alter table public.ew_liberacoes_lotes add column if not exists motivo_cancelamento text;
alter table public.ew_estoque_obras_movimentos add column if not exists estorno_de_id uuid unique
 references public.ew_estoque_obras_movimentos(id) on delete restrict;
alter table public.ew_estoque_obras_movimentos drop constraint if exists ew_estoque_origem_check;
alter table public.ew_estoque_obras_movimentos add constraint ew_estoque_origem_check
 check (origem in ('ABERTURA','COMPRA','SAIDA_MANUAL','AJUSTE','PLANO_CORTE',
 'IMPORTACAO_CEM','TRANSFERENCIA','PLANO_CORTE_LOTE','ESTORNO'));

create table if not exists public.ew_auditoria_operacoes (
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 obra_id uuid,
 obra_nome text not null,
 obra_codigo text,
 usuario_id uuid not null references auth.users(id),
 acao text not null check (acao in
  ('CANCELAR_ROMANEIO','CANCELAR_LIBERACOES','ESTORNAR_ESTOQUE','ARQUIVAR_OBRA')),
 referencia_id uuid,
 motivo text not null,
 detalhes jsonb not null default '{}'::jsonb,
 criado_em timestamptz not null default now()
);
create index if not exists ew_auditoria_operacoes_empresa_data
 on public.ew_auditoria_operacoes(empresa_id,criado_em desc);
create index if not exists ew_auditoria_operacoes_usuario_data
 on public.ew_auditoria_operacoes(usuario_id,criado_em desc);
alter table public.ew_auditoria_operacoes enable row level security;
revoke all on public.ew_auditoria_operacoes from public,anon,authenticated;
grant select on public.ew_auditoria_operacoes to authenticated;
create policy "Gestores consultam auditoria da propria empresa" on public.ew_auditoria_operacoes
for select to authenticated using (
 (select public.ew_sessao_eh_atual()) and exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.empresa_id=ew_auditoria_operacoes.empresa_id and ue.usuario_id=(select auth.uid())
  and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
  and ul.ativo and ul.excluido_em is null
 )
);

-- Mantém integrações e usuarias normais impedidas de alterar o status arquivada_em diretamente.
create or replace function public.ew_proteger_arquivamento_obra()
returns trigger language plpgsql set search_path to '' as $$
begin
 if (new.arquivada_em,new.arquivada_por,new.motivo_arquivamento)
 is distinct from (old.arquivada_em,old.arquivada_por,old.motivo_arquivamento)
 and current_user not in ('postgres','supabase_admin') then
  raise exception 'O arquivamento só pode ser realizado pela rotina de reconciliação.';
 end if;
 if old.arquivada_em is not null and current_user not in ('postgres','supabase_admin')
 then raise exception 'Obra arquivada: não são permitidas alterações.';end if;
 return new;
end;$$;
drop trigger if exists ew_proteger_arquivamento on public.obras;
create trigger ew_proteger_arquivamento before update on public.obras
for each row execute function public.ew_proteger_arquivamento_obra();
revoke all on function public.ew_proteger_arquivamento_obra() from public,anon,authenticated;

-- Todas as entradas operacionais devem travar a obra e rejeitar obra arquivada.
-- SELECT FOR SHARE impede corrida entre criação de movimento e arquivamento.
create or replace function public.ew_bloquear_insercao_obra_arquivada()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_obraid uuid; v_archived timestamptz;
begin
 if TG_TABLE_NAME='liberacoes_corte' then
  select obra_id into v_obraid from public.esquadrias where id=new.esquadria_id;
 else
  v_obraid:=new.obra_id;
 end if;
 if v_obraid is not null then
  select arquivada_em into v_archived from public.obras where id=v_obraid for share;
  if not found or v_archived is not null then
   raise exception 'Obra inexistente ou arquivada: operação bloqueada.';
  end if;
 end if;
 return new;
end;$$;
do $guard$
declare v_tab text;
begin
 foreach v_tab in array array[
  'esquadrias','liberacoes_corte','romaneios','ew_estoque_obras_movimentos',
  'ew_liberacoes_lotes','ew_planos_liberados','ew_estoques_locais',
  'ew_cem_obras_materiais','ew_cem_importacoes_materiais','ew_estoque_importacoes_cem'
 ] loop
  execute format('drop trigger if exists ew_bloquear_arquivada on public.%I',v_tab);
  execute format('create trigger ew_bloquear_arquivada before insert on public.%I
   for each row execute function public.ew_bloquear_insercao_obra_arquivada()',v_tab);
 end loop;
end;$guard$;
revoke all on function public.ew_bloquear_insercao_obra_arquivada() from public,anon,authenticated;

-- O cancelamento de romaneio já existente ganha lançamento automático na auditoria.
create or replace function public.ew_auditar_cancelamento_romaneio()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_nome text;v_codigo text;
begin
 if new.status='cancelado' and old.status is distinct from 'cancelado' then
  select nome,codigo into v_nome,v_codigo from public.obras where id=new.obra_id;
  insert into public.ew_auditoria_operacoes
   (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,referencia_id,motivo,detalhes)
  values(new.empresa_id,new.obra_id,coalesce(v_nome,'Obra sem nome'),v_codigo,
   coalesce(new.cancelado_por,auth.uid()),'CANCELAR_ROMANEIO',new.id,
   coalesce(new.motivo_cancelamento,'Motivo não informado'),
   jsonb_build_object('numero',new.numero,'status_anterior',old.status,'status_novo',new.status,
      'criado_por',new.criado_por,'criado_em',new.criado_em,'cancelado_em',new.cancelado_em));
 end if;
 return new;
end;$$;
drop trigger if exists ew_auditar_cancelamento_romaneio on public.romaneios;
create trigger ew_auditar_cancelamento_romaneio after update of status on public.romaneios
for each row execute function public.ew_auditar_cancelamento_romaneio();
revoke all on function public.ew_auditar_cancelamento_romaneio() from public,anon,authenticated;
