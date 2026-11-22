-- EWGEST v46.20 - níveis de acesso por empresa (01 a 08)
-- Matriz relacional e verificação server-side. Perfil legado é mantido por compatibilidade.
BEGIN;
CREATE TABLE IF NOT EXISTS public.ew_permissoes_catalogo(
 chave text PRIMARY KEY,
 grupo text NOT NULL,
 descricao text NOT NULL,
 ordem smallint NOT NULL
);
CREATE TABLE IF NOT EXISTS public.ew_niveis_acesso(
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 nivel smallint NOT NULL CHECK(nivel BETWEEN 1 AND 8),
 nome text NOT NULL CHECK(length(trim(nome)) BETWEEN 2 AND 80),
 PRIMARY KEY(empresa_id,nivel)
);
CREATE TABLE IF NOT EXISTS public.ew_niveis_permissoes(
 empresa_id uuid NOT NULL,nivel smallint NOT NULL,
 chave text NOT NULL REFERENCES public.ew_permissoes_catalogo(chave),
 permitido boolean NOT NULL DEFAULT false,
 PRIMARY KEY(empresa_id,nivel,chave),
 FOREIGN KEY (empresa_id,nivel) REFERENCES public.ew_niveis_acesso(empresa_id,nivel) ON DELETE RESTRICT
);
CREATE TABLE IF NOT EXISTS public.ew_niveis_auditoria(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,
 nivel smallint NOT NULL,usuario_id uuid NOT NULL,
 antes jsonb NOT NULL,depois jsonb NOT NULL,
 criado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.usuarios_empresas ADD COLUMN IF NOT EXISTS nivel_acesso smallint
 CHECK(nivel_acesso BETWEEN 1 AND 8);
ALTER TABLE public.usuarios_login ADD COLUMN IF NOT EXISTS nivel_acesso smallint
 CHECK(nivel_acesso BETWEEN 1 AND 8);
INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES
('obras.consultar','Navegação','Consultar obras',1),
('relatorios.operacionais','Navegação','Consultar relatórios operacionais',2),
('relatorios.financeiros','Navegação','Consultar relatórios financeiros',3),
('obras.importar','Obras','Importar obra',4),
('obras.estornar','Obras','Estornar/excluir obra definitivamente',5),
('liberacoes.consultar','Liberação','Consultar liberações',6),
('liberacoes.criar','Liberação','Liberar para fabricação',7),
('liberacoes.cancelar','Liberação','Cancelar liberações',8),
('romaneios.consultar','Romaneios','Consultar romaneios',9),
('romaneios.emitir','Romaneios','Emitir romaneios de expedição',10),
('romaneios.cancelar','Romaneios','Cancelar romaneios',11),
('romaneios.transferir','Romaneios','Gerenciar romaneios de transferência',12),
('estoque.consultar','Estoque','Consultar estoque',13),
('estoque.receber','Estoque','Receber/cadastrar entradas',14),
('estoque.baixar','Estoque','Baixar material para fábrica/obra',15),
('estoque.transferir_galpoes','Estoque','Transferir entre galpões',16),
('estoque.transferir_obras','Estoque','Transferir entre obras',17),
('estoque.estornar','Estoque','Estornar movimentações de estoque',18),
('financeiro.consultar','Financeiro','Consultar financeiro',19),
('financeiro.faturar','Financeiro','Registrar faturamentos',20),
('financeiro.cancelar_faturamento','Financeiro','Cancelar faturamentos',21),
('financeiro.despesas','Financeiro','Registrar despesas e notas',22),
('financeiro.cancelar_despesas','Financeiro','Estornar despesas e notas',23),
('cadastros.consultar','Cadastros','Consultar cadastros técnicos',24),
('cadastros.editar','Cadastros','Alterar cadastros técnicos',25),
('usuarios.gerenciar','Administração','Cadastrar e administrar usuários',26),
('niveis.gerenciar','Administração','Configurar níveis e permissões',27),
('auditoria.consultar','Administração','Consultar auditoria de operações/acessos',28)
ON CONFLICT(chave) DO UPDATE SET grupo=EXCLUDED.grupo,descricao=EXCLUDED.descricao,ordem=EXCLUDED.ordem;
INSERT INTO public.ew_niveis_acesso(empresa_id,nivel,nome)
SELECT e.id,v.nivel,v.nome FROM public.empresas e CROSS JOIN (VALUES
 (1,'01 · Administrador'),(2,'02 · Gerência'),(3,'03 · Técnico'),
 (4,'04 · Almoxarifado'),(5,'05 · Financeiro'),
 (6,'06 · Consulta completa'),(7,'07 · Consulta operacional'),(8,'08 · Sem permissões')
) v(nivel,nome) ON CONFLICT DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT n.empresa_id,n.nivel,c.chave,
 CASE WHEN n.nivel=1 THEN true
 ELSE c.chave = ANY(CASE n.nivel
 WHEN 2 THEN ARRAY['obras.consultar','relatorios.operacionais','relatorios.financeiros','obras.importar','obras.estornar','liberacoes.consultar','liberacoes.criar','liberacoes.cancelar','romaneios.consultar','romaneios.emitir','romaneios.cancelar','romaneios.transferir','estoque.consultar','estoque.receber','estoque.baixar','estoque.transferir_galpoes','estoque.transferir_obras','estoque.estornar','financeiro.consultar','financeiro.faturar','financeiro.despesas','cadastros.consultar','cadastros.editar','usuarios.gerenciar','auditoria.consultar']::text[]
 WHEN 3 THEN ARRAY['obras.consultar','obras.importar','liberacoes.consultar','liberacoes.criar','romaneios.consultar','romaneios.emitir','estoque.consultar','relatorios.operacionais','cadastros.consultar']::text[]
 WHEN 4 THEN ARRAY['obras.consultar','liberacoes.consultar','romaneios.consultar','romaneios.emitir','romaneios.transferir','estoque.consultar','estoque.receber','estoque.baixar','estoque.transferir_galpoes','estoque.transferir_obras','relatorios.operacionais']::text[]
 WHEN 5 THEN ARRAY['obras.consultar','relatorios.operacionais','relatorios.financeiros','financeiro.consultar','financeiro.faturar','financeiro.cancelar_faturamento','financeiro.despesas','financeiro.cancelar_despesas']::text[]
 WHEN 6 THEN ARRAY['obras.consultar','liberacoes.consultar','romaneios.consultar','estoque.consultar','financeiro.consultar','relatorios.operacionais','relatorios.financeiros','cadastros.consultar']::text[]
 WHEN 7 THEN ARRAY['obras.consultar','liberacoes.consultar','romaneios.consultar','estoque.consultar','relatorios.operacionais','cadastros.consultar']::text[]
 WHEN 8 THEN ARRAY[]::text[]
 ELSE ARRAY[]::text[] END) END
FROM public.ew_niveis_acesso n CROSS JOIN public.ew_permissoes_catalogo c
ON CONFLICT DO NOTHING;

-- Atribuição inicial: EWERTON 01; gerentes 02; técnicos 03; almoxarifes 04;
-- financeiro 05; consulta 06; visitante desativado 08.
UPDATE public.usuarios_login SET nivel_acesso=CASE
 WHEN upper(trim(nome))='EWERTON' AND perfil='administrador' THEN 1
 WHEN perfil='administrador' THEN 1
 WHEN perfil='gerenciador' THEN 2
 WHEN perfil IN ('tecnico','supervisor') THEN 3
 WHEN perfil='almoxarife' THEN 4
 WHEN perfil='financeiro' THEN 5
 WHEN perfil='consulta' AND ativo AND excluido_em IS NULL THEN 6
 ELSE 8 END
 WHERE nivel_acesso IS NULL;
UPDATE public.usuarios_empresas ue SET nivel_acesso=ul.nivel_acesso
FROM public.usuarios_login ul WHERE ue.usuario_id=ul.usuario_id
AND ue.empresa_id=ul.empresa_id AND ue.nivel_acesso IS NULL;
-- Vínculos de migrações antigas podem existir sem cadastro de login correspondente.
UPDATE public.usuarios_empresas SET nivel_acesso=CASE
 WHEN perfil='administrador' THEN 1 WHEN perfil='gerenciador' THEN 2
 WHEN perfil IN ('tecnico','supervisor') THEN 3 WHEN perfil='almoxarife' THEN 4
 WHEN perfil='financeiro' THEN 5 WHEN perfil='consulta' THEN 6 ELSE 8 END
 WHERE nivel_acesso IS NULL;
ALTER TABLE public.usuarios_login ALTER COLUMN nivel_acesso SET DEFAULT 8;
ALTER TABLE public.usuarios_empresas ALTER COLUMN nivel_acesso SET DEFAULT 8;
ALTER TABLE public.usuarios_login ALTER COLUMN nivel_acesso SET NOT NULL;
ALTER TABLE public.usuarios_empresas ALTER COLUMN nivel_acesso SET NOT NULL;

ALTER TABLE public.ew_permissoes_catalogo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_niveis_acesso ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_niveis_permissoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_niveis_auditoria ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ew_permissoes_catalogo,public.ew_niveis_acesso,
 public.ew_niveis_permissoes,public.ew_niveis_auditoria FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.ew_permissoes_catalogo TO authenticated;
CREATE POLICY catalogo_permissoes_read ON public.ew_permissoes_catalogo
 FOR SELECT TO authenticated USING ((select auth.uid()) IS NOT NULL);

-- A autorização consulta o cadastro e o vínculo ATUAIS, não claims editáveis nem cache.
CREATE OR REPLACE FUNCTION public.ew_pode(p_empresa_id uuid,p_chave text)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS(
 SELECT 1 FROM public.usuarios_login ul
 JOIN public.usuarios_empresas ue ON ue.usuario_id=ul.usuario_id AND ue.empresa_id=ul.empresa_id
 JOIN public.ew_niveis_permissoes np ON np.empresa_id=ue.empresa_id
  AND np.nivel=ue.nivel_acesso AND np.chave=p_chave AND np.permitido
 WHERE ul.usuario_id=(SELECT auth.uid()) AND ul.empresa_id=p_empresa_id
  AND ul.ativo AND ul.excluido_em IS NULL AND ue.perfil=ul.perfil
  AND ue.nivel_acesso=ul.nivel_acesso
  AND public.ew_sessao_eh_atual()
 );
$fn$;
CREATE OR REPLACE FUNCTION public.ew_pode_atual(p_chave text)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT EXISTS (SELECT 1 FROM public.usuarios_login ul
 WHERE ul.usuario_id=(SELECT auth.uid())
 AND public.ew_pode(ul.empresa_id,p_chave));
$fn$;
CREATE OR REPLACE FUNCTION public.ew_exigir_permissao(p_chave text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
 BEGIN
 IF NOT public.ew_pode_atual(p_chave) THEN
  RAISE EXCEPTION 'PERMISSAO_NEGADA: acesso % não autorizado para seu nível.',p_chave;
 END IF;
 END;
$fn$;

CREATE OR REPLACE FUNCTION public.ew_meu_nivel(p_empresa_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 DECLARE v_level smallint;v_flags jsonb;
 BEGIN
 SELECT ul.nivel_acesso INTO v_level FROM public.usuarios_login ul
 JOIN public.usuarios_empresas ue ON ue.usuario_id=ul.usuario_id
 AND ue.empresa_id=ul.empresa_id
 WHERE ul.usuario_id=(SELECT auth.uid()) AND ul.empresa_id=p_empresa_id
 AND ul.ativo AND ul.excluido_em IS NULL AND ul.perfil=ue.perfil
 AND ul.nivel_acesso=ue.nivel_acesso AND public.ew_sessao_eh_atual();
 IF v_level IS NULL THEN RAISE EXCEPTION 'PERMISSAO_NEGADA: usuário sem nível ativo.';END IF;
 SELECT coalesce(jsonb_object_agg(chave,permitido),'{}'::jsonb) INTO v_flags
 FROM public.ew_niveis_permissoes WHERE empresa_id=p_empresa_id AND nivel=v_level;
 RETURN jsonb_build_object('nivel',v_level,'flags',v_flags);
 END;
$fn$;

CREATE OR REPLACE FUNCTION public.ew_listar_niveis(p_empresa_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 DECLARE v_levels jsonb;v_catalog jsonb;
 BEGIN
 PERFORM public.ew_exigir_permissao('niveis.gerenciar');
 IF NOT EXISTS (SELECT 1 FROM public.usuarios_login
 WHERE usuario_id=(select auth.uid()) AND empresa_id=p_empresa_id AND nivel_acesso=1)
 THEN RAISE EXCEPTION 'Somente nível 01 configura a matriz de acesso.';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('nivel',n.nivel,'nome',n.nome,
   'flags',(SELECT coalesce(jsonb_object_agg(p.chave,p.permitido),'{}'::jsonb)
    FROM public.ew_niveis_permissoes p WHERE p.empresa_id=n.empresa_id AND p.nivel=n.nivel))
 ORDER BY n.nivel),'[]'::jsonb) INTO v_levels
 FROM public.ew_niveis_acesso n WHERE n.empresa_id=p_empresa_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('chave',chave,'grupo',grupo,
   'descricao',descricao,'ordem',ordem) ORDER BY ordem),'[]'::jsonb) INTO v_catalog
 FROM public.ew_permissoes_catalogo;
 RETURN jsonb_build_object('niveis',v_levels,'catalogo',v_catalog);
 END;
$fn$;

CREATE OR REPLACE FUNCTION public.ew_salvar_nivel(p_empresa_id uuid,p_nivel smallint,p_flags text[])
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
 DECLARE v_old jsonb;v_new jsonb;v_unknown integer;
 BEGIN
 PERFORM public.ew_exigir_permissao('niveis.gerenciar');
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_login ul
 WHERE ul.usuario_id=(SELECT auth.uid()) AND ul.empresa_id=p_empresa_id
 AND ul.nivel_acesso=1 AND ul.ativo AND ul.excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Somente nível 01 pode editar níveis.';END IF;
 IF p_nivel NOT BETWEEN 2 AND 8 THEN
  RAISE EXCEPTION 'Nível 01 é protegido para evitar perda do acesso administrativo.';
 END IF;
 IF p_flags IS NULL THEN RAISE EXCEPTION 'Selecione as flags (ou lista vazia).';END IF;
 SELECT count(*) INTO v_unknown FROM unnest(p_flags) k
 WHERE NOT EXISTS(SELECT 1 FROM public.ew_permissoes_catalogo c WHERE c.chave=k);
 IF v_unknown>0 THEN RAISE EXCEPTION 'Existem flags de acesso desconhecidas.';END IF;
 PERFORM 1 FROM public.ew_niveis_acesso
 WHERE empresa_id=p_empresa_id AND nivel=p_nivel FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Nível inexistente.';END IF;
 SELECT coalesce(jsonb_object_agg(chave,permitido),'{}'::jsonb)
 INTO v_old FROM public.ew_niveis_permissoes WHERE empresa_id=p_empresa_id AND nivel=p_nivel;
 UPDATE public.ew_niveis_permissoes SET permitido=(chave=ANY(p_flags))
 WHERE empresa_id=p_empresa_id AND nivel=p_nivel;
 SELECT coalesce(jsonb_object_agg(chave,permitido),'{}'::jsonb)
 INTO v_new FROM public.ew_niveis_permissoes WHERE empresa_id=p_empresa_id AND nivel=p_nivel;
 INSERT INTO public.ew_niveis_auditoria(empresa_id,nivel,usuario_id,antes,depois)
 VALUES(p_empresa_id,p_nivel,(SELECT auth.uid()),v_old,v_new);
 RETURN jsonb_build_object('nivel',p_nivel,'flags',v_new);
 END;
$fn$;
REVOKE ALL ON FUNCTION public.ew_pode(uuid,text),
 public.ew_pode_atual(text),public.ew_exigir_permissao(text),
 public.ew_meu_nivel(uuid),public.ew_listar_niveis(uuid),
 public.ew_salvar_nivel(uuid,smallint,text[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_pode(uuid,text),public.ew_pode_atual(text),
 public.ew_exigir_permissao(text),public.ew_meu_nivel(uuid),
 public.ew_listar_niveis(uuid),public.ew_salvar_nivel(uuid,smallint,text[]) TO authenticated;
COMMIT;
