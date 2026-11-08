-- EWGEST: croquis tecnicos por tipologia, administrados separadamente
-- das liberacoes e das saidas da obra.
BEGIN;
CREATE TABLE IF NOT EXISTS public.tipologias_croquis (
  tipologia_id uuid PRIMARY KEY REFERENCES public.tipologias(id) ON DELETE RESTRICT,
  imagem_base64 text NOT NULL,
  mime_type text NOT NULL DEFAULT 'image/webp' CHECK (mime_type='image/webp'),
  origem text NOT NULL DEFAULT 'Cadastro manual',
  codigo_esquadria_referencia text,
  tamanho_bytes integer NOT NULL CHECK (tamanho_bytes>0 AND tamanho_bytes<=150000),
  cadastrado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_por uuid NOT NULL REFERENCES auth.users(id)
);
ALTER TABLE public.tipologias_croquis ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tipologias_croquis FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.tipologias_croquis TO authenticated;

DROP POLICY IF EXISTS "Administrador consulta croquis da empresa" ON public.tipologias_croquis;
CREATE POLICY "Administrador consulta croquis da empresa"
ON public.tipologias_croquis FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.tipologias t
  JOIN public.usuarios_empresas ue ON ue.empresa_id=t.empresa_id
  WHERE t.id=tipologias_croquis.tipologia_id
    AND ue.usuario_id=(SELECT auth.uid())
    AND lower(ue.perfil)='administrador'
));

CREATE OR REPLACE FUNCTION public.salvar_croqui_tipologia_admin(
  p_tipologia_id uuid,
  p_imagem_base64 text,
  p_origem text,
  p_codigo_esquadria_referencia text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_empresa uuid;
  v_bytes bytea;
  v_total integer;
  v_origem text:=left(coalesce(nullif(btrim(p_origem),''),'Cadastro manual'),255);
  v_codigo text:=left(nullif(btrim(p_codigo_esquadria_referencia),''),100);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_tipologia_id IS NULL THEN RAISE EXCEPTION 'Tipologia nao informada.'; END IF;
  SELECT empresa_id INTO v_empresa FROM public.tipologias WHERE id=p_tipologia_id;
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'Tipologia nao encontrada.'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_empresa
      AND ue.usuario_id=v_uid
      AND lower(ue.perfil)='administrador'
  ) THEN RAISE EXCEPTION 'Apenas o administrador pode cadastrar croquis.'; END IF;
  IF p_imagem_base64 IS NULL OR length(p_imagem_base64)<40 OR length(p_imagem_base64)>200000
     OR p_imagem_base64 !~ '^[A-Za-z0-9+/]+={0,2}$'
  THEN RAISE EXCEPTION 'O croqui precisa ser uma imagem WebP valida de ate 150 KB.'; END IF;
  BEGIN
    v_bytes:=pg_catalog.decode(p_imagem_base64,'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Imagem base64 invalida.';
  END;
  v_total:=pg_catalog.octet_length(v_bytes);
  IF v_total<20 OR v_total>150000
    OR pg_catalog.encode(pg_catalog.substring(v_bytes,1,4),'hex')<>'52494646'
    OR pg_catalog.encode(pg_catalog.substring(v_bytes,9,4),'hex')<>'57454250'
  THEN
    RAISE EXCEPTION 'Apenas croquis em formato WebP (maximo 150 KB) sao aceitos.';
  END IF;

  INSERT INTO public.tipologias_croquis
    (tipologia_id,imagem_base64,mime_type,origem,codigo_esquadria_referencia,
     tamanho_bytes,atualizado_por)
  VALUES(p_tipologia_id,p_imagem_base64,'image/webp',v_origem,v_codigo,v_total,v_uid)
  ON CONFLICT (tipologia_id) DO UPDATE
  SET imagem_base64=EXCLUDED.imagem_base64,
      origem=EXCLUDED.origem,
      codigo_esquadria_referencia=EXCLUDED.codigo_esquadria_referencia,
      tamanho_bytes=EXCLUDED.tamanho_bytes,
      atualizado_por=EXCLUDED.atualizado_por,
      atualizado_em=now();
  RETURN jsonb_build_object('tipologia_id',p_tipologia_id,'tamanho_bytes',v_total,
    'salvo',true);
END;
$$;

REVOKE ALL ON FUNCTION public.salvar_croqui_tipologia_admin(uuid,text,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.salvar_croqui_tipologia_admin(uuid,text,text,text)
  TO authenticated;
COMMIT;
NOTIFY pgrst,'reload schema';