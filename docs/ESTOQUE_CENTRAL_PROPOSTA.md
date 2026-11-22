# EWGEST — Estoque geral da empresa (proposta para próxima etapa)

**Escopo:** estoque central da própria empresa, separado do estoque de cada obra. Proposta técnica, NÃO instalada em produção na v46.16. Documento de decisões para próxima implementação.

## Regra de titularidade e localização

- **Dono do saldo:** empresa GVG, ou uma obra específica.
- **Localização física:** galpão AFOGADOS ou IMBIRIBEIRA cadastrado; o galpão não define o proprietário.
- Dois estoques centrais distintos por galpão compartilham o mesmo banco de materiais, sem ser cadastrados como obras fictícias.
- Material pode ser cadastrado manualmente no banco de materiais, sem importação técnica do CEM.
- Entrada manual de saldo inicial deve exigir motivo, usuário, data, quantidade, unidade, variante/cor, comprimento, galpão e autorização ADM. Entrada por NF-e deve continuar distinguível de abertura manual, sem gerar receita fictícia.

## Fluxos físicos que devem existir

1. Recebimento/abertura física no estoque central da empresa (galpão escolhido) → saldo central aumenta.
2. Remanejamento AFOGADOS ↔ IMBIRIBEIRA dentro do estoque central → muda galpão, não o proprietário.
3. Atendimento a obra A: transferência central → obra A, indicando galpão real de saída e galpão destino. Transação atômica debita o estoque central e credita o estoque da obra.
4. Atendimento a obra B: repetição independente, sem misturar quantidade ou custo com a obra A.
5. Devolução de sobra: obra → estoque central em transação atômica, somente se houver saldo disponível e nenhuma baixa/dependência ativa.
6. Estorno de recebimento/transferência em ordem inversa às dependências, preservando todas as pernas e quem efetuou cada operação.

## Controle e auditoria

- Não permitir saldos negativos nem estornos quando houver consumo ou transferência posterior não revertidos.
- Barras/peças/metros respeitam a unidade cadastrada e suas regras de quantidade. Não confundir quantidade prevista com saldo físico.
- Código, descrição, cor, comprimento e unidade vêm do catálogo único de materiais, sem duplicação por galpão.
- Incluir o estoque central nos relatórios de movimentações, com filtro por proprietário do saldo (empresa/obra), galpão, pessoa e tipo de operação.
- Relatórios financeiros devem distinguir **compra**, **movimentação interna** e **custo efetivamente apropriado à obra**. Transferência interna não deve gerar faturamento ao cliente automaticamente.
- Romaneio de transferência é comprovante documental da movimentação já executada, e nunca duplica a baixa.
- Permissões de abertura e estorno por ADM, e operação do almoxarife conforme papel definido com trilha de auditoria e motivo.

## Arquitetura a implementar

- Usar uma estrutura de saldos por proprietário (empresa/obra), material/variação, comprimento, unidade e galpão.
- Preferir razão imutável de movimentações e operações idempotentes por UUID; saldo calculado ou materializado com proteção transacional.
- Não inserir estoques gerais como linhas da tabela `obras` apenas para contornar as regras existentes.
- Verificar se `ew_estoque_movimentacoes` (histórico global já presente) pode ser reaproveitada com segurança, pois no esquema atual não guarda galpão. Não alterar nem migrar seus registros sem plano de compatibilidade.
- Homologar em Supabase de testes com recebimento, saída para 2 obras, transferências entre galpões, baixas de corte, romaneios, devoluções, estornos e relatórios antes de publicar.

**Não faz parte da v46.16:** criação real de saldo central, transferência central↔obra e nova lógica de rateio financeiro. Nenhum estoque central será criado por atualizar a interface de relatórios.
