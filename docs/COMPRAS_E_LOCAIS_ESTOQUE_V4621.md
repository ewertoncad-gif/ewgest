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

## Estoques anteriormente cadastrados como obras

Nas capturas de 23/11, o cadastro **ESTOQUE GVG** aparece como obra, com material FIT2130PTO e saldo físico (exemplo mostrado: 4 MT). **Não excluir nem converter automaticamente essa obra artificial.** Ela pode conter movimentos, despesas, transferências e estornos já referenciados por UUID.

Antes de migrar, é necessário: identificar o ID real e todos os movimentos por material, unidade, galpão, operação, despesa e transferência; conciliar saldo físico e vínculos; registrar uma conversão auditável para o novo local `Empresa · ESTOQUE GVG`; fazer a transferência de responsabilidade sem duplicar estoque ou receita; revisar os relatórios; só então retirar o cadastro artificial da seleção de obras.

A interface nova diferencia `Empresa · ...` de `Obra · ...`, mas **não migra os saldos antigos automaticamente** nesta fase.

## Arquitetura proposta

Para **obra**, a entrada de pedido usa a tabela já existente `ew_estoque_obras_movimentos`, com origem `COMPRA`. Para **empresa sem obra**, usa `ew_compras_locais_empresa` e o ledger novo `ew_compras_estoque_empresa`. Não inventar obras de estoque.

Aprovação de NF-e, lançamento de despesa, faturamento e recebimento físico são operações distintas: **um pedido recebido NÃO deve abrir outra entrada física quando o documento fiscal for lançado**. Por isso a integração financeira/nota fiscal ainda precisa de regra e tela de vinculação "nota referente a recebimento de pedido". A migração atual registra **somente a entrada física** do pedido, nunca o valor da despesa fiscal.

## Etapas de uso

1. **Compras → Solicitação**: escolher local de estoque, itens/cor/comprimento/unidade/quantidade, gravar solicitação.
2. **Compras → Cotação**: escolher solicitação e fornecedor, preencher preço de cada item, comparar fornecedores.
3. **Compras → Pedido**: selecionar cotação e emitir pedido com identificação e destino.
4. **Recebimento**: escolher a obra (ou local da empresa), selecionar pedido, marcar linhas, conferir quantidade total/recebida/pendente, informar quantidade que chegou e galpão.
5. **Estoque**: selecionar local; para obra mantém indicadores de necessidade CEM, para empresa exibe apenas saldos por material e galpão.

## Estornos, transferências e histórico — implementados na branch

- O recebimento vincula cada linha do pedido ao movimento físico criado, por UUID, em `ew_compras_recebimentos_movimentos`.
- O estorno preserva a operação original e cria um movimento inverso, atualizando a quantidade recebida e reabrindo o saldo do pedido.
- Se houver consumo ou transferência posterior **ainda não revertida**, o estorno é bloqueado; primeiro desfaça as dependências. Uma transferência efetivamente estornada deixa de bloquear o estorno do recebimento original.
- Entre local próprio da empresa e obra, a transferência registra as duas pontas de forma atômica; o estorno também exige saldo e dependências válidos no destino.
- A transferência **obra → obra** continua no fluxo legado, sem usar a nova rotina, para preservar os romaneios existentes.
- A transferência **empresa ↔ obra** não deve ser interpretada pelo gatilho de romaneios entre obras. A emissão de documento próprio para esse deslocamento ainda precisa ser validada.
- O painel de estoque e de recebimento exibe os locais próprios da empresa sem os transformar em obras.
- O filtro preserva a seleção de local da empresa mesmo ao atualizar o estoque.

## Permissões propostas

O SQL adiciona `compras.consultar`, `compras.solicitar`, `compras.cotar`, `compras.pedir`, `compras.receber`, `estoque.gerenciar_locais`. A matriz inicial é: níveis 01/02 todos; 03 consultar/solicitar; 04 consultar/receber; 05 consultar/cotar/pedir; 06/07 consultar; 08 sem acesso. Todas editáveis pelo ADM. Recebimento também exige `estoque.receber`. A nova flag `compras.consultar_valores` é liberada por padrão aos níveis 01, 02 e 05. Os níveis 04, 06 e 07 podem consultar a parte operacional do pedido, sem receber valores unitários ou totais; cotações e leitura direta de pedidos com valores são protegidas por RLS. A leitura operacional é feita por RPC que remove campos de preço.

## Proteção e testes

- As escritas de compras são feitas por RPC no banco, com verificação da empresa e flags.
- Tabelas novas têm RLS somente de leitura e nenhuma escrita direta para `authenticated`.
- O número do pedido não altera o saldo; apenas confirmar o recebimento movimenta material.
- A conferência soma recebimentos anteriores e rejeita quantidades acima do saldo pendente, duplicações por chave e quantidades não inteiras para barras.
- Uma tentativa repetida com o mesmo ID de operação devolve o registro original sem nova movimentação.
- Material é sempre vinculado a uma variação do catálogo da empresa.

### Validação efetuada em 24/11/2026

- JavaScript do novo módulo analisado sintaticamente; referências da interface conferidas no HTML.
- Foram executados **em `ewgest-restauracao-teste`**, na mesma transação encerrada por `ROLLBACK`, a proposta de base, o estorno, as transferências e o cenário sintético `tests/compras_v4621/10_fluxo_pedidos_transferencias_rollback.sql`.
- O cenário passou por: solicitação, cotação, pedido, recebimento parcial de 2/4, tentativa de excesso (bloqueada), repetição idempotente do mesmo recebimento, transferência empresa → obra, estorno de recebimento com dependência (bloqueado), estorno da transferência, estorno do recebimento, saldos zerados nas duas pontas, recebimento/estorno direto em obra e preços ocultos para o nível de almoxarifado.
- Verificado após o ensaio que as tabelas novas não persistiram e que a restauração de testes continuou sem obras, movimentos e fornecedores adicionais.
- No ensaio foi necessária uma harmonização temporária, com `ROLLBACK`, da coluna `criado_por` do cadastro de fornecedores, pois a restauração está defasada em relação à produção.

### Limitações dos testes

- Testes de transação executados em ambiente isolado com dados sintéticos. **Não** equivalem à homologação visual nem à verificação de fluxos de notas fiscais reais.
- Não foi feita execução de compra, recebimento, estorno ou transferência na produção.

### Validação inicial efetuada

- Verificação sintática do JavaScript novo na branch.
- Conferência dos IDs do novo módulo com o HTML principal.
- Migração SQL compilada no ambiente `ewgest-restauracao-teste` dentro de transação encerrada com **ROLLBACK**, sem persistir mudanças.

### Pendências antes da publicação

1. **Conciliação NF-e/Financeiro — impeditivo de publicação**: adicionar vínculo entre nota, pedido e recebimento já feito, permitindo registrar/associar custo fiscal sem criar novamente o saldo físico. O SQL atual não bloqueia um segundo recebimento pelo fluxo fiscal legado.
2. **Transferências e romaneios**: revisar documento de deslocamento entre obra e estoque próprio da empresa, sem acionar incorretamente o gatilho de transferência obra → obra. Validar impacto de estornos de obras e exclusões sobre compras ligadas.
3. **Homologação completa**: executar no ambiente de testes as operações com concorrência real (dois recebimentos simultâneos), casos de falha/retry, itens com unidades distintas, galpões distintos e permissões 03/04/05/06/07/08.
4. **Regressões e interface**: testar na navegação desktop e celular, consumo da produção, entrada manual NF-e, relatório financeiro, romaneios, transferências e relatórios.
5. **Migração do ESTOQUE GVG**: auditar e converter saldo histórico sem duplicar entradas ou apagar a obra artificial antes da conciliação.
6. **Operação comercial**: avaliar fornecedor inativo, cancelamentos de solicitação/cotação/pedido sem saldo recebido e políticas de aprovação do pedido.

**Decisão de segurança:** manter este PR fora de `main` até essas pendências serem resolvidas; não aplicar em produção uma estrutura de estoque que ainda não consegue conciliar e estornar corretamente.
