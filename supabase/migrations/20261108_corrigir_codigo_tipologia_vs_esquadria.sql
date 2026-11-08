-- CORRECAO EWGEST: nao confundir codigo da esquadria com codigo da tipologia.
-- Origem: relatorio CEM CASA BOA VIAGEM (12 pags). A importacao anterior usou
-- alguns cabecalhos que eram identificadores de itens (ex.: EA3) como tipologia.
-- Guardar os rotulos do relatorio em coluna separada para auditoria/revisao futura.
-- Na tabela mestre ficam somente 13 codigos de sistema claramente identificados.
-- Nao altera quantidade, metragem, liberacoes nem saidas de producao.
BEGIN;

ALTER TABLE public.esquadrias
  ADD COLUMN IF NOT EXISTS rotulo_tipologia_relatorio text;

DO $$
DECLARE
  v_empresa uuid;
  v_codigos int;
  v_tipologias int;
BEGIN
  SELECT id INTO STRICT v_empresa
  FROM public.empresas WHERE nome='GVG ESQUADRIAS';
  SELECT COUNT(*) INTO v_codigos
  FROM public.esquadrias e
  JOIN public.obras o ON o.id=e.obra_id
  WHERE o.nome='CASA BOA VIAGEM' AND o.codigo='ALU-3195-GVG-PE' AND o.empresa_id=v_empresa;
  IF v_codigos<>70 THEN
    RAISE EXCEPTION 'A obra mudou desde a revisao (% itens). Revisar antes de corrigir tipologias.',v_codigos;
  END IF;
  SELECT COUNT(*) INTO v_tipologias FROM public.tipologias WHERE empresa_id=v_empresa;
  IF v_tipologias<>37 THEN
    RAISE EXCEPTION 'O catalogo mudou desde a revisao (% codigos). Revisar antes de corrigir.',v_tipologias;
  END IF;
END $$;

UPDATE public.esquadrias e
SET rotulo_tipologia_relatorio=t.codigo
FROM public.tipologias t
WHERE e.tipologia_id=t.id
  AND e.rotulo_tipologia_relatorio IS NULL
  AND e.obra_id IN (
    SELECT o.id FROM public.obras o
    JOIN public.empresas emp ON emp.id=o.empresa_id
    WHERE o.nome='CASA BOA VIAGEM' AND o.codigo='ALU-3195-GVG-PE'
      AND emp.nome='GVG ESQUADRIAS'
  );

-- Somente vinculos cuja classificacao nao estava comprovada sao desfeitos.
UPDATE public.esquadrias e
SET tipologia_id=NULL
FROM public.tipologias t
WHERE e.tipologia_id=t.id
  AND t.empresa_id IN (SELECT id FROM public.empresas WHERE nome='GVG ESQUADRIAS')
  AND t.codigo NOT IN (
    'GOL-FIXN01',
    'GOLS-JCR200',
    'GOLS-JCR202',
    'GOLS-PCR200',
    'INV-FIXN00',
    'INV-PFGR01',
    'INV-PGR10201FXVZ',
    'INV-PGR107',
    'INV-PGR207',
    'INV-VNZN00',
    'PKA-JCR200',
    'SPLITNATV02',
    'UNIV-R08-GRADN00'
  );

-- Remover apenas classificacoes incorretas sem vinculos, nao itens das obras.
DELETE FROM public.tipologias t
WHERE t.empresa_id IN (SELECT id FROM public.empresas WHERE nome='GVG ESQUADRIAS')
  AND t.codigo NOT IN (
    'GOL-FIXN01',
    'GOLS-JCR200',
    'GOLS-JCR202',
    'GOLS-PCR200',
    'INV-FIXN00',
    'INV-PFGR01',
    'INV-PGR10201FXVZ',
    'INV-PGR107',
    'INV-PGR207',
    'INV-VNZN00',
    'PKA-JCR200',
    'SPLITNATV02',
    'UNIV-R08-GRADN00'
  )
  AND NOT EXISTS (SELECT 1 FROM public.esquadrias e WHERE e.tipologia_id=t.id);

DO $$
DECLARE
  v_catalogo int;
  v_confirmadas int;
  v_pendentes int;
  v_salvas int;
BEGIN
  SELECT COUNT(*) INTO v_catalogo
    FROM public.tipologias t
    JOIN public.empresas emp ON emp.id=t.empresa_id
    WHERE emp.nome='GVG ESQUADRIAS';
  SELECT COUNT(*) FILTER (WHERE e.tipologia_id IS NOT NULL),
         COUNT(*) FILTER (WHERE e.tipologia_id IS NULL),
         COUNT(*) FILTER (WHERE e.rotulo_tipologia_relatorio IS NOT NULL)
    INTO v_confirmadas,v_pendentes,v_salvas
    FROM public.esquadrias e JOIN public.obras o ON o.id=e.obra_id
    WHERE o.nome='CASA BOA VIAGEM' AND o.codigo='ALU-3195-GVG-PE';
  IF v_catalogo<>13 OR v_confirmadas<>35 OR v_pendentes<>35 OR v_salvas<>70 THEN
    RAISE EXCEPTION 'Conferencia falhou: catalogo %, vinculadas %, pendentes %, rotulos salvos %',
      v_catalogo,v_confirmadas,v_pendentes,v_salvas;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
