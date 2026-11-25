BEGIN;
-- v46.25: reconfirmação auditável de composição física sem alterar documentos antigos.
ALTER TABLE public.ew_auditoria_operacoes DROP CONSTRAINT ew_auditoria_operacoes_acao_check;
ALTER TABLE public.ew_auditoria_operacoes ADD CONSTRAINT ew_auditoria_operacoes_acao_check
CHECK (acao IN ('CANCELAR_ROMANEIO','CANCELAR_SAIDAS_AVULSAS','CANCELAR_LIBERACOES','ESTORNAR_ESTOQUE','ARQUIVAR_OBRA','CORRIGIR_ESCOPO_LIBERACAO','CORRIGIR_COMPOSICAO_SAIDA'));
CREATE OR REPLACE FUNCTION public.registrar_saida_producao(p_registro_id uuid, p_esquadria_id uuid, p_tipo text, p_quantidade integer, p_data_saida date, p_folhas_por_unidade integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_item public.esquadrias%ROWTYPE;
  v_folhas integer;
  v_marcos_liberados bigint;
  v_folhas_liberadas bigint;
  v_completas_enviadas bigint;
  v_marcos_enviados bigint;
  v_folhas_enviadas bigint;
  v_marcos_novos bigint;
  v_folhas_novas bigint;
  v_existente public.saidas_producao%ROWTYPE;
  v_primeira_liberacao date;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Entre na EWGEST para registrar uma saída.';
  END IF;
  IF p_registro_id IS NULL OR p_esquadria_id IS NULL THEN
    RAISE EXCEPTION 'Identificador do registro ou da esquadria ausente.';
  END IF;
  IF p_tipo IS NULL OR p_tipo NOT IN ('completo','marco','folha') THEN
    RAISE EXCEPTION 'Escolha completo, marco ou folha.';
  END IF;
  IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
    RAISE EXCEPTION 'Informe quantidade inteira e positiva.';
  END IF;
  IF p_data_saida IS NULL OR p_data_saida < DATE '2000-01-01' OR p_data_saida > current_date THEN
    RAISE EXCEPTION 'Informe uma data de saída válida e não futura.';
  END IF;
  -- Conjunto completo não precisa informar a composição física das folhas.
  -- Ela será confirmada quando houver saída desmembrada, se ainda não existir no cadastro.
  IF p_folhas_por_unidade IS NOT NULL AND p_folhas_por_unidade NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Quantidade de folhas por esquadria inválida (1 a 12).';
  END IF;
  IF p_tipo IN ('marco','folha') AND p_folhas_por_unidade IS NULL THEN
    RAISE EXCEPTION 'Informe a composição de folhas para expedição desmembrada.';
  END IF;

  -- Serializa lançamentos do mesmo item e garante que não superem o liberado.
  SELECT * INTO v_item FROM public.esquadrias
  WHERE id=p_esquadria_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esquadria não encontrada.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_item.empresa_id
      AND ue.usuario_id=v_usuario
      AND (
        ue.perfil IN ('administrador','gerenciador','supervisor')
        OR (
          ue.perfil='almoxarife'
          AND EXISTS(
            SELECT 1 FROM public.usuarios_login ul
            WHERE ul.usuario_id=v_usuario AND ul.empresa_id=ue.empresa_id
              AND ul.perfil='almoxarife' AND ul.ativo
          )
          AND EXISTS(
            SELECT 1 FROM public.romaneios r
            WHERE r.id::text=pg_catalog.current_setting('ewgest.romaneio_emissao_id',true)
              AND r.criado_por=v_usuario AND r.empresa_id=v_item.empresa_id
              AND r.obra_id=v_item.obra_id AND r.status='emitido'
              AND r.criado_em=pg_catalog.transaction_timestamp()
          )
        )
      )
  ) THEN
    RAISE EXCEPTION 'Sem permissão para registrar saídas desta empresa.';
  END IF;
  -- MAXIM-AR sai sempre como conjunto completo, sem opção de marco ou folha separados.
  IF v_item.descricao ~* 'MAXIM[[:space:]-]*AR' AND p_tipo<>'completo' THEN
    RAISE EXCEPTION 'MAXIM-AR só pode ser expedido como esquadria completa.';
  END IF;
  IF COALESCE(v_item.qtd_liberada,0) <= 0 THEN
    RAISE EXCEPTION 'Este código ainda não possui unidades liberadas para corte.';
  END IF;

  SELECT * INTO v_existente FROM public.saidas_producao WHERE id=p_registro_id;
  IF FOUND THEN
    IF v_existente.cancelado_em IS NOT NULL THEN
      RAISE EXCEPTION 'Saída já cancelada; não é possível reativar este identificador.';
    END IF;
    IF v_existente.esquadria_id<>p_esquadria_id
      OR v_existente.tipo<>p_tipo
      OR v_existente.quantidade<>p_quantidade
      OR v_existente.data_saida<>p_data_saida THEN
      RAISE EXCEPTION 'Identificador de operação já utilizado para outro lançamento.';
    END IF;
    RETURN jsonb_build_object('registro_id',v_existente.id,'repetido',true);
  END IF;

  SELECT folhas_por_unidade INTO v_folhas
    FROM public.esquadrias_saida_config
    WHERE esquadria_id=p_esquadria_id;
  IF v_folhas IS NULL AND p_folhas_por_unidade IS NOT NULL THEN
    INSERT INTO public.esquadrias_saida_config
      (esquadria_id,folhas_por_unidade,configurado_por)
    VALUES (p_esquadria_id,p_folhas_por_unidade,v_usuario);
    v_folhas:=p_folhas_por_unidade;
  ELSIF v_folhas IS NOT NULL AND p_folhas_por_unidade IS NOT NULL
    AND v_folhas<>p_folhas_por_unidade THEN
    -- Uma composição antiga só pode ser corrigida após estorno de TODOS os
    -- documentos ativos e quando corresponde à descrição técnica da esquadria.
    IF p_folhas_por_unidade IS DISTINCT FROM
       (substring(upper(v_item.descricao) from '([0-9]{1,2})[[:space:]]*FOLHA'))::integer
       OR EXISTS(SELECT 1 FROM public.saidas_producao s WHERE s.esquadria_id=v_item.id AND s.cancelado_em IS NULL)
       OR EXISTS(SELECT 1 FROM public.romaneios_itens i JOIN public.romaneios h ON h.id=i.romaneio_id
          WHERE i.esquadria_id=v_item.id AND h.status='emitido' AND h.cancelado_em IS NULL)
       OR EXISTS(SELECT 1 FROM public.ew_obra_faturamentos_itens i JOIN public.ew_obra_faturamentos h ON h.id=i.faturamento_id
          WHERE i.esquadria_id=v_item.id AND h.status='emitido') THEN
      RAISE EXCEPTION 'Composição já cadastrada: % folha(s). Confira a descrição técnica e estorne as saídas, romaneios e faturamentos ativos antes de corrigir.', v_folhas;
    END IF;
    INSERT INTO public.ew_auditoria_operacoes(empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,referencia_id,motivo,detalhes)
    SELECT v_item.empresa_id,o.id,o.nome,o.codigo,v_usuario,'CORRIGIR_COMPOSICAO_SAIDA',v_item.id,
      'Correção da composição física confirmada na expedição, sem documentos ativos',
      jsonb_build_object('folhas_anteriores',v_folhas,'folhas_novas',p_folhas_por_unidade,'esquadria',v_item.codigo,'registro_saida',p_registro_id)
    FROM public.obras o WHERE o.id=v_item.obra_id AND o.empresa_id=v_item.empresa_id;
    UPDATE public.esquadrias_saida_config SET folhas_por_unidade=p_folhas_por_unidade,
      configurado_por=v_usuario,configurado_em=now() WHERE esquadria_id=v_item.id;
    v_folhas:=p_folhas_por_unidade;
  END IF;
  IF v_folhas IS NULL AND p_tipo<>'completo' THEN
    RAISE EXCEPTION 'Antes de desmembrar, confirme a quantidade de folhas por esquadria.';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN tipo IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo='completo' THEN quantidade*v_folhas
                           WHEN tipo='folha' THEN quantidade ELSE 0 END),0)
    INTO v_marcos_enviados,v_folhas_enviadas
    FROM public.saidas_producao
    WHERE esquadria_id=p_esquadria_id AND cancelado_em IS NULL;

  v_marcos_novos:=CASE WHEN p_tipo IN ('completo','marco') THEN p_quantidade ELSE 0 END;
  v_folhas_novas:=CASE WHEN p_tipo='completo' THEN p_quantidade*v_folhas
                       WHEN p_tipo='folha' THEN p_quantidade ELSE 0 END;

  -- A autorização de saída exige que a PARTE também tenha sido liberada.
  SELECT COALESCE(SUM(CASE WHEN tipo_componente IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo_componente IN ('completo','folhas') THEN quantidade ELSE 0 END),0)
    INTO v_marcos_liberados,v_folhas_liberadas
    FROM public.liberacoes_corte
   WHERE esquadria_id=p_esquadria_id AND cancelado_em IS NULL;
  IF v_marcos_enviados+v_marcos_novos>v_marcos_liberados THEN
    RAISE EXCEPTION 'Marcos sem liberação suficiente. Disponíveis: %.',v_marcos_liberados-v_marcos_enviados;
  END IF;
  IF v_folhas IS NOT NULL AND v_folhas_enviadas+v_folhas_novas>v_folhas_liberadas*v_folhas THEN
    RAISE EXCEPTION 'Folhas sem liberação suficiente. Conjuntos liberados: %.',v_folhas_liberadas;
  END IF;
  IF p_tipo='completo' AND v_folhas IS NULL THEN
    SELECT COALESCE(SUM(quantidade),0) INTO v_completas_enviadas
    FROM public.saidas_producao WHERE esquadria_id=p_esquadria_id
      AND tipo='completo' AND cancelado_em IS NULL;
    IF v_completas_enviadas+p_quantidade>v_folhas_liberadas THEN
      RAISE EXCEPTION 'Não há conjuntos de folhas liberados para essa saída completa.';
    END IF;
  END IF;

  -- Bloqueia datas de saída anteriores à primeira liberação registrada do item.
  SELECT MIN(data_liberacao) INTO v_primeira_liberacao
  FROM public.liberacoes_corte WHERE esquadria_id=p_esquadria_id;
  IF v_primeira_liberacao IS NOT NULL AND p_data_saida<v_primeira_liberacao THEN
    RAISE EXCEPTION 'A saída não pode anteceder a primeira liberação (%).',
      v_primeira_liberacao;
  END IF;

  INSERT INTO public.saidas_producao
    (id,esquadria_id,tipo,quantidade,data_saida,usuario_id)
  VALUES (p_registro_id,p_esquadria_id,p_tipo,p_quantidade,p_data_saida,v_usuario);

  RETURN jsonb_build_object(
    'registro_id',p_registro_id,
    'repetido',false,
    'marcos_enviados',v_marcos_enviados+v_marcos_novos,
    'folhas_enviadas',CASE WHEN v_folhas IS NULL THEN NULL ELSE v_folhas_enviadas+v_folhas_novas END,
    'marcos_possiveis',v_marcos_liberados,
    'folhas_possiveis',CASE WHEN v_folhas IS NULL THEN NULL ELSE v_folhas_liberadas*v_folhas END
  );
END;
$function$;
COMMIT;
