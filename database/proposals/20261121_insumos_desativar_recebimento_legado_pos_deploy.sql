-- EWGEST #34 — aplicar DEPOIS da confirmação de publicação da v45.2.
-- Impede que o formulário legado crie custo sem correspondente estoque físico.
CREATE OR REPLACE FUNCTION public.ew_registrar_despesa_financeira(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_origem text, p_chave_nfe text, p_itens jsonb, p_observacoes text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();v_id uuid;v_linha jsonb;v_perfil uuid;v_acessorio uuid;
 v_qtd numeric;v_preco numeric;v_total numeric;
 v_chave text:=nullif(btrim(coalesce(p_chave_nfe,'')),'');
 v_antigo uuid;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF p_origem='manual' AND p_categoria IN ('vidros','outros') THEN
   RAISE EXCEPTION 'Vidros e outros insumos: registre a nota pelo Recebimento físico da versão atualizada.';
 END IF;
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM registra despesas financeiras.';END IF;
 IF p_operacao_id IS NULL OR p_obra_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.ew_obra_orcamento
   WHERE obra_id=p_obra_id AND empresa_id=p_empresa_id)
 THEN RAISE EXCEPTION 'Selecione uma obra com orçamento registrado.';END IF;
 IF p_categoria NOT IN ('aluminio','acessorios','vidros','outros') OR
    p_valor IS NULL OR p_valor<=0 OR p_valor>999999999999.99 OR
    p_valor<>round(p_valor,2) OR p_origem NOT IN ('manual','nfe_xml') OR
    length(coalesce(p_fornecedor,''))>240 OR length(coalesce(p_numero_documento,''))>100 OR
    length(coalesce(p_observacoes,''))>1000 THEN
  RAISE EXCEPTION 'Dados financeiros da despesa inválidos.';END IF;
 IF v_chave IS NOT NULL AND v_chave !~ '^[0-9]{44}$' THEN RAISE EXCEPTION 'Chave da NF-e inválida (44 dígitos).';END IF;
 IF p_origem='nfe_xml' AND v_chave IS NULL THEN RAISE EXCEPTION 'XML sem chave NF-e identificada.';END IF;
 IF jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens)>500
 THEN RAISE EXCEPTION 'Itens da despesa inválidos.';END IF;
 SELECT id INTO v_antigo FROM public.ew_obra_despesas WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF v_antigo IS NOT NULL THEN RETURN jsonb_build_object('id',v_antigo,'ja_registrado',true);END IF;
 INSERT INTO public.ew_obra_despesas(
 empresa_id,obra_id,categoria,valor,fornecedor,numero_documento,data_documento,
 origem,chave_nfe,status,observacoes,criado_por,aprovado_por,aprovado_em,operacao_id)
 VALUES(p_empresa_id,p_obra_id,p_categoria,p_valor,coalesce(p_fornecedor,''),
 coalesce(p_numero_documento,''),p_data_documento,p_origem,v_chave,
 'aprovada',coalesce(p_observacoes,''),v_uid,v_uid,now(),p_operacao_id)
 RETURNING id INTO v_id;
 FOR v_linha IN SELECT value FROM jsonb_array_elements(p_itens) LOOP
  IF jsonb_typeof(v_linha) IS DISTINCT FROM 'object' OR
     jsonb_typeof(v_linha->'quantidade') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_linha->'valor_unitario') IS DISTINCT FROM 'number' OR
     jsonb_typeof(v_linha->'valor_total') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'Item incompleto na nota.';END IF;
  v_qtd:=(v_linha->>'quantidade')::numeric;
  v_preco:=(v_linha->>'valor_unitario')::numeric;
  v_total:=(v_linha->>'valor_total')::numeric;
  IF v_qtd<=0 OR v_qtd>1e9 OR v_preco<0 OR v_preco>1e9 OR v_total<0 OR v_total>1e11
  THEN RAISE EXCEPTION 'Quantidade ou preço inválido no XML.'; END IF;
  v_perfil:=nullif(v_linha->>'perfil_id','')::uuid;
  v_acessorio:=nullif(v_linha->>'acessorio_id','')::uuid;
  IF v_perfil IS NOT NULL AND v_acessorio IS NOT NULL
  THEN RAISE EXCEPTION 'Item com duas classificações.';END IF;
  IF v_perfil IS NOT NULL AND (p_categoria<>'aluminio' OR NOT EXISTS(
    SELECT 1 FROM public.ew_perfis WHERE id=v_perfil AND empresa_id=p_empresa_id))
  THEN RAISE EXCEPTION 'Perfil não encontrado no catálogo da empresa.';END IF;
  IF v_acessorio IS NOT NULL AND (p_categoria<>'acessorios' OR NOT EXISTS(
    SELECT 1 FROM public.ew_acessorios WHERE id=v_acessorio AND empresa_id=p_empresa_id))
  THEN RAISE EXCEPTION 'Acessório não encontrado no catálogo da empresa.';END IF;
  INSERT INTO public.ew_obra_despesas_itens(
   despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,valor_unitario,valor_total,perfil_id,acessorio_id)
  VALUES(v_id,p_empresa_id,left(coalesce(v_linha->>'codigo',''),120),
   left(coalesce(v_linha->>'descricao',''),500),
   left(coalesce(v_linha->>'unidade',''),30),v_qtd,v_preco,v_total,v_perfil,v_acessorio);
 END LOOP;
 RETURN jsonb_build_object('id',v_id,'ja_registrado',false,'valor',p_valor,'itens',jsonb_array_length(p_itens));
END;$function$;

revoke execute on function public.ew_receber_despesa_com_itens_almox(uuid,uuid,text,numeric,text,text,date,text,uuid,jsonb) from authenticated;
