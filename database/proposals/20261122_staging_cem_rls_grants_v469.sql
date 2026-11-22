-- EWGEST v46.9 | normalizar grants e RLS das 10 tabelas centrais do importador CEM
-- Fonte: políticas do banco de produção, lidas sem dados em 22/11/2026.
-- Destino EXCLUSIVO: ewgest-restauracao-teste Free, 41 tabelas, 0 obras.
-- Mantém papéis empresariais e Auth existentes, revoga DELETE/INSERT excessivos do estágio legado.
-- Produção não alterada. NÃO REAPLICAR sem revisão de política.
BEGIN;
SET LOCAL search_path TO public,auth,pg_catalog;
DO $guard$
DECLARE total int; pol int; anon int; tab text; lines bigint;
BEGIN
 SELECT count(*) INTO total FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind='r';
 IF total<>41 THEN RAISE EXCEPTION 'Somente staging com 41 tabelas permitido (atual=%).',total;END IF;
 SELECT count(*) INTO pol FROM pg_policies WHERE schemaname='public' AND tablename=ANY(ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias','ew_cem_obras_materiais','ew_estoques_locais','ew_cem_importacoes_materiais','ew_obra_orcamento']);
 IF pol<>7 THEN RAISE EXCEPTION 'Políticas anteriores mudaram (% em vez de 7).',pol; END IF;
 SELECT count(*) INTO anon FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname=ANY(ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias','ew_cem_obras_materiais','ew_estoques_locais','ew_cem_importacoes_materiais','ew_obra_orcamento']) AND (has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('anon',c.oid,'INSERT'));
 IF anon<>0 THEN RAISE EXCEPTION 'Existem privilégios anônimos no staging.'; END IF;
 FOREACH tab IN ARRAY ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias','ew_cem_obras_materiais','ew_estoques_locais','ew_cem_importacoes_materiais','ew_obra_orcamento'] LOOP
  EXECUTE format('SELECT count(*) FROM public.%I',tab) INTO lines;
  IF lines<>0 THEN RAISE EXCEPTION 'Tabela % não está vazia (%).',tab,lines; END IF;
 END LOOP;
END $guard$;
DROP POLICY "Cadastrar esquadrias" ON public."esquadrias";
DROP POLICY "Consultar esquadrias da empresa" ON public."esquadrias";
DROP POLICY "Editar esquadrias" ON public."esquadrias";
DROP POLICY "ew_cem_obras_materiais_teste_pertence" ON public."ew_cem_obras_materiais";
DROP POLICY "Cadastrar obras" ON public."obras";
DROP POLICY "Consultar obras da empresa" ON public."obras";
DROP POLICY "Editar obras" ON public."obras";
CREATE POLICY "Cadastrar esquadrias" ON public."esquadrias" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = esquadrias.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text]))))));
CREATE POLICY "Consultar esquadrias da empresa" ON public."esquadrias" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = esquadrias.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Editar esquadrias" ON public."esquadrias" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = esquadrias.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text]))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = esquadrias.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text]))))));
CREATE POLICY "ADM atualiza acessórios" ON public."ew_acessorios" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_acessorios.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_acessorios.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "ADM insere acessórios" ON public."ew_acessorios" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_acessorios.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "Consultar acessórios da empresa" ON public."ew_acessorios" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_acessorios.empresa_id)))));
CREATE POLICY "ADM registra importações CEM" ON public."ew_cem_importacoes_materiais" FOR INSERT TO authenticated
 WITH CHECK (((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_cem_importacoes_materiais.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))) AND (criado_por = ( SELECT auth.uid() AS uid))));
CREATE POLICY "Empresa consulta importações CEM" ON public."ew_cem_importacoes_materiais" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_cem_importacoes_materiais.empresa_id)))));
CREATE POLICY "ADM atualiza materiais por obra CEM" ON public."ew_cem_obras_materiais" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_cem_obras_materiais.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_cem_obras_materiais.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "ADM vincula materiais por obra CEM" ON public."ew_cem_obras_materiais" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_cem_obras_materiais.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "Empresa consulta materiais por obra CEM" ON public."ew_cem_obras_materiais" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_cem_obras_materiais.empresa_id)))));
CREATE POLICY "Equipe da empresa consulta locais do estoque" ON public."ew_estoques_locais" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_estoques_locais.empresa_id)))));
CREATE POLICY "Consultar codigos alternativos" ON public."ew_materiais_alias" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = ew_materiais_alias.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "ADM atualiza variações" ON public."ew_materiais_variacoes" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_materiais_variacoes.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_materiais_variacoes.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "ADM insere variações" ON public."ew_materiais_variacoes" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_materiais_variacoes.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "Consultar variações da empresa" ON public."ew_materiais_variacoes" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_materiais_variacoes.empresa_id)))));
CREATE POLICY "ew_orcamento_insert" ON public."ew_obra_orcamento" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = ew_obra_orcamento.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = 'administrador'::text)))));
CREATE POLICY "ew_orcamento_select" ON public."ew_obra_orcamento" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = ew_obra_orcamento.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "ew_orcamento_update" ON public."ew_obra_orcamento" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = ew_obra_orcamento.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = 'administrador'::text)))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = ew_obra_orcamento.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = 'administrador'::text)))));
CREATE POLICY "ADM atualiza perfis" ON public."ew_perfis" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_perfis.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_perfis.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "ADM insere perfis" ON public."ew_perfis" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_perfis.empresa_id) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text]))))));
CREATE POLICY "Consultar perfis da empresa" ON public."ew_perfis" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.empresa_id = ew_perfis.empresa_id)))));
CREATE POLICY "Cadastrar obras" ON public."obras" FOR INSERT TO authenticated
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = obras.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text]))))));
CREATE POLICY "Consultar obras da empresa" ON public."obras" FOR SELECT TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = obras.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid))))));
CREATE POLICY "Editar obras" ON public."obras" FOR UPDATE TO authenticated
 USING ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = obras.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text]))))))
 WITH CHECK ((EXISTS ( SELECT 1
   FROM usuarios_empresas ue
  WHERE ((ue.empresa_id = obras.empresa_id) AND (ue.usuario_id = ( SELECT auth.uid() AS uid)) AND (ue.perfil = ANY (ARRAY['administrador'::text, 'gerenciador'::text, 'supervisor'::text]))))));
REVOKE ALL ON TABLE public."esquadrias" FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public."esquadrias" TO authenticated;
REVOKE ALL ON TABLE public."ew_acessorios" FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public."ew_acessorios" TO authenticated;
REVOKE ALL ON TABLE public."ew_cem_importacoes_materiais" FROM authenticated;
GRANT SELECT, INSERT ON TABLE public."ew_cem_importacoes_materiais" TO authenticated;
REVOKE ALL ON TABLE public."ew_cem_obras_materiais" FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public."ew_cem_obras_materiais" TO authenticated;
REVOKE ALL ON TABLE public."ew_estoques_locais" FROM authenticated;
GRANT SELECT ON TABLE public."ew_estoques_locais" TO authenticated;
REVOKE ALL ON TABLE public."ew_materiais_alias" FROM authenticated;
GRANT SELECT ON TABLE public."ew_materiais_alias" TO authenticated;
REVOKE ALL ON TABLE public."ew_materiais_variacoes" FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public."ew_materiais_variacoes" TO authenticated;
REVOKE ALL ON TABLE public."ew_obra_orcamento" FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public."ew_obra_orcamento" TO authenticated;
REVOKE ALL ON TABLE public."ew_perfis" FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public."ew_perfis" TO authenticated;
REVOKE ALL ON TABLE public."obras" FROM authenticated;
GRANT SELECT, UPDATE ON TABLE public."obras" TO authenticated;
DO $post$
DECLARE qty int; bad int;
BEGIN
 SELECT count(*) INTO qty FROM pg_policies WHERE schemaname='public' AND tablename=ANY(ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias','ew_cem_obras_materiais','ew_estoques_locais','ew_cem_importacoes_materiais','ew_obra_orcamento']);
 IF qty<>25 THEN RAISE EXCEPTION 'Políticas esperadas: 25, obtidas %.',qty;END IF;
 SELECT count(*) INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname=ANY(ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias','ew_cem_obras_materiais','ew_estoques_locais','ew_cem_importacoes_materiais','ew_obra_orcamento']) AND
 (has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('anon',c.oid,'INSERT') OR NOT c.relrowsecurity);
 IF bad<>0 THEN RAISE EXCEPTION 'RLS/anon inseguro em % tabelas.',bad;END IF;
END $post$;
COMMIT;
