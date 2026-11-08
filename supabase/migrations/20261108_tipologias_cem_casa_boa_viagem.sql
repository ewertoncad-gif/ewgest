-- Dados extraidos do PDF original Elevações(1).pdf (CEM Plus, 03/11/2026).
-- Conferencia automatica: 70 codigos/quantidades coincidem com esquadrias no Supabase.
-- Codigo de tipologia CEM e separado do codigo da esquadria. Nenhuma metragem muda.
BEGIN;
CREATE TEMP TABLE _ewgest_mapa_cem (codigo_esquadria text PRIMARY KEY,codigo_tipologia text NOT NULL) ON COMMIT DROP;
INSERT INTO _ewgest_mapa_cem(codigo_esquadria,codigo_tipologia) VALUES
  ('EA14','EA14'),
  ('EA14_1','EA14_1'),
  ('EA3','EA3'),
  ('EA11','EA3'),
  ('EA6A','EA6A_1'),
  ('EA6B','EA6B'),
  ('EA7','EA7'),
  ('EA12A','GOL-FIXN01'),
  ('EA1','GOLS-JCR200'),
  ('EA2','GOLS-JCR200'),
  ('EA9','GOLS-JCR200'),
  ('EA4','GOLS-JCR202'),
  ('EA8','GOLS-JCR202'),
  ('EA12B','GOLS-JCR202'),
  ('EA5','GOLS-PCR200'),
  ('GR02P','GR02P'),
  ('PVA8','GR06'),
  ('PVA8_1','GR06'),
  ('GR4P','GR4P'),
  ('GRA1A','GRA1A'),
  ('GRA1B','GRA1A'),
  ('GRA1C','GRA1A'),
  ('GRA1D','GRA1A'),
  ('GRA1E','GRA1A'),
  ('GR4A','GRA1A'),
  ('GR4B','GRA1A'),
  ('GRA2A','GRA2A'),
  ('GRA2B','GRA2A'),
  ('GRA3A','GRA2A'),
  ('GRA3B','GRA2A'),
  ('GRA2P','GRA2P'),
  ('EA10','INV-FIXN00'),
  ('EA13','INV-FIXN00'),
  ('E10','INV-FIXN00'),
  ('J01A','INV-FIXN00'),
  ('J10','INV-FIXN00'),
  ('J10.2','INV-FIXN00'),
  ('J01B','INV-FIXN00'),
  ('PVA6','INV-PFGR01'),
  ('PVA7','INV-PFGR01'),
  ('PVA1.A','INV-PGR10201FXVZ'),
  ('PVA1.3','INV-PGR10201FXVZ'),
  ('PVA4','INV-PGR10201FXVZ'),
  ('PVA5','INV-PGR107'),
  ('PVA09','INV-PGR207'),
  ('PVA10','INV-PGR207'),
  ('PVA1','INV-PGR207'),
  ('PVA2','INV-PGR207'),
  ('EA13_1','INV-VNZN00'),
  ('JVA1','INV-VNZN00'),
  ('J11','PKA-JCR200'),
  ('PLV1','PLV1'),
  ('PLV10','PLV10'),
  ('PLV2','PLV2'),
  ('PLV3','PLV3'),
  ('PLV4','PLV4'),
  ('PLV5','PLV5'),
  ('PLV6','PLV6'),
  ('PLV7','PLV7'),
  ('PLV8','PLV8'),
  ('PLV9','PLV9'),
  ('PT1A','PT1'),
  ('PT1B','PT1B'),
  ('SPLIT01','SPLITNATV02'),
  ('GC02A','UNIV-R08-GRADN00'),
  ('GC01','UNIV-R08-GRADN00'),
  ('GC02B','UNIV-R08-GRADN00'),
  ('GR02A','UNIV-R08-GRADN00'),
  ('GR03','UNIV-R08-GRADN00'),
  ('GR01','UNIV-R08-GRADN00');

-- Um registro por codigo mestre do CEM; descricao inicial extraida do cadastro existente.
INSERT INTO public.tipologias(empresa_id,codigo,descricao)
SELECT e.empresa_id, m.codigo_tipologia, (array_agg(e.descricao ORDER BY e.codigo))[1]
FROM public.esquadrias e
JOIN public.obras o ON o.id=e.obra_id
JOIN _ewgest_mapa_cem m ON m.codigo_esquadria=e.codigo
WHERE o.codigo='ALU-3195-GVG-PE' AND o.nome='CASA BOA VIAGEM'
GROUP BY e.empresa_id,m.codigo_tipologia
ON CONFLICT (empresa_id,codigo) DO NOTHING;

-- Vinca apenas registros ainda nao vinculados. Nao sobrescreve associacoes confirmadas.
UPDATE public.esquadrias e
SET tipologia_id=t.id
FROM public.obras o, _ewgest_mapa_cem m, public.tipologias t
WHERE e.obra_id=o.id AND o.codigo='ALU-3195-GVG-PE' AND o.nome='CASA BOA VIAGEM'
  AND e.codigo=m.codigo_esquadria
  AND t.empresa_id=e.empresa_id AND t.codigo=m.codigo_tipologia
  AND e.tipologia_id IS NULL;

DO $$
DECLARE v_itens int; v_sem_vinculo int; v_divergentes int;
BEGIN
 SELECT COUNT(*),COUNT(*) FILTER (WHERE e.tipologia_id IS NULL),
        COUNT(*) FILTER (WHERE t.codigo IS DISTINCT FROM m.codigo_tipologia)
 INTO v_itens,v_sem_vinculo,v_divergentes
 FROM public.esquadrias e JOIN public.obras o ON o.id=e.obra_id
 LEFT JOIN public.tipologias t ON t.id=e.tipologia_id
 JOIN _ewgest_mapa_cem m ON m.codigo_esquadria=e.codigo
 WHERE o.codigo='ALU-3195-GVG-PE' AND o.nome='CASA BOA VIAGEM';
 IF v_itens<>70 OR v_sem_vinculo<>0 OR v_divergentes<>0 THEN
   RAISE EXCEPTION 'Associacoes CEM nao conferem: itens %, sem vinculo %, divergentes %',v_itens,v_sem_vinculo,v_divergentes;
 END IF;
END $$;
COMMIT;
NOTIFY pgrst, 'reload schema';
