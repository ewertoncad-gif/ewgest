# EWGEST v46.17 — Relatórios ampliados e saída direta de material no romaneio

## Funcionalidades

- **Todo o período** selecionado por padrão; ao desmarcar, filtros de datas são aplicados.
- **Faturamento consolidado** por todas as obras ou seleção múltipla (incluindo arquivadas); total de fabricação, instalação, total geral e documentos cancelados separados.
- **Estoque** com seleção combinável de recebimentos, baixas à produção, transferências entre galpões, transferências entre obras, materiais diretos à obra e demais ajustes/estornos. Cada movimentação tem material, galpão, data, usuário e saldo calculado.
- **Liberações** por esquadria/parte/fábrica, incluindo lotes e situação de cancelamento.
- **Expedição** por romaneio com esquadrias completas, marcos, folhas, materiais avulsos e área expedida. Área histórica recuperada quando medidas/quantidade/folhas permitem.
- **m² × alumínio**: indicador COMPARATIVO, ainda não contabilização física de produção. m² expedidos por romaneios ativos; toneladas de barras fisicamente fornecidas à produção (PLANO_CORTE/LOTE) ou enviadas diretamente à obra (SAIDA_OBRA). Transferências entre galpões ou obras NÃO contam. Faltas de peso/área destacadas. Mudanças de peso de catálogo podem mudar estimativas históricas; perdas/sucata e data de conclusão real de fabricação ainda não cadastradas.

## Materiais diretos ao cliente

- Só **ADM e almoxarife** podem adicionar materiais físicos ao romaneio. Emissor escolhe do estoque da própria obra, por variação/cor, tamanho, galpão e quantidade disponível; não digita texto avulso sem vínculo.
- Perfis são baixados como **BARRA** inteira; acessórios são expedidos em unidades inteiras no contrato atual do romaneio. Frações de KG/MT requerem evolução específica do esquema e impressão — não converter silenciosamente.
- A emissão chama a mesma RPC existente `emitir_romaneio_com_saidas` e faz a baixa de material `origem=SAIDA_OBRA` na MESMA transação em que gera romaneio e saídas de esquadrias. Usa bloqueio consultado pelos demais lançamentos do estoque e chave idempotente.
- Cada saída de material é vinculada ao item do romaneio e ao lançamento do estoque na tabela `ew_romaneios_materiais_saidas` (RLS, sem leitura nem escrita direta do cliente). O peso estimado do perfil é registrado em `peso_kg` como snapshot.
- Cancelamento de romaneio exige confirmação de **devolução física** na interface e motivo, registra estorno positivo no estoque, vinculado ao original, e preserva rastreabilidade.
- `ew_estornar_movimento_obra` bloqueia estorno isolado de `SAIDA_OBRA`, exige cancelamento do romaneio e reconhece SAIDA_OBRA como consumo ao impedir estornos de entradas/transferências anteriores.
- Todo lançamento mantém empresa, obra, variação, comprimento, unidade, galpão, usuário, data e motivo.

## Staging e segurança

Banco isolado: `ewgest-restauracao-teste`. Migrações aplicadas:
- `v4617_material_saida_romaneio_stage`
- `v4617_bloquear_estorno_direto_stage`

Homologação em transação revertida: usuário ADM fictício, perfil e acessório fictícios, saldo insuficiente, duas linhas consumindo saldo acima da disponibilidade, idempotência, cancelamento/estorno, auditoria de vínculos, proibição de estorno direto e supervisor sem permissão. Resultado PASSOU, nenhum dado de fixture persistido. Novos vínculos sob RLS com `anon` e `authenticated` sem leitura direta; RPC sem execução pública/anon.

## Deploy

Arquivos SQL em `database/proposals/20261122_materiais_diretos_romaneio_v4617.sql` e `database/proposals/20261122_material_direto_bloquear_estorno_v4617.sql`. Antes da aplicação, snapshots das três RPCs originais em `database/rollback/20261122_pre_v4617_romaneio_rpc.sql` e `database/rollback/20261122_pre_v4617_estorno_individual.sql`.

**Pendente homologação manual**: navegador com conta ADM e almoxarife, obra de treinamento, material com saldo, expedição mista com esquadria + perfil/acessório, impressão, cancelamento com devolução física e relatórios; não testar com material de obras reais. Não reutilizar snapshot antigo após novos materiais emitidos sem análise de integridade dos vínculos.

## Estoque central da empresa

Não faz parte da v46.17. `docs/ESTOQUE_CENTRAL_PROPOSTA.md` continua a proposta oficial para estoque geral Afogados/Imbiribeira, separado das obras.
