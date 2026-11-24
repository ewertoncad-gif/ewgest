# EWGEST v46.21 — Compras e locais de estoque

**Issue:** #77 · **Status:** em desenvolvimento, aguardando revisão e homologação.  
**Branch:** `feature/compras-locais-estoque-v4621`.  
**Produção:** nenhuma migração aplicada; não publicar antes dos testes visuais, regressão dos fluxos legados, conferência de permissões/concorrência e revisão dos documentos de transporte.

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

Aprovação de NF-e, lançamento de despesa, faturamento e recebimento físico são operações distintas: **um pedido recebido NÃO deve abrir outra entrada física quando o documento fiscal for lançado**.

- **Pedidos para obras:** o Financeiro registra/aprova a nota (despesa da obra) sem movimentar novamente o estoque; em Compras → Pedido, o usuário financeiro vincula os itens da nota aos recebimentos já feitos. A vinculação conserva quantidades, unidades e valores originais, não cria movimento físico. Há controle de fornecedor/material/obra, quantidade na nota, vínculo único ativo por recebimento e bloqueio do recebimento fiscal antigo quando existe mercadoria correspondente pendente de conciliação.
- **Estoque próprio da empresa:** a nota do pedido é registrada no novo livro fiscal `ew_compras_notas_empresa`, por local empresarial, fornecedor e pedido, incluindo subtotais por linha. Não usa `ew_obra_despesas`, não cria obra fictícia e não movimenta o saldo físico. A soma por nota e a unicidade por fornecedor/documento são conferidas.
- Desvinculação/cancelamento fiscal com motivo preserva histórico. Antes de estornar o recebimento físico, a nota correspondente precisa ser desvinculada (obra) ou cancelada (empresa).
- O financeiro **das obras** permanece separado dos custos do estoque empresarial; será necessário integrar o novo livro fiscal aos relatórios consolidados da empresa antes do aceite final.

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

### Testes adicionais de 24/11/2026

Com as cinco propostas de banco v46.21 carregadas na mesma transação sintética, executadas **isoladamente** e seguidas por `ROLLBACK`, passaram:

- `tests/compras_v4621/20_conciliacao_nfe_rollback.sql`: dois recebimentos vinculados a uma nota aprovada, terceira entrega ainda sem nota, sem nova entrada no estoque; fornecedor/material, idempotência, bloqueio de reentrada fiscal, cancelamento de nota e estorno condicionados à desvinculação.
- `tests/compras_v4621/30_nota_estoque_empresa_rollback.sql`: nota de 2 recebimentos parciais de estoque próprio, custos por linha e total exato, sem segundo estoque, bloqueio de nota duplicada, cancelamento financeiro e estorno posterior.
- `tests/compras_v4621/40_migracao_estoque_legado_rollback.sql`: saldo sintético de 4 MT vindo de uma transferência entre obras, conversão de titularidade para local empresarial, conservação do saldo total e dos movimentos históricos e estorno da nova transferência.
- O ensaio de regressão de operações básicas da versão 46.21 (`10_fluxo_pedidos_transferencias_rollback.sql`) continua aprovado.
- O GitHub Actions verifica a sintaxe e os contratos da interface e das funções SQL; isso não substitui os testes de navegador.

### Limitações dos testes

- Testes de transação executados em ambiente isolado com dados sintéticos. **Não** equivalem à homologação visual nem à verificação de fluxos de notas fiscais reais.
- Não foi feita execução de compra, recebimento, estorno ou transferência na produção.

### Validação inicial efetuada

- Verificação sintática do JavaScript novo na branch.
- Conferência dos IDs do novo módulo com o HTML principal.
- Migração SQL compilada no ambiente `ewgest-restauracao-teste` dentro de transação encerrada com **ROLLBACK**, sem persistir mudanças.

### Pendências antes da publicação

1. **Publicação / migrações**: revisar as cinco propostas SQL, backups, dependências e políticas RLS; homologar em base isolada atualizada. As migrações não foram aplicadas em produção e a `main` não foi alterada.
2. **Transferências / documentos**: revisar documentação do deslocamento empresa ↔ obra, sem disparar romaneios de transferência entre obras de forma incorreta; testar estorno de obra e relatórios com compras vinculadas.
3. **Concorrência e permissões**: testes com requisições simultâneas reais, falha de rede/retry, unidades MT/KG/PC/BARRA, galpões distintos, fornecedores inativos e perfis 03/04/05/06/07/08; verificar idempotência em cada RPC.
4. **Regressões / navegador**: homologar visualmente em desktop/mobile, itens NF-e XML e notas manuais, consumo de produção, notas empresariais e relatórios financeiros. Conferir envio de número, valores, vínculos de nota e estornos pela interface.
5. **Relatórios e centros de custo**: incluir o livro `ew_compras_notas_empresa` nos relatórios de despesas **empresariais**, sem duplicar custos financeiros de obra. Definir centro de custo empresarial para notas globais.
6. **Migração do ESTOQUE GVG**: execução em produção ainda depende de autorização específica, backup e conferência do roteiro `docs/MIGRACAO_ESTOQUE_GVG_V4621.md`; o ensaio sintético de 4 MT foi validado, sem transferência real.
7. **Operação comercial**: avaliar cancelamento de solicitação/cotação/pedido que ainda não gerou entrada física e política de aprovação de pedidos.

**Decisão de segurança:** manter o PR #78 em **draft**, sem merge ou deploy até finalizar as pendências de documentação fiscal, relatórios, regressões de navegador e homologação. Os novos estornos e vínculos fiscais estão implementados e testados com dados sintéticos; a publicação exige validação operacional adicional.
