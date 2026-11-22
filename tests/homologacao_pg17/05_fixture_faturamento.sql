-- Dependências mínimas da RPC real de faturamento em PostgreSQL descartável.
-- Não contém dados, tabelas ou credenciais de produção.
\set ON_ERROR_STOP on
CREATE TABLE public.ew_obra_faturamentos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id),
 categoria text NOT NULL CHECK(categoria IN('fabricacao','instalacao')),
 data_faturamento date NOT NULL,numero_documento text NOT NULL,
 observacoes text NOT NULL DEFAULT '',valor_total numeric(18,2) NOT NULL,
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 operacao_id uuid NOT NULL,status text NOT NULL DEFAULT 'emitido',
 UNIQUE(empresa_id,operacao_id)
);
CREATE TABLE public.ew_obra_faturamentos_itens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 faturamento_id uuid NOT NULL REFERENCES public.ew_obra_faturamentos(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 esquadria_id uuid NOT NULL REFERENCES public.esquadrias(id),
 quantidade numeric(14,6) NOT NULL,
 valor_unitario numeric(18,4) NOT NULL,
 valor_total numeric(18,2) NOT NULL
);
CREATE TABLE public.romaneios(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id),
 status text NOT NULL,
 cancelado_em timestamptz
);
CREATE TABLE public.romaneios_itens(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 romaneio_id uuid NOT NULL REFERENCES public.romaneios(id),
 esquadria_id uuid NOT NULL REFERENCES public.esquadrias(id),
 natureza text NOT NULL DEFAULT 'esquadria',
 tipo_saida text NOT NULL CHECK(tipo_saida IN ('completo','marco','folha')),
 quantidade integer NOT NULL
);
CREATE TABLE public.esquadrias_saida_config(
 esquadria_id uuid PRIMARY KEY REFERENCES public.esquadrias(id),
 folhas_por_unidade integer NOT NULL CHECK(folhas_por_unidade BETWEEN 1 AND 12)
);
-- O faturamento legado é SECURITY INVOKER: precisa de permissões explícitas.
-- Este GRANT é APENAS para a fixture do teste, não para o SQL de produção.
GRANT SELECT,INSERT ON public.ew_obra_faturamentos,
 public.ew_obra_faturamentos_itens TO authenticated;
GRANT SELECT ON public.romaneios,public.romaneios_itens,
 public.esquadrias_saida_config TO authenticated;
GRANT SELECT,UPDATE ON public.esquadrias,public.ew_obra_orcamento TO authenticated;
