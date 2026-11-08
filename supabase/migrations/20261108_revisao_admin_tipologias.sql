-- EWGest: revisão administrativa de tipologias, sem perder histórico.
-- Provisória = código digitado no relatório, aguardando validação do administrador.
-- Vínculo de origem = regra para reconhecer futuramente aquele código E descrição CEM.
-- Quebrar vínculo de origem nunca remove vínculos históricos de public.esquadrias.
BEGIN;

ALTER TABLE public.tipologias
  ADD COLUMN IF NOT EXISTS provisoria boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS tipologias_empresa_codigo_normalizado_uidx
  ON public.tipologias (empresa_id, upper(btrim(codigo)));

CREATE TABLE IF NOT EXISTS public.tipologias_origens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  tipologia_id uuid NOT NULL REFERENCES public.tipologias(id) ON DELETE RESTRICT,
  codigo_origem text NOT NULL CHECK (length(btrim(codigo_origem))>0),
  descricao_origem text NOT NULL CHECK (length(btrim(descricao_origem))>0),
  ativo boolean NOT NULL DEFAULT true,
  registrado_em timestamptz NOT NULL DEFAULT now(),
  alterado_em timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tipologias_origens_identidade_uq UNIQUE (empresa_id,codigo_origem,descricao_origem)
);

CREATE INDEX IF NOT EXISTS tipologias_origens_tipologia_idx
 ON public.tipologias_origens(tipologia_id);

CREATE TABLE IF NOT EXISTS public.tipologias_edicoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  tipologia_id uuid NOT NULL REFERENCES public.tipologias(id) ON DELETE RESTRICT,
  codigo_antes text NOT NULL,
  descricao_antes text NOT NULL,
  codigo_depois text NOT NULL,
  descricao_depois text NOT NULL,
  era_provisoria boolean NOT NULL,
  manter_vinculo_origem boolean NOT NULL,
  usuario_id uuid NOT NULL REFERENCES auth.users(id),
  registrado_em timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tipologias_edicoes_tipologia_idx
 ON public.tipologias_edicoes(tipologia_id,registrado_em DESC);

ALTER TABLE public.tipologias_origens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipologias_edicoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tipologias_origens,public.tipologias_edicoes FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.tipologias_origens,public.tipologias_edicoes TO authenticated;
DROP POLICY IF EXISTS "Administrador consulta vinculos de origem" ON public.tipologias_origens;
CREATE POLICY "Administrador consulta vinculos de origem"
ON public.tipologias_origens FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=tipologias_origens.empresa_id
    AND ue.usuario_id=(SELECT auth.uid())
    AND lower(ue.perfil)='administrador'
));
DROP POLICY IF EXISTS "Administrador consulta revisoes de tipologias" ON public.tipologias_edicoes;
CREATE POLICY "Administrador consulta revisoes de tipologias"
ON public.tipologias_edicoes FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=tipologias_edicoes.empresa_id
    AND ue.usuario_id=(SELECT auth.uid())
    AND lower(ue.perfil)='administrador'
));

-- Só promover códigos provisórios não ambíguos. Ex.: EA14 possui uma descrição.
-- GRA1A / GRA2A têm quatro descrições cada e continuam pendentes para revisão.
WITH grupos AS (
 SELECT empresa_id,rotulo_tipologia_relatorio AS codigo,
        min(descricao) AS descricao, COUNT(DISTINCT descricao) AS variacoes
 FROM public.esquadrias
 WHERE tipologia_id IS NULL
   AND rotulo_tipologia_relatorio IS NOT NULL AND descricao IS NOT NULL
 GROUP BY empresa_id,rotulo_tipologia_relatorio
 HAVING COUNT(DISTINCT descricao)=1
)
INSERT INTO public.tipologias (empresa_id,codigo,descricao,provisoria)
SELECT g.empresa_id,g.codigo,g.descricao,true
FROM grupos g
WHERE NOT EXISTS (
 SELECT 1 FROM public.tipologias t
 WHERE t.empresa_id=g.empresa_id
   AND upper(btrim(t.codigo))=upper(btrim(g.codigo))
)
ON CONFLICT (empresa_id,codigo) DO NOTHING;

UPDATE public.esquadrias e
SET tipologia_id=t.id
FROM public.tipologias t
WHERE e.tipologia_id IS NULL
  AND e.rotulo_tipologia_relatorio=t.codigo
  AND e.descricao=t.descricao
  AND e.empresa_id=t.empresa_id
  AND t.provisoria=true
  AND NOT EXISTS (
    SELECT 1 FROM public.esquadrias other
    WHERE other.empresa_id=e.empresa_id
      AND other.rotulo_tipologia_relatorio=e.rotulo_tipologia_relatorio
      AND other.descricao IS DISTINCT FROM e.descricao
  );

-- Manter código + descrição tal como chegaram do sistema de origem.
-- A associação só atua automaticamente em importações futuras se 'ativo=true'
-- e quando o importador consultar explicitamente esta tabela.
INSERT INTO public.tipologias_origens
  (empresa_id,tipologia_id,codigo_origem,descricao_origem,ativo)
SELECT DISTINCT e.empresa_id,e.tipologia_id,
  btrim(e.rotulo_tipologia_relatorio),btrim(e.descricao),true
FROM public.esquadrias e
WHERE e.tipologia_id IS NOT NULL
  AND nullif(btrim(e.rotulo_tipologia_relatorio),'') IS NOT NULL
  AND nullif(btrim(e.descricao),'') IS NOT NULL
ON CONFLICT (empresa_id,codigo_origem,descricao_origem) DO NOTHING;

-- Atualização exclusivamente via RPC com autenticação e perfil de administrador.
CREATE OR REPLACE FUNCTION public.editar_tipologia_admin(
  p_tipologia_id uuid,
  p_codigo text,
  p_descricao text,
  p_manter_vinculo_origem boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_reg public.tipologias%ROWTYPE;
  v_codigo text:=btrim(p_codigo);
  v_descricao text:=btrim(p_descricao);
  v_origens integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'É necessário entrar na EWGEST.';
  END IF;
  IF p_tipologia_id IS NULL OR p_manter_vinculo_origem IS NULL
    OR v_codigo IS NULL OR length(v_codigo)<2 OR length(v_codigo)>80
    OR v_descricao IS NULL OR length(v_descricao)<5 OR length(v_descricao)>1000 THEN
    RAISE EXCEPTION 'Informe código, descrição e opção de vínculo válidos.';
  END IF;

  SELECT * INTO v_reg FROM public.tipologias WHERE id=p_tipologia_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipologia não encontrada.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_reg.empresa_id
      AND ue.usuario_id=v_uid
      AND lower(ue.perfil)='administrador'
  ) THEN
    RAISE EXCEPTION 'Somente o administrador desta empresa pode alterar tipologias.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.tipologias t
    WHERE t.empresa_id=v_reg.empresa_id AND t.id<>v_reg.id
      AND upper(btrim(t.codigo))=upper(v_codigo)
  ) THEN
    RAISE EXCEPTION 'Este código já pertence a outra tipologia. Não foi alterado nem unido automaticamente.';
  END IF;

  UPDATE public.tipologias
  SET codigo=v_codigo, descricao=v_descricao, provisoria=false
  WHERE id=v_reg.id;

  UPDATE public.tipologias_origens
  SET ativo=p_manter_vinculo_origem,alterado_em=now()
  WHERE tipologia_id=v_reg.id AND empresa_id=v_reg.empresa_id;
  GET DIAGNOSTICS v_origens=ROW_COUNT;

  INSERT INTO public.tipologias_edicoes
    (empresa_id,tipologia_id,codigo_antes,descricao_antes,codigo_depois,descricao_depois,
     era_provisoria,manter_vinculo_origem,usuario_id)
  VALUES
    (v_reg.empresa_id,v_reg.id,v_reg.codigo,v_reg.descricao,v_codigo,v_descricao,
     v_reg.provisoria,p_manter_vinculo_origem,v_uid);

  RETURN jsonb_build_object(
    'tipologia_id',v_reg.id,'codigo',v_codigo,'mantido_historico',true,
    'reconhecer_origem_em_importacoes_futuras',p_manter_vinculo_origem,
    'regras_de_origem_atualizadas',v_origens
  );
END;
$$;

REVOKE ALL ON FUNCTION public.editar_tipologia_admin(uuid,text,text,boolean)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.editar_tipologia_admin(uuid,text,text,boolean)
TO authenticated;

-- Conferência específica: 22 provisórias + 13 confirmadas, 11 itens ambíguos.
DO $$
DECLARE v_total int; v_vinculados int; v_pendentes int; v_provisorias int;
BEGIN
 SELECT COUNT(*) INTO v_total FROM public.tipologias;
 SELECT COUNT(*) FILTER(WHERE tipologia_id IS NOT NULL),
        COUNT(*) FILTER(WHERE tipologia_id IS NULL)
   INTO v_vinculados,v_pendentes FROM public.esquadrias;
 SELECT COUNT(*) INTO v_provisorias FROM public.tipologias WHERE provisoria;
 IF v_total<>35 OR v_vinculados<>59 OR v_pendentes<>11 OR v_provisorias<>22 THEN
  RAISE EXCEPTION 'Conferência falhou: catálogo %, vinculadas %, pendentes %, provisórias %',
    v_total,v_vinculados,v_pendentes,v_provisorias;
 END IF;
END $$;
COMMIT;
NOTIFY pgrst,'reload schema';