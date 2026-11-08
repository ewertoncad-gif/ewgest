-- Registrar a referencia de origem das 11 tipologias criadas a partir
-- de codigos individuais de esquadria, com reconhecimento DESATIVADO.
-- O administrador podera ativar essa referencia ao escolher "Manter vinculo".
-- Nao confundir com o codigo de tipologia declarado no cabecalho CEM.
BEGIN;
ALTER TABLE public.tipologias_origens
  ADD COLUMN IF NOT EXISTS tipo_chave_origem text NOT NULL DEFAULT 'codigo_tipologia_relatorio';
ALTER TABLE public.tipologias_origens
  DROP CONSTRAINT IF EXISTS tipologias_origens_tipo_chave_check;
ALTER TABLE public.tipologias_origens
  ADD CONSTRAINT tipologias_origens_tipo_chave_check
  CHECK (tipo_chave_origem IN ('codigo_tipologia_relatorio','codigo_esquadria_relatorio'));

WITH candidatos AS (
 SELECT e.empresa_id,e.tipologia_id,btrim(e.codigo) AS codigo_origem,
        btrim(e.descricao) AS descricao_origem
 FROM public.esquadrias e
 JOIN public.obras o ON o.id=e.obra_id
 WHERE o.codigo='ALU-3195-GVG-PE'
   AND o.nome='CASA BOA VIAGEM'
   AND e.codigo IN ('GR4A','GR4B','GRA1A','GRA1B','GRA1C',
                    'GRA1D','GRA1E','GRA2A','GRA2B','GRA3A','GRA3B')
   AND e.tipologia_id IS NOT NULL
)
INSERT INTO public.tipologias_origens
  (empresa_id,tipologia_id,codigo_origem,descricao_origem,ativo,tipo_chave_origem)
SELECT empresa_id,tipologia_id,codigo_origem,descricao_origem,
       false,'codigo_esquadria_relatorio'
FROM candidatos
ON CONFLICT (empresa_id,codigo_origem,descricao_origem) DO NOTHING;

DO $$
DECLARE v_origins int;v_inactive int;
BEGIN
 SELECT COUNT(*) INTO v_origins FROM public.tipologias_origens;
 SELECT COUNT(*) INTO v_inactive
  FROM public.tipologias_origens
  WHERE tipo_chave_origem='codigo_esquadria_relatorio' AND NOT ativo;
 IF v_origins<>52 OR v_inactive<>11 THEN
   RAISE EXCEPTION 'Conferencia das referencias falhou: total %, esquadrias inativas %',
     v_origins,v_inactive;
 END IF;
END $$;
COMMIT;
NOTIFY pgrst,'reload schema';