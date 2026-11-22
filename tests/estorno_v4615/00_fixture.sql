-- EWGEST v46.15: PostgreSQL 17 DESCARTÁVEL, apenas obras e IDs fictícios.
\set ON_ERROR_STOP on
CREATE SCHEMA auth;
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $roles$;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE public.empresas(id uuid PRIMARY KEY);
CREATE TABLE public.usuarios_empresas(
 empresa_id uuid NOT NULL REFERENCES public.empresas,
 usuario_id uuid NOT NULL REFERENCES auth.users,
 perfil text NOT NULL, PRIMARY KEY(empresa_id,usuario_id)
);
CREATE TABLE public.obras (
 id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES public.empresas,
 nome text NOT NULL, codigo text NOT NULL, arquivada_em timestamptz
);
CREATE TABLE public.ew_estoques_locais (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas,
 obra_id uuid NOT NULL REFERENCES public.obras,
 excluido_em timestamptz
);
CREATE TABLE public.ew_estoque_obras_movimentos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas,
 obra_id uuid NOT NULL REFERENCES public.obras,
 variacao_id uuid NOT NULL,
 comprimento_mm integer,
 unidade text NOT NULL,
 quantidade_delta numeric NOT NULL,
 origem text NOT NULL,
 transferencia_id uuid,
 estorno_de_id uuid UNIQUE REFERENCES public.ew_estoque_obras_movimentos(id),
 local_estoque text NOT NULL,
 operacao_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 usuario_id uuid,
 observacao text DEFAULT '',
 criado_em timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE public.usuarios_login (
 usuario_id uuid NOT NULL REFERENCES auth.users(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 perfil text NOT NULL, ativo boolean NOT NULL DEFAULT true,
 excluido_em timestamptz, PRIMARY KEY(usuario_id,empresa_id)
);
CREATE TABLE public.ew_auditoria_operacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL,obra_id uuid NOT NULL,obra_nome text,obra_codigo text,
 usuario_id uuid NOT NULL,acao text NOT NULL,referencia_id uuid,
 operacao_id uuid UNIQUE,motivo text NOT NULL,detalhes jsonb NOT NULL DEFAULT '{}'::jsonb
);
-- Apenas referência de NF para que o estorno genérico recuse recebimentos vinculados.
CREATE TABLE public.ew_nfe_recebimentos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 movimento_id uuid NOT NULL REFERENCES public.ew_estoque_obras_movimentos(id),
 empresa_id uuid REFERENCES public.empresas(id),
 obra_id uuid REFERENCES public.obras(id),
 estornado_em timestamptz
);
CREATE TABLE public._blockers (obra_id uuid PRIMARY KEY, motivo text NOT NULL);
CREATE FUNCTION public.ew_exigir_sessao_atual() RETURNS void LANGUAGE plpgsql
AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão requerida'; END IF; END $$;
CREATE FUNCTION public.ew_inspecionar_reversao_obra(p_obra_id uuid) RETURNS jsonb
LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('motivos',coalesce((
  SELECT jsonb_build_array(motivo) FROM public._blockers WHERE obra_id=p_obra_id
 ),'[]'::jsonb))
$$;

INSERT INTO auth.users(id) VALUES
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222'),
 ('33333333-3333-4333-8333-333333333333');
INSERT INTO public.empresas(id) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
INSERT INTO public.usuarios_empresas(empresa_id,usuario_id,perfil) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','administrador'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','almoxarife'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333','administrador');
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil)
 SELECT usuario_id,empresa_id,perfil FROM public.usuarios_empresas;
INSERT INTO public.obras(id,empresa_id,nome,codigo) VALUES
 ('aaaaaaaa-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Obra A','TESTE-A'),
 ('aaaaaaaa-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Obra B','TESTE-B'),
 ('aaaaaaaa-0000-4000-8000-000000000003','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Obra C','TESTE-C'),
 ('bbbbbbbb-0000-4000-8000-000000000001','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Outra empresa','TESTE-X');
INSERT INTO public.ew_estoques_locais(empresa_id,obra_id)
 SELECT empresa_id,id FROM public.obras;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
