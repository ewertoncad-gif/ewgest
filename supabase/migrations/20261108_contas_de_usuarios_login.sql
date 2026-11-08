-- EWGEST: cadastro privado de usuários com login independente do e-mail.
-- Senhas continuam exclusivamente no Supabase Auth.
-- A referência a auth.users e os históricos das obras são preservados.
BEGIN;

CREATE TABLE IF NOT EXISTS public.usuarios_login (
  usuario_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  login text NOT NULL,
  login_chave text GENERATED ALWAYS AS
    (lower(regexp_replace(btrim(login),'[[:space:]]+',' ','g'))) STORED,
  nome text NOT NULL,
  perfil text NOT NULL CHECK (perfil IN ('administrador','supervisor','tecnico','consulta')),
  ativo boolean NOT NULL DEFAULT true,
  criado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT usuarios_login_nome_valido CHECK (char_length(btrim(nome)) BETWEEN 2 AND 100),
  CONSTRAINT usuarios_login_login_valido CHECK (
    char_length(btrim(login)) BETWEEN 3 AND 100
    AND login=btrim(login)
    AND login !~ '[[:cntrl:]]'
  ),
  CONSTRAINT usuarios_login_unico UNIQUE(login_chave),
  CONSTRAINT usuarios_login_usuario_empresa_unico UNIQUE(usuario_id,empresa_id)
);

CREATE INDEX IF NOT EXISTS usuarios_login_empresa_idx ON public.usuarios_login(empresa_id,ativo);
ALTER TABLE public.usuarios_login ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.usuarios_login FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.usuarios_login TO authenticated;

DROP POLICY IF EXISTS "Usuario consulta proprio login e administrador consulta empresa" ON public.usuarios_login;
CREATE POLICY "Usuario consulta proprio login e administrador consulta empresa"
ON public.usuarios_login FOR SELECT TO authenticated
USING (
  usuario_id=(SELECT auth.uid()) OR EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.usuario_id=(SELECT auth.uid())
      AND ue.empresa_id=usuarios_login.empresa_id
      AND ue.perfil='administrador'
  )
);

-- Conta atual permanece intacta no Supabase Auth.
-- O login inicial do administrador é o próprio e-mail; ele pode alterá-lo
-- depois no site para Ewerton, Ewerton Santos ou outro apelido.
INSERT INTO public.usuarios_login (usuario_id,empresa_id,login,nome,perfil,ativo)
SELECT ue.usuario_id,ue.empresa_id,u.email,'Administrador',ue.perfil,true
FROM public.usuarios_empresas ue
JOIN auth.users u ON u.id=ue.usuario_id
WHERE ue.perfil='administrador' AND u.email IS NOT NULL
ON CONFLICT (usuario_id) DO NOTHING;

DO $$
DECLARE v_admins int;
BEGIN
 SELECT COUNT(*) INTO v_admins
 FROM public.usuarios_login WHERE perfil='administrador' AND ativo;
 IF v_admins<1 THEN
   RAISE EXCEPTION 'A conta do administrador não foi localizada. Migração revertida.';
 END IF;
END $$;
COMMIT;
NOTIFY pgrst,'reload schema';