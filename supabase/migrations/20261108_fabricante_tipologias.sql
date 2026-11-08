-- EWGEST: fabricante independente da descrição no catálogo de tipologias.
-- HYDRO só é inferido se a descrição TERMINA explicitamente com HYDRO.
-- Cadastros sem indicação ficam "Não informado"; PERFIL pode ser escolhido no site.
-- Não altera vínculos das obras, quantidades, croquis nem liberações.
BEGIN;

ALTER TABLE public.tipologias
  ADD COLUMN IF NOT EXISTS fabricante text;

UPDATE public.tipologias
SET fabricante='HYDRO'
WHERE fabricante IS NULL
  AND btrim(descricao) ~* '(^|[ -])HYDRO$';

ALTER TABLE public.tipologias
  DROP CONSTRAINT IF EXISTS tipologias_fabricante_valido;
ALTER TABLE public.tipologias
  ADD CONSTRAINT tipologias_fabricante_valido
  CHECK (fabricante IS NULL OR
    (length(btrim(fabricante)) BETWEEN 2 AND 80 AND fabricante=btrim(fabricante)));

CREATE INDEX IF NOT EXISTS tipologias_empresa_fabricante_idx
  ON public.tipologias(empresa_id,fabricante);

ALTER TABLE public.tipologias_edicoes
  ADD COLUMN IF NOT EXISTS fabricante_antes text;
ALTER TABLE public.tipologias_edicoes
  ADD COLUMN IF NOT EXISTS fabricante_depois text;

-- Nova RPC: edição atômica de código + descrição + fabricante + opção de origem.
-- A RPC anterior permanece para compatibilidade com versões antigas do app.
CREATE OR REPLACE FUNCTION public.editar_tipologia_com_fabricante_admin(
  p_tipologia_id uuid,
  p_codigo text,
  p_descricao text,
  p_fabricante text,
  p_manter_vinculo_origem boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_reg public.tipologias%ROWTYPE;
  v_codigo text:=btrim(p_codigo);
  v_descricao text:=btrim(p_descricao);
  v_fabricante text:=nullif(upper(btrim(p_fabricante)),'');
  v_origens integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'É necessário entrar na EWGEST.';
  END IF;
  IF p_tipologia_id IS NULL OR p_manter_vinculo_origem IS NULL
    OR v_codigo IS NULL OR length(v_codigo)<2 OR length(v_codigo)>80
    OR v_descricao IS NULL OR length(v_descricao)<5 OR length(v_descricao)>1000
    OR (v_fabricante IS NOT NULL AND (length(v_fabricante)<2 OR length(v_fabricante)>80))
  THEN
    RAISE EXCEPTION 'Informe código, descrição, fabricante e opção de vínculo válidos.';
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
    RAISE EXCEPTION 'Este código já pertence a outra tipologia. Nenhuma unificação foi feita.';
  END IF;

  UPDATE public.tipologias
  SET codigo=v_codigo, descricao=v_descricao, fabricante=v_fabricante,
      provisoria=false
  WHERE id=v_reg.id;

  UPDATE public.tipologias_origens
  SET ativo=p_manter_vinculo_origem,alterado_em=now()
  WHERE tipologia_id=v_reg.id AND empresa_id=v_reg.empresa_id;
  GET DIAGNOSTICS v_origens=ROW_COUNT;

  INSERT INTO public.tipologias_edicoes
    (empresa_id,tipologia_id,codigo_antes,descricao_antes,codigo_depois,descricao_depois,
     era_provisoria,manter_vinculo_origem,usuario_id,fabricante_antes,fabricante_depois)
  VALUES
    (v_reg.empresa_id,v_reg.id,v_reg.codigo,v_reg.descricao,v_codigo,v_descricao,
     v_reg.provisoria,p_manter_vinculo_origem,v_uid,v_reg.fabricante,v_fabricante);

  RETURN jsonb_build_object(
    'tipologia_id',v_reg.id,'codigo',v_codigo,'fabricante',v_fabricante,
    'mantido_historico',true,
    'reconhecer_origem_em_importacoes_futuras',p_manter_vinculo_origem,
    'regras_de_origem_atualizadas',v_origens
  );
END;
$$;

REVOKE ALL ON FUNCTION public.editar_tipologia_com_fabricante_admin(uuid,text,text,text,boolean)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.editar_tipologia_com_fabricante_admin(uuid,text,text,text,boolean)
  TO authenticated;

COMMIT;
NOTIFY pgrst,'reload schema';