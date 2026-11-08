-- EWGest: catalogo minimo de tipologias (codigos de fabricacao CEM)
-- Cadastro original preservado: dimensoes, quantidades, areas e liberacoes nao mudam.
CREATE TABLE IF NOT EXISTS public.tipologias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  codigo text NOT NULL,
  descricao text NOT NULL,
  criado_em timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tipologias_codigo_por_empresa_unique UNIQUE (empresa_id, codigo),
  CONSTRAINT tipologias_codigo_nao_vazio CHECK (length(btrim(codigo)) > 0)
);

ALTER TABLE public.tipologias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tipologias FROM PUBLIC, anon;
GRANT SELECT ON public.tipologias TO authenticated;
DROP POLICY IF EXISTS "Consultar tipologias da empresa" ON public.tipologias;
CREATE POLICY "Consultar tipologias da empresa"
ON public.tipologias FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=tipologias.empresa_id
    AND ue.usuario_id=(SELECT auth.uid())
));

ALTER TABLE public.esquadrias
  ADD COLUMN IF NOT EXISTS tipologia_id uuid REFERENCES public.tipologias(id);
CREATE INDEX IF NOT EXISTS esquadrias_tipologia_id_idx
  ON public.esquadrias(tipologia_id);

-- O PDF CEM apresentado confirma GOLS-JCR202 para EA4 e EA8.
-- Nao associamos outros codigos apenas por descricao similar.
INSERT INTO public.tipologias (empresa_id,codigo,descricao)
SELECT DISTINCT e.empresa_id,
  'GOLS-JCR202',
  'JANELA DE CORRER - 2 FOLHAS - PEITORIL FIXO - LINHA GOLD SLIM - HYDRO'
FROM public.esquadrias e
JOIN public.obras o ON o.id=e.obra_id
WHERE o.nome='CASA BOA VIAGEM'
  AND e.codigo IN ('EA4','EA8')
  AND e.descricao='JANELA DE CORRER - 2 FOLHAS - PEITORIL FIXO - LINHA GOLD SLIM - HYDRO'
ON CONFLICT (empresa_id,codigo) DO NOTHING;

UPDATE public.esquadrias e
SET tipologia_id=t.id
FROM public.tipologias t, public.obras o
WHERE e.obra_id=o.id
  AND o.nome='CASA BOA VIAGEM'
  AND e.empresa_id=t.empresa_id
  AND e.codigo IN ('EA4','EA8')
  AND e.descricao=t.descricao
  AND t.codigo='GOLS-JCR202'
  AND e.tipologia_id IS DISTINCT FROM t.id;

NOTIFY pgrst, 'reload schema';
