-- EWGEST #31 — Proposta NÃO aplicada em produção.
-- RPCs restritas ao recebimento pelo almoxarife. A função e a transação
-- financeira são independentes do acesso de leitura ao orçamento da obra.
-- Toda chamada verifica auth.uid(), sessão válida, empresa e perfil.
-- SECURITY DEFINER requer revisão criteriosa antes de implantação.
begin;

create or replace function public.ew_quantidades_recebidas_obra(
 p_empresa_id uuid,p_obra_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
    and u.empresa_id=p_empresa_id and u.perfil in ('almoxarife','administrador')
 ) or not exists (
  select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
 ) then
  raise exception 'Acesso não autorizado ao recebimento.';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'variacao_id',r.variacao_id,'comprimento_mm',r.comprimento_mm,
   'unidade',r.unidade,'quantidade',r.quantidade
 )), '[]'::jsonb)
 into v_result from (
  select n.variacao_id,n.comprimento_mm,n.unidade,sum(n.quantidade) quantidade
  from public.ew_nfe_recebimentos n
  join public.ew_obra_despesas_itens i on i.id=n.despesa_item_id and i.empresa_id=n.empresa_id
  join public.ew_obra_despesas d on d.id=i.despesa_id and d.empresa_id=n.empresa_id
  where n.empresa_id=p_empresa_id and n.obra_id=p_obra_id and d.status='aprovada'
  group by n.variacao_id,n.comprimento_mm,n.unidade
 ) r;
 return coalesce(v_result,'[]'::jsonb);
end
$func$;

create or replace function public.ew_receber_despesa_almox(
 p_empresa_id uuid,p_obra_id uuid,p_categoria text,p_valor numeric,
 p_fornecedor text,p_numero_documento text,p_data_documento date,
 p_observacoes text,p_operacao_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare v_uid uuid:=auth.uid();v_id uuid;v_old public.ew_obra_despesas%rowtype;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_operacao_id is null or
  not exists(select 1 from public.usuarios_empresas u
    where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and u.perfil='almoxarife')
 then raise exception 'Acesso não autorizado ao recebimento.';end if;
 if p_categoria not in ('vidros','outros') or p_valor is null or p_valor<=0
    or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
    or p_data_documento is null
    or char_length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
    or length(coalesce(p_fornecedor,''))>240
    or length(coalesce(p_observacoes,''))>1000
 then raise exception 'Dados da nota inválidos.';end if;
 if not exists(select 1 from public.ew_obra_orcamento o
    where o.empresa_id=p_empresa_id and o.obra_id=p_obra_id)
 then raise exception 'Obra sem orçamento vinculado.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 select * into v_old from public.ew_obra_despesas d
   where d.empresa_id=p_empresa_id and d.operacao_id=p_operacao_id;
 if found then
  if v_old.obra_id<>p_obra_id or v_old.categoria<>p_categoria or v_old.valor<>p_valor or v_old.status<>'aprovada'
  then raise exception 'Identificador já utilizado em outra operação.';end if;
  return jsonb_build_object('id',v_old.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
   and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
   and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
   and lower(btrim(d.fornecedor))=lower(btrim(coalesce(p_fornecedor,''))))
 then raise exception 'Já existe nota com mesmo número, fornecedor e categoria nesta obra.';end if;
 insert into public.ew_obra_despesas
  (empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,
   data_documento,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 values(p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',coalesce(p_fornecedor,''),
  btrim(p_numero_documento),p_data_documento,'aprovada',coalesce(p_observacoes,''),
  v_uid,v_uid,now(),p_operacao_id)
 returning id into v_id;
 return jsonb_build_object('id',v_id,'ja_registrado',false);
end
$func$;

create or replace function public.ew_receber_materiais_almox(
 p_empresa_id uuid,p_obra_id uuid,p_categoria text,p_valor numeric,
 p_fornecedor text,p_numero_documento text,p_data_documento date,
 p_observacoes text,p_local_estoque text,p_itens jsonb,p_operacao_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();
 v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_previous public.ew_obra_despesas%rowtype;
 v_despesa_id uuid;v_item_id uuid;v_mov_id uuid;
 v_row jsonb;v_var public.ew_materiais_variacoes%rowtype;
 v_codigo text;v_descricao text;v_unidade text;v_length integer;
 v_qty numeric;v_subtotal numeric;v_sum numeric:=0;v_count integer:=0;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas u
   where u.usuario_id=v_uid and u.empresa_id=p_empresa_id and u.perfil='almoxarife')
 then raise exception 'Acesso não autorizado ao recebimento.';end if;
 if p_categoria not in ('aluminio','acessorios') or p_valor is null
    or p_valor<=0 or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
    or p_data_documento is null
    or char_length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
    or length(coalesce(p_observacoes,''))>1000
    or jsonb_typeof(p_itens) is distinct from 'array'
    or jsonb_array_length(p_itens) not between 1 and 100
 then raise exception 'Nota ou itens recebidos inválidos.';end if;
 if not exists(select 1 from public.ew_fornecedores f where f.empresa_id=p_empresa_id
    and f.nome=p_fornecedor and f.ativo)
 then raise exception 'Selecione fornecedor cadastrado e ativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=p_empresa_id
    and l.nome=v_local and l.ativo)
 then raise exception 'Selecione galpão de destino ativo.';end if;
 if not exists(select 1 from public.ew_obra_orcamento o
    where o.empresa_id=p_empresa_id and o.obra_id=p_obra_id)
  or not exists(select 1 from public.ew_estoques_locais l where l.empresa_id=p_empresa_id
    and l.obra_id=p_obra_id and l.excluido_em is null)
 then raise exception 'Obra sem orçamento ou estoque ativo.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 select * into v_previous from public.ew_obra_despesas d
  where d.empresa_id=p_empresa_id and d.operacao_id=p_operacao_id;
 if found then
   if v_previous.obra_id<>p_obra_id or v_previous.categoria<>p_categoria
      or v_previous.valor<>p_valor or v_previous.status<>'aprovada'
   then raise exception 'Identificador já utilizado para outro lançamento.';end if;
   select count(*) into v_count
    from public.ew_nfe_recebimentos n
    join public.ew_obra_despesas_itens i on i.id=n.despesa_item_id
    where i.despesa_id=v_previous.id and n.empresa_id=p_empresa_id;
   if v_count<>jsonb_array_length(p_itens) then
    raise exception 'Operação anterior incompleta; confira antes de repetir.';end if;
   return jsonb_build_object('id',v_previous.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
   and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
   and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
   and lower(btrim(d.fornecedor))=lower(btrim(p_fornecedor)))
 then raise exception 'Já existe nota com este número, fornecedor e categoria nesta obra.';end if;

 -- Primeiro valida todas as linhas sem gravar saldos.
 for v_row in select value from jsonb_array_elements(p_itens) loop
   if jsonb_typeof(v_row) is distinct from 'object' or
     jsonb_typeof(v_row->'quantidade') is distinct from 'number' or
     jsonb_typeof(v_row->'valor_total') is distinct from 'number' or
     jsonb_typeof(v_row->'variacao_id') is distinct from 'string'
   then raise exception 'Linha de material incompleta.';end if;
   v_qty:=(v_row->>'quantidade')::numeric;
   v_subtotal:=(v_row->>'valor_total')::numeric;
   if v_qty<=0 or v_qty>1000000 or v_qty<>round(v_qty,3)
      or v_subtotal<0 or v_subtotal>999999999999.99 or v_subtotal<>round(v_subtotal,2)
   then raise exception 'Quantidade ou valor do material inválido.';end if;
   select * into v_var from public.ew_materiais_variacoes v
    where v.id=(v_row->>'variacao_id')::uuid and v.empresa_id=p_empresa_id and v.ativo;
   if not found or (p_categoria='aluminio' and v_var.tipo<>'perfil')
     or (p_categoria='acessorios' and v_var.tipo<>'acessorio')
   then raise exception 'Material ou cor incompatível com a categoria.';end if;
   if not exists(select 1 from public.ew_cem_obras_materiais m
     where m.empresa_id=p_empresa_id and m.obra_id=p_obra_id and m.variacao_id=v_var.id)
   then raise exception 'O material não está previsto nesta obra.';end if;
   if v_var.tipo='perfil' then
    if jsonb_typeof(v_row->'comprimento_mm') is distinct from 'number'
    then raise exception 'Informe o comprimento da barra.';end if;
    v_length:=(v_row->>'comprimento_mm')::integer;
    if v_length not between 100 and 20000 or v_qty<>trunc(v_qty)
    then raise exception 'Perfis exigem barras inteiras e comprimento válido.';end if;
   elsif v_row->>'comprimento_mm' is not null
   then raise exception 'Acessórios não possuem comprimento de barra.';end if;
   v_count:=v_count+1;v_sum:=v_sum+v_subtotal;
 end loop;
 if v_sum<>p_valor then raise exception 'A soma dos itens não confere com a nota.';end if;

 insert into public.ew_obra_despesas
 (empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,
  data_documento,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 values(p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',p_fornecedor,btrim(p_numero_documento),
  p_data_documento,'aprovada',coalesce(p_observacoes,''),v_uid,v_uid,now(),p_operacao_id)
 returning id into v_despesa_id;
 for v_row in select value from jsonb_array_elements(p_itens) loop
  select * into v_var from public.ew_materiais_variacoes v
   where v.id=(v_row->>'variacao_id')::uuid and v.empresa_id=p_empresa_id and v.ativo;
  v_qty:=(v_row->>'quantidade')::numeric;
  v_subtotal:=(v_row->>'valor_total')::numeric;
  if v_var.tipo='perfil' then
   select p.codigo,p.descricao into v_codigo,v_descricao from public.ew_perfis p
    where p.id=v_var.perfil_id and p.empresa_id=p_empresa_id;
   v_unidade:='BARRA';v_length:=(v_row->>'comprimento_mm')::integer;
  else
   select a.codigo,a.descricao,
    case when upper(btrim(a.unidade_item)) in ('PEÇA','PECA','PÇ','PÇS') then 'PC'
     when upper(btrim(a.unidade_item)) in ('PAR','PARES') then 'PR'
     when upper(btrim(a.unidade_item)) in ('METRO','M') then 'MT'
     when upper(btrim(a.unidade_item))='UNIDADE' then 'UN'
     else upper(btrim(a.unidade_item)) end
   into v_codigo,v_descricao,v_unidade
   from public.ew_acessorios a
   where a.id=v_var.acessorio_id and a.empresa_id=p_empresa_id;
   v_length:=null;
   if v_unidade not in ('PC','PR','CJ','MT','KG','UN')
   then raise exception 'Unidade do acessório não suportada.';end if;
  end if;
  if v_codigo is null then raise exception 'Material sem cadastro.';end if;
  insert into public.ew_obra_despesas_itens
  (despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
    valor_unitario,valor_total,perfil_id,acessorio_id)
  values(v_despesa_id,p_empresa_id,left(v_codigo,120),left(v_descricao,500),
    v_unidade,v_qty,round(v_subtotal/v_qty,6),v_subtotal,v_var.perfil_id,v_var.acessorio_id)
  returning id into v_item_id;
  -- Entrada física somente depois da nota validada. Mesmo commit/transação.
  insert into public.ew_estoque_obras_movimentos
  (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque)
  values(p_empresa_id,p_obra_id,v_var.id,v_length,v_unidade,v_qty,
   'COMPRA',gen_random_uuid(),'Recebimento NF '||left(p_numero_documento,75),
   v_uid,v_local)
  returning id into v_mov_id;
  insert into public.ew_nfe_recebimentos
  (empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,
   quantidade,local_estoque,movimento_id,usuario_id)
  values(p_empresa_id,p_obra_id,v_item_id,v_var.id,v_length,v_unidade,
   v_qty,v_local,v_mov_id,v_uid);
 end loop;
 return jsonb_build_object('id',v_despesa_id,'ja_registrado',false,
   'itens_recebidos',v_count,'obra_id',p_obra_id);
end
$func$;

revoke all on function public.ew_quantidades_recebidas_obra(uuid,uuid) from public;
revoke all on function public.ew_receber_despesa_almox(uuid,uuid,text,numeric,text,text,date,text,uuid) from public;
revoke all on function public.ew_receber_materiais_almox(uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid) from public;
revoke execute on function public.ew_quantidades_recebidas_obra(uuid,uuid) from anon;
revoke execute on function public.ew_receber_despesa_almox(uuid,uuid,text,numeric,text,text,date,text,uuid) from anon;
revoke execute on function public.ew_receber_materiais_almox(uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid) from anon;
grant execute on function public.ew_quantidades_recebidas_obra(uuid,uuid) to authenticated;
grant execute on function public.ew_receber_despesa_almox(uuid,uuid,text,numeric,text,text,date,text,uuid) to authenticated;
grant execute on function public.ew_receber_materiais_almox(uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid) to authenticated;

commit;
