-- v46.20 - Defesa em profundidade: flags validadas por RLS, não só pela interface.
-- Financeiro 05 e Consulta 06 enxergam financeiro apenas com flag; Consulta 07/08 não.
BEGIN;
DROP POLICY IF EXISTS "ew_faturas_select" ON public.ew_obra_faturamentos;
CREATE POLICY ew_flags_read ON public.ew_obra_faturamentos FOR SELECT TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.consultar')
 OR public.ew_pode(empresa_id,'relatorios.financeiros'));
DROP POLICY IF EXISTS "ew_faturas_insert" ON public.ew_obra_faturamentos;
CREATE POLICY ew_flags_insert ON public.ew_obra_faturamentos FOR INSERT TO authenticated
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.faturar'));
DROP POLICY IF EXISTS "ew_faturas_update" ON public.ew_obra_faturamentos;
CREATE POLICY ew_flags_update ON public.ew_obra_faturamentos FOR UPDATE TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.faturar'))
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.faturar'));
DROP POLICY IF EXISTS "ew_faturas_itens_select" ON public.ew_obra_faturamentos_itens;
CREATE POLICY ew_flags_read ON public.ew_obra_faturamentos_itens FOR SELECT TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.consultar')
 OR public.ew_pode(empresa_id,'relatorios.financeiros'));
DROP POLICY IF EXISTS "ew_faturas_itens_insert" ON public.ew_obra_faturamentos_itens;
CREATE POLICY ew_flags_insert ON public.ew_obra_faturamentos_itens FOR INSERT TO authenticated
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.faturar'));
DROP POLICY IF EXISTS "ew_despesas_select" ON public.ew_obra_despesas;
CREATE POLICY ew_flags_read ON public.ew_obra_despesas FOR SELECT TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.consultar')
 OR public.ew_pode(empresa_id,'relatorios.financeiros'));
DROP POLICY IF EXISTS "ew_despesas_insert" ON public.ew_obra_despesas;
CREATE POLICY ew_flags_insert ON public.ew_obra_despesas FOR INSERT TO authenticated
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.despesas'));
DROP POLICY IF EXISTS "ew_despesas_update" ON public.ew_obra_despesas;
CREATE POLICY ew_flags_update ON public.ew_obra_despesas FOR UPDATE TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.despesas'))
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.despesas'));
DROP POLICY IF EXISTS "ew_despesas_itens_select" ON public.ew_obra_despesas_itens;
CREATE POLICY ew_flags_read ON public.ew_obra_despesas_itens FOR SELECT TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.consultar')
 OR public.ew_pode(empresa_id,'relatorios.financeiros'));
DROP POLICY IF EXISTS "ew_despesas_itens_insert" ON public.ew_obra_despesas_itens;
CREATE POLICY ew_flags_insert ON public.ew_obra_despesas_itens FOR INSERT TO authenticated
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.despesas'));
DROP POLICY IF EXISTS "ew_despesas_itens_update_admin" ON public.ew_obra_despesas_itens;
CREATE POLICY ew_flags_update ON public.ew_obra_despesas_itens FOR UPDATE TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.despesas'))
 WITH CHECK(public.ew_pode(empresa_id,'financeiro.despesas'));
DROP POLICY IF EXISTS "ew_orcamento_select" ON public.ew_obra_orcamento;
CREATE POLICY ew_flags_read ON public.ew_obra_orcamento FOR SELECT TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.consultar')
 OR public.ew_pode(empresa_id,'relatorios.financeiros'));
DROP POLICY IF EXISTS "ew_orcamento_insert" ON public.ew_obra_orcamento;
CREATE POLICY ew_flags_insert ON public.ew_obra_orcamento FOR INSERT TO authenticated
 WITH CHECK(public.ew_pode(empresa_id,'obras.importar'));
DROP POLICY IF EXISTS "ew_orcamento_update" ON public.ew_obra_orcamento;
CREATE POLICY ew_flags_update ON public.ew_obra_orcamento FOR UPDATE TO authenticated
 USING(public.ew_pode(empresa_id,'obras.importar'))
 WITH CHECK(public.ew_pode(empresa_id,'obras.importar'));
DROP POLICY IF EXISTS "ew_obra_niveis_ler" ON public.ew_obra_orcamento_niveis;
CREATE POLICY ew_flags_read ON public.ew_obra_orcamento_niveis FOR SELECT TO authenticated
 USING(public.ew_pode(empresa_id,'financeiro.consultar')
 OR public.ew_pode(empresa_id,'relatorios.financeiros'));
DROP POLICY IF EXISTS "ew_obra_niveis_criar" ON public.ew_obra_orcamento_niveis;
CREATE POLICY ew_flags_insert ON public.ew_obra_orcamento_niveis FOR INSERT TO authenticated
 WITH CHECK(public.ew_pode(empresa_id,'obras.importar'));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.obras;
CREATE POLICY ew_nivel_select_restrito ON public.obras AS RESTRICTIVE
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'obras.consultar'));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.esquadrias;
CREATE POLICY ew_nivel_select_restrito ON public.esquadrias AS RESTRICTIVE
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'obras.consultar'));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.romaneios;
CREATE POLICY ew_nivel_select_restrito ON public.romaneios AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'romaneios.consultar') OR public.ew_pode(empresa_id,'relatorios.operacionais')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_estoque_obras_movimentos;
CREATE POLICY ew_nivel_select_restrito ON public.ew_estoque_obras_movimentos AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'relatorios.operacionais')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_nfe_recebimentos;
CREATE POLICY ew_nivel_select_restrito ON public.ew_nfe_recebimentos AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'estoque.receber') OR public.ew_pode(empresa_id,'financeiro.consultar') OR public.ew_pode(empresa_id,'relatorios.financeiros')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_perfis;
CREATE POLICY ew_nivel_select_restrito ON public.ew_perfis AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'relatorios.operacionais')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_acessorios;
CREATE POLICY ew_nivel_select_restrito ON public.ew_acessorios AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'relatorios.operacionais')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_materiais_variacoes;
CREATE POLICY ew_nivel_select_restrito ON public.ew_materiais_variacoes AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'estoque.consultar') OR public.ew_pode(empresa_id,'relatorios.operacionais')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.tipologias;
CREATE POLICY ew_nivel_select_restrito ON public.tipologias AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'obras.consultar')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.fabricantes;
CREATE POLICY ew_nivel_select_restrito ON public.fabricantes AS RESTRICTIVE
 FOR SELECT TO authenticated USING((public.ew_pode(empresa_id,'cadastros.consultar') OR public.ew_pode(empresa_id,'obras.consultar')));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_auditoria_operacoes;
CREATE POLICY ew_nivel_select_restrito ON public.ew_auditoria_operacoes AS RESTRICTIVE
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'auditoria.consultar'));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.ew_historico_acessos;
CREATE POLICY ew_nivel_select_restrito ON public.ew_historico_acessos AS RESTRICTIVE
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'auditoria.consultar'));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.usuarios_login;
CREATE POLICY ew_nivel_select_restrito ON public.usuarios_login AS RESTRICTIVE
 FOR SELECT TO authenticated USING((usuario_id=(SELECT auth.uid()) OR public.ew_pode(empresa_id,'usuarios.gerenciar') OR public.ew_pode(empresa_id,'auditoria.consultar')));
-- Tabelas sem empresa_id: consulta depende da empresa da esquadria/romaneio.
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.liberacoes_corte;
CREATE POLICY ew_nivel_select_restrito ON public.liberacoes_corte AS RESTRICTIVE
 FOR SELECT TO authenticated USING(EXISTS(
 SELECT 1 FROM public.esquadrias e WHERE e.id=liberacoes_corte.esquadria_id
 AND (public.ew_pode(e.empresa_id,'liberacoes.consultar')
  OR public.ew_pode(e.empresa_id,'relatorios.operacionais'))));
DROP POLICY IF EXISTS ew_nivel_select_restrito ON public.romaneios_itens;
CREATE POLICY ew_nivel_select_restrito ON public.romaneios_itens AS RESTRICTIVE
 FOR SELECT TO authenticated USING(EXISTS(
 SELECT 1 FROM public.romaneios r WHERE r.id=romaneios_itens.romaneio_id
 AND (public.ew_pode(r.empresa_id,'romaneios.consultar')
  OR public.ew_pode(r.empresa_id,'relatorios.operacionais'))));
-- Obra e estoque só podem ser alterados caso a respectiva flag esteja habilitada.
DROP POLICY IF EXISTS ew_nivel_insert_restrito ON public.obras;
CREATE POLICY ew_nivel_insert_restrito ON public.obras AS RESTRICTIVE
 FOR INSERT TO authenticated WITH CHECK(public.ew_pode(empresa_id,'obras.importar'));
DROP POLICY IF EXISTS ew_nivel_update_restrito ON public.obras;
CREATE POLICY ew_nivel_update_restrito ON public.obras AS RESTRICTIVE
 FOR UPDATE TO authenticated USING(public.ew_pode(empresa_id,'obras.importar')
 OR public.ew_pode(empresa_id,'obras.estornar'))
 WITH CHECK(public.ew_pode(empresa_id,'obras.importar')
 OR public.ew_pode(empresa_id,'obras.estornar'));
DROP POLICY IF EXISTS ew_nivel_insert_restrito ON public.ew_estoque_obras_movimentos;
CREATE POLICY ew_nivel_insert_restrito ON public.ew_estoque_obras_movimentos AS RESTRICTIVE
 FOR INSERT TO authenticated WITH CHECK(
 public.ew_pode(empresa_id,'estoque.baixar') OR public.ew_pode(empresa_id,'estoque.receber')
 OR public.ew_pode(empresa_id,'estoque.transferir_obras')
 OR public.ew_pode(empresa_id,'estoque.transferir_galpoes')
 OR public.ew_pode(empresa_id,'estoque.estornar'));
COMMIT;