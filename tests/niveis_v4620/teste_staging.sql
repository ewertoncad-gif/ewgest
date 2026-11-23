-- Homologação em banco de testes. TODOS os usuários fictícios e mudanças revertidos.
BEGIN;
INSERT INTO public.usuarios_login(usuario_id,empresa_id,login,nome,perfil,nivel_acesso,ativo)
 VALUES('040b8754-8557-449c-8ad4-eaa34155c920',
 '9ea7617c-6603-4bc1-91e1-c5e274c334d9','TESTE_ADMIN_V4620','Administrador fictício',
 'administrador',1,true);
SELECT set_config('request.jwt.claim.sub','040b8754-8557-449c-8ad4-eaa34155c920',true);
DO $t$
DECLARE r jsonb;res jsonb;n integer;
BEGIN
 IF NOT public.ew_pode('9ea7617c-6603-4bc1-91e1-c5e274c334d9','niveis.gerenciar')
 THEN RAISE EXCEPTION 'Nível 01 não autorizado';END IF;
 r:=public.ew_listar_niveis('9ea7617c-6603-4bc1-91e1-c5e274c334d9');
 IF jsonb_array_length(r->'niveis')<>8 OR jsonb_array_length(r->'catalogo')<>28
 THEN RAISE EXCEPTION 'Matriz incompleta: %',r;END IF;
 res:=public.ew_salvar_nivel('9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 7,ARRAY['obras.consultar','relatorios.operacionais']);
 IF (res->'flags'->>'relatorios.financeiros')::boolean
 THEN RAISE EXCEPTION 'Nivel 07 ganhou financeiro';END IF;
 BEGIN
  PERFORM public.ew_salvar_nivel('9ea7617c-6603-4bc1-91e1-c5e274c334d9',1,ARRAY[]::text[]);
  RAISE EXCEPTION 'Permitiu alteração do nível 01';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'Nível 01 é protegido%' THEN RAISE; END IF;
 END;
END;$t$;
INSERT INTO public.usuarios_empresas(empresa_id,usuario_id,perfil,nivel_acesso)
 VALUES('9ea7617c-6603-4bc1-91e1-c5e274c334d9',
 'c7777777-7777-4777-8777-777777777777','consulta',7);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,login,nome,perfil,nivel_acesso,ativo)
 VALUES('c7777777-7777-4777-8777-777777777777',
 '9ea7617c-6603-4bc1-91e1-c5e274c334d9','CONSULTA_V4620','Consulta fictício',
 'consulta',7,true);
SELECT set_config('request.jwt.claim.sub','c7777777-7777-4777-8777-777777777777',true);
DO $test$
BEGIN
 IF NOT public.ew_pode('9ea7617c-6603-4bc1-91e1-c5e274c334d9','relatorios.operacionais')
 THEN RAISE EXCEPTION 'Relatórios operacionais deveriam estar autorizados';END IF;
 IF public.ew_pode('9ea7617c-6603-4bc1-91e1-c5e274c334d9','relatorios.financeiros')
 THEN RAISE EXCEPTION 'Relatórios financeiros foram liberados ao nível 07';END IF;
 BEGIN
  PERFORM public.ew_exigir_permissao('financeiro.faturar');
  RAISE EXCEPTION 'Consulta indevidamente autorizada a faturar';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'PERMISSAO_NEGADA%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.ew_salvar_nivel('9ea7617c-6603-4bc1-91e1-c5e274c334d9',7,ARRAY['financeiro.faturar']);
  RAISE EXCEPTION 'Consulta alterou a matriz';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'PERMISSAO_NEGADA%' THEN RAISE; END IF;
 END;
END;
$test$;
ROLLBACK;
SELECT 'OK: 8 níveis e 28 flags; nível 01 protegido; 07 sem financeiro; edição rejeitada para consulta' AS resultado;