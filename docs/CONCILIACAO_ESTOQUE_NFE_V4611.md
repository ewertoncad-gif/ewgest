# EWGEST v46.11 — Conciliação de transferências após estorno físico de NF-e

**Situação:** correção SQL aplicada exclusivamente à produção EWGEST em 22/11/2026 após ensaio completo com `BEGIN/ROLLBACK`; nenhum movimento de estoque ou NF-e foi criado, apagado ou alterado pela migração. UI prevista para o site principal.

## Problema identificado

A janela **Estoque → Conferir / estornar** mostrava 4 movimentos de transferências internas (Afogados → Imbiribeira) sem contrapartida formal, embora os recebimentos físicos de duas NF-e já estivessem estornados e o saldo de cada material em cada galpão estivesse zerado. A antiga `ew_estornar_estoque_obra` bloqueava qualquer obra que tivesse **histórico** de recebimento de NF-e, inclusive notas já estornadas. Reverter as quatro pernas seria incorreto porque recriaria saldos negativos/positivos; os estornos físicos já haviam saído do galpão de destino.

## Solução aplicada

O SQL `database/proposals/20261122_conciliacao_transferencias_nfe_v4611.sql` incluiu a função interna `ew_transferencias_nfe_conciliadas(uuid)`, de execução negada a `anon` e `authenticated`, usada exclusivamente pelas duas funções existentes `SECURITY DEFINER` que conferem/estornam o estoque. Nenhum `GRANT` de tabela foi ampliado.

A função reconhece uma transferência **somente se todos os critérios seguintes forem verdadeiros**:

- A obra possui NF-e recebidas, **todas fisicamente estornadas**, com operações e movimentos de estorno individualizados, quantidades exatas e referências compatíveis ao material/obra/empresa;
- **Todos** os saldos por material, comprimento, unidade e galpão são exatamente zero;
- Não existem movimentos de consumo de produção; os únicos movimentos ainda sem estorno são transferências **dentro da mesma obra**;
- Cada transferência tem exatamente duas pernas, quantidades inversas, mesmo material, obra e unidade, em dois galpões distintos.

Com esse cenário, `ew_inspecionar_reversao_obra` devolve `transferencias_nfe_conciliadas` e deixa de considerar aquelas pernas como **pendência de estoque**. A operação `ew_estornar_estoque_obra` não gera novos movimentos: ela registra em `ew_auditoria_operacoes`, mediante usuário autenticado, motivo e identificação da operação, uma **conciliação sem alteração física**; retorna `estornados=0`, `conciliados=N` e `saldos_zerados=true`. A gravação real da conciliação só acontece quando o usuário clicar e confirmar.

Na UI `v46.11`, o botão passa a mostrar **Registrar conciliação (saldo zero)** no cenário específico; os botões de estorno individual ficam bloqueados, os lançamentos exibem **Histórico conciliado pelo estorno da NF-e**, e o texto explicita que não serão criados novos movimentos.

## Verificações

- Ensaio SQL no banco real com ROLLBACK validou a análise de 4 transferências e 0 para obra sem NF. Verificou que a função auxiliar não pode ser chamada por `anon` nem `authenticated`. O ensaio não deixou função instalada.
- Migração aplicada em transação com pré-condições sobre hashes das funções antigas e os registros da obra. Após o COMMIT: **4 transferências históricas conciliáveis, 0 recebimentos ativos e 8 movimentos físicos históricos preservados**.
- Teste automatizado `scripts/test-conciliacao-transferencias-nfe-v4611.mjs`: janela de conciliação, texto de confirmação sem alteração de saldos, persistência de auditoria via RPC, travamento de estorno individual e rejeição caso os registros mudem entre a conferência e a confirmação.
- O código do banco não executa a operação em nome do usuário: a auditoria só será criada pelo clique explícito do ADM/gerenciador autorizado e nunca cancela uma NF-e fiscal na SEFAZ.
- O estorno **financeiro** das NF 123 e 125, se desejado, continua **separado** da reconciliação dos movimentos de estoque. Use **Financeiro das obras → Estornar lançamento**.

**Limites:** esta regra não serve para compras/recebimentos ativos, operações de consumo, movimentos de outras obras, transferências incompletas, saldo diferente de zero ou recebimentos cujo histórico não foi comprovado. Nesses casos os bloqueios originais permanecem. Não use esta correção como autorização para ignorar diferenças de estoque físico.
