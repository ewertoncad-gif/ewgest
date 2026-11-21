-- EWGEST #34 — recebimento atômico de vidros/outros com estoque físico.
-- O lançamento grava documento, itens e estoque na mesma transação.
create or replace function public.ew_insumos_receber(
 p_empresa_id uuid,p_obra_id uuid,p_categoria text,p_valor numeric,
 p_fornecedor text,p_numero_documento text,p_data_documento date,
 p_observacoes text,p_operacao_id uuid,p_itens jsonb,p_local_estoque text
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();v_item jsonb;v_despesa uuid;v_despesa_item uuid;v_catalogo uuid;
 v_antiga public.ew_obra_despesas%rowtype;
 v_qtd numeric;v_subtotal numeric;v_total numeric:=0;v_count integer:=0;
 v_desc text;v_unit text;v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_cad public.ew_insumos_catalogo%rowtype;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
    and u.usuario_id=v_uid and u.perfil in ('administrador','almoxarife'))
 then raise exception 'Usuário sem permissão para recebimento.';end if;
 if p_categoria not in ('vidros','outros') or p_valor is null or p_valor<=0
  or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
  or p_data_documento is null or length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
  or length(coalesce(p_observacoes,''))>1000
  or jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) not between 1 and 100
 then raise exception 'Categoria, valor ou itens de NF inválidos.';end if;
 if not exists(select 1 from public.ew_obra_orcamento b
    where b.empresa_id=p_empresa_id and b.obra_id=p_obra_id)
  or not exists(select 1 from public.ew_estoques_locais l
    where l.empresa_id=p_empresa_id and l.obra_id=p_obra_id and l.excluido_em is null)
 then raise exception 'Selecione obra com orçamento e estoque ativo.';end if;
 if not exists(select 1 from public.ew_locais_fisicos l
    where l.empresa_id=p_empresa_id and l.nome=v_local and l.ativo)
 then raise exception 'Galpão de recebimento não cadastrado/ativo.';end if;
 if not exists(select 1 from public.ew_fornecedores f
    where f.empresa_id=p_empresa_id and f.nome=p_fornecedor and f.ativo)
 then raise exception 'Selecione fornecedor ativo cadastrado.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria||'|'||
   lower(btrim(p_fornecedor))||'|'||lower(btrim(p_numero_documento)),541890));
 select * into v_antiga from public.ew_obra_despesas d
 where d.empresa_id=p_empresa_id and d.operacao_id=p_operacao_id;
 if found then
  if v_antiga.obra_id<>p_obra_id or v_antiga.categoria<>p_categoria
   or v_antiga.valor<>p_valor or v_antiga.status<>'aprovada'
   then raise exception 'Identificador de operação reutilizado para outro documento.';end if;
  select count(*) into v_count from public.ew_insumos_movimentos m
   join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
   where i.despesa_id=v_antiga.id and m.empresa_id=p_empresa_id and m.origem='RECEBIMENTO';
  if v_count<>jsonb_array_length(p_itens) then
   raise exception 'Nota anterior não possui os itens físicos esperados.';end if;
  return jsonb_build_object('id',v_antiga.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
  and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
  and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
  and lower(btrim(d.fornecedor))=lower(btrim(p_fornecedor)))
 then raise exception 'Nota já recebida deste fornecedor/categoria nesta obra.';end if;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   if jsonb_typeof(v_item) is distinct from 'object'
    or jsonb_typeof(v_item->'quantidade') is distinct from 'number'
    or jsonb_typeof(v_item->'valor_total') is distinct from 'number'
   then raise exception 'Item da nota deve ter quantidade e subtotal numéricos.';end if;
   v_desc:=upper(btrim(pg_catalog.regexp_replace(coalesce(v_item->>'descricao',''),'\s+',' ','g')));
   v_unit:=btrim(coalesce(v_item->>'unidade',''));
   v_qtd:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   if length(v_desc) not between 2 and 500
    or v_unit not in ('PC','UN','M2','MT','KG','CX','CJ','PR')
    or v_qtd<=0 or v_qtd>1000000 or v_qtd<>round(v_qtd,3)
    or (v_unit in ('PC','UN','CX','CJ','PR') and v_qtd<>trunc(v_qtd))
    or v_subtotal<0 or v_subtotal>999999999999.99 or v_subtotal<>round(v_subtotal,2)
   then raise exception 'Descrição, unidade, quantidade ou subtotal inválidos.';end if;
   v_count:=v_count+1;v_total:=v_total+v_subtotal;
 end loop;
 if v_total<>p_valor then raise exception 'A soma dos itens não confere com o valor da nota.';end if;
 insert into public.ew_obra_despesas(
  empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,data_documento,
  status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id
 ) values(
  p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',p_fornecedor,btrim(p_numero_documento),
  p_data_documento,'aprovada',coalesce(p_observacoes,''),v_uid,v_uid,now(),p_operacao_id
 ) returning id into v_despesa;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   v_desc:=upper(btrim(pg_catalog.regexp_replace(v_item->>'descricao','\s+',' ','g')));
   v_unit:=v_item->>'unidade';v_qtd:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   -- Cadastro compartilhado, sem mesclar itens de unidades distintas.
   insert into public.ew_insumos_catalogo(empresa_id,categoria,descricao,unidade,criado_por)
   values(p_empresa_id,p_categoria,v_desc,v_unit,v_uid)
   on conflict(empresa_id,categoria,descricao,unidade) do nothing;
   select * into v_cad from public.ew_insumos_catalogo c
    where c.empresa_id=p_empresa_id and c.categoria=p_categoria
     and c.descricao=v_desc and c.unidade=v_unit for update;
   if not found or not v_cad.ativo then raise exception 'Insumo desativado ou indisponível no catálogo.';end if;
   v_catalogo:=v_cad.id;
   insert into public.ew_obra_despesas_itens(
    despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
    valor_unitario,valor_total,perfil_id,acessorio_id
   ) values(v_despesa,p_empresa_id,'',v_desc,v_unit,v_qtd,
     round(v_subtotal/v_qtd,6),v_subtotal,null,null)
   returning id into v_despesa_item;
   insert into public.ew_insumos_movimentos(
    empresa_id,obra_id,insumo_id,local_estoque,quantidade_delta,
    origem,despesa_item_id,operacao_id,observacao,usuario_id
   ) values(p_empresa_id,p_obra_id,v_catalogo,v_local,v_qtd,'RECEBIMENTO',
    v_despesa_item,p_operacao_id,'Recebimento NF '||left(p_numero_documento,70),v_uid);
 end loop;
 return jsonb_build_object('id',v_despesa,'ja_registrado',false,'itens',v_count,'estoque_fisico',true);
end
$func$;
revoke all on function public.ew_insumos_receber(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb,text) from public;
revoke execute on function public.ew_insumos_receber(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb,text) from anon;
grant execute on function public.ew_insumos_receber(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb,text) to authenticated;
