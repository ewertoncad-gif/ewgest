-- EWGEST 46.29.22. Autorizações explícitas, exatas e por empresa.
-- Nenhum reconhecimento retroativo. Executar como migração transacional.
BEGIN;
CREATE SCHEMA IF NOT EXISTS ew_tipologias_interna;
REVOKE ALL ON SCHEMA ew_tipologias_interna FROM PUBLIC, anon, authenticated;
CREATE TABLE ew_tipologias_interna.regras_cem (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL,
 descricao_origem text COLLATE "C" NOT NULL CHECK (length(descricao_origem) BETWEEN 1 AND 1000),
 tipologia_id uuid NOT NULL, modulacao_id uuid NOT NULL, principal_id uuid NOT NULL,
 descricao_modulacao text COLLATE "C" NOT NULL, quantidade_modulos integer,
 descricao_tipologia text COLLATE "C" NOT NULL,
 obra_origem_id uuid NOT NULL, esquadria_origem_id uuid NOT NULL,
 autorizado_por uuid NOT NULL, autorizado_em timestamptz NOT NULL DEFAULT now(),
 desativado_por uuid, desativado_em timestamptz, ativo boolean NOT NULL DEFAULT true,
 CHECK ((ativo AND desativado_em IS NULL AND desativado_por IS NULL)
     OR (NOT ativo AND desativado_em IS NOT NULL AND desativado_por IS NOT NULL))
);
-- O hash evita o limite de tamanho do índice B-tree em descrições UTF-8 longas.
-- A consulta sempre compara também o texto integral; colisões não vinculam itens.
CREATE UNIQUE INDEX regras_cem_uma_ativa ON ew_tipologias_interna.regras_cem(empresa_id, md5(descricao_origem)) WHERE ativo;
CREATE TABLE ew_tipologias_interna.aplicacoes_cem (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), regra_id uuid NOT NULL,
 empresa_id uuid NOT NULL, obra_id uuid NOT NULL, esquadria_id uuid NOT NULL UNIQUE,
 tipologia_id uuid NOT NULL, modulacao_id uuid NOT NULL,
 descricao_origem text NOT NULL, importado_por uuid NOT NULL, importado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ew_tipologias_interna.regras_cem ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_tipologias_interna.aplicacoes_cem ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA ew_tipologias_interna FROM PUBLIC, anon, authenticated;
ALTER TABLE public.esquadrias ADD COLUMN reconhecimento_regra_cem_id uuid;
CREATE FUNCTION ew_tipologias_interna.bloquear_empresa(p_empresa_id uuid)
RETURNS void LANGUAGE sql SET search_path TO '' AS $$
 SELECT pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ew-tipologia-cem|'||p_empresa_id::text,0));
$$;
-- A regra só é válida enquanto o destino técnico continua intacto e não há
-- classificações conflitantes. A quantidade de módulos, quando informada dos
-- dois lados, deve ser compatível; não se deduz quantidade a partir de folhas.
CREATE FUNCTION ew_tipologias_interna.encontrar(p_empresa_id uuid,p_descricao text,p_modulos integer)
RETURNS uuid LANGUAGE sql STABLE SET search_path TO '' AS $$
 SELECT r.id
 FROM ew_tipologias_interna.regras_cem r
 JOIN public.tipologias t ON t.id=r.tipologia_id AND t.empresa_id=r.empresa_id
 JOIN public.tipologias p ON p.id=r.principal_id AND p.empresa_id=r.empresa_id
 JOIN public.tipologias_modulacoes m ON m.id=r.modulacao_id AND m.empresa_id=r.empresa_id
 WHERE r.empresa_id=p_empresa_id AND r.ativo
   AND md5(r.descricao_origem)=md5(btrim(p_descricao))
   AND r.descricao_origem=btrim(p_descricao) COLLATE "C"
   AND coalesce(t.tipologia_principal_id,t.id)=r.principal_id
   AND p.tipologia_principal_id IS NULL AND NOT t.provisoria AND NOT p.provisoria
   AND m.tipologia_principal_id=r.principal_id
   AND m.descricao COLLATE "C"=r.descricao_modulacao
   AND t.descricao COLLATE "C"=r.descricao_tipologia
   AND m.quantidade_modulos IS NOT DISTINCT FROM r.quantidade_modulos
   AND (p_modulos IS NULL OR m.quantidade_modulos IS NULL OR p_modulos=m.quantidade_modulos)
   AND NOT EXISTS (SELECT 1 FROM public.tipologias_modulacoes outra
      WHERE outra.empresa_id=r.empresa_id AND outra.id<>r.modulacao_id
        AND btrim(outra.descricao) COLLATE "C"=r.descricao_origem)
   AND NOT EXISTS (SELECT 1 FROM public.esquadrias e
      WHERE e.empresa_id=r.empresa_id AND btrim(e.descricao) COLLATE "C"=r.descricao_origem
      AND e.modulacao_id IS NOT NULL AND e.modulacao_id<>r.modulacao_id)
   AND NOT EXISTS (SELECT 1 FROM public.classificacoes_tipologias_auditoria a
      WHERE a.empresa_id=r.empresa_id AND btrim(a.descricao_origem) COLLATE "C"=r.descricao_origem
      AND a.modulacao_id IS NOT NULL AND a.modulacao_id<>r.modulacao_id);
$$;
CREATE FUNCTION public.ew_resolver_modulacao_com_regra(
 p_esquadria_id uuid,p_tipologia_id uuid,p_modulacao_id uuid,p_criar_modulacao boolean,
 p_descricao_modulacao text,p_quantidade_modulos integer,p_confirmar_divergencia boolean,
 p_reconhecer_futuras boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
 v_item public.esquadrias%rowtype; v_mod public.tipologias_modulacoes%rowtype;
 v_tip public.tipologias%rowtype; v_result jsonb; v_regra uuid; v_existente ew_tipologias_interna.regras_cem%rowtype;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id;
 IF auth.uid() IS NULL OR v_item.id IS NULL OR NOT public.ew_pode(v_item.empresa_id,'cadastros.editar') THEN
   RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar';
 END IF;
 IF p_reconhecer_futuras IS NULL THEN RAISE EXCEPTION 'Informe o alcance da associação.'; END IF;
 PERFORM ew_tipologias_interna.bloquear_empresa(v_item.empresa_id);
 -- Mantém a RPC existente como fonte das regras de família, duplicidade e auditoria.
 v_result:=public.resolver_modulacao_pendente_admin(p_esquadria_id,p_tipologia_id,p_modulacao_id,p_criar_modulacao,p_descricao_modulacao,p_quantidade_modulos,p_confirmar_divergencia);
 IF NOT p_reconhecer_futuras THEN RETURN v_result||jsonb_build_object('regra_autorizada',false); END IF;
 SELECT * INTO STRICT v_item FROM public.esquadrias WHERE id=p_esquadria_id AND empresa_id=v_item.empresa_id;
 SELECT * INTO STRICT v_mod FROM public.tipologias_modulacoes WHERE id=v_item.modulacao_id AND empresa_id=v_item.empresa_id;
 SELECT * INTO STRICT v_tip FROM public.tipologias WHERE id=v_item.tipologia_id AND empresa_id=v_item.empresa_id;
 SELECT * INTO v_existente FROM ew_tipologias_interna.regras_cem
  WHERE empresa_id=v_item.empresa_id AND ativo AND md5(descricao_origem)=md5(btrim(v_item.descricao));
 IF FOUND THEN
   IF v_existente.descricao_origem IS DISTINCT FROM btrim(v_item.descricao) COLLATE "C"
      OR v_existente.modulacao_id<>v_mod.id THEN
      RAISE EXCEPTION 'Conflito de reconhecimento: já existe outra regra. Desative a regra anterior ou confirme somente nesta obra.';
   END IF;
   v_regra:=v_existente.id;
 ELSE
   INSERT INTO ew_tipologias_interna.regras_cem(empresa_id,descricao_origem,tipologia_id,modulacao_id,principal_id,descricao_modulacao,descricao_tipologia,quantidade_modulos,obra_origem_id,esquadria_origem_id,autorizado_por)
    VALUES(v_item.empresa_id,btrim(v_item.descricao),v_tip.id,v_mod.id,v_mod.tipologia_principal_id,v_mod.descricao,v_tip.descricao,v_mod.quantidade_modulos,v_item.obra_id,v_item.id,auth.uid())
    RETURNING id INTO v_regra;
 END IF;
 IF ew_tipologias_interna.encontrar(v_item.empresa_id,v_item.descricao,v_item.quantidade_modulos) IS DISTINCT FROM v_regra THEN
   RAISE EXCEPTION 'Descrição ambígua, destino alterado ou módulos incompatíveis. Confirme somente nesta obra e revise os cadastros.';
 END IF;
 RETURN v_result||jsonb_build_object('regra_autorizada',true,'regra_id',v_regra);
END;
$$;
CREATE FUNCTION public.ew_listar_regras_cem(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'cadastros.editar') THEN
  RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar';
 END IF;
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(r)||jsonb_build_object('aplicavel',ew_tipologias_interna.encontrar(r.empresa_id,r.descricao_origem,NULL)=r.id) ORDER BY r.autorizado_em DESC)
  FROM ew_tipologias_interna.regras_cem r WHERE r.empresa_id=p_empresa_id),'[]'::jsonb);
END;
$$;
CREATE FUNCTION public.ew_desativar_regra_cem(p_regra_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_empresa uuid;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 SELECT empresa_id INTO v_empresa FROM ew_tipologias_interna.regras_cem WHERE id=p_regra_id;
 IF auth.uid() IS NULL OR v_empresa IS NULL OR NOT public.ew_pode(v_empresa,'cadastros.editar') THEN
  RAISE EXCEPTION 'PERMISSAO_NEGADA: cadastros.editar';
 END IF;
 PERFORM ew_tipologias_interna.bloquear_empresa(v_empresa);
 UPDATE ew_tipologias_interna.regras_cem SET ativo=false,desativado_em=now(),desativado_por=auth.uid()
 WHERE id=p_regra_id AND empresa_id=v_empresa AND ativo;
 RETURN jsonb_build_object('desativada',true);
END;
$$;
-- Consulta somente de leitura, protegida pela mesma permissão da importação.
CREATE FUNCTION public.ew_buscar_regra_cem(p_empresa_id uuid,p_descricao text,p_modulos integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'obras.importar') THEN
  RAISE EXCEPTION 'PERMISSAO_NEGADA: obras.importar';
 END IF;
 PERFORM ew_tipologias_interna.bloquear_empresa(p_empresa_id);
 RETURN ew_tipologias_interna.encontrar(p_empresa_id,p_descricao,p_modulos);
END;
$$;
-- Só a inserção de nova esquadria com marca explícita da importação usa a regra.
-- O registro histórico é imutável e nenhuma obra existente é atualizada.
CREATE FUNCTION ew_tipologias_interna.aplicar_regra_cem()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r ew_tipologias_interna.regras_cem%rowtype;
BEGIN
 IF TG_OP='UPDATE' THEN
  IF NEW.reconhecimento_regra_cem_id IS DISTINCT FROM OLD.reconhecimento_regra_cem_id THEN
   RAISE EXCEPTION 'A origem de reconhecimento é imutável.';
  END IF;
  RETURN NEW;
 END IF;
 IF NEW.reconhecimento_regra_cem_id IS NULL THEN RETURN NEW; END IF;
 IF auth.uid() IS NULL OR NOT public.ew_pode(NEW.empresa_id,'obras.importar') THEN
  RAISE EXCEPTION 'PERMISSAO_NEGADA: obras.importar';
 END IF;
 PERFORM ew_tipologias_interna.bloquear_empresa(NEW.empresa_id);
 IF ew_tipologias_interna.encontrar(NEW.empresa_id,NEW.descricao,NEW.quantidade_modulos) IS DISTINCT FROM NEW.reconhecimento_regra_cem_id THEN
  RAISE EXCEPTION 'Reconhecimento CEM inválido ou alterado. Atualize a importação.';
 END IF;
 SELECT * INTO STRICT r FROM ew_tipologias_interna.regras_cem WHERE id=NEW.reconhecimento_regra_cem_id AND empresa_id=NEW.empresa_id AND ativo;
 IF NEW.tipologia_id IS NOT NULL OR NEW.modulacao_id IS NOT NULL THEN
  RAISE EXCEPTION 'Não misture classificação explícita com reconhecimento automático.';
 END IF;
 NEW.tipologia_id:=r.tipologia_id; NEW.modulacao_id:=r.modulacao_id;
 INSERT INTO ew_tipologias_interna.aplicacoes_cem(regra_id,empresa_id,obra_id,esquadria_id,tipologia_id,modulacao_id,descricao_origem,importado_por)
 VALUES(r.id,NEW.empresa_id,NEW.obra_id,NEW.id,r.tipologia_id,r.modulacao_id,NEW.descricao,auth.uid());
 RETURN NEW;
END;
$$;
CREATE TRIGGER ew_reconhecimento_cem_guard BEFORE INSERT OR UPDATE OF reconhecimento_regra_cem_id ON public.esquadrias
 FOR EACH ROW EXECUTE FUNCTION ew_tipologias_interna.aplicar_regra_cem();
-- Altera apenas os campos do INSERT na RPC base, compartilhada pelas importações
-- financeira e de precificação. A migração falha se a versão de origem divergir.
DO $$
DECLARE v_sql text; v_old text; v_new text;
BEGIN
 SELECT pg_get_functiondef('public.ew_importar_obra_cem(uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb)'::regprocedure) INTO v_sql;
 v_old:='qtd_liberada,qtd_fabricada,rotulo_tipologia_relatorio,quantidade_modulos)';
 v_new:='qtd_liberada,qtd_fabricada,rotulo_tipologia_relatorio,quantidade_modulos,reconhecimento_regra_cem_id)';
 IF strpos(v_sql,v_old)=0 THEN RAISE EXCEPTION 'Importador CEM incompatível: lista de colunas.'; END IF;
 v_sql:=replace(v_sql,v_old,v_new);
 v_old:='nullif(v_rotulo,''''),v_modulos) RETURNING id INTO v_esquadria_id;';
 v_new:='nullif(v_rotulo,''''),v_modulos,public.ew_buscar_regra_cem(p_empresa_id,v_descricao,v_modulos)) RETURNING id INTO v_esquadria_id;';
 IF strpos(v_sql,v_old)=0 THEN RAISE EXCEPTION 'Importador CEM incompatível: lista de valores.'; END IF;
 EXECUTE replace(v_sql,v_old,v_new);
END;
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ew_tipologias_interna FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ew_resolver_modulacao_com_regra(uuid,uuid,uuid,boolean,text,integer,boolean,boolean),public.ew_listar_regras_cem(uuid),public.ew_desativar_regra_cem(uuid),public.ew_buscar_regra_cem(uuid,text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ew_resolver_modulacao_com_regra(uuid,uuid,uuid,boolean,text,integer,boolean,boolean),public.ew_listar_regras_cem(uuid),public.ew_desativar_regra_cem(uuid),public.ew_buscar_regra_cem(uuid,text,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
