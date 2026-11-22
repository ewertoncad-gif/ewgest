# EWGEST v46.9 — Plano seguro de homologação no Supabase Free

**Data da conferência:** 22/11/2026. **Status:** levantamento somente leitura; nenhuma alteração aplicada a nenhum projeto. O PR #64 continua rascunho.

## Estado dos ambientes

| Aspecto | ewgest-producao | ewgest-restauracao-teste |
|---|---:|---:|
| PostgreSQL | 17.11 | 17.11 |
| Tabelas do schema public | 59 | 35 |
| Funções do schema public (assinaturas contabilizadas) | 98 | 44 |
| Tabelas public com RLS ligado | 59 | 24 |
| Tabelas public sem RLS | 0 | 11 |

O teste não é um espelho confiável de produção. Falta, entre outros, o controle completo de romaneios, módulos e auditoria, algumas tabelas de faturamento e registro de importações do CEM. **Não restaurar dados reais nele antes da adequação de políticas e permissões.**

### Tabelas ausentes no staging (24)

- `classificacoes_tipologias_auditoria`, `esquadrias_descricoes_revisoes`, `esquadrias_saida_config`
- `ew_cem_importacoes_materiais`, `ew_comprimentos_comerciais`, `ew_estoque_importacoes_cem`, `ew_historico_acessos`
- `ew_obra_faturamentos_itens`, `ew_obras_exclusoes_historico`, `ew_sessoes_unicas`
- `romaneios`, `romaneios_itens`, `romaneios_motoristas`, `romaneios_numeracao_historico`, `romaneios_veiculos`, `saidas_producao`
- `tipologias_abreviacoes`, `tipologias_abreviacoes_historico`, `tipologias_croquis`, `tipologias_edicoes`, `tipologias_identificacoes_historico`, `tipologias_modulacoes`, `tipologias_modulacoes_contadores`, `tipologias_origens`

Também existem diferenças de funções, políticas e privilégios. Somente criar as 24 tabelas **não** bastará para reproduzir o fluxo da GVG.

## Achado de segurança do staging antigo

As 11 tabelas a seguir estão **com RLS desligado** e possuem `SELECT` e `INSERT` permitidos ao papel `anon` pela camada PostgreSQL na data da conferência:

`ew_acessorios`, `ew_estoque_obras_movimentos`, `ew_estoques_locais`, `ew_locais_fisicos`, `ew_materiais_variacoes`, `ew_nfe_recebimentos`, `ew_obra_despesas`, `ew_obra_despesas_itens`, `ew_obra_faturamentos`, `ew_obra_orcamento`, `ew_perfis`.

A exposição efetiva pela API depende ainda da configuração do Data API, mas não devemos assumir proteção nessa configuração. A produção, ao contrário, tem RLS habilitado nas 59 tabelas públicas; habilitar RLS é necessário, mas **não substitui revisar cada política e GRANT**.

A proposta **não aplicada** `database/proposals/20261122_staging_free_hardening_sem_dados.sql` bloqueia os privilégios anônimos e ativa RLS **somente nessas 11 tabelas**, dentro de uma transação com pré-condições (35 tabelas públicas, 11 alvos ainda sem RLS, 0 linhas em cada alvo). Se qualquer verificação falhar, a transação aborta; a proposta não migra dados ou autoriza nova funcionalidade. **Não executar automaticamente no ambiente atual sem revisar as dependências.** Como não inclui políticas de leitura/gravação de negócio, depois de aplicado ele bloqueará acesso comum a essas tabelas até que suas políticas sejam restauradas corretamente.

## Sequência recomendada antes de publicar v46.9

1. Fazer inventário e preservar o conteúdo do projeto de testes; confirmar que pode ser reutilizado. Não sobrescrever uma restauração valiosa.
2. Proteger acesso anônimo e ativar as políticas corretas (não abrir política `USING (true)` para contornar erro).
3. Reconstruir schema, funções, triggers, grants e políticas a partir de migrações versionadas e comparadas com produção, **sem copiar usuários, sessões, credenciais ou obras reais**.
4. Criar **usuários de teste fictícios** pelos mecanismos apropriados de autenticação, com perfis ADM/almoxarife/empresa B, e testar via Data API real, incluindo RLS e idempotência.
5. Executar as propostas de precificação na ordem documentada, importar o ZIP de treinamento com dados não sensíveis e conferir orçamento, previsão de estoque e rateio financeiro.
6. Testar restauração do backup criptografado em banco independente, incluindo estrutura, chaves e dados, com credenciais protegidas. A existência de artefato criptografado no GitHub não prova restauração.
7. Revisar o PR #64, migrar produção em janela controlada, conferir status e fazer rollback se houver divergência.

**Restrições:** sem plano Supabase Pro, sem criar branch paga, sem gravar em produção, sem liberar dados reais no staging desprotegido. Por ora, regressões executáveis ficam no GitHub Actions com PostgreSQL/PostgREST descartáveis.

## Evidências

- [Homologação HTTP concorrente e testes reais do importador — CI](https://github.com/ewertoncad-gif/ewgest/actions/runs/45023090185)
- [Regressão do modal, entrada de percentual e travamento de valores inválidos](https://github.com/ewertoncad-gif/ewgest/actions/runs/45023366167)
- `docs/HOMOLOGACAO_PRECIFICACAO_V469.md` traz os cenários SQL, ZIP e faturamento detalhados.


## Atualização de execução — 22/11/2026

**Correção de segurança do staging aplicada e verificada.** O projeto `ewgest-restauracao-teste` possuía 35 tabelas públicas, 11 delas sem RLS, com permissões `anon`; após confirmar que as 11 estavam vazias, executamos dentro de uma transação a proposta `database/proposals/20261122_staging_free_hardening_sem_dados.sql` **somente naquele projeto**. As 11 agora estão com RLS ativo e sem privilégios anônimos de leitura/inserção.

Também identificamos 13 outras tabelas que **já** tinham RLS e políticas apenas de `authenticated`, mas ainda traziam `SELECT/INSERT` para `anon`. Foi aplicada a proposta guardada `database/proposals/20261122_staging_revogar_anon_restante.sql`, sem mudar as políticas nem os privilégios explícitos dos usuários autenticados.

**Comprovação pós-execução:**
- Staging: 35 tabelas públicas; **35 com RLS**, **0 sem RLS**, **0 com `anon SELECT`**, **0 com `anon INSERT`**.
- Produção: 59 tabelas públicas; **59 com RLS**, **0 com `anon SELECT/INSERT`**; **nenhuma mudança executada nela**.
- Staging manteve **1 usuário Auth, 1 empresa, 0 obras e 0 esquadrias**. Os scripts não criam/excluem linhas.
- Os scripts aplicados foram projetados para **recusar reaplicação** caso a estrutura esperada já tenha mudado.

**Atenção à funcionalidade:** As 11 tabelas que não tinham políticas passaram a negar também acesso ordinário de usuários autenticados até que políticas corretas sejam reconstruídas. É intencional neste estágio de segurança; não usar o projeto como ambiente funcional de homologação antes de recuperar as permissões multiempresa. O Supabase Advisor sinaliza outras tabelas com RLS sem políticas, que também precisam ser avaliadas individualmente.

### Inventário técnico detalhado

O arquivo [`docs/DRIFT_SCHEMA_SUPABASE_V469.md`](DRIFT_SCHEMA_SUPABASE_V469.md) documenta as diferenças reais de catálogo (somente metadados), incluindo **24 tabelas de produção ausentes**, **75 colunas faltantes em tabelas compartilhadas**, **32 colunas com definição divergente**, **54 funções ausentes**, **4 compartilhadas com definição diferente**, **69 políticas RLS faltantes**, **13 triggers e 109 índices ausentes**. A contagem de colunas é abrangente, diferindo do levantamento inicial de 47 colunas restrito a 12 tabelas centrais.

O plano agora é reconstruir **estrutura + constraints + funções + políticas** com dados exclusivamente fictícios; não copiar usuários, empresas reais ou obras de produção. Não aplicar a migração da v46.9 no site ativo antes da homologação efetiva e restauração demonstrada.


## Situação mais recente do ambiente de testes

O staging foi preparado para ensaios reais da precificação, **sem alterar produção**. A situação atual é **40 tabelas públicas com RLS ativo**, zero tabelas com `anon SELECT/INSERT` e zero funções públicas executáveis por `anon`. O gatilho de RLS automático foi instalado e conferido.

A migração **somente de estrutura** `20261122_precificacao_categorias_historico_fase1.sql` foi ensaiada com `ROLLBACK` e aplicada no staging: criou cinco tabelas de histórico, protegidas por RLS e, nas revisões, por triggers de imutabilidade. Foram executados ensaios de leitura ADM vs. almoxarife e tentativas de modificação do histórico com dados fictícios, **todos revertidos**.

**Evidência e limites:** [`docs/HOMOLOGACAO_SUPABASE_FREE_V469.md`](HOMOLOGACAO_SUPABASE_FREE_V469.md).

**Não considerar a v46.9 pronta:** ainda faltam as funções de importação/estoque do legado, a restauração de políticas RLS, um teste completo via Supabase Auth/API e o ensaio de restauração do backup. Os números do inventário de drift são a linha-base anterior à criação das cinco tabelas de preço; a lacuna do legado não foi eliminada. PR #64 permanece draft.
