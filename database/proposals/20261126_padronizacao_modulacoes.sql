-- EWGEST 46.29.30: padronização explícita e transacional, sem recriar vínculos.
CREATE TABLE ew_tipologias_interna.padronizacoes_modulacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL, modulacao_id uuid NOT NULL, esquadria_referencia_id uuid NOT NULL,
 descricao_anterior text NOT NULL, descricao_nova text NOT NULL,
 quantidade_anterior integer, quantidade_nova integer NOT NULL,
 alterado_por uuid NOT NULL, alterado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ew_tipologias_interna.padronizacoes_modulacoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_tipologias_interna.padronizacoes_modulacoes FROM PUBLIC, anon, authenticated;
CREATE FUNCTION ew_tipologias_interna.modulos_explicitos(p_texto text)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
 SELECT CASE WHEN count(*)=1 AND max(length(ltrim(m[1],'0'))) BETWEEN 1 AND 3
 THEN CASE WHEN max(ltrim(m[1],'0'))::integer BETWEEN 1 AND 100 THEN max(ltrim(m[1],'0'))::integer END END
 FROM pg_catalog.regexp_matches(coalesce(p_texto,''), '\m([0-9]+)([[:space:]]+M[ÓO]DULO(?:S|\(S\))?)(?=$|[[:space:].,;:/-])','gi') AS m;
$$;
CREATE FUNCTION ew_tipologias_interna.descricao_padronizada(p_texto text,p_qtd integer)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
 SELECT CASE WHEN p_qtd BETWEEN 1 AND 100 AND ew_tipologias_interna.modulos_explicitos(p_texto) IS NOT NULL
 THEN pg_catalog.regexp_replace(btrim(p_texto),'\m([0-9]+)([[:space:]]+M[ÓO]DULO(?:S|\(S\))?)(?=$|[[:space:].,;:/-])',p_qtd::text||'\2','i') END;
$$;
CREATE FUNCTION public.ew_resolver_modulacao_padronizada(
 p_esquadria_id uuid,p_tipologia_id uuid,p_modulacao_esperada uuid,
 p_descricao_esperada text,p_quantidade_modulos integer,p_confirmar_divergencia boolean,p_reconhecer_futuras boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
 v_item public.esquadrias%rowtype; v_tip public.tipologias%rowtype;
 v_principal public.tipologias%rowtype; v_mod public.tipologias_modulacoes%rowtype;
 v_desc text; v_origem text; v_ids uuid[]; v_padronizada boolean:=false;
 v_result jsonb; v_qtd integer;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id;
 IF auth.uid() IS NULL OR v_item.id IS NULL OR NOT public.ew_pode(v_item.empresa_id,'cadastros.editar') THEN
  RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar';
 END IF;
 IF p_quantidade_modulos IS NULL OR p_quantidade_modulos NOT BETWEEN 1 AND 100
 OR p_confirmar_divergencia IS NULL OR p_reconhecer_futuras IS NULL THEN
  RAISE EXCEPTION 'Informe a modulação e as confirmações.';
 END IF;
 PERFORM ew_tipologias_interna.bloquear_empresa(v_item.empresa_id);
 SELECT * INTO STRICT v_item FROM public.esquadrias WHERE id=p_esquadria_id AND empresa_id=v_item.empresa_id FOR UPDATE;
 IF v_item.modulacao_id IS NOT NULL THEN RAISE EXCEPTION 'Pendência já resolvida; atualize a tela.'; END IF;
 SELECT * INTO STRICT v_tip FROM public.tipologias WHERE id=p_tipologia_id AND empresa_id=v_item.empresa_id AND NOT provisoria;
 SELECT * INTO STRICT v_principal FROM public.tipologias WHERE id=coalesce(v_tip.tipologia_principal_id,v_tip.id) AND empresa_id=v_item.empresa_id AND tipologia_principal_id IS NULL AND NOT provisoria FOR UPDATE;
 v_desc:=ew_tipologias_interna.descricao_padronizada(v_principal.descricao,p_quantidade_modulos);
 v_origem:=btrim(v_item.descricao);
 IF p_reconhecer_futuras AND ew_tipologias_interna.modulos_explicitos(v_origem) IS NOT NULL AND ew_tipologias_interna.modulos_explicitos(v_origem)<>p_quantidade_modulos THEN
  RAISE EXCEPTION 'A quantidade escolhida difere da origem CEM. Confirme somente nesta obra.';
 END IF;
 IF v_desc IS NULL OR v_desc COLLATE "C" IS DISTINCT FROM btrim(p_descricao_esperada) COLLATE "C" THEN
  RAISE EXCEPTION 'A descrição do catálogo mudou ou não pode ser adaptada; atualize a tela.';
 END IF;
 -- Somente mesma família, mesma quantidade expressa e descrição oficial ou origem exata.
 -- Qualquer outro candidato com a mesma quantidade exige revisão; nunca funde por quantidade.
 SELECT array_agg(m.id ORDER BY m.id) INTO v_ids FROM public.tipologias_modulacoes m
 WHERE m.empresa_id=v_item.empresa_id AND m.tipologia_principal_id=v_principal.id
 AND ((btrim(m.descricao) COLLATE "C"=v_desc COLLATE "C" OR (btrim(m.descricao) COLLATE "C"=v_origem COLLATE "C" AND ew_tipologias_interna.modulos_explicitos(m.descricao)=p_quantidade_modulos))
 OR m.quantidade_modulos=p_quantidade_modulos
 OR ew_tipologias_interna.modulos_explicitos(m.descricao)=p_quantidade_modulos);
 IF coalesce(cardinality(v_ids),0)>1 THEN RAISE EXCEPTION 'Mais de uma configuração possível para esta modulação. Revise o cadastro.'; END IF;
 IF coalesce(cardinality(v_ids),0)=1 THEN
  SELECT * INTO STRICT v_mod FROM public.tipologias_modulacoes WHERE id=v_ids[1] AND empresa_id=v_item.empresa_id FOR UPDATE;
  v_qtd:=ew_tipologias_interna.modulos_explicitos(v_mod.descricao);
  IF btrim(v_mod.descricao) COLLATE "C" NOT IN (v_desc COLLATE "C",v_origem COLLATE "C")
     OR v_qtd IS DISTINCT FROM p_quantidade_modulos
     OR (v_mod.quantidade_modulos IS NOT NULL AND v_mod.quantidade_modulos<>p_quantidade_modulos) THEN
   RAISE EXCEPTION 'Configuração existente com descrição ou quantidade incompatível. Revise o cadastro.';
  END IF;
 END IF;
 IF v_mod.id IS DISTINCT FROM p_modulacao_esperada THEN RAISE EXCEPTION 'A variação disponível mudou; atualize a tela.'; END IF;
 IF v_mod.id IS NOT NULL AND (v_mod.descricao COLLATE "C" IS DISTINCT FROM v_desc COLLATE "C" OR v_mod.quantidade_modulos IS DISTINCT FROM p_quantidade_modulos) THEN
  IF NOT p_confirmar_divergencia THEN RAISE EXCEPTION 'Confirme a padronização da descrição antes de associar.'; END IF;
  -- Não reescreve, desativa ou invalida silenciosamente autorizações já concedidas.
  IF EXISTS(SELECT 1 FROM ew_tipologias_interna.regras_cem r WHERE r.empresa_id=v_item.empresa_id AND r.modulacao_id=v_mod.id AND r.ativo) THEN
   RAISE EXCEPTION 'Esta variação possui reconhecimento ativo. Revise a autorização antes de padronizar.';
  END IF;
  INSERT INTO ew_tipologias_interna.padronizacoes_modulacoes(empresa_id,modulacao_id,esquadria_referencia_id,descricao_anterior,descricao_nova,quantidade_anterior,quantidade_nova,alterado_por)
  VALUES(v_item.empresa_id,v_mod.id,v_item.id,v_mod.descricao,v_desc,v_mod.quantidade_modulos,p_quantidade_modulos,auth.uid());
  UPDATE public.tipologias_modulacoes SET descricao=v_desc,quantidade_modulos=p_quantidade_modulos
  WHERE id=v_mod.id AND empresa_id=v_item.empresa_id AND tipologia_principal_id=v_principal.id;
  v_padronizada:=true;
 END IF;
 -- A RPC anterior conserva a validação de família, permissões, escopo e auditoria.
 -- Se a autorização futura falhar, a padronização e a associação são revertidas juntas.
 v_result:=public.ew_resolver_modulacao_com_regra(p_esquadria_id,p_tipologia_id,v_mod.id,v_mod.id IS NULL,
  CASE WHEN v_mod.id IS NULL THEN v_desc END,CASE WHEN v_mod.id IS NULL THEN p_quantidade_modulos END,
  p_confirmar_divergencia,p_reconhecer_futuras);
 RETURN v_result||jsonb_build_object('modulacao_padronizada',v_padronizada);
END;
$$;
REVOKE ALL ON FUNCTION ew_tipologias_interna.modulos_explicitos(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ew_tipologias_interna.descricao_padronizada(text,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ew_resolver_modulacao_padronizada(uuid,uuid,uuid,text,integer,boolean,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ew_resolver_modulacao_padronizada(uuid,uuid,uuid,text,integer,boolean,boolean) TO authenticated;

NOTIFY pgrst,'reload schema';
