-- EWGEST v46.9 | reconciliação de integridade do importador CEM somente em Supabase staging
-- Equivalência de constraints/índices de materiais, perfis, aliases, obras e estoques.
-- Não alterar produção. Alvos vazios: preservar Auth e empresa existentes.
BEGIN;
SET LOCAL search_path TO public,auth,pg_catalog;
DO $guard$
DECLARE tab text; n bigint; x integer;
BEGIN
 SELECT count(*) INTO x FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace WHERE s.nspname='public' AND c.relkind='r';
 IF x<>41 OR (SELECT count(*) FROM auth.users)<>1 OR (SELECT count(*) FROM public.empresas)<>1
  THEN RAISE EXCEPTION 'Staging divergiu (41 tabelas, 1 Auth e 1 empresa esperados).';END IF;
 FOREACH tab IN ARRAY ARRAY['obras','esquadrias','ew_perfis','ew_acessorios','ew_materiais_variacoes','ew_materiais_alias',
 'ew_cem_obras_materiais','ew_cem_importacoes_materiais','ew_estoques_locais','ew_obra_orcamento'] LOOP
  EXECUTE format('select count(*) from public.%I',tab) INTO n;
  IF n<>0 THEN RAISE EXCEPTION 'Tabela % não está vazia: %. Abortando.',tab,n; END IF;
 END LOOP;
END $guard$;
ALTER TABLE public.ew_acessorios ALTER COLUMN fabricante DROP DEFAULT;
ALTER TABLE public.ew_acessorios ALTER COLUMN unidade_item SET DEFAULT 'PC';
ALTER TABLE public.ew_perfis ALTER COLUMN fabricante DROP DEFAULT;
ALTER TABLE public.ew_materiais_alias ALTER COLUMN tipo SET NOT NULL;
ALTER TABLE public.ew_materiais_alias ALTER COLUMN fabricante SET NOT NULL;
ALTER TABLE public.ew_materiais_alias ALTER COLUMN codigo_alternativo SET NOT NULL;
ALTER TABLE public.ew_materiais_variacoes ALTER COLUMN ativo SET NOT NULL;
ALTER TABLE public.ew_cem_obras_materiais ALTER COLUMN quantidade_prevista TYPE numeric(18,4);
ALTER TABLE public.ew_cem_obras_materiais ALTER COLUMN comprimento_total_m TYPE numeric(18,4);
ALTER TABLE public.ew_obra_orcamento ALTER COLUMN aluminio DROP DEFAULT;
ALTER TABLE public.ew_obra_orcamento ALTER COLUMN acessorios DROP DEFAULT;
ALTER TABLE public.ew_obra_orcamento ALTER COLUMN vidros DROP DEFAULT;
ALTER TABLE public.ew_obra_orcamento ALTER COLUMN outros DROP DEFAULT;
ALTER TABLE public.ew_obra_orcamento ALTER COLUMN fabricacao DROP DEFAULT;
ALTER TABLE public.ew_obra_orcamento ALTER COLUMN instalacao DROP DEFAULT;
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_empresa_id_unico" UNIQUE (empresa_id, id);
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_unico" UNIQUE (empresa_id, fabricante, codigo);
ALTER TABLE public."ew_estoques_locais" ADD CONSTRAINT "ew_estoques_locais_empresa_id_obra_id_key" UNIQUE (empresa_id, obra_id);
ALTER TABLE public."ew_materiais_alias" ADD CONSTRAINT "ew_materiais_alias_empresa_id_tipo_fabricante_codigo_altern_key" UNIQUE (empresa_id, tipo, fabricante, codigo_alternativo);
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_empresa_id_unico" UNIQUE (empresa_id, id);
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_unico" UNIQUE (empresa_id, fabricante, codigo);
ALTER TABLE public."esquadrias" ADD CONSTRAINT "esquadrias_quantidade_modulos_check" CHECK (((quantidade_modulos >= 1) AND (quantidade_modulos <= 100)));
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_codigo_check" CHECK (((length(btrim(codigo)) >= 1) AND (length(btrim(codigo)) <= 90)));
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_descricao_check" CHECK (((length(btrim(descricao)) >= 2) AND (length(btrim(descricao)) <= 500)));
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_fabricante_check" CHECK (((length(btrim(fabricante)) >= 1) AND (length(btrim(fabricante)) <= 150)));
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_quantidade_por_embalagem_check" CHECK (((quantidade_por_embalagem IS NULL) OR (quantidade_por_embalagem > (0)::numeric)));
ALTER TABLE public."ew_cem_obras_materiais" ADD CONSTRAINT "cem_mat_tipo_check" CHECK ((((tipo = 'perfil'::text) AND (perfil_id IS NOT NULL) AND (acessorio_id IS NULL)) OR ((tipo = 'acessorio'::text) AND (acessorio_id IS NOT NULL) AND (perfil_id IS NULL))));
ALTER TABLE public."ew_cem_obras_materiais" ADD CONSTRAINT "ew_cem_obras_materiais_linhas_calculo_check" CHECK ((linhas_calculo >= 0));
ALTER TABLE public."ew_estoques_locais" ADD CONSTRAINT "ew_local_archive_consistency" CHECK ((((excluido_em IS NULL) AND (excluido_por IS NULL) AND (restauravel_ate IS NULL)) OR ((excluido_em IS NOT NULL) AND (excluido_por IS NOT NULL) AND (restauravel_ate IS NOT NULL))));
ALTER TABLE public."ew_materiais_alias" ADD CONSTRAINT "ew_alias_tipo" CHECK ((((tipo = 'perfil'::text) AND (perfil_id IS NOT NULL) AND (acessorio_id IS NULL)) OR ((tipo = 'acessorio'::text) AND (acessorio_id IS NOT NULL) AND (perfil_id IS NULL))));
ALTER TABLE public."ew_materiais_alias" ADD CONSTRAINT "ew_materiais_alias_tipo_check" CHECK ((tipo = ANY (ARRAY['perfil'::text, 'acessorio'::text])));
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_materiais_variacoes_tipo_check" CHECK ((tipo = ANY (ARRAY['perfil'::text, 'acessorio'::text])));
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_var_uma_origem" CHECK ((((tipo = 'perfil'::text) AND (perfil_id IS NOT NULL) AND (acessorio_id IS NULL)) OR ((tipo = 'acessorio'::text) AND (acessorio_id IS NOT NULL) AND (perfil_id IS NULL))));
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_codigo_check" CHECK (((length(btrim(codigo)) >= 1) AND (length(btrim(codigo)) <= 90)));
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_comprimento_comercial_mm_check" CHECK (((comprimento_comercial_mm IS NULL) OR (comprimento_comercial_mm > 0)));
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_descricao_check" CHECK (((length(btrim(descricao)) >= 2) AND (length(btrim(descricao)) <= 500)));
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_fabricante_check" CHECK (((length(btrim(fabricante)) >= 1) AND (length(btrim(fabricante)) <= 150)));
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_peso_kg_m_check" CHECK (((peso_kg_m IS NULL) OR (peso_kg_m >= (0)::numeric)));
ALTER TABLE public."esquadrias" ADD CONSTRAINT "esquadrias_tipologia_id_fkey" FOREIGN KEY (tipologia_id) REFERENCES tipologias(id);
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_atualizado_por_fkey" FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_acessorios" ADD CONSTRAINT "ew_acessorios_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES empresas(id);
ALTER TABLE public."ew_cem_obras_materiais" ADD CONSTRAINT "cem_mat_aces_fk" FOREIGN KEY (empresa_id, acessorio_id) REFERENCES ew_acessorios(empresa_id, id);
ALTER TABLE public."ew_cem_obras_materiais" ADD CONSTRAINT "cem_mat_perfil_fk" FOREIGN KEY (empresa_id, perfil_id) REFERENCES ew_perfis(empresa_id, id);
ALTER TABLE public."ew_estoques_locais" ADD CONSTRAINT "ew_estoques_locais_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_estoques_locais" ADD CONSTRAINT "ew_estoques_locais_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES empresas(id);
ALTER TABLE public."ew_estoques_locais" ADD CONSTRAINT "ew_estoques_locais_excluido_por_fkey" FOREIGN KEY (excluido_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_estoques_locais" ADD CONSTRAINT "ew_estoques_locais_obra_id_fkey" FOREIGN KEY (obra_id) REFERENCES obras(id);
ALTER TABLE public."ew_materiais_alias" ADD CONSTRAINT "ew_materiais_alias_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_materiais_variacoes_atualizado_por_fkey" FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_materiais_variacoes_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_materiais_variacoes_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES empresas(id);
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_var_acessorio_fk" FOREIGN KEY (empresa_id, acessorio_id) REFERENCES ew_acessorios(empresa_id, id);
ALTER TABLE public."ew_materiais_variacoes" ADD CONSTRAINT "ew_var_perfil_fk" FOREIGN KEY (empresa_id, perfil_id) REFERENCES ew_perfis(empresa_id, id);
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_atualizado_por_fkey" FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_criado_por_fkey" FOREIGN KEY (criado_por) REFERENCES auth.users(id);
ALTER TABLE public."ew_perfis" ADD CONSTRAINT "ew_perfis_empresa_id_fkey" FOREIGN KEY (empresa_id) REFERENCES empresas(id);
CREATE UNIQUE INDEX ew_acessorios_codigo_fabricante_normalizado ON public.ew_acessorios USING btree (empresa_id, upper(btrim(fabricante)), upper(btrim(codigo)));
CREATE UNIQUE INDEX cem_mat_empresa_obra_var_unique ON public.ew_cem_obras_materiais USING btree (empresa_id, obra_id, variacao_id);
CREATE INDEX idx_cem_materiais_obras ON public.ew_cem_obras_materiais USING btree (empresa_id, obra_id, tipo);
CREATE INDEX ew_local_status_idx ON public.ew_estoques_locais USING btree (empresa_id, excluido_em, restauravel_ate);
CREATE UNIQUE INDEX ew_var_acessorio_unica ON public.ew_materiais_variacoes USING btree (empresa_id, acessorio_id, acabamento, cor, codigo_cor) WHERE (acessorio_id IS NOT NULL);
CREATE UNIQUE INDEX ew_var_perfil_unica ON public.ew_materiais_variacoes USING btree (empresa_id, perfil_id, acabamento, cor, codigo_cor) WHERE (perfil_id IS NOT NULL);
CREATE INDEX ew_var_por_empresa ON public.ew_materiais_variacoes USING btree (empresa_id, tipo);
CREATE UNIQUE INDEX ew_perfis_codigo_fabricante_normalizado ON public.ew_perfis USING btree (empresa_id, upper(btrim(fabricante)), upper(btrim(codigo)));
DO $post$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_constraint k JOIN pg_class t ON t.oid=k.conrelid JOIN pg_namespace s ON s.oid=t.relnamespace
 WHERE s.nspname='public' AND k.conname IN ('ew_acessorios_empresa_id_unico','ew_acessorios_unico','ew_estoques_locais_empresa_id_obra_id_key','ew_materiais_alias_empresa_id_tipo_fabricante_codigo_altern_key','ew_perfis_empresa_id_unico','ew_perfis_unico','esquadrias_quantidade_modulos_check','ew_acessorios_codigo_check','ew_acessorios_descricao_check','ew_acessorios_fabricante_check','ew_acessorios_quantidade_por_embalagem_check','cem_mat_tipo_check','ew_cem_obras_materiais_linhas_calculo_check','ew_local_archive_consistency','ew_alias_tipo','ew_materiais_alias_tipo_check','ew_materiais_variacoes_tipo_check','ew_var_uma_origem','ew_perfis_codigo_check','ew_perfis_comprimento_comercial_mm_check','ew_perfis_descricao_check','ew_perfis_fabricante_check','ew_perfis_peso_kg_m_check','esquadrias_tipologia_id_fkey','ew_acessorios_atualizado_por_fkey','ew_acessorios_criado_por_fkey','ew_acessorios_empresa_id_fkey','cem_mat_aces_fk','cem_mat_perfil_fk','ew_estoques_locais_criado_por_fkey','ew_estoques_locais_empresa_id_fkey','ew_estoques_locais_excluido_por_fkey','ew_estoques_locais_obra_id_fkey','ew_materiais_alias_criado_por_fkey','ew_materiais_variacoes_atualizado_por_fkey','ew_materiais_variacoes_criado_por_fkey','ew_materiais_variacoes_empresa_id_fkey','ew_var_acessorio_fk','ew_var_perfil_fk','ew_perfis_atualizado_por_fkey','ew_perfis_criado_por_fkey','ew_perfis_empresa_id_fkey');
 IF n<>42 THEN RAISE EXCEPTION 'Constraints esperadas: 42, encontradas: %',n;END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity)<>0
 THEN RAISE EXCEPTION 'RLS desligado inesperadamente.';END IF;
END $post$;
COMMIT;
