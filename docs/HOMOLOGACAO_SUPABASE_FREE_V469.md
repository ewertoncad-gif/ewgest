# EWGEST v46.9 — Homologação real do esquema no Supabase Free

**Data:** 22/11/2026. **Ambiente utilizado:** projeto existente `ewgest-restauracao-teste` (PostgreSQL 17.11). **Produção intocada**, sem upgrade de plano, sem exclusão/importação de obras, sem senhas, tokens ou dados comerciais copiados.

## 1. Fortalecimento de segurança do staging — aplicado e verificado

Estado inicial: 35 tabelas públicas; 24 com RLS; 11 sem RLS e com grants `SELECT/INSERT` para `anon`; outras 13 já tinham RLS, mas conservavam permissões SQL anônimas. Existiam 15 funções públicas executáveis por `anon` (7 `SECURITY DEFINER`).

Migrações **executadas somente no staging**, com precondições e transações que abortam em caso de diferença:

1. `database/proposals/20261122_staging_free_hardening_sem_dados.sql`: 11 tabelas vazias, RLS ligado e revogação dos privilégios anônimos.
2. `database/proposals/20261122_staging_revogar_anon_restante.sql`: revogação de grants anônimos nas outras 13 tabelas, preservando as políticas `authenticated`.
3. `database/proposals/20261122_staging_revogar_anon_funcoes.sql`: revogação de `EXECUTE` anônimo em 15 funções, incluindo 7 privilegiadas. A primeira tentativa abortou integralmente, porque a verificação supunha que todas as funções tinham acesso `authenticated`; após confirmar as 6 funções internas que **já** eram bloqueadas, o guard passou e a migração foi aplicada. Pós-teste: 44 funções públicas, 0 anon EXECUTE, 38 funções com authenticated EXECUTE e 6 internas sem esse direito.
4. `database/proposals/20261122_staging_auto_rls_event_trigger.sql`: instalação no staging do event trigger `ensure_rls`, ausente anteriormente, com a mesma função `rls_auto_enable()`, hash MD5 `846ec2fbff751d24b890656d63c3a9bf` e tags de produção. Um `CREATE TABLE` dentro de `BEGIN/ROLLBACK` confirmou que a nova tabela recebe RLS automaticamente; ao final não restou tabela de teste.

**Resultado:** nenhuma tabela pública do staging possui concessões `SELECT/INSERT` para `anon`; nenhuma função pública permite `EXECUTE` por `anon`. A produção mantém sua configuração original (59 tabelas, todas com RLS); nenhuma migração deste bloco foi aplicada lá.

**Nota:** 26 tabelas antigas do staging têm RLS mas não têm política de acesso — o bloqueio aos usuários comuns é intencional até a reconstrução das políticas multiempresa. Não criar políticas permissivas apenas para tornar os testes verdes.

## 2. Cinco tabelas de precificação — aplicadas somente no staging

Foi executado primeiro um ensaio da migração `database/proposals/20261122_precificacao_categorias_historico_fase1.sql` com `BEGIN; ... ROLLBACK;`, e o sistema confirmou **0 tabelas persistidas**. Após sucesso, a mesma migração versionada foi **aplicada no staging**, sem alterações em dados pré-existentes.

Tabelas instaladas:

- `ew_precificacao_categorias` (cadastro por empresa)
- `ew_precificacao_tipologias_padrao` (preferência por tipologia)
- `ew_precificacao_revisoes` (revisões aprovadas)
- `ew_precificacao_revisoes_categorias` (snapshot por categoria)
- `ew_precificacao_revisoes_itens` (snapshot por esquadria)

Validação read-only posterior confirmou **40 tabelas públicas, 40 com RLS**. Nas 5 tabelas novas: 5 políticas de leitura `TO authenticated` restritas a administrador/gerenciador, nenhum `SELECT/INSERT` para `anon`, nenhum `INSERT` direto para o papel `authenticated` e 3 triggers de imutabilidade em revisões e snapshots.

## 3. Testes transacionais sobre o Supabase real

Sem executar login via API de Auth, foi simulada no contexto SQL a claim JWT de **um usuário de staging já existente** com `SET LOCAL ROLE authenticated`. Dados inventados foram sempre incluídos em transações revertidas integralmente.

- **Permissões da categoria:** perfil administrador consegue ler categoria fictícia da própria empresa; ao trocar temporariamente o vínculo para `almoxarife` dentro da transação, a consulta retorna zero registros. No fim, `ROLLBACK` restaurou o perfil administrador. Zero categorias fictícias persistidas.
- **Histórico imutável:** criação temporária de obra, esquadria, categoria, revisão, snapshot de categoria e snapshot por item. As tentativas de `UPDATE` na revisão, `UPDATE` na categoria histórica e `DELETE` no item histórico foram todas rejeitadas pelo trigger. A transação foi revertida.
- **Pós-testes:** staging conserva **1 usuário Auth e 1 empresa já existentes**, **0 obras**, **0 esquadrias**, **0 revisões** e **0 categorias artificiais**.

Esses testes exercem PostgreSQL, FKs, RLS e triggers no projeto Supabase real, mas **não são autenticação Supabase Auth por login HTTP de verdade**. Também não exercem a importação real de CEM em staging, pois o legado do staging ainda diverge do ambiente de produção.

## 4. Pendências para v46.9 ficar publicável

O inventário está em [DRIFT_SCHEMA_SUPABASE_V469.md](DRIFT_SCHEMA_SUPABASE_V469.md). Ele foi feito **antes** das cinco novas tabelas de precificação; seus números comparam os dois schemas de legado e permanecem úteis como diagnóstico. O staging antigo continua sem 24 tabelas de legado existentes em produção, com 75 colunas faltantes nas tabelas em comum, 32 diferenças de definição, 54 funções faltantes, 4 funções divergentes, 69 políticas ausentes, 13 triggers e 109 índices faltantes.

Falta reconstruir o **legado** de importação de obras, estoque, romaneios e faturamento de forma fiel, preservar Auth/usuários existentes, validar login real pela API, simular importação completa com ZIP sem dados comerciais, executar restauração efetiva do backup criptografado e revisar implantação/rollback. **Não aplicar ainda a RPC de importação ou os tetos novos no staging enquanto suas dependências antigas permanecerem incompatíveis.**

**Status:** PR #64 permanece rascunho. v46.8 continua publicada; nenhuma migração de v46.9 foi aplicada em produção.
