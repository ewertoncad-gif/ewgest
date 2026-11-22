-- EWGEST | PROPOSTA DE ESQUEMA — histórico de categorias e precificação.
-- FASE 1: documentar e versionar somente. NÃO EXECUTAR EM PRODUÇÃO.
--
-- Fase 2: integrar tela após valores e níveis da importação CEM.
-- Fase 3: implementar RPC transacional que salva uma revisão aprovada junto
-- com a obra e suas esquadrias e regras de faturamento.
-- Tabelas novas somente. Não ALTERAR contratos legados ou faturamento existente.
--
-- VALIDAÇÃO NECESSÁRIA antes de aplicar:
-- - ambiente de homologação compatível com o schema de produção;
-- - guardar snapshot/backup e planejar rollback;
-- - revisar RLS, GRANT e política de aprovação por administradores;
-- - garantir commits atômicos e idempotentes com a importação da obra.
BEGIN;

CREATE TABLE IF NOT EXISTS public.ew_precificacao_categorias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id) ON DELETE RESTRICT,
 nome text NOT NULL CHECK(length(btrim(nome)) BETWEEN 2 AND 120),
 ativo boolean NOT NULL DEFAULT true,
 criado_por uuid REFERENCES auth.users(id),
 criado_em timestamptz NOT NULL DEFAULT now(),
 atualizado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE (id,empresa_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS ew_precificacao_categorias_nome_empresa_idx
 ON public.ew_precificacao_categorias (empresa_id,lower(btrim(nome)));

-- Categoria sugerida do cadastro técnico (não modificar tipologia histórica).
CREATE TABLE IF NOT EXISTS public.ew_precificacao_tipologias_padrao (
 empresa_id uuid NOT NULL REFERENCES public.empresas(id) ON DELETE RESTRICT,
 tipologia_id uuid NOT NULL REFERENCES public.tipologias(id) ON DELETE RESTRICT,
 categoria_id uuid NOT NULL,
 alterado_por uuid REFERENCES auth.users(id),
 atualizado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,tipologia_id),
 FOREIGN KEY(categoria_id,empresa_id)
   REFERENCES public.ew_precificacao_categorias(id,empresa_id) ON DELETE RESTRICT
);
-- Antes de salvar o padrão, a futura RPC deverá confirmar que a tipologia pertence
-- à empresa. Essa verificação deve ser feita no banco, não apenas no frontend.

-- Uma revisão aprovada NÃO pode ser reescrita: criar versão posterior.
CREATE TABLE IF NOT EXISTS public.ew_precificacao_revisoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id) ON DELETE RESTRICT,
 obra_id uuid NOT NULL,
 versao integer NOT NULL CHECK(versao>=1),
 revisao_anterior_id uuid,
 fabricacao_original_centavos bigint NOT NULL CHECK(fabricacao_original_centavos>=0),
 instalacao_original_centavos bigint NOT NULL CHECK(instalacao_original_centavos>=0),
 fabricacao_distribuida_centavos bigint NOT NULL CHECK(fabricacao_distribuida_centavos>=0),
 instalacao_distribuida_centavos bigint NOT NULL CHECK(instalacao_distribuida_centavos>=0),
 percentual_fabricacao_bp integer NOT NULL CHECK(percentual_fabricacao_bp BETWEEN 0 AND 10000),
 area_total_m2 numeric(20,6) NOT NULL CHECK(area_total_m2>0),
 estado text NOT NULL DEFAULT 'aprovada' CHECK(estado='aprovada'),
 resumo_origem text NOT NULL DEFAULT 'importacao_cem',
 motivo text NOT NULL DEFAULT 'Aprovação da precificação por obra',
 aprovado_por uuid NOT NULL REFERENCES auth.users(id),
 aprovado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,obra_id,versao),
 UNIQUE(id,empresa_id,obra_id),
 FOREIGN KEY(empresa_id,obra_id) REFERENCES public.obras(empresa_id,id)
  ON DELETE RESTRICT,
 FOREIGN KEY(revisao_anterior_id) REFERENCES public.ew_precificacao_revisoes(id)
  ON DELETE RESTRICT,
 CHECK(fabricacao_original_centavos+instalacao_original_centavos =
       fabricacao_distribuida_centavos+instalacao_distribuida_centavos)
);
CREATE INDEX IF NOT EXISTS ew_precificacao_revisoes_obra_idx
 ON public.ew_precificacao_revisoes(empresa_id,obra_id,versao DESC);

-- Histórico do preço base e valores recalculados por categoria.
CREATE TABLE IF NOT EXISTS public.ew_precificacao_revisoes_categorias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL,
 obra_id uuid NOT NULL,
 revisao_id uuid NOT NULL,
 categoria_id uuid,
 categoria_nome_snapshot text NOT NULL CHECK(length(btrim(categoria_nome_snapshot)) BETWEEN 2 AND 120),
 preco_base_m2_centavos bigint NOT NULL CHECK(preco_base_m2_centavos>=0),
 area_m2 numeric(20,6) NOT NULL CHECK(area_m2>=0),
 fabricacao_centavos bigint NOT NULL CHECK(fabricacao_centavos>=0),
 instalacao_centavos bigint NOT NULL CHECK(instalacao_centavos>=0),
 UNIQUE(revisao_id,categoria_nome_snapshot),
 FOREIGN KEY(revisao_id,empresa_id,obra_id)
  REFERENCES public.ew_precificacao_revisoes(id,empresa_id,obra_id)
  ON DELETE RESTRICT,
 FOREIGN KEY(categoria_id,empresa_id)
  REFERENCES public.ew_precificacao_categorias(id,empresa_id) ON DELETE RESTRICT
);

-- Snapshot financeiro individual; categoria/linha/texto são capturados na época.
CREATE TABLE IF NOT EXISTS public.ew_precificacao_revisoes_itens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL,
 obra_id uuid NOT NULL,
 revisao_id uuid NOT NULL,
 indice_importacao integer NOT NULL CHECK(indice_importacao>=0),
 esquadria_id uuid REFERENCES public.esquadrias(id) ON DELETE RESTRICT,
 tipologia_id uuid REFERENCES public.tipologias(id) ON DELETE RESTRICT,
 categoria_id uuid,
 categoria_nome_snapshot text NOT NULL,
 codigo_snapshot text NOT NULL,
 descricao_snapshot text NOT NULL,
 linha_snapshot text,
 largura_mm numeric(12,3) NOT NULL CHECK(largura_mm>0),
 altura_mm numeric(12,3) NOT NULL CHECK(altura_mm>0),
 quantidade integer NOT NULL CHECK(quantidade>0),
 area_m2 numeric(20,6) NOT NULL CHECK(area_m2>0),
 fabricacao_centavos bigint NOT NULL CHECK(fabricacao_centavos>=0),
 instalacao_centavos bigint NOT NULL CHECK(instalacao_centavos>=0),
 UNIQUE(revisao_id,indice_importacao),
 FOREIGN KEY(revisao_id,empresa_id,obra_id)
  REFERENCES public.ew_precificacao_revisoes(id,empresa_id,obra_id) ON DELETE RESTRICT,
 FOREIGN KEY(categoria_id,empresa_id)
  REFERENCES public.ew_precificacao_categorias(id,empresa_id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS ew_precificacao_itens_consulta_obra_idx
 ON public.ew_precificacao_revisoes_itens(empresa_id,obra_id,esquadria_id);

-- A RPC de aprovação (fase 3) deve validar no servidor, numa transação:
-- 1. autor = administrador da mesma empresa e obra;
-- 2. unicidade e imutabilidade de (empresa,obra,versão);
-- 3. categoria, tipologia e esquadria pertencem à empresa/obra informada;
-- 4. soma das áreas e de todas as linhas coincide com os totais da revisão;
-- 5. orçamento original confere com ew_obra_orcamento;
-- 6. versão 1 é aprovada atomicamente com importação, não há obra semi-importada;
-- 7. operação idempotente impede retries criando revisões duplicadas.
-- Não criar RPC de escrita privilegiada enquanto estes testes não existirem.

-- Impedir retificações silenciosas em revisões e snapshots aprovados.
CREATE OR REPLACE FUNCTION public.ew_precificacao_impedir_mutacao_revisao()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
 RAISE EXCEPTION 'Precificação aprovada é imutável: crie uma nova revisão auditável.';
END;
$$;
REVOKE ALL ON FUNCTION public.ew_precificacao_impedir_mutacao_revisao() FROM PUBLIC,anon,authenticated;
DO $triggers$
DECLARE tabela text;
BEGIN
 FOREACH tabela IN ARRAY ARRAY[
  'ew_precificacao_revisoes','ew_precificacao_revisoes_categorias',
  'ew_precificacao_revisoes_itens'
 ] LOOP
  EXECUTE format('DROP TRIGGER IF EXISTS ew_precificacao_no_update_delete ON public.%I',tabela);
  EXECUTE format('CREATE TRIGGER ew_precificacao_no_update_delete BEFORE UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.ew_precificacao_impedir_mutacao_revisao()',tabela);
 END LOOP;
END
$triggers$;

ALTER TABLE public.ew_precificacao_categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_precificacao_tipologias_padrao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_precificacao_revisoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_precificacao_revisoes_categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_precificacao_revisoes_itens ENABLE ROW LEVEL SECURITY;

-- Consultas por empresa: administrativa/gerencial.
CREATE POLICY ew_prec_cat_select ON public.ew_precificacao_categorias FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
 ue.empresa_id=ew_precificacao_categorias.empresa_id AND ue.usuario_id=(SELECT auth.uid())
 AND ue.perfil IN ('administrador','gerenciador')));
CREATE POLICY ew_prec_padroes_select ON public.ew_precificacao_tipologias_padrao FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
 ue.empresa_id=ew_precificacao_tipologias_padrao.empresa_id AND ue.usuario_id=(SELECT auth.uid())
 AND ue.perfil IN ('administrador','gerenciador')));
CREATE POLICY ew_prec_rev_select ON public.ew_precificacao_revisoes FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
 ue.empresa_id=ew_precificacao_revisoes.empresa_id AND ue.usuario_id=(SELECT auth.uid())
 AND ue.perfil IN ('administrador','gerenciador')));
CREATE POLICY ew_prec_rev_cats_select ON public.ew_precificacao_revisoes_categorias FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
 ue.empresa_id=ew_precificacao_revisoes_categorias.empresa_id AND ue.usuario_id=(SELECT auth.uid())
 AND ue.perfil IN ('administrador','gerenciador')));
CREATE POLICY ew_prec_rev_itens_select ON public.ew_precificacao_revisoes_itens FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
 ue.empresa_id=ew_precificacao_revisoes_itens.empresa_id AND ue.usuario_id=(SELECT auth.uid())
 AND ue.perfil IN ('administrador','gerenciador')));

-- Apenas leitura REST por administradores/gerenciadores. Escrita futura via RPC
-- autorizada que aplicará as validações listadas. Nunca liberar INSERT anônimo.
REVOKE ALL ON public.ew_precificacao_categorias,
 public.ew_precificacao_tipologias_padrao,public.ew_precificacao_revisoes,
 public.ew_precificacao_revisoes_categorias,public.ew_precificacao_revisoes_itens
 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.ew_precificacao_categorias,
 public.ew_precificacao_tipologias_padrao,public.ew_precificacao_revisoes,
 public.ew_precificacao_revisoes_categorias,public.ew_precificacao_revisoes_itens TO authenticated;
COMMIT;
