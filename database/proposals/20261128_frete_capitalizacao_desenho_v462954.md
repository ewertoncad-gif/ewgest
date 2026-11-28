# Frete incorporável ao custo de aquisição — desenho técnico

## Diagnóstico verificado no banco
- `ew_compras_interna.custo_abrir_lote` exige correspondência exata de custo com a evidência fiscal original; atualizar `custo_lotes.custo_centavos` rompe essa identidade.
- `ew_compras_interna.custo_mover_fragmento` usa a diferença de arredondamentos acumulados sobre os intervalos de quantidade do lote para calcular centavos de cada evento.
- Transferências e consumos geram eventos e fragmentos. Alterar apenas o lote também deixa eventos já gravados com valores incompatíveis.

## Próxima migração proposta (não implementada)
1. Criar camada de complementos de aquisição, identificada por empresa, vínculo ativo de frete, lote fiscal e operação. Preservar o custo fiscal original. Uma apropriação ativa por título; estorno com justificativa e histórico.
2. Validar no servidor a prévia fiscal da versão 53, a identidade do título separado e a inexistência de outra apropriação do mesmo frete. A confirmação deve recalcular sob locks compatíveis com os fluxos de estoque e rejeitar qualquer mudança na prévia.
3. Primeira etapa restrita a lotes sem eventos de transferência/consumo (inclusive estornados): validar fragmento original e saldo integral. Não liberar para lotes movimentados até existir mecanismo de ajuste compensatório testado.
4. Propagar a camada adicional pelos intervalos de quantidade e registrar componente de frete por evento em separado, com arredondamento acumulado; garantir soma exata, estorno, e separação de custo fiscal e custo gerencial.
5. Reconhecer o componente apenas uma vez na DRE: excluir da despesa direta o valor capitalizado por meio de classificação/controle específico, reconhecer custo quando consumido; preservar o título financeiro e suas baixas. Não criar conta adicional.
6. Bloquear estorno do vínculo ou da nota enquanto houver complemento ativo ou consumo sem estorno/ajuste autorizado. Testar concorrência, reexecução, transferência em cadeia, estorno e isolamento entre empresas.

## Critério de publicação
Nenhum complemento real deve ser gravado enquanto a cadeia de eventos e DRE não estiver coberta por testes integrados. A conferência fiscal continua consultiva. O fechamento mensal da versão 54 também é consultivo: não representa bloqueio contábil nem comprova por si só a conciliação de folha e títulos.
