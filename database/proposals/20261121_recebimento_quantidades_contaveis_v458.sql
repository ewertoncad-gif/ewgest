-- EWGEST v45.8: protegendo quantidades contaveis de acessorios em recebimentos NF.
-- Mantem metros e quilos fracionaveis. Nao altera estoque historico.
CREATE OR REPLACE FUNCTION public.ew_receber_materiais_almox(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_observacoes text, p_local_estoque text, p_itens jsonb, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 -- Serializar por número da nota, fornecedor e categoria além do UUID da operação:
 -- duas sessões usando UUIDs diferentes não devem duplicar a mesma NF.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   p_empresa_id::text||'|'||p_obra_id::text||'|'||p_categoria||'|'||
   lower(btrim(coalesce(p_fornecedor,'')))||'|'||lower(btrim(p_numero_documento)),541890));
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
  if v_unidade in ('PC','UN','PR','CJ','CX') and v_qty<>trunc(v_qty) then
   raise exception 'Acessorios em % exigem quantidade inteira (1, 2, 3...).',v_unidade;
  end if;
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
$function$;

CREATE OR REPLACE FUNCTION public.ew_registrar_recebimento_manual_financeiro(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_observacoes text, p_local_estoque text, p_itens jsonb, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_op_anterior public.ew_obra_despesas%ROWTYPE;
 v_despesa jsonb;v_despesa_id uuid;v_row jsonb;
 v_var public.ew_materiais_variacoes%ROWTYPE;
 v_codigo text;v_descricao text;v_unidade text;
 v_quantidade numeric;v_item_valor numeric;v_soma numeric:=0;
 v_comprimento integer;v_recebimento uuid;v_mov jsonb;v_item_id uuid;
 v_count integer:=0;v_total_itens integer;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_empresa_id IS NULL OR p_obra_id IS NULL OR p_operacao_id IS NULL OR
    NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
      WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode registrar entrada de material e nota fiscal.';END IF;
 IF p_categoria NOT IN ('aluminio','acessorios') OR p_valor IS NULL OR
   p_valor<=0 OR p_valor>999999999999.99 OR p_valor<>round(p_valor,2)
 THEN RAISE EXCEPTION 'Categoria ou valor total da nota inválidos.';END IF;
 IF jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR
   jsonb_array_length(p_itens) NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Selecione de 1 a 100 materiais recebidos.';END IF;
 v_total_itens:=jsonb_array_length(p_itens);
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais
   WHERE empresa_id=p_empresa_id AND obra_id=p_obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'O estoque da obra não existe ou está arquivado.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_locais_fisicos
   WHERE empresa_id=p_empresa_id AND nome=v_local AND ativo)
 THEN RAISE EXCEPTION 'Informe um galpão ativo cadastrado.';END IF;
 IF length(btrim(coalesce(p_numero_documento,''))) NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Informe o número da nota/documento.';END IF;
 IF length(coalesce(p_fornecedor,''))>240 OR length(coalesce(p_observacoes,''))>1000
 THEN RAISE EXCEPTION 'Fornecedor ou observação muito extensos.';END IF;
 -- Impede tentativas simultâneas com a mesma operação e repetições após falha de rede.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_operacao_id::text,541889));
 SELECT * INTO v_op_anterior FROM public.ew_obra_despesas
 WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF v_op_anterior.obra_id<>p_obra_id OR v_op_anterior.categoria<>p_categoria
    OR v_op_anterior.valor<>p_valor OR v_op_anterior.status<>'aprovada'
  THEN RAISE EXCEPTION 'Identificador de operação já utilizado para outro lançamento.'; END IF;
  SELECT count(*) INTO v_count FROM public.ew_nfe_recebimentos n
   JOIN public.ew_obra_despesas_itens i ON i.id=n.despesa_item_id
   WHERE i.despesa_id=v_op_anterior.id AND n.empresa_id=p_empresa_id;
  IF v_count<>v_total_itens THEN
   RAISE EXCEPTION 'Operação existente não possui todos os recebimentos. Confira o histórico.';END IF;
  RETURN jsonb_build_object('id',v_op_anterior.id,'ja_registrado',true,'itens_recebidos',v_count);
 END IF;

 -- Valida tudo antes da primeira gravação. Cada linha requer valor para preservar custo unitário.
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_row->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_row->'valor_total') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Informe quantidade e subtotal de cada material.';END IF;
  v_quantidade:=(v_row->>'quantidade')::numeric;
  v_item_valor:=(v_row->>'valor_total')::numeric;
  IF v_quantidade<=0 OR v_quantidade>1000000 OR v_quantidade<>round(v_quantidade,3)
     OR v_item_valor<0 OR v_item_valor>999999999999.99 OR v_item_valor<>round(v_item_valor,2)
  THEN RAISE EXCEPTION 'Quantidade ou subtotal do material inválidos.';END IF;
  IF jsonb_typeof(v_row->'variacao_id') IS DISTINCT FROM 'string'
  THEN RAISE EXCEPTION 'Informe a cor/variação de cada material.';END IF;
  SELECT * INTO v_var FROM public.ew_materiais_variacoes
   WHERE id=(v_row->>'variacao_id')::uuid AND empresa_id=p_empresa_id AND ativo;
  IF NOT FOUND OR
    (p_categoria='aluminio' AND v_var.tipo<>'perfil') OR
    (p_categoria='acessorios' AND v_var.tipo<>'acessorio')
  THEN RAISE EXCEPTION 'Material ou variação incompatível com a categoria.'; END IF;
  IF v_var.tipo='perfil' THEN
   IF jsonb_typeof(v_row->'comprimento_mm') IS DISTINCT FROM 'number'
   THEN RAISE EXCEPTION 'Informe o comprimento das barras em mm.';END IF;
   v_comprimento:=(v_row->>'comprimento_mm')::integer;
   IF v_comprimento NOT BETWEEN 100 AND 20000 OR v_quantidade<>trunc(v_quantidade)
   THEN RAISE EXCEPTION 'Perfis exigem barras inteiras e comprimento comercial válido.';END IF;
  ELSE
   IF v_row ? 'comprimento_mm' AND v_row->>'comprimento_mm' IS NOT NULL
   THEN RAISE EXCEPTION 'Acessórios não devem informar comprimento de barra.';END IF;
  END IF;
  v_soma:=v_soma+v_item_valor; v_count:=v_count+1;
 END LOOP;
 IF v_soma<>p_valor
 THEN RAISE EXCEPTION 'A soma dos subtotais dos itens deve ser igual ao valor total da nota.';END IF;

 v_despesa:=public.ew_registrar_despesa_financeira(p_empresa_id,p_obra_id,p_categoria,
  p_valor,p_fornecedor,p_numero_documento,p_data_documento,'manual',NULL,
  '[]'::jsonb,p_observacoes,p_operacao_id);
 IF coalesce((v_despesa->>'ja_registrado')::boolean,false) OR (v_despesa->>'id') IS NULL
 THEN RAISE EXCEPTION 'Documento já registrado; confira o histórico antes de repetir.'; END IF;
 v_despesa_id:=(v_despesa->>'id')::uuid;

 FOR v_row IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  SELECT * INTO v_var FROM public.ew_materiais_variacoes
   WHERE id=(v_row->>'variacao_id')::uuid AND empresa_id=p_empresa_id AND ativo;
  v_quantidade:=(v_row->>'quantidade')::numeric;
  v_item_valor:=(v_row->>'valor_total')::numeric;
  IF v_var.tipo='perfil' THEN
   SELECT p.codigo,p.descricao INTO v_codigo,v_descricao
   FROM public.ew_perfis p WHERE p.id=v_var.perfil_id AND p.empresa_id=p_empresa_id;
   v_unidade:='BARRA';v_comprimento:=(v_row->>'comprimento_mm')::integer;
  ELSE
   SELECT a.codigo,a.descricao,
     CASE
       WHEN upper(btrim(a.unidade_item)) IN ('PEÇA','PECA','PÇ','PÇS') THEN 'PC'
       WHEN upper(btrim(a.unidade_item)) IN ('PAR','PARES') THEN 'PR'
       WHEN upper(btrim(a.unidade_item)) IN ('METRO','M') THEN 'MT'
       WHEN upper(btrim(a.unidade_item))='UNIDADE' THEN 'UN'
       ELSE upper(btrim(a.unidade_item))
     END INTO v_codigo,v_descricao,v_unidade
   FROM public.ew_acessorios a WHERE a.id=v_var.acessorio_id AND a.empresa_id=p_empresa_id;
   v_comprimento:=NULL;
   IF v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN')
   THEN RAISE EXCEPTION 'Unidade do acessório não suportada para estoque físico (%).',v_unidade;END IF;
  END IF;
  IF v_codigo IS NULL THEN RAISE EXCEPTION 'Material sem cadastro válido.';END IF;
  IF v_unidade IN ('PC','UN','PR','CJ','CX') AND v_quantidade<>trunc(v_quantidade) THEN
   RAISE EXCEPTION 'Acessorios em % exigem quantidade inteira (1, 2, 3...).',v_unidade;
  END IF;
  INSERT INTO public.ew_obra_despesas_itens
   (despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,
    quantidade,valor_unitario,valor_total,perfil_id,acessorio_id)
  VALUES(v_despesa_id,p_empresa_id,left(v_codigo,120),left(v_descricao,500),
    v_unidade,v_quantidade,round(v_item_valor/v_quantidade,6),v_item_valor,
    v_var.perfil_id,v_var.acessorio_id)
  RETURNING id INTO v_item_id;
  v_mov:=public.ew_movimentar_estoque_obra_local(p_empresa_id,p_obra_id,v_var.id,
    v_comprimento,v_unidade,v_quantidade,'COMPRA',
    'Entrada manual NF '||left(p_numero_documento,75),gen_random_uuid(),v_local);
  IF coalesce((v_mov->>'repetida')::boolean,false) OR (v_mov->>'id') IS NULL
  THEN RAISE EXCEPTION 'Falha ao vincular movimento ao estoque da obra.';END IF;
  INSERT INTO public.ew_nfe_recebimentos
   (empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,
    quantidade,local_estoque,movimento_id,usuario_id)
  VALUES(p_empresa_id,p_obra_id,v_item_id,v_var.id,v_comprimento,v_unidade,
    v_quantidade,v_local,(v_mov->>'id')::uuid,v_uid) RETURNING id INTO v_recebimento;
 END LOOP;
 RETURN jsonb_build_object('id',v_despesa_id,'obra_id',p_obra_id,
  'itens_recebidos',v_count,'valor',p_valor,'local_estoque',v_local,'ja_registrado',false);
END;
$function$;
