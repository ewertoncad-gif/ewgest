# EWGEST v46.21 — Compras e locais de estoque

**Issue:** #77 · **Status:** em desenvolvimento, aguardando revisão e homologação.  
**Branch:** `feature/compras-locais-estoque-v4621`.  
**Produção:** nenhuma migração aplicada; não integrar/publicar antes da conciliação fiscal e dos estornos.

## Definições operacionais

- **Local de estoque**: titular dos materiais. Pode ser uma obra verdadeira ou um local próprio da empresa sem vínculo com obra.
- **Galpão**: posição física onde o material permanece. Afogados/Imbiribeira são galpões, não obras.
- **Necessidade**: quantidade planejada pelo CEM, apenas para obras, e diferente de saldo físico.
- **Saldo físico**: entradas menos saídas; nunca criado pela importação de um orçamento ou pedido não recebido.
- **Solicitação**: demanda por itens, sem compras ou saldo lançados.
- **Cotação**: oferta de um fornecedor com valores por item; várias cotações por solicitação são possíveis.
- **Pedido**: cotação escolhida, com quantidades e preços congelados.
- **Recebimento**: operação imutável de quantidades realmente recebidas, com galpão, autor, data e ID idempotente.

## Arquitetura proposta

Para **obra**, a entrada de pedido usa a tabela já existente `ew_estoque_obras_movimentos`, com origem `COMPRA`. Para **empresa sem obra**, usa `ew_compras_locais_empresa` e o ledger novo `ew_compras_estoque_empresa`. Não inventar obras de estoque.

Aprovação de NF-e, lançamento de despesa, faturamento e recebimento físico são operações distintas: **um pedido recebido NÃO deve abrir outra entrada física quando o documento fiscal for lançado**. Por isso a integração financeira/nota fiscal ainda precisa de regra e tela de vinculação "nota referente a recebimento de pedido". A migração atual registra **somente a entrada física** do pedido, nunca o valor da despesa fiscal.

## Etapas de uso

1. **Compras → Solicitação**: escolher local de estoque, itens/cor/comprimento/unidade/quantidade, gravar solicitação.
2. **Compras → Cotação**: escolher solicitação e fornecedor, preencher preço de cada item, comparar fornecedores.
3. **Compras → Pedido**: selecionar cotação e emitir pedido com identificação e destino.
4. **Recebimento**: escolher a obra (ou local da empresa), selecionar pedido, marcar linhas, conferir quantidade total/recebida/pendente, informar quantidade que chegou e galpão.
5. **Estoque**: selecionar local; para obra mantém indicadores de necessidade CEM, para empresa exibe apenas saldos por material e galpão.

## Permissões propostas

O SQL adiciona `compras.consultar`, `compras.solicitar`, `compras.cotar`, `compras.pedir`, `compras.receber`, `estoque.gerenciar_locais`. A matriz inicial é: níveis 01/02 todos; 03 consultar/solicitar; 04 consultar/receber; 05 consultar/cotar/pedir; 06/07 consultar; 08 sem acesso. Todas editáveis pelo ADM. Recebimento também exige `estoque.receber`.

## Proteção e testes

- As escritas de compras são feitas por RPC no banco, com verificação da empresa e flags.
- Tabelas novas têm RLS somente de leitura e nenhuma escrita direta para `authenticated`.
- O número do pedido não altera o saldo; apenas confirmar o recebimento movimenta material.
- A conferência soma recebimentos anteriores e rejeita quantidades acima do saldo pendente, duplicações por chave e quantidades não inteiras para barras.
- Uma tentativa repetida com o mesmo ID de operação devolve o registro original sem nova movimentação.
- Material é sempre vinculado a uma variação do catálogo da empresa.

### Validação inicial efetuada

- Verificação sintática do JavaScript novo na branch.
- Conferência dos IDs do novo módulo com o HTML principal.
- Migração SQL compilada no ambiente `ewgest-restauracao-teste` dentro de transação encerrada com **ROLLBACK**, sem persistir mudanças.

### Pendências antes da publicação

1. **Estorno de recebimento**: registrar o vínculo de cada recebimento com seus movimentos; permitir estorno apenas se o saldo ainda existe e depois das devoluções necessárias, respeitando transferências, consumo, romaneios e auditoria. O script ainda não implementa essa reversão.
2. **Conciliação com NF-e/Financeiro**: vínculo explícito entre nota, pedido e recebimento para evitar duplicar estoque ou despesas. O script ainda não bloqueia um segundo recebimento via fluxo fiscal existente.
3. **Transferência entre estoque da empresa e obras**: o novo saldo da empresa ainda não integra as operações de transferência atuais.
4. **Homologação funcional end-to-end** com usuários reais de teste e permissões em ambos os tipos de destino, unidades e galpões; testes de corrida (dois recebimentos simultâneos), erro e retry.
5. **Regressões** de obras, estoque, recebimento fiscal, materiais, romaneios e relatórios; teste visual mobile/desktop.
6. Avaliar fornecedores inativos com pedidos antigos, cancelamento de solicitações/cotações/pedidos não recebidos e identidade do responsável por cada aprovação.

**Decisão de segurança:** manter este PR fora de `main` até essas pendências serem resolvidas; não aplicar em produção uma estrutura de estoque que ainda não consegue conciliar e estornar corretamente.
