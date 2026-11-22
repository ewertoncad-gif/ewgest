-- EWGEST v46.15 — vínculo imutável das contrapartidas parciais.
-- USO INTERNO: chamadas somente pelas funções de estorno; nenhuma leitura
-- nem escrita direta pela API/Data API do Supabase.
BEGIN;
CREATE TABLE IF NOT EXISTS public.ew_estornos_parcelas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  obra_id uuid NOT NULL REFERENCES public.obras(id),
  operacao_id uuid NOT NULL,
  movimento_original_id uuid NOT NULL REFERENCES public.ew_estoque_obras_movimentos(id) ON DELETE RESTRICT,
  movimento_estorno_id uuid NOT NULL UNIQUE REFERENCES public.ew_estoque_obras_movimentos(id) ON DELETE RESTRICT,
  local_estoque text NOT NULL,
  quantidade numeric NOT NULL CHECK(quantidade > 0),
  criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ew_estornos_parcelas_operacao_idx
  ON public.ew_estornos_parcelas (operacao_id,empresa_id);
CREATE INDEX IF NOT EXISTS ew_estornos_parcelas_original_idx
  ON public.ew_estornos_parcelas (movimento_original_id);
ALTER TABLE public.ew_estornos_parcelas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_estornos_parcelas FROM PUBLIC, anon, authenticated;
COMMIT;
