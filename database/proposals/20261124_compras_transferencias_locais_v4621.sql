-- EWGEST v46.21 — transferência atômica entre locais de estoque e estorno.
-- Usar APÓS 20261123_compras_locais_estoque_v4621.sql e 20261124_compras_estorno_recebimento_v4621.sql.
-- Não aplicar produção até revisão, auditoria e testes E2E.
begin;

create table if not exists public.ew_compras_transferencias(
 id uuid primary key default gen_random_uuid(),
 empresa_id uuid not null references public.empresas(id),
 operacao_id uuid not null unique,
 origem_tipo text not null check(origem_tipo in ('OBRA','EMPRESA')),
 origem_id uuid not null,
 destino_tipo text not null check(destino_tipo in ('OBRA','EMPRESA')),
 destino_id uuid not null,
 origem_galpao text not null,
 destino_galpao text not null,
 variacao_id uuid not null references public.ew_materiais_variacoes(id),
 comprimento_mm integer,
 unidade text not null,
 quantidade numeric(16,3) not null check(quantidade>0),
 motivo text not null,
 movimento_origem_obra_id uuid references public.ew_estoque_obras_movimentos(id),
 movimento_destino_obra_id uuid references public.ew_estoque_obras_movimentos(id),
 movimento_origem_empresa_id uuid references public.ew_compras_estoque_empresa(id),
 movimento_destino_empresa_id uuid references public.ew_compras_estoque_empresa(id),
 criado_em timestamptz not null default now(),
 criado_por uuid not null references auth.users(id),
 estornado_em timestamptz,
 estornado_por uuid references auth.users(id),
 estorno_operacao_id uuid unique,
 estorno_motivo text,
 constraint ew_compra_transf_destino check((origem_tipo,origem_id,origem_galpao)<>(destino_tipo,destino_id,destino_galpao)),
 constraint ew_compra_transf_movimentos check(
  (origem_tipo='OBRA' and movimento_origem_obra_id is not null and movimento_origem_empresa_id is null)
  or (origem_tipo='EMPRESA' and movimento_origem_empresa_id is not null and movimento_origem_obra_id is null)),
 constraint ew_compra_transf_dest_mov check(
  (destino_tipo='OBRA' and movimento_destino_obra_id is not null and movimento_destino_empresa_id is null)
  or (destino_tipo='EMPRESA' and movimento_destino_empresa_id is not null and movimento_destino_obra_id is null))
);
create index if not exists ew_compras_transferencias_emp_idx on public.ew_compras_transferencias(empresa_id,criado_em desc);
alter table public.ew_compras_transferencias enable row level security;
create policy "ew_compras_transf_leitura" on public.ew_compras_transferencias
 for select to authenticated using(public.ew_pode(empresa_id,'estoque.consultar'));
grant select on public.ew_compras_transferencias to authenticated;
revoke insert,update,delete on public.ew_compras_transferencias from anon,authenticated;

create or replace function public.ew_compras_transferir_locais(
 p_empresa_id uuid,
 p_origem_tipo text,p_origem_id uuid,p_destino_tipo text,p_destino_id uuid,
 p_variacao_id uuid,p_comprimento_mm integer,p_unidade text,p_quantidade numeric,
 p_origem_galpao text,p_destino_galpao text,p_motivo text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare
 v_uid uuid:=auth.uid();v_tipo1 text:=upper(btrim(coalesce(p_origem_tipo,'')));
 v_tipo2 text:=upper(btrim(coalesce(p_destino_tipo,'')));
 v_galpao1 text:=upper(btrim(coalesce(p_origem_galpao,'')));
 v_galpao2 text:=upper(btrim(coalesce(p_destino_galpao,'')));
 v_un text:=upper(btrim(coalesce(p_unidade,'')));
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_var public.ew_materiais_variacoes%rowtype;
 v_unidade_cadastro text;v_key1 text;v_key2 text;v_saldo numeric;
 v_trans public.ew_compras_transferencias%rowtype;
 v_origem_mov uuid;v_destino_mov uuid;v_novo_id uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_operacao_id is null then
  raise exception 'Sessão ou operação inválida.';end if;
 if not public.ew_pode(p_empresa_id,'estoque.transferir_obras') then
  raise exception 'Sem permissão para transferência entre locais.';end if;
 if v_tipo1 not in ('OBRA','EMPRESA') or v_tipo2 not in ('OBRA','EMPRESA') or
    p_origem_id is null or p_destino_id is null or
    (v_tipo1=v_tipo2 and p_origem_id=p_destino_id and v_galpao1=v_galpao2)
 then raise exception 'Informe origem e destino de estoque diferentes.';end if;
 -- Obra -> obra continua no fluxo legado, inclusive romaneio automático.
 if v_tipo1='OBRA' and v_tipo2='OBRA' then
  raise exception 'Para transferir entre duas obras, utilize Transferência entre obras.';
 end if;
 if length(v_motivo) not between 5 and 350 then
  raise exception 'Informe motivo de 5 a 350 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('COMPRAS_TRANSF|'||p_operacao_id::text,95823));
 select * into v_trans from public.ew_compras_transferencias where operacao_id=p_operacao_id;
 if found then
  if v_trans.empresa_id<>p_empresa_id or v_trans.origem_tipo<>v_tipo1 or
   v_trans.origem_id<>p_origem_id or v_trans.destino_tipo<>v_tipo2 or
   v_trans.destino_id<>p_destino_id or v_trans.variacao_id<>p_variacao_id or
   v_trans.comprimento_mm is distinct from p_comprimento_mm or v_trans.unidade<>v_un or
   v_trans.quantidade<>p_quantidade or v_trans.origem_galpao<>v_galpao1 or
   v_trans.destino_galpao<>v_galpao2 or v_trans.estornado_em is not null
  then raise exception 'Identificador de transferência já utilizado para outra operação.';end if;
  return jsonb_build_object('id',v_trans.id,'repetida',true);
 end if;
 if not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_galpao1 and ativo) or
    not exists(select 1 from public.ew_locais_fisicos
   where empresa_id=p_empresa_id and nome=v_galpao2 and ativo)
 then raise exception 'Galpão físico de origem/destino inválido.';end if;
 if (v_tipo1='OBRA' and not exists(select 1 from public.obras o
   join public.ew_estoques_locais l on l.obra_id=o.id and l.empresa_id=o.empresa_id
    where o.id=p_origem_id and o.empresa_id=p_empresa_id
     and o.arquivada_em is null and l.excluido_em is null))
 or (v_tipo2='OBRA' and not exists(select 1 from public.obras o
   join public.ew_estoques_locais l on l.obra_id=o.id and l.empresa_id=o.empresa_id
    where o.id=p_destino_id and o.empresa_id=p_empresa_id
     and o.arquivada_em is null and l.excluido_em is null))
 or (v_tipo1='EMPRESA' and not exists(select 1 from public.ew_compras_locais_empresa
    where id=p_origem_id and empresa_id=p_empresa_id and ativo))
 or (v_tipo2='EMPRESA' and not exists(select 1 from public.ew_compras_locais_empresa
    where id=p_destino_id and empresa_id=p_empresa_id and ativo))
 then raise exception 'Local de estoque inexistente, arquivado ou de outra empresa.';end if;
 select * into v_var from public.ew_materiais_variacoes
 where id=p_variacao_id and empresa_id=p_empresa_id and ativo;
 if not found then raise exception 'Material sem vínculo com esta empresa.';end if;
 if v_var.tipo='acessorio' then
  select upper(btrim(a.unidade_item)) into v_unidade_cadastro from public.ew_acessorios a
  where a.id=v_var.acessorio_id and a.empresa_id=p_empresa_id;
  if v_un<>v_unidade_cadastro then raise exception 'Unidade do acessório não coincide com o cadastro.';end if;
 end if;
 if p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000 or
   p_quantidade<>round(p_quantidade,3) or
   (v_var.tipo='perfil' and (v_un<>'BARRA' or p_comprimento_mm not between 100 and 20000)) or
   (v_var.tipo<>'perfil' and (v_un not in ('PC','PR','CJ','MT','KG','UN') or p_comprimento_mm is not null)) or
   (v_un in ('BARRA','PC','PR','CJ','UN','MT') and p_quantidade<>trunc(p_quantidade))
 then raise exception 'Quantidade, unidade ou comprimento inválido.';end if;

 v_key1:=case when v_tipo1='OBRA' then p_origem_id::text else
  'COMPRA_EMPRESA|'||p_origem_id::text end||'|'||p_variacao_id::text||'|'||
  coalesce(p_comprimento_mm::text,'-')||'|'||v_un;
 v_key2:=case when v_tipo2='OBRA' then p_destino_id::text else
  'COMPRA_EMPRESA|'||p_destino_id::text end||'|'||p_variacao_id::text||'|'||
  coalesce(p_comprimento_mm::text,'-')||'|'||v_un;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key1,v_key2),34777));
 if v_key2<>v_key1 then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key1,v_key2),34777));
 end if;

 if v_tipo1='OBRA' then
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=p_origem_id
    and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm
    and m.unidade=v_un and m.local_estoque=v_galpao1;
 else
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_compras_estoque_empresa m
  where m.empresa_id=p_empresa_id and m.local_empresa_id=p_origem_id
    and m.variacao_id=p_variacao_id and m.comprimento_mm is not distinct from p_comprimento_mm
    and m.unidade=v_un and m.galpao=v_galpao1;
 end if;
 if v_saldo<p_quantidade then
  raise exception 'Saldo insuficiente na origem: % %. Transferência não realizada.',v_saldo,v_un;
 end if;
 if v_tipo1='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_origem_id,p_variacao_id,p_comprimento_mm,v_un,-p_quantidade,
    'TRANSFERENCIA',gen_random_uuid(),left('Transferência local '||p_operacao_id::text||': '||v_motivo,500),v_uid,v_galpao1)
  returning id into v_origem_mov;
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,transferencia_id)
  values(p_empresa_id,p_origem_id,p_variacao_id,p_comprimento_mm,v_un,v_galpao1,
    -p_quantidade,'TRANSFERENCIA',p_operacao_id) returning id into v_origem_mov;
 end if;
 if v_tipo2='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_destino_id,p_variacao_id,p_comprimento_mm,v_un,p_quantidade,
    'TRANSFERENCIA',gen_random_uuid(),left('Transferência local '||p_operacao_id::text||': '||v_motivo,500),v_uid,v_galpao2)
  returning id into v_destino_mov;
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,transferencia_id)
  values(p_empresa_id,p_destino_id,p_variacao_id,p_comprimento_mm,v_un,v_galpao2,
    p_quantidade,'TRANSFERENCIA',p_operacao_id) returning id into v_destino_mov;
 end if;
 insert into public.ew_compras_transferencias(
  empresa_id,operacao_id,origem_tipo,origem_id,destino_tipo,destino_id,
  origem_galpao,destino_galpao,variacao_id,comprimento_mm,unidade,quantidade,motivo,
  movimento_origem_obra_id,movimento_destino_obra_id,
  movimento_origem_empresa_id,movimento_destino_empresa_id,criado_por)
 values(p_empresa_id,p_operacao_id,v_tipo1,p_origem_id,v_tipo2,p_destino_id,
  v_galpao1,v_galpao2,p_variacao_id,p_comprimento_mm,v_un,p_quantidade,v_motivo,
  case when v_tipo1='OBRA' then v_origem_mov else null end,
  case when v_tipo2='OBRA' then v_destino_mov else null end,
  case when v_tipo1='EMPRESA' then v_origem_mov else null end,
  case when v_tipo2='EMPRESA' then v_destino_mov else null end,v_uid)
 returning id into v_novo_id;
 return jsonb_build_object('id',v_novo_id,'repetida',false,
   'saldo_origem',v_saldo-p_quantidade,'quantidade',p_quantidade);
end;$f$;

create or replace function public.ew_compras_estornar_transferencia(
 p_transferencia_id uuid,p_motivo text,p_operacao_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $f$
declare
 v_uid uuid:=auth.uid();v_t public.ew_compras_transferencias%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_key1 text;v_key2 text;v_saldo numeric;v_destino_criado timestamptz;v_destino uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if p_transferencia_id is null or p_operacao_id is null or v_uid is null
 then raise exception 'Sessão ou operação inválida.';end if;
 if length(v_motivo) not between 5 and 400 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 select * into v_t from public.ew_compras_transferencias where id=p_transferencia_id for update;
 if not found then raise exception 'Transferência inexistente.';end if;
 if not public.ew_pode(v_t.empresa_id,'estoque.estornar') then
  raise exception 'Sem permissão para estornar transferência.';end if;
 if v_t.estornado_em is not null then
  if v_t.estorno_operacao_id=p_operacao_id then
   return jsonb_build_object('id',v_t.id,'ja_estornado',true,'repetida',true);
  end if;
  raise exception 'Transferência já estornada.';end if;
 if exists(select 1 from public.ew_compras_transferencias t where
   t.estorno_operacao_id=p_operacao_id and t.id<>v_t.id)
 then raise exception 'Identificador de estorno já utilizado.';end if;
 v_key1:=case when v_t.origem_tipo='OBRA' then v_t.origem_id::text else
  'COMPRA_EMPRESA|'||v_t.origem_id::text end||'|'||v_t.variacao_id::text||'|'||
  coalesce(v_t.comprimento_mm::text,'-')||'|'||v_t.unidade;
 v_key2:=case when v_t.destino_tipo='OBRA' then v_t.destino_id::text else
  'COMPRA_EMPRESA|'||v_t.destino_id::text end||'|'||v_t.variacao_id::text||'|'||
  coalesce(v_t.comprimento_mm::text,'-')||'|'||v_t.unidade;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(v_key1,v_key2),34777));
 if v_key2<>v_key1 then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(v_key1,v_key2),34777));
 end if;
 if v_t.destino_tipo='OBRA' then
  select m.criado_em into v_destino_criado from public.ew_estoque_obras_movimentos m
  where m.id=v_t.movimento_destino_obra_id and m.empresa_id=v_t.empresa_id
    and m.obra_id=v_t.destino_id and m.quantidade_delta=v_t.quantidade
    and m.origem='TRANSFERENCIA';
  if not found then raise exception 'Movimento do destino não confere.';end if;
  if exists(select 1 from public.ew_estoque_obras_movimentos m
   where m.empresa_id=v_t.empresa_id and m.obra_id=v_t.destino_id
     and m.variacao_id=v_t.variacao_id
     and m.comprimento_mm is not distinct from v_t.comprimento_mm
     and m.unidade=v_t.unidade and m.local_estoque=v_t.destino_galpao
     and m.quantidade_delta<0 and m.origem<>'ESTORNO' and m.criado_em>=v_destino_criado
       and not exists(select 1 from public.ew_estoque_obras_movimentos rev where rev.estorno_de_id=m.id))
  then raise exception 'Destino possui saídas posteriores. Desfaça dependências antes do estorno.';end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=v_t.empresa_id and m.obra_id=v_t.destino_id
    and m.variacao_id=v_t.variacao_id
    and m.comprimento_mm is not distinct from v_t.comprimento_mm
    and m.unidade=v_t.unidade and m.local_estoque=v_t.destino_galpao;
 else
  select m.criado_em into v_destino_criado from public.ew_compras_estoque_empresa m
  where m.id=v_t.movimento_destino_empresa_id and m.empresa_id=v_t.empresa_id
    and m.local_empresa_id=v_t.destino_id and m.quantidade_delta=v_t.quantidade
    and m.origem='TRANSFERENCIA';
  if not found then raise exception 'Movimento empresarial do destino não confere.';end if;
  if exists(select 1 from public.ew_compras_estoque_empresa m
    where m.empresa_id=v_t.empresa_id and m.local_empresa_id=v_t.destino_id
      and m.variacao_id=v_t.variacao_id
      and m.comprimento_mm is not distinct from v_t.comprimento_mm
      and m.unidade=v_t.unidade and m.galpao=v_t.destino_galpao
      and m.quantidade_delta<0 and m.origem not in ('ESTORNO_PEDIDO','ESTORNO_TRANSFERENCIA')
       and m.criado_em>=v_destino_criado
       and not exists(select 1 from public.ew_compras_estoque_empresa rev where rev.estorno_de_id=m.id))
  then raise exception 'Destino possui saídas posteriores. Desfaça dependências antes do estorno.';end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_compras_estoque_empresa m
  where m.empresa_id=v_t.empresa_id and m.local_empresa_id=v_t.destino_id
    and m.variacao_id=v_t.variacao_id
    and m.comprimento_mm is not distinct from v_t.comprimento_mm
    and m.unidade=v_t.unidade and m.galpao=v_t.destino_galpao;
 end if;
 if v_saldo<v_t.quantidade then raise exception 'Saldo físico insuficiente no destino.';end if;

 -- A saída original e a entrada de destino são revertidas em uma única transação.
 if v_t.destino_tipo='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(v_t.empresa_id,v_t.destino_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   -v_t.quantidade,'ESTORNO',gen_random_uuid(),left('Estorno transferência: '||v_motivo,500),
   v_uid,v_t.destino_galpao,v_t.movimento_destino_obra_id);
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,estorno_de_id,transferencia_id)
  values(v_t.empresa_id,v_t.destino_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.destino_galpao,-v_t.quantidade,'ESTORNO_TRANSFERENCIA',v_t.movimento_destino_empresa_id,
   v_t.operacao_id);
 end if;
 if v_t.origem_tipo='OBRA' then
  insert into public.ew_estoque_obras_movimentos(
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(v_t.empresa_id,v_t.origem_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.quantidade,'ESTORNO',gen_random_uuid(),left('Estorno transferência: '||v_motivo,500),
   v_uid,v_t.origem_galpao,v_t.movimento_origem_obra_id);
 else
  insert into public.ew_compras_estoque_empresa(
   empresa_id,local_empresa_id,variacao_id,comprimento_mm,unidade,galpao,
   quantidade_delta,origem,estorno_de_id,transferencia_id)
  values(v_t.empresa_id,v_t.origem_id,v_t.variacao_id,v_t.comprimento_mm,v_t.unidade,
   v_t.origem_galpao,v_t.quantidade,'ESTORNO_TRANSFERENCIA',v_t.movimento_origem_empresa_id,
   v_t.operacao_id);
 end if;
 update public.ew_compras_transferencias set
  estornado_em=now(),estornado_por=v_uid,estorno_motivo=v_motivo,
  estorno_operacao_id=p_operacao_id where id=v_t.id;
 return jsonb_build_object('id',v_t.id,'repetida',false,'estornado',true);
end;$f$;

revoke all on function public.ew_compras_transferir_locais(
 uuid,text,uuid,text,uuid,uuid,integer,text,numeric,text,text,text,uuid) from public,anon;
revoke all on function public.ew_compras_estornar_transferencia(uuid,text,uuid) from public,anon;
grant execute on function public.ew_compras_transferir_locais(
 uuid,text,uuid,text,uuid,uuid,integer,text,numeric,text,text,text,uuid) to authenticated;
grant execute on function public.ew_compras_estornar_transferencia(uuid,text,uuid) to authenticated;

commit;
