-- Migração Supabase produção, aplicada em 2026-11-21 às 10:27.
-- Cadastro aditivo de fornecedores por empresa, sem alterar movimento de estoque.

-- EWGEST 2026-11-21: cadastro de fornecedores por empresa.
-- A tabela de galpões ew_locais_fisicos já existe e deve ser reutilizada.
-- Migração aditiva: não modifica notas, estoques nem obras existentes.
CREATE TABLE IF NOT EXISTS public.ew_fornecedores (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 nome text NOT NULL,
 ativo boolean NOT NULL DEFAULT true,
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT ew_fornecedores_nome_valido CHECK (
  char_length(btrim(nome)) BETWEEN 3 AND 180 AND nome = upper(btrim(nome))
 )
);
CREATE UNIQUE INDEX IF NOT EXISTS ew_fornecedores_empresa_nome_uq
 ON public.ew_fornecedores (empresa_id,upper(btrim(nome)));
CREATE INDEX IF NOT EXISTS ew_fornecedores_empresa_ativo_idx
 ON public.ew_fornecedores (empresa_id,ativo);

ALTER TABLE public.ew_fornecedores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Equipe consulta fornecedores da empresa"
 ON public.ew_fornecedores FOR SELECT TO authenticated
 USING (EXISTS (
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=ew_fornecedores.empresa_id AND ue.usuario_id=(SELECT auth.uid())
 ));
CREATE POLICY "ADM cadastra fornecedores da empresa"
 ON public.ew_fornecedores FOR INSERT TO authenticated
 WITH CHECK (
  criado_por=(SELECT auth.uid()) AND EXISTS (
   SELECT 1 FROM public.usuarios_empresas ue
   WHERE ue.empresa_id=ew_fornecedores.empresa_id AND ue.usuario_id=(SELECT auth.uid())
     AND ue.perfil='administrador'
  )
 );
CREATE POLICY "ADM atualiza fornecedores da empresa"
 ON public.ew_fornecedores FOR UPDATE TO authenticated
 USING (EXISTS (
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=ew_fornecedores.empresa_id AND ue.usuario_id=(SELECT auth.uid())
    AND ue.perfil='administrador'
 ))
 WITH CHECK (EXISTS (
  SELECT 1 FROM public.usuarios_empresas ue
  WHERE ue.empresa_id=ew_fornecedores.empresa_id AND ue.usuario_id=(SELECT auth.uid())
    AND ue.perfil='administrador'
 ));

REVOKE ALL ON public.ew_fornecedores FROM PUBLIC,anon;
GRANT SELECT,INSERT,UPDATE ON public.ew_fornecedores TO authenticated;
NOTIFY pgrst, 'reload schema';
