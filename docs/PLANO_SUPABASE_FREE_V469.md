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
