-- EWGEST v4 - Liberações para corte
-- Executar no SQL Editor de ewgest-producao, SOMENTE uma vez antes de publicar o novo app.html.
-- Não muda medidas, códigos, quantidades iniciais nem dados existentes.
BEGIN;

CREATE TABLE IF NOT EXISTS public.liberacoes_corte (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  esquadria_id uuid NOT NULL REFERENCES public.esquadrias(id) ON DELETE RESTRICT,
  quantidade integer NOT NULL CHECK (quantidade > 0),
  data_liberacao date NOT NULL,
  usuario_id uuid NOT NULL REFERENCES auth.users(id),
  registrada_em timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT liberacoes_corte_data_valida CHECK (data_liberacao >= DATE '2000-01-01')
);

CREATE INDEX IF NOT EXISTS liberacoes_corte_esquadria_idx
  ON public.liberacoes_corte(esquadria_id, data_liberacao DESC);

ALTER TABLE public.liberacoes_corte ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.liberacoes_corte FROM anon;
GRANT SELECT ON public.liberacoes_corte TO authenticated;

DROP POLICY IF EXISTS "Consultar liberações da empresa" ON public.liberacoes_corte;
CREATE POLICY "Consultar liberações da empresa"
ON public.liberacoes_corte FOR SELECT TO authenticated
USING (EXISTS (
 SELECT 1 FROM public.esquadrias e
 JOIN public.usuarios_empresas ue ON ue.empresa_id = e.empresa_id
 WHERE e.id = liberacoes_corte.esquadria_id
 AND ue.usuario_id = (SELECT auth.uid())
));

-- RPC executa validação e gravação atomicamente. Não dê acesso direto de INSERT ao navegador.
CREATE OR REPLACE FUNCTION public.registrar_liberacao_corte(
  p_esquadria_id uuid,
  p_quantidade integer,
  p_data_liberacao date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item public.esquadrias%ROWTYPE;
  v_usuario uuid;
  v_registro uuid;
BEGIN
  v_usuario := auth.uid();
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Faça login antes de registrar a liberação.';
  END IF;
  IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
    RAISE EXCEPTION 'Informe uma quantidade positiva.';
  END IF;
  IF p_data_liberacao IS NULL OR p_data_liberacao > current_date OR p_data_liberacao < DATE '2000-01-01' THEN
    RAISE EXCEPTION 'Informe uma data válida, não futura.';
  END IF;

  SELECT * INTO v_item
  FROM public.esquadrias
  WHERE id = p_esquadria_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esquadria não encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id = v_item.empresa_id
      AND ue.usuario_id = v_usuario
      AND ue.perfil IN ('administrador', 'supervisor')
  ) THEN
    RAISE EXCEPTION 'Você não tem permissão para liberar esquadrias desta empresa.';
  END IF;

  IF p_quantidade > v_item.quantidade - v_item.qtd_liberada THEN
    RAISE EXCEPTION 'Quantidade excede o saldo aguardando liberação (%).',
      v_item.quantidade - v_item.qtd_liberada;
  END IF;

  INSERT INTO public.liberacoes_corte(esquadria_id, quantidade, data_liberacao, usuario_id)
  VALUES (p_esquadria_id, p_quantidade, p_data_liberacao, v_usuario)
  RETURNING id INTO v_registro;

  UPDATE public.esquadrias
  SET qtd_liberada = qtd_liberada + p_quantidade
  WHERE id = p_esquadria_id;

  RETURN jsonb_build_object('registro_id',v_registro,'quantidade_liberada',p_quantidade,'saldo',v_item.quantidade - v_item.qtd_liberada - p_quantidade);
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_liberacao_corte(uuid, integer, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.registrar_liberacao_corte(uuid, integer, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_liberacao_corte(uuid, integer, date) TO authenticated;
COMMIT;

-- Verificação: deve retornar um objeto com nome e assinatura da função.
SELECT p.proname AS funcao, pg_get_function_identity_arguments(p.oid) AS parametros
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='registrar_liberacao_corte';