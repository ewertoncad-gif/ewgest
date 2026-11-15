-- Uma sessão por usuário para todos os perfis do EWGEST.
-- A identidade da sessão vem do JWT assinado, nunca do navegador.
create table if not exists public.ew_sessoes_unicas (
 usuario_id uuid primary key references auth.users(id) on delete cascade,
 sessao_auth_id uuid not null,
 assumida_em timestamptz not null default now(),
 ultima_verificacao_em timestamptz not null default now()
);
create unique index if not exists ew_sessoes_unicas_sessao_key
 on public.ew_sessoes_unicas(sessao_auth_id);
alter table public.ew_sessoes_unicas enable row level security;
revoke all on public.ew_sessoes_unicas from public,anon,authenticated;

create or replace function public.ew_sessao_eh_atual()
returns boolean language sql stable security definer
set search_path to '' as $$
 select (select auth.uid()) is not null
 and nullif((select auth.jwt())->>'session_id','') is not null
 and exists (
  select 1 from public.ew_sessoes_unicas s where s.usuario_id=(select auth.uid())
    and s.sessao_auth_id=((select auth.jwt())->>'session_id')::uuid
 );
$$;
revoke all on function public.ew_sessao_eh_atual() from public,anon;
grant execute on function public.ew_sessao_eh_atual() to authenticated;

create or replace function public.ew_exigir_sessao_atual()
returns void language plpgsql security definer set search_path to '' as $$
begin
 if (select auth.uid()) is null or not public.ew_sessao_eh_atual() then
   raise exception 'EWGEST_SESSAO_SUBSTITUIDA: esta conta está conectada em outro dispositivo.'
     using errcode='P0001';
 end if;
end;$$;
revoke all on function public.ew_exigir_sessao_atual() from public,anon;
grant execute on function public.ew_exigir_sessao_atual() to authenticated;

create or replace function public.ew_controlar_sessao_unica(p_acao text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_uid uuid:=(select auth.uid());v_session uuid;
 v_active uuid;v_login_ativo boolean;
begin
 if v_uid is null then raise exception 'Sessão não autenticada.';end if;
 if nullif((select auth.jwt())->>'session_id','') is null
 then raise exception 'Token sem identidade de sessão.';end if;
 v_session:=((select auth.jwt())->>'session_id')::uuid;
 if p_acao not in ('consultar','assumir','validar','sair')
 then raise exception 'Operação de sessão inválida.';end if;
 -- Evita criar controle para contas suspensas ou desvinculadas.
 select exists (
  select 1 from public.usuarios_login ul
  join public.usuarios_empresas ue on ue.usuario_id=ul.usuario_id and ue.empresa_id=ul.empresa_id
  where ul.usuario_id=v_uid and ul.ativo
 ) into v_login_ativo;
 if not v_login_ativo then raise exception 'Usuário sem acesso ativo.';end if;
 -- Não confundir um token assinado já encerrado com sessão ativa no Auth.
 if not exists(select 1 from auth.sessions a where a.id=v_session and a.user_id=v_uid)
 then raise exception 'Sessão de autenticação expirada ou encerrada.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text,776661));
 select sessao_auth_id into v_active from public.ew_sessoes_unicas
 where usuario_id=v_uid for update;
 if p_acao='validar' then
   return jsonb_build_object('autorizado',v_active is not distinct from v_session and v_active is not null,
    'estado',case when v_active=v_session then 'ativa' else 'substituida' end);
 end if;
 if p_acao='sair' then
   delete from public.ew_sessoes_unicas where usuario_id=v_uid and sessao_auth_id=v_session;
   return jsonb_build_object('autorizado',true,'estado','saida_registrada');
 end if;
 if v_active=v_session then
   update public.ew_sessoes_unicas set ultima_verificacao_em=now() where usuario_id=v_uid;
   return jsonb_build_object('autorizado',true,'estado','ativa');
 end if;
 if v_active is not null and p_acao='consultar' then
   return jsonb_build_object('autorizado',false,'estado','outro_dispositivo');
 end if;
 insert into public.ew_sessoes_unicas(usuario_id,sessao_auth_id,assumida_em,ultima_verificacao_em)
 values(v_uid,v_session,now(),now())
 on conflict(usuario_id) do update set sessao_auth_id=excluded.sessao_auth_id,
 assumida_em=excluded.assumida_em,ultima_verificacao_em=excluded.ultima_verificacao_em;
 return jsonb_build_object('autorizado',true,'estado',
  case when v_active is null then 'iniciada' else 'substituida_anterior' end);
end;$$;
revoke all on function public.ew_controlar_sessao_unica(text) from public,anon;
grant execute on function public.ew_controlar_sessao_unica(text) to authenticated;
