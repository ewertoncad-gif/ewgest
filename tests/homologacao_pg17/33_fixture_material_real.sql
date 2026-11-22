-- Contratos das tabelas tecnicas de materiais do CEM em PostgreSQL descartavel.
-- Apenas para execucao das funcoes REAIS de importacao, com dados inventados.
\set ON_ERROR_STOP on
CREATE TABLE public.ew_perfis (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 codigo text NOT NULL,descricao text NOT NULL,fabricante text NOT NULL,
 linha text NOT NULL DEFAULT '',prenativo text NOT NULL DEFAULT '',
 peso_kg_m numeric,comprimento_comercial_mm integer,
 unidade_referencia text NOT NULL DEFAULT 'BARRA',
 observacoes text NOT NULL DEFAULT '', ativo boolean NOT NULL DEFAULT true,
 criado_por uuid REFERENCES auth.users(id),atualizado_por uuid REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now(), atualizado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,id),UNIQUE(empresa_id,fabricante,codigo)
);
CREATE TABLE public.ew_acessorios (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 codigo text NOT NULL,descricao text NOT NULL,fabricante text NOT NULL,
 linha text NOT NULL DEFAULT '',prenativo text NOT NULL DEFAULT '',
 unidade_item text NOT NULL DEFAULT 'PC',unidade_embalagem text NOT NULL DEFAULT '',
 quantidade_por_embalagem numeric,observacoes text NOT NULL DEFAULT '',
 ativo boolean NOT NULL DEFAULT true,
 criado_por uuid REFERENCES auth.users(id),atualizado_por uuid REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now(), atualizado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,id),UNIQUE(empresa_id,fabricante,codigo)
);
CREATE TABLE public.ew_materiais_alias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 tipo text NOT NULL,perfil_id uuid REFERENCES public.ew_perfis(id),
 acessorio_id uuid REFERENCES public.ew_acessorios(id),
 fabricante text NOT NULL,codigo_alternativo text NOT NULL,
 criado_por uuid NOT NULL REFERENCES auth.users(id),criado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,tipo,fabricante,codigo_alternativo)
);
CREATE TABLE public.ew_materiais_variacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 tipo text NOT NULL,perfil_id uuid,
 acessorio_id uuid,acabamento text NOT NULL DEFAULT 'NÃO INFORMADO',
 cor text NOT NULL DEFAULT 'NÃO INFORMADA',codigo_cor text NOT NULL DEFAULT '',
 observacoes text NOT NULL DEFAULT '',ativo boolean NOT NULL DEFAULT true,
 criado_por uuid REFERENCES auth.users(id),atualizado_por uuid REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now(),atualizado_em timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (empresa_id,perfil_id) REFERENCES public.ew_perfis(empresa_id,id),
 FOREIGN KEY (empresa_id,acessorio_id) REFERENCES public.ew_acessorios(empresa_id,id)
);
CREATE UNIQUE INDEX test_var_perfil
 ON public.ew_materiais_variacoes(empresa_id,perfil_id,acabamento,cor,codigo_cor)
 WHERE tipo='perfil';
CREATE UNIQUE INDEX test_var_acessorio
 ON public.ew_materiais_variacoes(empresa_id,acessorio_id,acabamento,cor,codigo_cor)
 WHERE tipo='acessorio';
CREATE TABLE public.ew_cem_obras_materiais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id),
 tipo text NOT NULL,
 perfil_id uuid,acessorio_id uuid,
 variacao_id uuid NOT NULL REFERENCES public.ew_materiais_variacoes(id),
 linhas_calculo integer NOT NULL DEFAULT 0,
 criado_em timestamptz NOT NULL DEFAULT now(),atualizado_em timestamptz NOT NULL DEFAULT now(),
 quantidade_prevista numeric,unidade_prevista text,comprimento_total_m numeric,
 origem_quantitativos text,barras_planejadas jsonb,
 FOREIGN KEY (empresa_id,perfil_id) REFERENCES public.ew_perfis(empresa_id,id),
 FOREIGN KEY (empresa_id,acessorio_id) REFERENCES public.ew_acessorios(empresa_id,id),
 UNIQUE(empresa_id,obra_id,variacao_id)
);
CREATE TABLE public.ew_cem_importacoes_materiais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id),
 operacao_id uuid NOT NULL UNIQUE,codigo_obra_cem text NOT NULL,
 importou_perfis boolean NOT NULL DEFAULT false,
 importou_acessorios boolean NOT NULL DEFAULT false,
 resumo jsonb NOT NULL,criado_por uuid NOT NULL REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now()
);
-- Somente uma sentinela de movimentos fisicos: o importador CEM nao pode escreve-la.
CREATE TABLE public.ew_estoque_movimentos_sentinela (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 descricao text
);
GRANT SELECT ON public.ew_perfis,public.ew_acessorios,public.ew_materiais_alias,
 public.ew_materiais_variacoes,public.ew_cem_obras_materiais,
 public.ew_cem_importacoes_materiais,public.ew_estoque_movimentos_sentinela
 TO authenticated;
