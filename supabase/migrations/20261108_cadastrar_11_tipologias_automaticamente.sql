-- EWGEST: registrar imediatamente as 11 esquadrias ainda pendentes como
-- 11 tipologias independentes, usando temporariamente o proprio codigo da esquadria.
-- O administrador podera corrigir os codigos e descricoes posteriormente.
-- Sem uniao automatica. Preserva nomes de origem, obras, liberacoes e saidas.
BEGIN;

DO $$
DECLARE
  v_empresa uuid;
  v_itens int;
  v_colisoes int;
BEGIN
  SELECT id INTO STRICT v_empresa
    FROM public.empresas WHERE nome='GVG ESQUADRIAS';

  SELECT COUNT(*) INTO v_itens
  FROM public.esquadrias e
  JOIN public.obras o ON o.id=e.obra_id
  WHERE e.tipologia_id IS NULL
    AND e.empresa_id=v_empresa
    AND o.codigo='ALU-3195-GVG-PE'
    AND o.nome='CASA BOA VIAGEM';

  IF v_itens<>11 THEN
    RAISE EXCEPTION 'A quantidade de pendencias mudou (%). Revise antes de cadastrar.',v_itens;
  END IF;

  SELECT COUNT(*) INTO v_colisoes
  FROM public.esquadrias e
  JOIN public.tipologias t ON t.empresa_id=e.empresa_id
   AND upper(btrim(t.codigo))=upper(btrim(e.codigo))
  JOIN public.obras o ON o.id=e.obra_id
  WHERE e.tipologia_id IS NULL
    AND o.codigo='ALU-3195-GVG-PE'
    AND o.nome='CASA BOA VIAGEM';

  IF v_colisoes>0 THEN
    RAISE EXCEPTION 'Ha % codigos iguais a tipologias existentes. Revisar manualmente.',v_colisoes;
  END IF;
END $$;

INSERT INTO public.tipologias(empresa_id,codigo,descricao,provisoria)
SELECT e.empresa_id,btrim(e.codigo),btrim(e.descricao),true
FROM public.esquadrias e
JOIN public.obras o ON o.id=e.obra_id
WHERE e.tipologia_id IS NULL
  AND e.empresa_id=o.empresa_id
  AND o.nome='CASA BOA VIAGEM'
  AND o.codigo='ALU-3195-GVG-PE';

UPDATE public.esquadrias e
SET tipologia_id=t.id
FROM public.tipologias t,public.obras o
WHERE o.id=e.obra_id
  AND o.nome='CASA BOA VIAGEM'
  AND o.codigo='ALU-3195-GVG-PE'
  AND e.empresa_id=t.empresa_id
  AND e.tipologia_id IS NULL
  AND upper(btrim(e.codigo))=upper(btrim(t.codigo))
  AND btrim(e.descricao)=btrim(t.descricao)
  AND t.provisoria=true;

-- Nao criar regra de reconhecimento de origem CEM automaticamente.
-- GRA1A e GRA2A foram utilizados para VARIAS descricoes de tipologia.
-- A origem original continua no campo e.rotulo_tipologia_relatorio para
-- a revisao do administrador, sem gerar correspondencias falsas.

DO $$
DECLARE v_pendentes int;v_cadastradas int;v_assoc int;
BEGIN
  SELECT COUNT(*) INTO v_pendentes FROM public.esquadrias WHERE tipologia_id IS NULL;
  SELECT COUNT(*) INTO v_cadastradas FROM public.tipologias;
  SELECT COUNT(*) INTO v_assoc FROM public.esquadrias WHERE tipologia_id IS NOT NULL;
  IF v_pendentes<>0 OR v_cadastradas<>46 OR v_assoc<>70 THEN
    RAISE EXCEPTION 'Falha na conferencia: pendentes %, tipologias %, esquadrias associadas %',
      v_pendentes,v_cadastradas,v_assoc;
  END IF;
END $$;

COMMIT;
NOTIFY pgrst,'reload schema';