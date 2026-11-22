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


## 5. Reconstrução central do importador CEM — execução em staging

**Etapa aplicada e testada em 22/11/2026**, no projeto `ewgest-restauracao-teste` exclusivamente. Produção permanece com 59 tabelas públicas, 98 funções públicas e **sem** qualquer objeto novo de precificação.

### Migrações do estágio (aplicadas com pré-ensaio + ROLLBACK)

1. `database/proposals/20261122_staging_cem_core_contracts_v469.sql` — **44 colunas** faltantes alinhadas para contratos das tabelas centrais, incluindo catálogo de perfis e acessórios, variações, estoque local, esquadrias e planejamento de barras; criou `ew_cem_importacoes_materiais` com 10 campos, chave única, FKs, RLS ativo e grants fechados.
2. `database/proposals/20261122_staging_cem_core_integridade_v469.sql` — **42 restrições adicionais** de integridade (unicidade, CHECKs e FKs), índices de materiais, aliases e estoque; corrigiu defaults, nulidade e precisão numérica em alvos vazios. FK `esquadrias_modulacao_id_fkey` continua pendente porque `tipologias_modulacoes` ainda não existe no staging. Duas restrições com nomes diferentes já tinham efeito equivalente no staging; não foram criadas em duplicidade.
3. `database/proposals/20261122_staging_importador_real_v469.sql` — restaurou do código de produção, **sem importar dados**, as rotinas `ew_criar_obra_estoque`, `ew_conciliar_codigo_cem`, `importar_materiais_cem`, `ew_importar_cem_conciliado`; substituiu a função antiga de `ew_importar_obra_cem` pela adaptação versionada v46.9 que devolve UUIDs das esquadrias na ordem do ZIP. O wrapper financeiro legado já era idêntico ao de produção. Restabeleceu privilégios `EXECUTE` somente a `authenticated`.
4. `database/proposals/20261122_staging_cem_rls_grants_v469.sql` — restaurou as **25 políticas de produção** em dez tabelas centrais de importação, substituindo as sete políticas antigas, e ajustou os `GRANTs` do perfil `authenticated` para refletir o padrão de produção. Removeu `DELETE`/escritas diretas que o staging antigo permitia indevidamente.
5. `database/proposals/20261122_precificacao_importacao_rpc_v469.sql` — após ensaio que não persistiu a função, **instalou somente no staging** a nova RPC `ew_importar_obra_cem_precificacao` com o rateio revalidado no servidor e gravação atômica da revisão com a obra. Papel `anon` sem EXECUTE; `authenticated` pode executar, com verificação interna do vínculo de administrador.

### Testes no Supabase REAL (dados fictícios, sem persistência)

Executados dentro de `BEGIN; ... ROLLBACK;`, com **o usuário Auth já existente no staging** e uma claim SQL simulada. Não usamos senha nem token de produção.

- O importador financeiro legado REAL criou temporariamente obra + 2 esquadrias + orçamento de dois níveis + estoque local.
- O mesmo importador com materiais REAL criou um perfil fictício, um acessório fictício, 2 variações, vínculos do CEM, plano de barras e registro de importação. Sem baixa física.
- A RPC v46.9 combinada ao importador REAL fechou o valor de 70/30 contratado em **60/40 aprovado**, com duas esquadrias e 2 preços individuais; retry com o mesmo ID não duplicou obra; alteração de um centavo foi rejeitada antes de qualquer operação de escrita.
- A RPC combinada **com materiais e planejamento de barras** passou e não deixou dados parciais quando o preço estava adulterado.
- A RPC barrou a tentativa de aprovação quando o perfil da sessão simulada foi trocado temporariamente para `almoxarife`. O perfil `administrador` original foi preservado pelo ROLLBACK.
- O teste pode ser reexecutado com o arquivo versionado **`tests/homologacao_supabase_free/10_importador_real_com_precificacao_rollback.sql`**. Ele nunca faz COMMIT e verifica no final que as tabelas permanecem vazias.

### Estado verificado após os testes

| Indicador | Staging Free | Produção |
|---|---:|---:|
| Tabelas públicas | 41 | 59 |
| Tabelas com RLS ativo | 41 | 59 |
| Funções públicas | 50 | 98 |
| Tabelas com privilégios anon de leitura/inserção | 0 | 0 |
| Funções públicas com anon EXECUTE | 0 | 3 (estado original; sem alterações) |
| Obras | 0 | 5 |
| Esquadrias | 0 | 88 |
| Usuários Auth | 1 | 6 |
| RPC de importação com preços v46.9 | instalada | ausente |

Supabase Advisor do staging: 20 tabelas com RLS sem políticas (`INFO`, algumas são módulos antigos ainda por reconstruir) e aviso sobre proteção contra senhas vazadas (`WARN`). Não abrir políticas amplas nem alterar produção automaticamente.

**Faltam**, antes de liberar a v46.9: reconstruir romaneios, configuração de folhas, faturamento por itens, funções de faturamento e respectivos limites, relacionamentos de tipologias/modulações, a checagem real de sessões (`ew_exigir_sessao_atual` ainda é simulada no staging) e teste de login via Supabase Auth/PostgREST com JWT verdadeiro; também conferir backup restaurável e fluxo visual do site. O staging é **parcialmente homologado, não um espelho completo da produção**. PR #64 mantém-se em rascunho.
