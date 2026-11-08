-- EWGEST: cadastro mestre de fabricantes por empresa.
-- Fabricante da tipologia deixa de ser texto livre sem referência.
-- Edições e novo cadastro seguem restritos ao administrador.
BEGIN;
CREATE TABLE IF NOT EXISTS public.fabricantes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  nome text NOT NULL,
  criado_em timestamptz NOT NULL DEFAULT now(),
  criado_por uuid REFERENCES auth.users(id),
  CONSTRAINT fabricantes_nome_valido CHECK (
    nome=upper(btrim(nome)) AND length(nome) BETWEEN 2 AND 80
  ),
  CONSTRAINT fabricantes_empresa_nome_unique UNIQUE(empresa_id,nome)
);
ALTER TABLE public.fabricantes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fabricantes FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fabricantes TO authenticated;
DROP POLICY IF EXISTS "Administrador consulta fabricantes da empresa" ON public.fabricantes;
CREATE POLICY "Administrador consulta fabricantes da empresa"
ON public.fabricantes FOR SELECT TO authenticated
USING (EXISTS(
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=fabricantes.empresa_id
    AND ue.usuario_id=(SELECT auth.uid())
    AND lower(ue.perfil)='administrador'
));

INSERT INTO public.fabricantes(empresa_id,nome)
SELECT DISTINCT empresa_id,upper(btrim(fabricante))
FROM public.tipologias WHERE nullif(btrim(fabricante),'') IS NOT NULL
ON CONFLICT (empresa_id,nome) DO NOTHING;

ALTER TABLE public.tipologias
  DROP CONSTRAINT IF EXISTS tipologias_fabricante_cadastrado_fk;
ALTER TABLE public.tipologias
  ADD CONSTRAINT tipologias_fabricante_cadastrado_fk
  FOREIGN KEY(empresa_id,fabricante)
  REFERENCES public.fabricantes(empresa_id,nome)
  ON UPDATE CASCADE ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.cadastrar_fabricante_admin(
  p_empresa_id uuid,p_nome text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_nome text:=upper(btrim(p_nome));
  v_id uuid;
  v_criado boolean:=false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_empresa_id IS NULL OR v_nome IS NULL OR length(v_nome) NOT BETWEEN 2 AND 80 THEN
    RAISE EXCEPTION 'Informe um nome de fabricante válido (2 a 80 caracteres).';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.usuarios_empresas ue WHERE ue.empresa_id=p_empresa_id
      AND ue.usuario_id=v_uid AND lower(ue.perfil)='administrador'
  ) THEN RAISE EXCEPTION 'Somente o administrador pode cadastrar fabricantes.'; END IF;
  INSERT INTO public.fabricantes(empresa_id,nome,criado_por)
  VALUES(p_empresa_id,v_nome,v_uid)
  ON CONFLICT (empresa_id,nome) DO NOTHING
  RETURNING id INTO v_id;
  v_criado:=v_id IS NOT NULL;
  IF NOT v_criado THEN
    SELECT id INTO v_id FROM public.fabricantes
    WHERE empresa_id=p_empresa_id AND nome=v_nome;
  END IF;
  RETURN jsonb_build_object('id',v_id,'nome',v_nome,'criado',v_criado);
END;
$$;
REVOKE ALL ON FUNCTION public.cadastrar_fabricante_admin(uuid,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cadastrar_fabricante_admin(uuid,text) TO authenticated;

-- Uma só operação salva fabricante e tipologia.
-- Novo fabricante exige p_criar_fabricante=true, confirmado pelo administrador.
CREATE OR REPLACE FUNCTION public.editar_tipologia_fabricante_catalogo_admin(
  p_tipologia_id uuid,
  p_codigo text,
  p_descricao text,
  p_fabricante text,
  p_manter_vinculo_origem boolean,
  p_criar_fabricante boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid:=auth.uid();
  v_empresa uuid;
  v_nome text:=nullif(upper(btrim(p_fabricante)),'');
  v_criado boolean:=false;
  v_resultado jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Entre na EWGEST.'; END IF;
  IF p_tipologia_id IS NULL OR p_criar_fabricante IS NULL THEN
    RAISE EXCEPTION 'Cadastro ou autorização inválidos.';
  END IF;
  SELECT empresa_id INTO v_empresa
    FROM public.tipologias WHERE id=p_tipologia_id FOR UPDATE;
  IF v_empresa IS NULL THEN RAISE EXCEPTION 'Tipologia não encontrada.'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.usuarios_empresas ue WHERE ue.empresa_id=v_empresa
      AND ue.usuario_id=v_uid AND lower(ue.perfil)='administrador'
  ) THEN RAISE EXCEPTION 'Somente o administrador pode editar este cadastro.'; END IF;
  IF v_nome IS NOT NULL THEN
    IF length(v_nome) NOT BETWEEN 2 AND 80 THEN
      RAISE EXCEPTION 'Nome de fabricante inválido.';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.fabricantes
                  WHERE empresa_id=v_empresa AND nome=v_nome) THEN
      IF NOT p_criar_fabricante THEN
        RAISE EXCEPTION 'Fabricante % ainda não cadastrado. Confirme a inclusão no cadastro de fabricantes.',v_nome;
      END IF;
      INSERT INTO public.fabricantes(empresa_id,nome,criado_por)
      VALUES(v_empresa,v_nome,v_uid)
      ON CONFLICT (empresa_id,nome) DO NOTHING;
      GET DIAGNOSTICS v_criado=ROW_COUNT;
    END IF;
  END IF;
  -- Quando a descrição terminar com um fabricante já cadastrado, os campos
  -- precisam concordar. Sem coincidência, o campo estruturado prevalece.
  IF EXISTS(
    SELECT 1 FROM public.fabricantes f
    WHERE f.empresa_id=v_empresa AND f.nome IS DISTINCT FROM v_nome
      AND upper(btrim(p_descricao)) LIKE '% - '||f.nome
  ) THEN
    RAISE EXCEPTION 'A descrição termina com outro fabricante. Corrija a descrição ou o campo Fabricante.';
  END IF;
  v_resultado:=public.editar_tipologia_com_fabricante_admin(
    p_tipologia_id,p_codigo,p_descricao,v_nome,p_manter_vinculo_origem
  );
  RETURN v_resultado || jsonb_build_object('fabricante_cadastrado_nesta_edicao',v_criado);
END;
$$;
REVOKE ALL ON FUNCTION public.editar_tipologia_fabricante_catalogo_admin(uuid,text,text,text,boolean,boolean)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.editar_tipologia_fabricante_catalogo_admin(uuid,text,text,text,boolean,boolean)
  TO authenticated;

COMMIT;
NOTIFY pgrst,'reload schema';