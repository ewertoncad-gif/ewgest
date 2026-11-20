-- EWGEST - Entrada manual de materiais com nota e estoque em uma unica transacao.
-- Nao modifica saldos preexistentes nem processa XML; somente execucao com consentimento ADM.
CREATE OR REPLACE FUNCTION public.ew_registrar_recebimento_manual_financeiro(
 p_empresa_id uuid,p_obra_id uuid,p_categoria text,p_valor numeric,
 p_fornecedor text,p_numero_documento text,p_data_documento date,
 p_observacoes text,p_local_estoque text,p_itens jsonb,p_operacao_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
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
REVOKE ALL ON FUNCTION public.ew_registrar_recebimento_manual_financeiro(
 uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_registrar_recebimento_manual_financeiro(
 uuid,uuid,text,numeric,text,text,date,text,text,jsonb,uuid) TO authenticated;

-- Uma despesa vinculada a estoque físico não pode ser cancelada sem estorno.
-- O cancelamento simples anterior faria gasto=0 mas manteria as barras no estoque.
CREATE OR REPLACE FUNCTION public.ew_cancelar_despesa_financeira(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
   ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar despesas aprovadas.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe o motivo do cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'aprovada'
 THEN RAISE EXCEPTION 'Somente despesas aprovadas podem ser canceladas.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos r
    JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
    WHERE i.despesa_id=p_despesa_id AND r.empresa_id=p_empresa_id)
 THEN RAISE EXCEPTION 'Esta nota possui materiais recebidos. Estorne as entradas de estoque antes de cancelar a despesa.';END IF;
 UPDATE public.ew_obra_despesas
 SET status='cancelada',cancelado_por=v_uid,cancelado_em=now(),
 observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status','cancelada');
END;$function$;
