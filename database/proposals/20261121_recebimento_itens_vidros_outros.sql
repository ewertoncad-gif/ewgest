-- EWGEST #31: registrar vidro/outros insumos discriminados, sem entrada de estoque fictícia.
-- Criar somente após testar/homologar. Autorização do almoxarife por empresa e sessão.
create or replace function public.ew_receber_despesa_com_itens_almox(
 p_empresa_id uuid,p_obra_id uuid,p_categoria text,p_valor numeric,
 p_fornecedor text,p_numero_documento text,p_data_documento date,
 p_observacoes text,p_operacao_id uuid,p_itens jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $func$
declare
 v_uid uuid:=auth.uid();v_item jsonb;v_despesa uuid;
 v_previous public.ew_obra_despesas%rowtype;
 v_qty numeric;v_subtotal numeric;v_total numeric:=0;
 v_descricao text;v_unidade text;v_count integer:=0;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_empresa_id is null or p_obra_id is null or p_operacao_id is null
    or not exists(select 1 from public.usuarios_empresas u where u.empresa_id=p_empresa_id
      and u.usuario_id=v_uid and u.perfil='almoxarife')
 then raise exception 'Acesso não autorizado ao recebimento.';end if;
 if p_categoria not in ('vidros','outros') or p_valor is null
    or p_valor<=0 or p_valor>999999999999.99 or p_valor<>round(p_valor,2)
    or p_data_documento is null or
    length(btrim(coalesce(p_numero_documento,''))) not between 1 and 100
    or length(coalesce(p_observacoes,''))>1000
    or jsonb_typeof(p_itens) is distinct from 'array'
    or jsonb_array_length(p_itens) not between 1 and 100
 then raise exception 'Nota, categoria ou itens inválidos.';end if;
 if not exists(select 1 from public.ew_obra_orcamento o
      where o.empresa_id=p_empresa_id and o.obra_id=p_obra_id)
 then raise exception 'Obra sem orçamento cadastrado.';end if;
 if not exists(select 1 from public.ew_fornecedores f where f.empresa_id=p_empresa_id
      and f.nome=p_fornecedor and f.ativo)
 then raise exception 'Selecione um fornecedor ativo cadastrado.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria||'|'||
   lower(btrim(p_fornecedor))||'|'||lower(btrim(p_numero_documento)),541890));
 select * into v_previous from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
   and d.operacao_id=p_operacao_id;
 if found then
   if v_previous.obra_id<>p_obra_id or v_previous.categoria<>p_categoria
      or v_previous.valor<>p_valor or v_previous.status<>'aprovada'
   then raise exception 'Identificador já utilizado para outro lançamento.';end if;
   select count(*) into v_count from public.ew_obra_despesas_itens i
     where i.despesa_id=v_previous.id and i.empresa_id=p_empresa_id;
   if v_count<>jsonb_array_length(p_itens) then
    raise exception 'Documento anterior não corresponde ao número de itens.';end if;
   return jsonb_build_object('id',v_previous.id,'ja_registrado',true);
 end if;
 if exists(select 1 from public.ew_obra_despesas d where d.empresa_id=p_empresa_id
     and d.obra_id=p_obra_id and d.status='aprovada' and d.categoria=p_categoria
     and lower(btrim(d.numero_documento))=lower(btrim(p_numero_documento))
     and lower(btrim(d.fornecedor))=lower(btrim(p_fornecedor)))
 then raise exception 'Esta nota já foi lançada para o fornecedor e categoria selecionados.';end if;

 for v_item in select value from jsonb_array_elements(p_itens) loop
   if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item->'quantidade') is distinct from 'number'
      or jsonb_typeof(v_item->'valor_total') is distinct from 'number'
   then raise exception 'Item sem quantidade ou subtotal numérico.';end if;
   v_descricao:=btrim(coalesce(v_item->>'descricao',''));
   v_unidade:=btrim(coalesce(v_item->>'unidade',''));
   v_qty:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   if char_length(v_descricao) not between 2 and 500
      or v_unidade not in ('PC','UN','M2','MT','KG','CX','CJ','PR')
      or v_qty<=0 or v_qty>1000000 or v_qty<>round(v_qty,3)
      or v_subtotal<0 or v_subtotal>999999999999.99
      or v_subtotal<>round(v_subtotal,2)
   then raise exception 'Descrição, unidade, quantidade ou valor inválido no item.';end if;
   v_total:=v_total+v_subtotal;
   v_count:=v_count+1;
 end loop;
 if v_total<>p_valor then raise exception 'A soma dos itens não corresponde ao total da nota.';end if;
 insert into public.ew_obra_despesas(
  empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,
  data_documento,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 values(p_empresa_id,p_obra_id,p_categoria,p_valor,'manual',p_fornecedor,
   btrim(p_numero_documento),p_data_documento,'aprovada',coalesce(p_observacoes,''),
   v_uid,v_uid,now(),p_operacao_id)
 returning id into v_despesa;
 for v_item in select value from jsonb_array_elements(p_itens) loop
   v_qty:=(v_item->>'quantidade')::numeric;
   v_subtotal:=(v_item->>'valor_total')::numeric;
   insert into public.ew_obra_despesas_itens(
     despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,
     valor_unitario,valor_total,perfil_id,acessorio_id)
   values(v_despesa,p_empresa_id,'',left(btrim(v_item->>'descricao'),500),
     v_item->>'unidade',v_qty,round(v_subtotal/v_qty,6),v_subtotal,null,null);
 end loop;
 -- Nenhuma gravação em ew_nfe_recebimentos ou ew_estoque_obras_movimentos:
 -- não há catálogo físico de vidros/outros insumos neste estágio.
 return jsonb_build_object('id',v_despesa,'ja_registrado',false,
   'itens_recebidos',v_count,'sem_estoque_fisico',true);
end
$func$;
revoke all on function public.ew_receber_despesa_com_itens_almox(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb) from public;
revoke execute on function public.ew_receber_despesa_com_itens_almox(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb) from anon;
grant execute on function public.ew_receber_despesa_com_itens_almox(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb) to authenticated;
