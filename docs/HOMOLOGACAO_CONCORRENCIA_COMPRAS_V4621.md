# Ensaio concorrente v46.21 — roteiro de homologação

Estado: planejado, **não executado**. Nunca executar em produção.

Pré-requisitos: restauração descartável atualizada, seis propostas SQL aplicadas apenas nessa restauração, dois usuários sintéticos com autorização de Compras/Estoque, dois clientes PostgreSQL independentes, e fixture de pedido de 2 BARRA (6000 mm), sem recebimento. Usar a estrutura da fixture de `50_idempotencia_operacoes_rollback.sql`, mas com dados comprometidos em uma base descartável para serem visíveis às duas sessões. Registrar UUIDs da empresa, usuários, pedido, obra e variação; não usar credenciais no repositório.

## Caso 1 — saldo concorrente
1. Sessão A: BEGIN; configurar claims do usuário A; executar ew_compras_receber_pedido com 2 BARRA, galpão válido e UUID de operação A. Não confirmar ainda.
2. Sessão B: BEGIN; configurar claims do usuário B; executar a mesma RPC com 2 BARRA e UUID B. Aguardar a trava (usar statement_timeout de 30 s e registrar SQLSTATE).
3. Sessão A: COMMIT; B deve rejeitar o excesso após adquirir a trava. ROLLBACK B.
4. Verificar pedido CONCLUIDO, apenas um recebimento ativo e saldo físico igual a 2 para a variação e obra sintéticas.

## Caso 2 — reenvio simultâneo
Repetir com pedido novo e o mesmo UUID de operação e conteúdo nas duas sessões, usando o mesmo usuário para simular retry. Após commit A, B deve devolver o mesmo ID com repetida=true; confirmar que existe uma única movimentação física e um recebimento.

## Caso 3 — NF-e e pedido
Preparar nova fixture com nota aprovada, material, unidade e comprimento idênticos. Testar as duas ordens de aquisição de trava (recebimento por pedido primeiro e entrada fiscal legada primeiro). Confirmar a regra de negócio em ambas as ordens: ausência de dupla entrada física; não aceitar como aprovação apenas ausência de deadlock.

## Caso 4 — transferência e estorno
Preparar recebimento empresarial e executar transferência empresa→obra em A sem commit. Em B tentar estornar o recebimento. Após commit A, B deve rejeitar estorno incompatível com a dependência ou saldo. Testar também a ordem inversa. Conferir ambas as pontas, trilha e ausência de saldo negativo.

## Caso 5 — cancelamento e emissão
Em duas sessões, disputar cancelamento de cotação e emissão do pedido. Apenas um resultado comercial incompatível pode ser confirmado. Conferir status, quantidade de pedidos e histórico.

## Evidência e encerramento
Registrar SHA das propostas, IDs de fixtures sintéticas, resultados e SQLSTATEs (sem tokens), saldo final e tempos de espera. Não confundir timeout ou erro de permissão com bloqueio de negócio correto. Repetir ordens inversas em fixtures independentes. Limpar somente pela restauração da base descartável; nunca remover históricos reais. A aprovação exige todos os casos e verificação de que nenhuma operação atingiu produção.
