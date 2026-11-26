# Homologação de custos por lote — bloqueio de publicação

## Estado em 26/11/2026

- Produção e ambiente de restauração comparados: 92 e 52 tabelas base respectivamente nos schemas public e ew_compras_interna. A restauração não contém 40 tabelas da produção.
- A criação de branch de banco exige confirmação de custo; nenhuma branch de banco foi criada.
- O piloto das RPCs cobre primeira transferência inequívoca entre obras, estoque próprio e insumos, além de seus estornos.
- As definições foram verificadas no schema real em transação revertida. Isso não equivale a executar as operações com usuários reais.
- A lógica de autorização foi reproduzida com tabelas temporárias e JWTs sintéticos: 376 combinações nível/flag, oito níveis, empresa incorreta, sessão inválida, usuário inativo e anônimo. Nenhuma configuração real foi alterada.
- A prévia estrita não resolve transferências sucessivas, movimentação de galpão, consumo ou cancelamento fiscal de lotes rastreados. Não instalar o piloto em produção.

## Ordem da instalação experimental em ambiente atualizado e isolado
1. 20261126_lotes_aquisicao_evidencias.sql
2. 20261126_transferencias_fisicas_custo.sql
3. 20261126_previa_apropriacao_transferencias.sql
4. 20261126_motor_lotes_custo.sql
5. 20261126_ponte_lotes_transferencias.sql
6. 20261126_piloto_rpc_custo_entre_obras.sql
7. 20261126_piloto_rpc_custo_locais_insumos.sql
8. 20261126_piloto_financeiro_lotes.sql

Não aplicar as propostas antigas de razão paralelamente ao novo motor.

## Critérios de aprovação obrigatórios antes de publicação

- Ambiente de homologação com mesmas tabelas, funções, triggers, constraints, RLS e grants que a produção de referência, sem copiar dados pessoais.
- Aquisição física e fiscal, conversões de unidade, recebimentos parciais, notas conciliadas e independentes.
- Transferências sucessivas entre obras, estoque próprio e galpões, incluindo misturas de lotes e concorrência.
- Produção sem duplicação de despesa, estorno parcial e integral em ordem correta, bloqueio de cancelamento/desvinculação fiscal com dependências.
- Reconciliar estoque físico e fragmentos de custo antes e depois de cada operação, manter custo desconhecido pendente.
- Testes reais de RPC com JWTs de oito níveis e dois tenants, mudanças de flags, sessão revogada e tentativas de acesso aos objetos privados.
- Regressões de frontend, testes financeiros, CI e teste no navegador.
- Não remover sinalização de pendência enquanto houver divergência.
- Somente após todos os critérios: migração revisada, backup validado, publicação e verificação do domínio.

