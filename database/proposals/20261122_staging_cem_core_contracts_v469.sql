-- EWGEST v46.9 | reconstrução ADITIVA de contratos essenciais do importador CEM no staging Free
-- Destino EXCLUSIVO: ewgest-restauracao-teste. Não executar na produção.
-- Capturado em 22/11/2026 por comparação read-only com esquema real de produção.
-- Guarda: 40 tabelas públicas, 1 auth.user, 1 empresa, 0 obras e todas as 9 tabelas-alvo vazias.
-- Não copia dados de produção nem concede privilégios anônimos.
BEGIN;
DO $pre$
DECLARE tb text; total integer; lines bigint;
BEGIN
 SELECT count(*) INTO total FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind IN ('r','p');
 IF total<>40 THEN RAISE EXCEPTION 'Staging inesperado: tabelas=%; esperado 40.',total;END IF;
 IF (SELECT count(*) FROM auth.users)<>1 OR (SELECT count(*) FROM public.empresas)<>1 OR
 (SELECT count(*) FROM public.obras)<>0 OR (SELECT count(*) FROM public.esquadrias)<>0
 THEN RAISE EXCEPTION 'Dados de referência do staging mudaram; parar.';END IF;
 FOREACH tb IN ARRAY ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias','ew_cem_obras_materiais','ew_estoques_locais','ew_obra_orcamento'] LOOP
  EXECUTE format('select count(*) from public.%I',tb) INTO lines;
  IF lines<>0 THEN RAISE EXCEPTION 'Tabela % não está vazia (%): abortar.',tb,lines; END IF;
 END LOOP;
 IF to_regclass('public.ew_cem_importacoes_materiais') IS NOT NULL THEN
  RAISE EXCEPTION 'Tabela ew_cem_importacoes_materiais já existe.';
 END IF;
END $pre$;
ALTER TABLE public."esquadrias" ADD COLUMN "tipologia_id" uuid;
ALTER TABLE public."esquadrias" ADD COLUMN "rotulo_tipologia_relatorio" text;
ALTER TABLE public."esquadrias" ADD COLUMN "quantidade_modulos" integer;
ALTER TABLE public."esquadrias" ADD COLUMN "modulacao_id" uuid;
ALTER TABLE public."ew_acessorios" ADD COLUMN "linha" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_acessorios" ADD COLUMN "prenativo" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_acessorios" ADD COLUMN "unidade_embalagem" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_acessorios" ADD COLUMN "quantidade_por_embalagem" numeric(14,3);
ALTER TABLE public."ew_acessorios" ADD COLUMN "observacoes" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_acessorios" ADD COLUMN "ativo" boolean DEFAULT true NOT NULL;
ALTER TABLE public."ew_acessorios" ADD COLUMN "criado_por" uuid;
ALTER TABLE public."ew_acessorios" ADD COLUMN "atualizado_por" uuid;
ALTER TABLE public."ew_acessorios" ADD COLUMN "criado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_acessorios" ADD COLUMN "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_cem_obras_materiais" ADD COLUMN "criado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_cem_obras_materiais" ADD COLUMN "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_cem_obras_materiais" ADD COLUMN "origem_quantitativos" text;
ALTER TABLE public."ew_estoques_locais" ADD COLUMN "criado_por" uuid;
ALTER TABLE public."ew_estoques_locais" ADD COLUMN "criado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_estoques_locais" ADD COLUMN "excluido_por" uuid;
ALTER TABLE public."ew_estoques_locais" ADD COLUMN "restauravel_ate" timestamp with time zone;
ALTER TABLE public."ew_materiais_alias" ADD COLUMN "criado_por" uuid NOT NULL;
ALTER TABLE public."ew_materiais_alias" ADD COLUMN "criado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "acabamento" text DEFAULT 'NÃO INFORMADO'::text NOT NULL;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "cor" text DEFAULT 'NÃO INFORMADA'::text NOT NULL;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "codigo_cor" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "observacoes" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "criado_por" uuid;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "atualizado_por" uuid;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "criado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_materiais_variacoes" ADD COLUMN "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "linha" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "prenativo" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "peso_kg_m" numeric(12,5);
ALTER TABLE public."ew_perfis" ADD COLUMN "comprimento_comercial_mm" integer;
ALTER TABLE public."ew_perfis" ADD COLUMN "unidade_referencia" text DEFAULT 'BARRA'::text NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "observacoes" text DEFAULT ''::text NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "ativo" boolean DEFAULT true NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "criado_por" uuid;
ALTER TABLE public."ew_perfis" ADD COLUMN "atualizado_por" uuid;
ALTER TABLE public."ew_perfis" ADD COLUMN "criado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."ew_perfis" ADD COLUMN "atualizado_em" timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public."obras" ADD COLUMN "arquivada_por" uuid;
ALTER TABLE public."obras" ADD COLUMN "motivo_arquivamento" text;
CREATE TABLE public.ew_cem_importacoes_materiais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id),
 operacao_id uuid NOT NULL UNIQUE,
 codigo_obra_cem text NOT NULL,
 importou_perfis boolean NOT NULL DEFAULT false,
 importou_acessorios boolean NOT NULL DEFAULT false,
 resumo jsonb NOT NULL,
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_cem_importacoes_obras ON public.ew_cem_importacoes_materiais(empresa_id,obra_id,criado_em DESC);
ALTER TABLE public.ew_cem_importacoes_materiais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ew_cem_importacoes_materiais FROM PUBLIC, anon, authenticated;
DO $post$
DECLARE c integer;rls_enabled boolean;
BEGIN
 SELECT count(*) INTO c FROM pg_catalog.pg_attribute a
 JOIN pg_catalog.pg_class t ON t.oid=a.attrelid JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
 WHERE n.nspname='public' AND t.relname='ew_cem_importacoes_materiais' AND a.attnum>0 AND NOT a.attisdropped;
 SELECT relrowsecurity INTO rls_enabled FROM pg_catalog.pg_class WHERE oid='public.ew_cem_importacoes_materiais'::regclass;
 IF c<>10 OR rls_enabled IS DISTINCT FROM true OR
  pg_catalog.has_table_privilege('anon','public.ew_cem_importacoes_materiais','SELECT') OR
  pg_catalog.has_table_privilege('authenticated','public.ew_cem_importacoes_materiais','INSERT')
 THEN RAISE EXCEPTION 'Cadastro de importações CEM incompleto ou permissivo.';END IF;
END $post$;
COMMIT;
