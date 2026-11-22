# EWGEST v46.15 — Estornos encadeados, parcelas e galpões

**Situação em 22/11/2026:** código e testes concluídos; Supabase de testes e produção receberam quatro migrações aditivas/funcionais com sucesso. Os saldos e contagens anteriores da produção foram preservados (5 obras, 642 movimentos, 2 recebimentos, 319 contrapartidas, 2 auditorias). A publicação do frontend na `main` é etapa separada.

## Regra de negócio

**Disponibilidade é por obra, variação do material, comprimento e unidade.** O galpão é a posição física; mudar de galpão não transfere o material para outra obra.

| Dependência | Tratamento |
|---|---|
| Material mudou de galpão dentro da mesma obra | A entrada original pode ser estornada no(s) galpão(ões) com saldo atual, sem devolução fictícia ao galpão antigo |
| Material saiu de A para B | A reversão atômica retira a quantidade disponível de B e a devolve à obra A; preserva as duas pernas e o motivo |
| Material de B saiu para C | É preciso estornar B→C antes de A→B |
| Material foi usado na fabricação | Bloqueado até estornar a baixa de produção (e cancelar romaneio/saída/liberação que dependam dela) |
| Material está em dois galpões | Repartir a retirada conforme o saldo de cada galpão, com vínculos e auditoria individualizada |
| Recebimento de NF-e | Continua no fluxo específico `ew_estornar_recebimento_nfe`, que já busca saldo em qualquer galpão da mesma obra e não cancela a NF-e fiscal |
| Estorno integral da obra | Permitido no lote somente para entradas positivas independentes, sem NF-e e sem operações dependentes ainda ativas. Cadeias complexas devem ser revertidas antes, individualmente |
| Transferências internas já compensadas e saldo zero | Reconhecer como histórico conciliado, sem criar movimentos inversos artificiais |
| Existência de compra/reposição posterior | Não prova que a quantidade transferida continua disponível. Sem lote individual, consumo posterior não estornado bloqueia conservadoramente |

## Implementação na PR #70

Arquivos versionados:

- `database/proposals/20261122_estornos_parcelas_v4615.sql`: tabela interna `ew_estornos_parcelas` com FK para movimento original e contrapartida, quantidade, galpão e operação; RLS ligada e acesso direto revogado a `anon` e `authenticated`.
- `database/proposals/20261122_estornos_rastreabilidade_v4615.sql`: adapta as RPCs reais de entrada individual e transferência entre obras para devolver quantidades distribuídas em diferentes galpões; locks por obra/material, idempotência, checagem de consumo e transferência posterior e trilha de auditoria.
- `database/proposals/20261122_transferencias_internas_conciliadas_v4615.sql`: identifica transferências internas com pares íntegros quando não resta outro movimento original aberto nem saldo em galpão.
- `database/proposals/20261122_estornos_inspecao_lote_v4615.sql`: adapta as RPCs de inspeção e estorno total; contrapartidas `ESTORNO` não são novas pendências; estorno em lote com transferência/consumo ativo é bloqueado; registro de conciliação não cria estoque.
- `app.html`: no histórico, parcelas extras aparecem como **contrapartidas de estorno**, sem botão para cancelar novamente; transferências internas conciliadas aparecem no histórico completo, não entre pendências.
- **Segurança (revisão adicional):** o estorno de transferência entre obras confere tanto o vínculo de administrador/gerenciador em `usuarios_empresas` quanto o cadastro `usuarios_login` ativo, não excluído e com perfil consistente. O PostgreSQL 17 fictício verifica bloqueio de login inativo, excluído e perfil divergente, sem gerar movimentações.

Todos os passos financeiros, de produção, liberações e romaneios continuam independentes e não são cancelados automaticamente.

## Verificações isoladas

`Homologar estornos v46.15 sem tocar produção` usa PostgreSQL 17 descartável e IDs inteiramente fictícios. Exercita as funções de estorno de estoque reais, incluindo:

1. Transferência entre obras movida para outro galpão antes do estorno;
2. Consumo de produção que impede a devolução, mesmo com reposição de saldo posterior;
3. Transferência A→B→C que deve ser desfeita de trás para a frente;
4. Romaneio/saída com bloqueio ativo;
5. Estorno individual de entrada em galpão diferente do original;
6. Bloqueio de estorno individual enquanto consumo está ativo;
7. Retirada de parcelas em dois galpões, com três contrapartidas ligadas à mesma transferência, saldo correto e retry idempotente;
8. Saldo insuficiente sem criação parcial de lançamentos;
9. Entrada estornada em dois galpões com duas parcelas e proibição de cancelar a própria contrapartida;
10. Conferência da obra com transferências internas históricas conciliadas e nenhum novo estoque;
11. Estorno total simples permitido; transferências, consumo e romaneios ativos bloqueados.

**Limitação dos testes:** o PostgreSQL isolado contém contratos mínimos das tabelas, não uma cópia do Supabase inteiro; a parte de conciliação de NF-e é simulada no teste da inspeção, enquanto a função de NF-e real continua inalterada. As funções SQL compilam e são exercitadas em banco descartável, mas isso ainda não equivale a um teste completo com autenticação Supabase real.

## Verificações de implantação e acompanhamento

- **Corrigido e testado:** transferências internas encadeadas devem ser desfeitas na ordem inversa; compra posterior não autoriza reverter transferência cujo material foi consumido ou remanejado. O estorno não simula retorno físico a galpão diferente.
- **Implementado:** painel apresenta movimentos posteriores com tipo, galpão, data, obra destino (quando disponível) e referência abreviada; o servidor verifica novamente antes de realizar o estorno.
- **Validação em staging:** quatro migrações compiladas, RLS e privilégios verificados; testes isolados do PostgreSQL 17 e da interface aprovados. **Ainda pendente:** teste end-to-end com autenticação HTTP/PostgREST e restauração completa do backup em ambiente isolado.
- **Validado:** novas parcelas têm RLS habilitada e acesso direto negado a `anon` e `authenticated`; RPCs de estorno exigem usuário ativo e privilégios. Advisories preexistentes de outras rotinas permanecem para tratamento separado.
- **Pendente:** homologação manual do fluxo no navegador com obra de treinamento; nunca testar estornos com materiais de obras reais sem conferência.

**Regra inegociável:** atualizar o sistema jamais executa estornos automaticamente; todo estorno requer motivo, permissão e confirmação explícita.

## Implantação do banco de dados — evidências

- Banco staging `ewgest-restauracao-teste`: migrações `v4615_*_stage` aplicadas com sucesso.
- Banco produção `ewgest-producao`: migrações `v4615_estornos_parcelas_prod`, `v4615_estornos_rastreabilidade_prod`, `v4615_estornos_transferencias_conciliadas_prod` e `v4615_estornos_inspecao_lote_prod`, todas aplicadas em 22/11/2026.
- Conferência após migração: 642 lançamentos de estoque, 319 estornos existentes e **zero parcelas novas**, sem operações de estoque executadas por essas migrações.
- Backup diário criptografado do dia 22/11/2026 aprovado no GitHub Actions, com artefato disponível; restauração completa ainda não foi realizada.
- Snapshot do código original de quatro RPCs preservado em `database/rollback/20261122_pre_v4615_functions.sql`. Após uso das novas parcelas, rollback de funções antigas exige análise de compatibilidade de histórico.
- Preview da interface disponibilizada pelo Cloudflare Pages no branch da PR #70; aguardar homologação com obra de treinamento.
