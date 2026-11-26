-- Extensão do piloto. Sem rastreabilidade integral, manter custos pendentes.
-- Executar depois do piloto entre obras e antes dos testes; não publicar isoladamente.
CREATE OR REPLACE FUNCTION public.ew_compras_estornar_transferencia(p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if v_t.origem_tipo='OBRA' or v_t.destino_tipo='OBRA' then
  perform ew_compras_interna.custo_estornar_se_integrada(v_t.empresa_id,'LOCAIS',v_t.id,p_operacao_id);
 end if;
 return jsonb_build_object('id',v_t.id,'repetida',false,'estornado',true);
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_compras_transferir_locais(p_empresa_id uuid, p_origem_tipo text, p_origem_id uuid, p_destino_tipo text, p_destino_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_galpao text, p_destino_galpao text, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if v_tipo1='OBRA' or v_tipo2='OBRA' then
  perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'LOCAIS',v_novo_id);
 end if;
 return jsonb_build_object('id',v_novo_id,'repetida',false,
   'saldo_origem',v_saldo-p_quantidade,'quantidade',p_quantidade);
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_insumos_estornar_transferencia(p_empresa_id uuid, p_transferencia_operacao_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_saida public.ew_insumos_movimentos%rowtype;
 v_entrada public.ew_insumos_movimentos%rowtype;v_total integer;
 v_saldo numeric;v_op uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,'estoque.estornar')) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
   and u.usuario_id=v_uid)
 then raise exception 'Somente ADM pode estornar transferências.';end if;
 if length(btrim(coalesce(p_motivo,''))) not between 5 and 400 or p_transferencia_operacao_id is null
 then raise exception 'Informe motivo de 5 a 400 caracteres e operação válida.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_transferencia_operacao_id::text,9011));
 select count(*) into v_total from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_transferencia_operacao_id
   and m.origem='TRANSFERENCIA';
 if v_total<>2 then raise exception 'Transferência original não encontrada ou incompleta.';end if;
 select * into v_saida from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta<0 for update;
 select * into v_entrada from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
   and m.operacao_id=p_transferencia_operacao_id and m.origem='TRANSFERENCIA'
   and m.quantidade_delta>0 for update;
 if v_saida.id is null or v_entrada.id is null or v_saida.insumo_id<>v_entrada.insumo_id
    or v_saida.quantidade_delta<>-v_entrada.quantidade_delta
 then raise exception 'Movimentos da transferência não conferem.';end if;
 if exists(select 1 from public.ew_insumos_movimentos m where m.estorno_de_id in (v_saida.id,v_entrada.id))
 then raise exception 'Transferência já estornada.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||v_entrada.obra_id::text||'|'||
   v_entrada.insumo_id::text||'|'||v_entrada.local_estoque,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo from public.ew_insumos_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_entrada.obra_id
   and m.insumo_id=v_entrada.insumo_id and m.local_estoque=v_entrada.local_estoque;
 if v_saldo<v_entrada.quantidade_delta then
  raise exception 'Estorno bloqueado: destino já utilizou/transferiu parte do material.';end if;
 insert into public.ew_insumos_movimentos(
  empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
  origem,operacao_id,estorno_de_id,observacao,usuario_id
 ) values
 (p_empresa_id,v_entrada.obra_id,v_entrada.insumo_id,v_entrada.local_estoque,
  -v_entrada.quantidade_delta,'ESTORNO',v_op,v_entrada.id,btrim(p_motivo),v_uid),
 (p_empresa_id,v_saida.obra_id,v_saida.insumo_id,v_saida.local_estoque,
  -v_saida.quantidade_delta,'ESTORNO',v_op,v_saida.id,btrim(p_motivo),v_uid);
 if v_saida.obra_id<>v_entrada.obra_id then
  perform ew_compras_interna.custo_estornar_se_integrada(p_empresa_id,'INSUMOS',v_saida.transferencia_id,v_op);
 end if;
 return jsonb_build_object('estornado',true,'operacao_estorno',v_op);
end
$function$;
CREATE OR REPLACE FUNCTION public.ew_insumos_transferir(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_insumo_id uuid, p_origem_local text, p_destino_local text, p_quantidade numeric, p_observacao text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();v_origem text:=upper(btrim(coalesce(p_origem_local,'')));
 v_destino text:=upper(btrim(coalesce(p_destino_local,'')));
 v_saldo numeric;v_qtd integer;v_transfer uuid:=gen_random_uuid();
begin
 IF NOT (public.ew_pode(p_empresa_id,case when p_origem_obra_id=p_destino_obra_id then 'estoque.transferir_galpoes' else 'estoque.transferir_obras' end)) THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: operação de estoque'; END IF;

 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id)
 then raise exception 'Somente ADM transfere estes materiais.';end if;
 if p_operacao_id is null or p_origem_obra_id is null or p_destino_obra_id is null
  or p_insumo_id is null or (p_origem_obra_id=p_destino_obra_id and v_origem=v_destino)
  or p_quantidade is null or p_quantidade<=0 or p_quantidade>1000000
  or p_quantidade<>round(p_quantidade,3) or length(coalesce(p_observacao,''))>400
 then raise exception 'Transferência inválida.';end if;
 if not exists(select 1 from public.ew_insumos_catalogo c where c.id=p_insumo_id
    and c.empresa_id=p_empresa_id and c.ativo)
 then raise exception 'Material não pertence à empresa ou está inativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_origem and l.ativo)
 or not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_destino and l.ativo)
 then raise exception 'Galpão de origem/destino inválido.';end if;
 if not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_origem_obra_id and l.excluido_em is null)
 or not exists(select 1 from public.ew_estoques_locais l
   where l.empresa_id=p_empresa_id and l.obra_id=p_destino_obra_id and l.excluido_em is null)
 then raise exception 'Obras com estoque ativo são obrigatórias.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,9011));
 select count(*) into v_qtd from public.ew_insumos_movimentos m
   where m.empresa_id=p_empresa_id and m.operacao_id=p_operacao_id and m.origem='TRANSFERENCIA';
 if v_qtd>0 then
   if v_qtd<>2 or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_origem_obra_id and m.local_estoque=v_origem
     and m.quantidade_delta=-p_quantidade
   ) or not exists(
    select 1 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
     and m.operacao_id=p_operacao_id and m.insumo_id=p_insumo_id
     and m.obra_id=p_destino_obra_id and m.local_estoque=v_destino
     and m.quantidade_delta=p_quantidade
   ) then raise exception 'Operação já utilizada em outra transferência.';end if;
   return jsonb_build_object('ja_registrado',true);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_origem_obra_id::text||'|'||
   p_insumo_id::text||'|'||v_origem,9012));
 select coalesce(sum(m.quantidade_delta),0) into v_saldo
 from public.ew_insumos_movimentos m where m.empresa_id=p_empresa_id
  and m.obra_id=p_origem_obra_id and m.insumo_id=p_insumo_id
  and m.local_estoque=v_origem;
 if v_saldo<p_quantidade then raise exception 'Saldo insuficiente na origem. Disponível: %',v_saldo;end if;
 insert into public.ew_insumos_movimentos(
   empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,origem,
   operacao_id,transferencia_id,observacao,usuario_id
 ) values
 (p_empresa_id,p_origem_obra_id,p_insumo_id,v_origem,-p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid),
 (p_empresa_id,p_destino_obra_id,p_insumo_id,v_destino,p_quantidade,'TRANSFERENCIA',
   p_operacao_id,v_transfer,coalesce(p_observacao,''),v_uid);
 if p_origem_obra_id<>p_destino_obra_id then
  perform ew_compras_interna.custo_primeira_transferencia(p_empresa_id,'INSUMOS',v_transfer);
 end if;
 return jsonb_build_object('transferencia_id',v_transfer,'ja_registrado',false);
end
$function$;
