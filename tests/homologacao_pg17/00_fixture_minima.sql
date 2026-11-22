-- Homologação isolada em PostgreSQL descartável do GitHub Actions.
-- ATENÇÃO: são somente os contratos mínimos das tabelas dependentes.
-- NÃO é um espelho do schema de produção; a importação preexistente é simulada.
\set ON_ERROR_STOP on
CREATE SCHEMA auth;
DO $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated')
 THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon')
 THEN CREATE ROLE anon NOLOGIN; END IF;
END $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $ SELECT coalesce(
 NULLIF(current_setting('request.jwt.claim.sub',true),''),
 NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'sub'
)::uuid $;
CREATE TABLE public.empresas (id uuid PRIMARY KEY,nome text NOT NULL);
CREATE TABLE public.usuarios_empresas (
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 usuario_id uuid NOT NULL REFERENCES auth.users(id),
 perfil text NOT NULL, PRIMARY KEY(empresa_id,usuario_id)
);
CREATE TABLE public.tipologias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 codigo text NOT NULL
);
CREATE TABLE public.obras (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 codigo text NOT NULL,nome text NOT NULL,
 UNIQUE(id,empresa_id),UNIQUE(empresa_id,id),UNIQUE(empresa_id,codigo)
);
CREATE TABLE public.esquadrias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL,
 codigo text NOT NULL,
 descricao text NOT NULL,
 largura_mm numeric NOT NULL,altura_mm numeric NOT NULL,
 quantidade integer NOT NULL,
 FOREIGN KEY(empresa_id,obra_id) REFERENCES public.obras(empresa_id,id)
);
CREATE TABLE public.ew_obra_orcamento (
 empresa_id uuid NOT NULL,
 obra_id uuid NOT NULL,
 valor_total numeric NOT NULL,
 fabricacao numeric NOT NULL,
 instalacao numeric NOT NULL,
 PRIMARY KEY(empresa_id,obra_id),
 FOREIGN KEY(empresa_id,obra_id) REFERENCES public.obras(empresa_id,id)
);
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão obrigatória';END IF;
END $$;
-- Stub de infraestrutura: substitui SOMENTE o importador financeiro legado.
-- O módulo NOVO será executado integralmente pelos arquivos versionados.
CREATE FUNCTION public.ew_importar_obra_cem_financeiro(
 p_empresa_id uuid,p_codigo_obra text,p_nome_obra text,p_cliente text,
 p_esquadrias jsonb,p_perfis jsonb,p_acessorios jsonb,p_operacao_id uuid,
 p_decisoes jsonb,p_orcamento jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
 v_obra uuid;v_id uuid;v_item jsonb;v_ids jsonb:='[]'::jsonb;
 v_fab numeric:=0;v_inst numeric:=0;
BEGIN
 INSERT INTO public.obras(empresa_id,codigo,nome)
 VALUES(p_empresa_id,p_codigo_obra,p_nome_obra) RETURNING id INTO v_obra;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_esquadrias) LOOP
  INSERT INTO public.esquadrias(empresa_id,obra_id,codigo,descricao,
   largura_mm,altura_mm,quantidade)
  VALUES(p_empresa_id,v_obra,v_item->>'codigo',v_item->>'descricao',
   (v_item->>'largura_mm')::numeric,(v_item->>'altura_mm')::numeric,
   (v_item->>'quantidade')::integer)
  RETURNING id INTO v_id;
  v_ids:=v_ids||jsonb_build_array(v_id);
 END LOOP;
 SELECT coalesce(sum((x->>'valor')::numeric) FILTER(WHERE x->>'categoria_base'='fabricacao'),0),
  coalesce(sum((x->>'valor')::numeric) FILTER(WHERE x->>'categoria_base'='instalacao'),0)
 INTO v_fab,v_inst FROM jsonb_array_elements(p_orcamento->'niveis') x;
 INSERT INTO public.ew_obra_orcamento(empresa_id,obra_id,valor_total,fabricacao,instalacao)
 VALUES(p_empresa_id,v_obra,v_fab+v_inst,v_fab,v_inst);
 RETURN jsonb_build_object('obra_criada',true,'obra_id',v_obra,
  'orcamento_gravado',true,'esquadrias_novas',jsonb_array_length(p_esquadrias),
  'esquadrias_ids',v_ids,'estoque_fisico_alterado',false);
END $$;
REVOKE ALL ON FUNCTION public.ew_importar_obra_cem_financeiro(
 uuid,text,text,text,jsonb,jsonb,jsonb,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
INSERT INTO auth.users(id) VALUES
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222');
INSERT INTO public.empresas(id,nome) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Empresa fictícia A'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Empresa fictícia B');
INSERT INTO public.usuarios_empresas(empresa_id,usuario_id,perfil) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','administrador'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','almoxarife');
INSERT INTO public.tipologias(empresa_id,codigo)
VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','GOLD-JCR101'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','GC100');
GRANT USAGE ON SCHEMA public,auth TO authenticated,anon;
GRANT SELECT ON auth.users,public.empresas,public.usuarios_empresas,public.tipologias,public.obras,
 public.esquadrias,public.ew_obra_orcamento TO authenticated;
GRANT EXECUTE ON FUNCTION public.ew_exigir_sessao_atual() TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon;
