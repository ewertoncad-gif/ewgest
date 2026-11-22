-- EWGEST v46.9: complementos dos contratos minimos para chamar
-- FUNCOES LEGADAS REAIS da producao em PostgreSQL descartavel.
-- Usa apenas dados inventados. Sem acesso Supabase e sem mutacoes reais.
\set ON_ERROR_STOP on
ALTER TABLE public.obras
 ADD COLUMN cliente text,
 ADD COLUMN situacao text NOT NULL DEFAULT 'Em andamento',
 ADD COLUMN arquivada_em timestamptz;

ALTER TABLE public.esquadrias
 ADD COLUMN localizacao text,
 ADD COLUMN qtd_liberada integer NOT NULL DEFAULT 0,
 ADD COLUMN qtd_fabricada integer NOT NULL DEFAULT 0,
 ADD COLUMN rotulo_tipologia_relatorio text,
 ADD COLUMN quantidade_modulos integer;

ALTER TABLE public.ew_obra_orcamento
 ADD COLUMN aluminio numeric(14,2) NOT NULL DEFAULT 0,
 ADD COLUMN acessorios numeric(14,2) NOT NULL DEFAULT 0,
 ADD COLUMN vidros numeric(14,2) NOT NULL DEFAULT 0,
 ADD COLUMN outros numeric(14,2) NOT NULL DEFAULT 0,
 ADD COLUMN criado_por uuid REFERENCES auth.users(id);

CREATE TABLE public.ew_estoques_locais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL UNIQUE REFERENCES public.obras(id),
 criado_por uuid REFERENCES auth.users(id)
);

CREATE TABLE public.ew_niveis_orcamento_catalogo (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 nome text NOT NULL,
 categoria_base text NOT NULL,
 UNIQUE(empresa_id,nome)
);
CREATE TABLE public.ew_empresas_faturamento_catalogo (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 nome text NOT NULL,
 UNIQUE(empresa_id,nome)
);
CREATE TABLE public.ew_obra_orcamento_niveis (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id),
 linha integer NOT NULL,
 nivel_id uuid NOT NULL REFERENCES public.ew_niveis_orcamento_catalogo(id),
 empresa_faturamento_id uuid NOT NULL REFERENCES public.ew_empresas_faturamento_catalogo(id),
 nivel_nome text NOT NULL,
 empresa_faturamento_nome text NOT NULL,
 categoria_base text NOT NULL,
 valor numeric(14,2) NOT NULL,
 percentual numeric(14,5) NOT NULL,
 faturar boolean NOT NULL,
 UNIQUE(empresa_id,obra_id,linha)
);

-- ATENCAO: SOMENTE este subfluxo de materiais nao e exercitado.
-- Falhar explicitamente em vez de fingir que importou materiais.
CREATE OR REPLACE FUNCTION public.ew_importar_cem_conciliado(
 p_empresa_id uuid,p_codigo_obra text,p_perfis jsonb,
 p_acessorios jsonb,p_operacao_id uuid,p_decisoes jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'CI real-sem-materiais: conciliação de materiais NÃO homologada';
END $$;

-- Apenas consultas de verificação feitas com papel autenticado no CI.
GRANT SELECT ON public.ew_estoques_locais, public.ew_obra_orcamento_niveis
 TO authenticated;
