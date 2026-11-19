-- EWGEST v43.6: motivo operacional de 5 a 400 caracteres em reversões e exclusão auditadas.

CREATE OR REPLACE FUNCTION public.ew_arquivar_obra_reconciliada(p_obra_id uuid, p_confirmacao text, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_ver jsonb;
 v_record public.ew_obras_exclusoes_historico%rowtype;v_motivo text:=btrim(coalesce(p_motivo,''));
begin
 perform public.ew_exigir_sessao_atual();
 if p_obra_id is null or p_operacao_id is null then raise exception 'Obra e operação obrigatórias.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_record from public.ew_obras_exclusoes_historico where operacao_id=p_operacao_id;
 if found then
  if v_record.obra_excluida_id<>p_obra_id or v_record.excluido_por<>v_uid
   then raise exception 'Identificador já usado em outra operação.';end if;
  return jsonb_build_object('excluida',true,'repetida',true,'nome',v_record.obra_nome);
 end if;
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra já arquivada ou não encontrada.';end if;
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 v_ver:=public.ew_inspecionar_reversao_obra(p_obra_id);
 if not (v_ver->>'permitido')::boolean then raise exception
  'ARQUIVAMENTO_BLOQUEADO: %',
  array_to_string(array(select jsonb_array_elements_text(v_ver->'motivos')),' ');
 end if;
 if upper(btrim(coalesce(p_confirmacao,'')))<>upper(coalesce(nullif(btrim(v_ob.codigo),''),v_ob.nome))
 then raise exception 'Confirmação incorreta. Digite o código da obra.';end if;
 update public.obras set arquivada_em=now(),arquivada_por=v_uid,motivo_arquivamento=v_motivo
 where id=p_obra_id and arquivada_em is null;
 insert into public.ew_obras_exclusoes_historico
  (operacao_id,empresa_id,obra_excluida_id,obra_nome,obra_codigo,motivo,resumo,excluido_por)
 values(p_operacao_id,v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,
  left(v_motivo,300),v_ver->'resumo',v_uid);
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ARQUIVAR_OBRA',
  p_operacao_id,v_motivo,jsonb_build_object(
   'resumo',v_ver->'resumo','cadastros_gerais_preservados',true,
   'historico_operacional_preservado',true));
 return jsonb_build_object('excluida',true,'repetida',false,
  'nome',v_ob.nome,'codigo',v_ob.codigo,'historico_preservado',true);
end;$function$
;

CREATE OR REPLACE FUNCTION public.ew_cancelar_liberacoes_obra(p_obra_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_e record;
 v_qtd integer;v_ativas integer;v_lotes integer;v_motivo text:=btrim(coalesce(p_motivo,''));v_liberacoes jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 5 and 400 then raise exception 'Informe o motivo, de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u join public.usuarios_login ul
   on ul.usuario_id=u.usuario_id and ul.empresa_id=u.empresa_id
  where u.usuario_id=v_uid and u.empresa_id=v_ob.empresa_id
   and u.perfil in ('administrador','gerenciador') and ul.perfil=u.perfil and ul.ativo
   and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem cancelar liberações.';end if;
 perform 1 from public.esquadrias where obra_id=p_obra_id order by id for update;
 if exists (select 1 from public.romaneios where obra_id=p_obra_id and status<>'cancelado')
  then raise exception 'Cancele os romaneios emitidos antes das liberações.';end if;
 if exists(select 1 from public.saidas_producao s join public.esquadrias e
    on e.id=s.esquadria_id where e.obra_id=p_obra_id and s.cancelado_em is null)
  then raise exception 'Existem saídas de produção ativas. Estorne-as primeiro.';end if;
 if exists(select 1 from public.esquadrias where obra_id=p_obra_id and qtd_fabricada<>0)
  then raise exception 'Existem quantidades fabricadas que precisam ser conciliadas.';end if;
 -- Confere consistência acumulada ANTES de qualquer alteração.
 for v_e in
  select e.id,e.codigo,e.qtd_liberada,coalesce(sum(l.quantidade)
    filter(where l.cancelado_em is null),0)::integer as ativos
  from public.esquadrias e left join public.liberacoes_corte l on l.esquadria_id=e.id
  where e.obra_id=p_obra_id group by e.id,e.codigo,e.qtd_liberada
 loop
  if v_e.qtd_liberada<>v_e.ativos then
   raise exception 'Saldo de liberação inconsistente para %. Solicite conferência técnica.',v_e.codigo;
  end if;
 end loop;
 select count(*),coalesce(sum(l.quantidade),0) into v_ativas,v_qtd
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'esquadria',e.codigo,
  'quantidade',l.quantidade,'liberado_em',l.registrada_em,'liberado_por',l.usuario_id)),
  '[]'::jsonb) into v_liberacoes
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 update public.liberacoes_corte l set cancelado_em=now(),cancelado_por=v_uid,motivo_cancelamento=v_motivo
 from public.esquadrias e where l.esquadria_id=e.id and e.obra_id=p_obra_id
 and l.cancelado_em is null;
 update public.esquadrias set qtd_liberada=0 where obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
  where obra_id=p_obra_id and cancelado_em is null;
 update public.ew_liberacoes_lotes set cancelado_em=now(),cancelado_por=v_uid,
  motivo_cancelamento=v_motivo where obra_id=p_obra_id and cancelado_em is null;
 if v_ativas>0 or v_lotes>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_LIBERACOES',v_motivo,
   jsonb_build_object('registros',v_ativas,'quantidade',v_qtd,'lotes',v_lotes,
    'liberacoes_originais',v_liberacoes,
    'estoque','Baixas de materiais ainda precisam de estorno separado'));
 end if;
 return jsonb_build_object('canceladas',v_ativas,'unidades',v_qtd,'lotes',v_lotes,
  'estoque_pendente',true,'historico_preservado',true);
end;$function$
;

CREATE OR REPLACE FUNCTION public.ew_cancelar_saidas_avulsas_obra(p_obra_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_total int;v_details jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 5 and 400 then raise exception 'Motivo obrigatório de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas ue join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_ob.empresa_id
  and ue.perfil in ('administrador','gerenciador') and ue.perfil=ul.perfil
  and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Sem permissão para cancelar saídas avulsas.';end if;
 perform 1 from public.esquadrias e where e.obra_id=p_obra_id order by e.id for update;
 if exists(select 1 from public.romaneios r where r.obra_id=p_obra_id and r.status<>'cancelado')
 then raise exception 'Cancele os romaneios antes de estornar saídas avulsas.';end if;
 -- Não permitir operação aqui sobre saída ligada a qualquer romaneio.
 if exists(select 1 from public.saidas_producao s
  join public.esquadrias e on e.id=s.esquadria_id
  where e.obra_id=p_obra_id and s.cancelado_em is null
  and exists(select 1 from public.romaneios_itens ri where ri.saida_producao_id=s.id))
 then raise exception 'Existem saídas vinculadas a romaneios com estorno pendente. Solicite conferência técnica.';end if;
 select count(*),coalesce(jsonb_agg(jsonb_build_object('id',s.id,'esquadria_id',s.esquadria_id,
  'tipo',s.tipo,'quantidade',s.quantidade,'data_saida',s.data_saida,
  'registrada_em',s.registrada_em,'usuario_original',s.usuario_id)),'[]'::jsonb)
 into v_total,v_details
 from public.saidas_producao s join public.esquadrias e on e.id=s.esquadria_id
 where e.obra_id=p_obra_id and s.cancelado_em is null;
 update public.saidas_producao s set cancelado_em=now(),cancelado_por=v_uid
 from public.esquadrias e
 where s.esquadria_id=e.id and e.obra_id=p_obra_id and s.cancelado_em is null;
 if v_total>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_SAIDAS_AVULSAS',
   v_motivo,jsonb_build_object('saidas_canceladas',v_total,'saidas_originais',v_details));
 end if;
 return jsonb_build_object('canceladas',v_total,'historico_preservado',true);
end;$function$
;

CREATE OR REPLACE FUNCTION public.ew_estornar_estoque_obra(p_obra_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Identificador de operação obrigatório.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 v_status:=public.ew_inspecionar_reversao_obra(p_obra_id);
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao<>'ESTORNAR_ESTOQUE' or v_audit.obra_id<>p_obra_id or v_audit.usuario_id<>v_uid
   then raise exception 'Identificador de operação já utilizado.';end if;
  return jsonb_build_object('repetida',true,'estornados',
    v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 if (v_status->'resumo'->>'romaneios')::int>0
   or (v_status->'resumo'->>'saidas_producao')::int>0
   or (v_status->'resumo'->>'liberacoes')::int>0
   or (v_status->'resumo'->>'lotes_cem')::int>0
   or (v_status->'resumo'->>'planos_liberados')::int>0
   or (v_status->'resumo'->>'unidades_liberadas')::int>0
   or (v_status->'resumo'->>'fabricadas')::int>0
 then raise exception 'Cancele romaneios, saídas e liberações antes de estornar o estoque.';end if;
 perform 1 from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id order by m.id for update;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
   group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
   having sum(m.quantidade_delta)<0) then
  raise exception 'Saldo negativo em galpão. Concilie o estoque antes do estorno.';end if;
 -- Registra em detalhes cada movimento que será revertido.
 select count(*),
  coalesce(jsonb_agg(jsonb_build_object('id',m.id,'origem',m.origem,
   'quantidade',m.quantidade_delta,'local',m.local_estoque,
   'unidade',m.unidade,'comprimento_mm',m.comprimento_mm,
   'variacao_id',m.variacao_id,'criado_em',m.criado_em,'usuario_original',m.usuario_id)),
   '[]'::jsonb)
 into v_n,v_originais from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if v_n=0 then
  if (v_status->'resumo'->>'saldos_nao_zerados')::int>0 then
   raise exception 'Não existem movimentos pendentes, mas há saldos diferentes de zero.';end if;
  return jsonb_build_object('repetida',false,'estornados',0,'historico_preservado',true);
 end if;
 insert into public.ew_estoque_obras_movimentos (
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
 select m.empresa_id,m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,
  -m.quantidade_delta,'ESTORNO',gen_random_uuid(),left('Estorno para reimportação: '||v_motivo,500),
  v_uid,m.local_estoque,m.id
 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if exists(select 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
 group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
 having sum(m.quantidade_delta)<>0) then
  raise exception 'A operação não zerou todos os saldos. Nenhum estorno foi confirmado.';end if;
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_operacao_id,v_motivo,jsonb_build_object('movimentos_estornados',v_n,
   'movimentos_originais',v_originais));
 return jsonb_build_object('repetida',false,'estornados',v_n,'historico_preservado',true);
end;$function$
;

CREATE OR REPLACE FUNCTION public.ew_estornar_movimento_obra(p_obra_id uuid, p_movimento_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid := auth.uid();
 v_obra public.obras%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_audit public.ew_auditoria_operacoes%rowtype;
 v_ver jsonb;
 v_mov public.ew_estoque_obras_movimentos%rowtype;
 v_motivo text := btrim(coalesce(p_motivo,''));
 v_saldo numeric;
 v_n integer := 0;
 v_par integer;
 v_soma numeric;
 v_materials integer;
 v_locais integer;
 v_originais jsonb := '[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_obra_id is null or p_movimento_id is null or p_operacao_id is null then
  raise exception 'Obra, movimento, operação e usuário são obrigatórios.';
 end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo com 5 a 400 caracteres.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_obra from public.obras where id=p_obra_id for update;
 if not found or v_obra.arquivada_em is not null then
  raise exception 'Obra não encontrada ou já arquivada.';
 end if;
 if not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_obra.empresa_id
   and ue.perfil in ('administrador','gerenciador')
   and ul.perfil=ue.perfil and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem realizar estornos.'; end if;
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao <> 'ESTORNAR_ESTOQUE'
   or v_audit.obra_id is distinct from p_obra_id or v_audit.usuario_id <> v_uid
   or v_audit.referencia_id is distinct from p_movimento_id then
   raise exception 'Identificador de operação já usado em outro estorno.';
  end if;
  return jsonb_build_object('repetida',true,
   'estornados',v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 select * into v_original from public.ew_estoque_obras_movimentos
 where id=p_movimento_id and obra_id=p_obra_id for update;
 if not found then raise exception 'Movimentação não encontrada nesta obra.'; end if;
 if v_original.estorno_de_id is not null then
  raise exception 'Uma contrapartida de estorno não pode ser cancelada novamente.';
 end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos e
  where e.estorno_de_id=p_movimento_id) then
  raise exception 'Esta movimentação já foi estornada.';
 end if;
 v_ver := public.ew_inspecionar_reversao_obra(p_obra_id);
 if exists (
  select 1 from pg_catalog.jsonb_array_elements_text(v_ver->'motivos') as x(motivo)
  where x.motivo not like 'Estorne as movimentações do estoque%'
 ) then
  raise exception 'Cancele romaneios, saídas e liberações e resolva outras pendências antes do estorno individual.';
 end if;
 -- Transferência entre galpões é uma operação única de duas pernas.
 if v_original.transferencia_id is not null then
  if v_original.origem<>'TRANSFERENCIA' then
   raise exception 'Movimento de transferência possui origem inconsistente.';
  end if;
  select count(*),coalesce(sum(m.quantidade_delta),0),
   count(distinct (m.variacao_id::text||'|'||coalesce(m.comprimento_mm::text,'')||'|'||m.unidade)),
   count(distinct m.local_estoque)
  into v_par,v_soma,v_materials,v_locais
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.transferencia_id=v_original.transferencia_id;
  if v_par<>2 or v_soma<>0 or v_materials<>1 or v_locais<>2 then
   raise exception 'Transferência incompleta ou inconsistente. Não é seguro estornar uma perna isoladamente.';
  end if;
 end if;
 -- Toda a obra é serializada pelo mesmo bloqueio da reversão total.
 perform 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
  and (m.id=p_movimento_id or
   (v_original.transferencia_id is not null
    and m.transferencia_id=v_original.transferencia_id))
 order by m.id for update;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  if v_mov.estorno_de_id is not null or exists(
   select 1 from public.ew_estoque_obras_movimentos s where s.estorno_de_id=v_mov.id
  ) then raise exception 'Uma das movimentações já foi estornada. Recarregue o histórico.'; end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.variacao_id=v_mov.variacao_id
   and m.comprimento_mm is not distinct from v_mov.comprimento_mm
   and m.unidade=v_mov.unidade and m.local_estoque=v_mov.local_estoque;
  if v_saldo-v_mov.quantidade_delta<0 then
   raise exception 'Estorno individual deixaria saldo negativo em % (% %). Desfaça antes as movimentações posteriores dependentes.',
    v_mov.local_estoque,v_saldo,v_mov.unidade;
  end if;
 end loop;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  insert into public.ew_estoque_obras_movimentos (
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id
  ) values (
   v_mov.empresa_id,v_mov.obra_id,v_mov.variacao_id,v_mov.comprimento_mm,
   v_mov.unidade,-v_mov.quantidade_delta,'ESTORNO',pg_catalog.gen_random_uuid(),
   left('Estorno individual: '||v_motivo,500),v_uid,v_mov.local_estoque,v_mov.id
  );
  v_n:=v_n+1;
  v_originais:=v_originais||jsonb_build_array(jsonb_build_object(
   'movimento_id',v_mov.id,'origem',v_mov.origem,'quantidade',v_mov.quantidade_delta,
   'variacao_id',v_mov.variacao_id,'comprimento_mm',v_mov.comprimento_mm,
   'unidade',v_mov.unidade,'galpao',v_mov.local_estoque,
   'usuario_original',v_mov.usuario_id,'registrado_em',v_mov.criado_em,
   'transferencia_id',v_mov.transferencia_id
  ));
 end loop;
 insert into public.ew_auditoria_operacoes (
  empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
  referencia_id,operacao_id,motivo,detalhes
 ) values (
  v_obra.empresa_id,p_obra_id,v_obra.nome,v_obra.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_movimento_id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','individual','movimentos_estornados',v_n,
   'movimentos_originais',v_originais)
 );
 return jsonb_build_object('repetida',false,'estornados',v_n,
  'historico_preservado',true);
end;
$function$
;
