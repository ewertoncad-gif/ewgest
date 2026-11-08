-- EWGest: classificar um grupo pendente com o mesmo codigo + descricao de origem.
-- Cria tipologia provisoria revisavel, sem inventar codigos ou alterar historico.
-- Somente administrador autenticado. Mudancas feitas exclusivamente por RPC.
BEGIN;

CREATE OR REPLACE FUNCTION public.classificar_tipologia_pendente_admin(
  p_esquadria_id uuid,
  p_codigo text,
  p_descricao text,
  p_manter_vinculo_origem boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_item public.esquadrias%ROWTYPE;
  v_codigo text:=btrim(p_codigo);
  v_descricao text:=btrim(p_descricao);
  v_orig_code text;
  v_orig_desc text;
  v_tipologia_id uuid;
  v_qtd integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_esquadria_id IS NULL OR p_manter_vinculo_origem IS NULL
    OR v_codigo IS NULL OR length(v_codigo)<2 OR length(v_codigo)>80
    OR v_descricao IS NULL OR length(v_descricao)<5 OR length(v_descricao)>1000 THEN
    RAISE EXCEPTION 'Informe uma esquadria, um codigo, uma descricao e a opcao de vinculo validos.';
  END IF;

  SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria nao encontrada.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.usuario_id=v_uid AND ue.empresa_id=v_item.empresa_id
      AND lower(ue.perfil)='administrador'
  ) THEN
    RAISE EXCEPTION 'Somente o administrador pode classificar tipologias da empresa.';
  END IF;
  IF v_item.tipologia_id IS NOT NULL THEN
    RAISE EXCEPTION 'Esta esquadria ja possui uma tipologia. Atualize a tela antes de classificar.';
  END IF;
  v_orig_code:=nullif(btrim(v_item.rotulo_tipologia_relatorio),'');
  v_orig_desc:=nullif(btrim(v_item.descricao),'');
  IF v_orig_code IS NULL OR v_orig_desc IS NULL THEN
    RAISE EXCEPTION 'Este item nao tem codigo e descricao de origem para classificacao.';
  END IF;

  -- Garante que duas tentativas sobre o mesmo codigo e descricao nao abram
  -- simultaneamente novas tipologias para o mesmo grupo de esquadrias.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_item.empresa_id::text||'|'||v_orig_code||'|'||v_orig_desc));
  IF EXISTS (
    SELECT 1 FROM public.esquadrias e WHERE e.id=p_esquadria_id
       AND e.tipologia_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Este grupo ja foi classificado. Recarregue o catalogo.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tipologias t
    WHERE t.empresa_id=v_item.empresa_id
      AND upper(btrim(t.codigo))=upper(v_codigo)
  ) THEN
    RAISE EXCEPTION 'O codigo % ja existe no catalogo. Escolha outro codigo. A unificacao com uma tipologia existente exige uma operacao propria.',v_codigo;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tipologias_origens r
    WHERE r.empresa_id=v_item.empresa_id
      AND r.codigo_origem=v_orig_code
      AND r.descricao_origem=v_orig_desc
  ) THEN
    RAISE EXCEPTION 'Esta origem ja tem regra de vinculo. Revise a classificacao antes de continuar.';
  END IF;

  INSERT INTO public.tipologias(empresa_id,codigo,descricao,provisoria)
    VALUES (v_item.empresa_id,v_codigo,v_descricao,true)
    RETURNING id INTO v_tipologia_id;

  UPDATE public.esquadrias e
  SET tipologia_id=v_tipologia_id
  WHERE e.empresa_id=v_item.empresa_id
    AND e.tipologia_id IS NULL
    AND btrim(e.rotulo_tipologia_relatorio)=v_orig_code
    AND btrim(e.descricao)=v_orig_desc;
  GET DIAGNOSTICS v_qtd=ROW_COUNT;
  IF v_qtd<1 THEN RAISE EXCEPTION 'Nenhuma esquadria foi classificada.'; END IF;

  INSERT INTO public.tipologias_origens(
    empresa_id,tipologia_id,codigo_origem,descricao_origem,ativo)
  VALUES(v_item.empresa_id,v_tipologia_id,v_orig_code,v_orig_desc,
    p_manter_vinculo_origem);

  INSERT INTO public.tipologias_edicoes(
    empresa_id,tipologia_id,codigo_antes,descricao_antes,codigo_depois,
    descricao_depois,era_provisoria,manter_vinculo_origem,usuario_id)
  VALUES(
    v_item.empresa_id,v_tipologia_id,v_orig_code,v_orig_desc,v_codigo,
    v_descricao,true,p_manter_vinculo_origem,v_uid);

  RETURN jsonb_build_object(
    'tipologia_id',v_tipologia_id,
    'codigo',v_codigo,
    'esquadrias_classificadas',v_qtd,
    'codigo_origem',v_orig_code,
    'manter_vinculo_origem',p_manter_vinculo_origem,
    'provisoria',true);
END;
$$;

REVOKE ALL ON FUNCTION public.classificar_tipologia_pendente_admin(uuid,text,text,boolean)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.classificar_tipologia_pendente_admin(uuid,text,text,boolean)
  TO authenticated;
COMMIT;
NOTIFY pgrst,'reload schema';