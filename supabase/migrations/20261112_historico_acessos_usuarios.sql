-- EWGEST: histórico de entradas, últimas comunicações e saídas confirmadas.
-- Nenhuma senha, token, IP ou informação de navegação é armazenada.
create table if not exists public.ew_historico_acessos (
  id uuid primary key default gen_random_uuid(),
  sessao_id uuid not null unique,
  empresa_id uuid not null references public.empresas(id),
  usuario_id uuid not null references auth.users(id),
  entrada_em timestamptz not null default now(),
  ultima_atividade_em timestamptz,
  saida_em timestamptz,
  origem text not null default 'EWGEST' check (
    origem in ('EWGEST','SESSAO_RECUPERADA','AUTENTICACAO_ANTERIOR')
  ),
  registrado_em timestamptz not null default now(),
  constraint ew_acesso_saida_apos_entrada check (
    saida_em is null or saida_em >= entrada_em
  ),
  constraint ew_acesso_atividade_apos_entrada check (
    ultima_atividade_em is null or ultima_atividade_em >= entrada_em
  )
);

create index if not exists ew_historico_acessos_empresa_data_idx
 on public.ew_historico_acessos (empresa_id,entrada_em desc);
create index if not exists ew_historico_acessos_usuario_data_idx
 on public.ew_historico_acessos (usuario_id,entrada_em desc);

alter table public.ew_historico_acessos enable row level security;
revoke all on public.ew_historico_acessos from public, anon, authenticated;
grant select on public.ew_historico_acessos to authenticated;

create policy "Somente ADM consulta historico de acessos da empresa"
 on public.ew_historico_acessos
 for select to authenticated
 using (exists (
   select 1 from public.usuarios_empresas ue
   where ue.usuario_id=(select auth.uid())
     and ue.empresa_id=ew_historico_acessos.empresa_id
     and ue.perfil='administrador'
 ));

-- Resgate das sessões de autenticação ainda disponíveis na última semana.
-- auth.sessions registra quando uma sessão foi criada, mas NÃO prova o
-- horário de saída nem a última interação; ambos ficam NULL.
insert into public.ew_historico_acessos
 (sessao_id,empresa_id,usuario_id,entrada_em,ultima_atividade_em,saida_em,origem)
select s.id, ul.empresa_id, s.user_id, s.created_at, null, null, 'AUTENTICACAO_ANTERIOR'
from auth.sessions s
join public.usuarios_login ul on ul.usuario_id=s.user_id
where s.created_at >= now() - interval '7 days'
on conflict(sessao_id) do nothing;

-- Único ponto de escrita do histórico: sessão autenticada e membro da empresa.
create or replace function public.ew_registrar_evento_acesso(
  p_empresa_id uuid,
  p_sessao_id uuid,
  p_evento text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_atual public.ew_historico_acessos%rowtype;
  v_agora timestamptz := now();
begin
  if v_usuario is null or p_empresa_id is null or p_sessao_id is null then
    raise exception 'Sessão de acesso inválida.';
  end if;
  if p_evento not in ('entrada','atividade','saida') then
    raise exception 'Evento de acesso inválido.';
  end if;
  if not exists (
    select 1 from public.usuarios_empresas ue
    where ue.empresa_id=p_empresa_id and ue.usuario_id=v_usuario
  ) then
    raise exception 'Usuário sem acesso à empresa.';
  end if;

  -- Para novas entradas ou sessões abertas antes da instrumentação,
  -- um registro é criado sem permitir escolher horários arbitrários.
  if p_evento in ('entrada','atividade') then
    insert into public.ew_historico_acessos
      (sessao_id,empresa_id,usuario_id,entrada_em,ultima_atividade_em,origem)
    values
      (p_sessao_id,p_empresa_id,v_usuario,v_agora,v_agora,
       case when p_evento='entrada' then 'EWGEST' else 'SESSAO_RECUPERADA' end)
    on conflict (sessao_id) do nothing;
  end if;

  select * into v_atual
  from public.ew_historico_acessos where sessao_id=p_sessao_id for update;

  if not found then
    return jsonb_build_object('registrado',false,'motivo','sessao_nao_localizada');
  end if;

  if v_atual.empresa_id<>p_empresa_id or v_atual.usuario_id<>v_usuario then
    raise exception 'Sessão não pertence ao usuário desta empresa.';
  end if;

  if p_evento='saida' then
    if v_atual.saida_em is null then
      update public.ew_historico_acessos
      set saida_em=v_agora, ultima_atividade_em=v_agora
      where id=v_atual.id;
    end if;
  elsif v_atual.saida_em is null then
    update public.ew_historico_acessos
    set ultima_atividade_em=v_agora
    where id=v_atual.id;
  end if;

  return jsonb_build_object(
    'registrado',true,
    'evento',p_evento,
    'sessao_id',p_sessao_id
  );
end; $$;

revoke all on function public.ew_registrar_evento_acesso(uuid,uuid,text)
 from public, anon, authenticated;
grant execute on function public.ew_registrar_evento_acesso(uuid,uuid,text)
 to authenticated;
