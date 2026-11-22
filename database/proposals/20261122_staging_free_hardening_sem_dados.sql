-- EWGEST v46.9 — PROPOSTA NÃO APLICADA.
-- Destino EXCLUSIVO: projeto ewgest-restauracao-teste (schema antigo).
-- Nunca executar na produção e nunca usar como substituto de restauração fiel.
-- O staging atual: 35 tabelas públicas, 11 sem RLS, todas as 11 vazias.
-- A transação aborta se qualquer precondição mudar.
\set ON_ERROR_STOP on
BEGIN;
DO $seguranca$
DECLARE
 nomes text[] := ARRAY[
  'ew_acessorios',
  'ew_estoque_obras_movimentos',
  'ew_estoques_locais',
  'ew_locais_fisicos',
  'ew_materiais_variacoes',
  'ew_nfe_recebimentos',
  'ew_obra_despesas',
  'ew_obra_despesas_itens',
  'ew_obra_faturamentos',
  'ew_obra_orcamento',
  'ew_perfis'
 ];
 tabela text;
 n_tabelas integer;
 n_linhas bigint;
 rls_ativo boolean;
BEGIN
 SELECT count(*) INTO n_tabelas FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind IN ('r','p');
 IF n_tabelas<>35 THEN
  RAISE EXCEPTION 'Ambiente inesperado (tabelas públicas=%). Não aplicar.',n_tabelas;
 END IF;
 FOREACH tabela IN ARRAY nomes LOOP
  SELECT c.relrowsecurity INTO rls_ativo
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname=tabela AND c.relkind IN ('r','p');
  IF rls_ativo IS DISTINCT FROM false THEN
   RAISE EXCEPTION 'Tabela % ausente ou RLS já alterado; revalidar staging.',tabela;
  END IF;
  EXECUTE pg_catalog.format('SELECT count(*) FROM public.%I',tabela) INTO n_linhas;
  IF n_linhas<>0 THEN
   RAISE EXCEPTION 'Tabela % contém % registros. Não alterar sem plano de dados.',tabela,n_linhas;
  END IF;
 END LOOP;
END $seguranca$;

-- Retira privilégios anônimos; RLS sem política concede zero acesso por padrão.
-- As futuras políticas por empresa devem vir de restauração/revisão independente.
REVOKE ALL ON TABLE public.ew_acessorios FROM PUBLIC, anon;
ALTER TABLE public.ew_acessorios ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_estoque_obras_movimentos FROM PUBLIC, anon;
ALTER TABLE public.ew_estoque_obras_movimentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_estoques_locais FROM PUBLIC, anon;
ALTER TABLE public.ew_estoques_locais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_locais_fisicos FROM PUBLIC, anon;
ALTER TABLE public.ew_locais_fisicos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_materiais_variacoes FROM PUBLIC, anon;
ALTER TABLE public.ew_materiais_variacoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_nfe_recebimentos FROM PUBLIC, anon;
ALTER TABLE public.ew_nfe_recebimentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_obra_despesas FROM PUBLIC, anon;
ALTER TABLE public.ew_obra_despesas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_obra_despesas_itens FROM PUBLIC, anon;
ALTER TABLE public.ew_obra_despesas_itens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_obra_faturamentos FROM PUBLIC, anon;
ALTER TABLE public.ew_obra_faturamentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_obra_orcamento FROM PUBLIC, anon;
ALTER TABLE public.ew_obra_orcamento ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ew_perfis FROM PUBLIC, anon;
ALTER TABLE public.ew_perfis ENABLE ROW LEVEL SECURITY;

DO $verificar$
DECLARE qtd integer;
BEGIN
 SELECT count(*) INTO qtd
 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname=ANY(ARRAY[
  'ew_acessorios',
  'ew_estoque_obras_movimentos',
  'ew_estoques_locais',
  'ew_locais_fisicos',
  'ew_materiais_variacoes',
  'ew_nfe_recebimentos',
  'ew_obra_despesas',
  'ew_obra_despesas_itens',
  'ew_obra_faturamentos',
  'ew_obra_orcamento',
  'ew_perfis'
 ]) AND c.relrowsecurity
   AND NOT pg_catalog.has_table_privilege('anon',c.oid,'SELECT')
   AND NOT pg_catalog.has_table_privilege('anon',c.oid,'INSERT');
 IF qtd<>11 THEN RAISE EXCEPTION 'Hardening incompleto: % / 11',qtd; END IF;
END $verificar$;
COMMIT;
-- Próximas etapas: schema fiel de produção, políticas por empresa, testes
-- autenticados e restauração efetiva. Não liberar dados reais neste staging
-- enquanto as etapas restantes não forem homologadas.
