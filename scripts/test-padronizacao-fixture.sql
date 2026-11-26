-- Banco descartável de CI: tabelas mínimas e um resolver-base simulado.
-- O reconhecimento futuro e a padronização são as funções SQL reais.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida'; END IF; END $$;
CREATE FUNCTION public.ew_pode(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT auth.uid() IS NOT NULL AND $1='10000000-0000-0000-0000-000000000001'::uuid $$;
CREATE TABLE public.tipologias(id uuid PRIMARY KEY,empresa_id uuid NOT NULL,codigo text,descricao text NOT NULL,tipologia_principal_id uuid,provisoria boolean NOT NULL DEFAULT false);
CREATE TABLE public.tipologias_modulacoes(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,tipologia_principal_id uuid NOT NULL,descricao text NOT NULL,quantidade_modulos integer,numero_variacao integer GENERATED ALWAYS AS IDENTITY,codigo_interno text DEFAULT 'MOD',tipologia_legada_id uuid);
CREATE TABLE public.esquadrias(id uuid PRIMARY KEY,empresa_id uuid NOT NULL,obra_id uuid NOT NULL,descricao text NOT NULL,quantidade_modulos integer,tipologia_id uuid,modulacao_id uuid);
CREATE TABLE public.classificacoes_tipologias_auditoria(empresa_id uuid NOT NULL,modulacao_id uuid,descricao_origem text NOT NULL);
CREATE FUNCTION public.resolver_modulacao_pendente_admin(p_e uuid,p_t uuid,p_m uuid,p_criar boolean,p_desc text,p_q integer,p_div boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e public.esquadrias%rowtype; m public.tipologias_modulacoes%rowtype;
BEGIN
 SELECT * INTO STRICT e FROM public.esquadrias WHERE id=p_e;
 IF p_criar THEN INSERT INTO public.tipologias_modulacoes(empresa_id,tipologia_principal_id,descricao,quantidade_modulos) VALUES(e.empresa_id,p_t,p_desc,p_q) RETURNING * INTO m;
 ELSE SELECT * INTO STRICT m FROM public.tipologias_modulacoes WHERE id=p_m AND empresa_id=e.empresa_id AND tipologia_principal_id=p_t; END IF;
 IF NOT p_div AND btrim(e.descricao)<>btrim(m.descricao) THEN RAISE EXCEPTION 'Divergência'; END IF;
 UPDATE public.esquadrias SET tipologia_id=p_t,modulacao_id=m.id WHERE id=p_e;
 INSERT INTO public.classificacoes_tipologias_auditoria VALUES(e.empresa_id,m.id,e.descricao);
 RETURN jsonb_build_object('modulacao_id',m.id,'nova_modulacao',p_criar,'numero_variacao',m.numero_variacao);
END $$;
