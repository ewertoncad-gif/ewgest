# EWGEST — Regras de estorno encadeado e disponibilidade física

**Estado:** regras propostas e em homologação no PostgreSQL 17 fictício. Não confundir esta branch com versão já publicada. **Produção v46.14 não foi alterada por esta proposta.**

## Regra de negócio

O que libera o estorno não é a existência de uma movimentação antiga, e sim a **disponibilidade física atual do item**, com sua obra de origem, variação, unidade e comprimento corretos. Galpão não muda a propriedade da obra.

| Situação | Regra de reversão |
|---|---|
| Entrada/recebimento sem movimentação posterior | Estornar a quantidade disponível; registrar motivo e contrapartida |
| Movido entre galpões da **mesma obra** | Não exigir que esteja no galpão original. Buscar o saldo real na obra |
| Transferido de obra A para obra B | Reverter **atomicamente as duas pontas** apenas após confirmar a disponibilidade em B; devolver o saldo para A |
| B transferiu depois para C | Reverter primeiro a transferência B→C; depois A→B |
| Usado na fabricação | Não devolver; é preciso reverter a baixa de material e liberar o saldo antes |
| Já existe romaneio ativo da esquadria | Cancelar primeiro o romaneio, depois a saída de produção, depois a baixa do material e só então a operação original |
| Quantidade já parcialmente utilizada | Não autorizar estorno integral enquanto houver consumo ainda ativo; estorno parcial requer vínculo explícito de quantidades e lotes |
| NF-e física | A função `ew_estornar_recebimento_nfe` atual já busca materiais disponíveis em qualquer galpão da **mesma obra**, preserva a nota no financeiro e audita os locais de retirada |
| Estorno de todo o estoque da obra | A sequência acima deve ser executada para **cada item dependente**. Não inverter movimentações históricas cegamente; transferências entre obras exigem reversão em ambas as obras |
| Histórico conciliado por NF-e e saldo zero | Conservar como histórico, sem gerar movimentos inversos artificiais nem permitir novo estorno da mesma transferência |
| Saldo positivo da mesma tipologia vindo de outra nota | **Não presumir** que o lote original está disponível: sem rastreamento de lotes, consumo posterior ainda ativo bloqueia a devolução |

## O que a primeira proposta SQL v46.15 efetivamente cobre

- `ew_estornar_movimento_obra`: entrada genérica sem NF com quantidade **inteira disponível em algum galpão** pode ser estornada dali, mesmo que tenha sido registrada em outro local. Bloqueia consumo ou remessa a outra obra não revertidos.
- `ew_estornar_transferencia_entre_obras`: identifica o galpão com estoque inteiro disponível em B e registra a devolução de B para A com duas contrapartidas vinculadas; bloqueia consumo e nova transferência entre obras ainda não revertidos.
- Mantém controle de sessão, perfil, lock transacional, UUID de idempotência e vínculos `estorno_de_id`, sem apagar registros.
- **A proposta ainda não foi aplicada à produção**; validação em PostgreSQL isolado. Não fazer merge antes de cenários aprovados.

## Itens ainda necessários antes da implementação completa

1. **Estorno por parcelas**: quando a mesma quantidade está distribuída por dois ou mais galpões, uma única contrapartida `estorno_de_id` não representa todas as retiradas (restrição `UNIQUE` no banco). É necessário um mecanismo de alocação de parcelas, idempotência e auditoria sem deixar linhas órfãs.
2. **Estorno de toda a obra**: a função atual reverte diretamente movimentações não estornadas; precisa de planejamento explícito das dependências e prova de saldos antes de inserir cada lote de contrapartidas. Não deve neutralizar recebimentos de NF-e já tratados pelo fluxo específico.
3. **Conciliação de transferências internas não ligadas a NF-e**: após estornar entrada em galpão diferente, as pernas antigas de transferência podem continuar no histórico como pendências para arquivar a obra. Precisam ser reconhecidas como compensadas, por critério auditável.
4. **Rastreabilidade de consumo e lotes**: preferir vínculos explícitos de saída/baixa/romaneio para decisões específicas; até que existam, a nova checagem bloqueia conservadoramente material com consumo posterior ativo daquela variação/medida/unidade.
5. **UI**: mostrar a cadeia de bloqueio de cada material, retirar o botão de estorno individual de movimentação histórica conciliada e conferir atualização por obra sem agir nas demais.

**Nenhuma ação de estorno deve ocorrer automaticamente durante atualização do site.**
