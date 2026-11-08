-- EWGEST: controle de saída da produção para a obra (marcos e folhas)
-- Executar APENAS no SQL Editor do projeto ewgest-producao antes de publicar a interface.
-- Não modifica esquadrias, metragens, liberações ou fabricação já registradas.
BEGIN;

CREATE TABLE IF NOT EXISTS public.esquadrias_saida_config (
  esquadria_id uuid PRIMARY KEY REFERENCES public.esquadrias(id) ON DELETE RESTRICT,
  folhas_por_unidade integer NOT NULL CHECK (folhas_por_unidade BETWEEN 1 AND 12),
  configurado_por uuid NOT NULL REFERENCES auth.users(id),
  configurado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.saidas_producao (
  id uuid PRIMARY KEY,
  esquadria_id uuid NOT NULL REFERENCES public.esquadrias(id) ON DELETE RESTRICT,
  tipo text NOT NULL CHECK (tipo IN ('completo','marco','folha')),
  quantidade integer NOT NULL CHECK (quantidade > 0),
  data_saida date NOT NULL CHECK (data_saida >= DATE '2000-01-01'),
  usuario_id uuid NOT NULL REFERENCES auth.users(id),
  registrada_em timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS saidas_producao_esquadria_data_idx
ON public.saidas_producao(esquadria_id, data_saida DESC);

ALTER TABLE public.esquadrias_saida_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saidas_producao ENABLE ROW LEVEL SECURITY;

-- A aplicação apenas consulta estas tabelas. A gravação fica restrita à função abaixo.
REVOKE ALL ON public.esquadrias_saida_config FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.saidas_producao FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.esquadrias_saida_config, public.saidas_producao TO authenticated;

DROP POLICY IF EXISTS "Consultar composição das esquadrias da empresa" ON public.esquadrias_saida_config;
CREATE POLICY "Consultar composição das esquadrias da empresa"
ON public.esquadrias_saida_config FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.esquadrias e
  JOIN public.usuarios_empresas ue ON ue.empresa_id=e.empresa_id
  WHERE e.id=esquadrias_saida_config.esquadria_id
    AND ue.usuario_id=(SELECT auth.uid())
));

DROP POLICY IF EXISTS "Consultar saídas da empresa" ON public.saidas_producao;
CREATE POLICY "Consultar saídas da empresa"
ON public.saidas_producao FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.esquadrias e
  JOIN public.usuarios_empresas ue ON ue.empresa_id=e.empresa_id
  WHERE e.id=saidas_producao.esquadria_id
    AND ue.usuario_id=(SELECT auth.uid())
));

-- Cada registro representa um despacho: "completo" = uma esquadria com 1 marco e
-- todas as folhas; "marco" = marcos soltos; "folha" = folhas físicas avulsas.
-- Um UUID de operação evita duplicação em tentativas repetidas por falha de rede.
CREATE OR REPLACE FUNCTION public.registrar_saida_producao(
  p_registro_id uuid,
  p_esquadria_id uuid,
  p_tipo text,
  p_quantidade integer,
  p_data_saida date,
  p_folhas_por_unidade integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_usuario uuid := auth.uid();
  v_item public.esquadrias%ROWTYPE;
  v_folhas integer;
  v_marcos_enviados bigint;
  v_folhas_enviadas bigint;
  v_marcos_novos bigint;
  v_folhas_novas bigint;
  v_existente public.saidas_producao%ROWTYPE;
  v_primeira_liberacao date;
BEGIN
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
  IF p_folhas_por_unidade IS NULL OR p_folhas_por_unidade NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Confirme a quantidade de folhas por esquadria (1 a 12).';
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
      AND ue.perfil IN ('administrador','supervisor')
  ) THEN
    RAISE EXCEPTION 'Sem permissão para registrar saídas desta empresa.';
  END IF;
  IF COALESCE(v_item.qtd_liberada,0) <= 0 THEN
    RAISE EXCEPTION 'Este código ainda não possui unidades liberadas para corte.';
  END IF;

  SELECT * INTO v_existente FROM public.saidas_producao WHERE id=p_registro_id;
  IF FOUND THEN
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
  IF v_folhas IS NULL THEN
    INSERT INTO public.esquadrias_saida_config
      (esquadria_id,folhas_por_unidade,configurado_por)
    VALUES (p_esquadria_id,p_folhas_por_unidade,v_usuario);
    v_folhas:=p_folhas_por_unidade;
  ELSIF v_folhas<>p_folhas_por_unidade THEN
    RAISE EXCEPTION 'Composição já cadastrada: % folha(s) por esquadria. Não foi alterada.', v_folhas;
  END IF;

  SELECT COALESCE(SUM(CASE WHEN tipo IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo='completo' THEN quantidade*v_folhas
                           WHEN tipo='folha' THEN quantidade ELSE 0 END),0)
    INTO v_marcos_enviados,v_folhas_enviadas
    FROM public.saidas_producao
    WHERE esquadria_id=p_esquadria_id;

  v_marcos_novos:=CASE WHEN p_tipo IN ('completo','marco') THEN p_quantidade ELSE 0 END;
  v_folhas_novas:=CASE WHEN p_tipo='completo' THEN p_quantidade*v_folhas
                       WHEN p_tipo='folha' THEN p_quantidade ELSE 0 END;

  IF v_marcos_enviados + v_marcos_novos > v_item.qtd_liberada THEN
    RAISE EXCEPTION 'Marcos enviados superariam as % unidades liberadas. Saldo: %.',
      v_item.qtd_liberada,v_item.qtd_liberada-v_marcos_enviados;
  END IF;
  IF v_folhas_enviadas + v_folhas_novas > v_item.qtd_liberada*v_folhas THEN
    RAISE EXCEPTION 'Folhas enviadas superariam as folhas das unidades liberadas. Saldo: %.',
      v_item.qtd_liberada*v_folhas-v_folhas_enviadas;
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
    'folhas_enviadas',v_folhas_enviadas+v_folhas_novas,
    'marcos_possiveis',v_item.qtd_liberada,
    'folhas_possiveis',v_item.qtd_liberada*v_folhas
  );
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_saida_producao(uuid,uuid,text,integer,date,integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_saida_producao(uuid,uuid,text,integer,date,integer)
  TO authenticated;
COMMIT;
NOTIFY pgrst, 'reload schema';

-- Apenas conferência da instalação (não grava saídas).
SELECT p.proname AS funcao, pg_get_function_identity_arguments(p.oid) AS parametros
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='registrar_saida_producao';
