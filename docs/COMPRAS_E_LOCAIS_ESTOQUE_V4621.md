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

### Relatórios, comprovantes e proteção de repetição — 24/11/2026

- **Relatórios → Custos do estoque da empresa**: novo relatório financeiro, separado do faturamento e das despesas das obras. Consulta `ew_compras_notas_empresa` apenas, com filtros de local de estoque, fornecedor e período; permite mostrar notas canceladas sem incluí-las nos totais ativos. Exportação CSV e impressão reutilizam os controles existentes.
- Visibilidade do relatório restrita à combinação de flags `relatorios.financeiros`, `financeiro.consultar` e `compras.consultar_valores`. Os registros permanecem protegidos pelas políticas RLS do livro fiscal.
- **Estoque → Transferir entre locais → Imprimir espelho**: duas vias com origem, destino, galpões, material, quantidade, data, status e identificador histórico. É um documento interno de consulta, **não gera nova movimentação**, não substitui NF-e ou documentos legais de transporte.
- O recebimento por pedido agora **bloqueia a linha do pedido antes da checagem de operação repetida**, garantindo serialização por pedido. O gatilho de NF-e usa a mesma trava transacional por material/obra/unidade para evitar duas entradas físicas simultâneas originadas por fluxos diferentes.
- Solicitações e cotações usam uma trava por identificador de operação, após autorização. O reenvio de solicitações, cotações, pedidos e recebimentos confere também empresa, pedido e dados associados, evitando reutilização de IDs com novos valores.
- Novo teste `scripts/test-relatorios-custos-empresa-v4621.mjs` usa dados sintéticos para verificar totais em centavos, documentos cancelados, filtros, empresa isolada e bloqueio de permissão, executado pelo GitHub Actions.
- `scripts/test-compras-v4621.mjs` valida a impressão interna, as duas vias e a sanitização de texto HTML.
- `tests/compras_v4621/50_idempotencia_operacoes_rollback.sql` foi executado em `ewgest-restauracao-teste` com `ROLLBACK`: reenvio idêntico aceito, alteração de valores/quantidades com mesmo ID rejeitada, nenhum saldo duplicado e apenas um registro por operação.
- As quatro baterias anteriores de SQL (10/20/30/40) foram novamente executadas na restauração de testes, aprovadas e revertidas integralmente.

**Ainda pendente:** ensaio com **duas sessões reais simultâneas** em uma base de homologação preparada para esse fim. Os bloqueios de concorrência foram implementados e os casos sequenciais testados, mas não se deve declarar corrida simultânea homologada sem o ensaio específico.

### Cancelamentos comerciais auditáveis — 24/11/2026

Implementados na branch, **não publicados**:

- **Solicitação**: o perfil com `compras.solicitar` pode cancelar uma solicitação `ABERTA` com motivo de 5 a 400 caracteres. Se existirem cotações abertas sem pedido, elas passam a `CANCELADA` na mesma transação. Nenhuma linha é excluída.
- **Cotação**: o perfil com `compras.cotar` pode cancelar apenas uma cotação de solicitação ainda aberta e sem pedido gerado. A cotação cancelada é removida das opções de emissão de pedido, inclusive por validação no banco.
- **Pedido**: o perfil com `compras.pedir` pode cancelar diretamente apenas um pedido `ABERTO` que **nunca tenha gerado recebimento**, mesmo que o recebimento anterior tenha sido estornado. Pedidos com histórico físico ou fiscal exigem revisão do fluxo, e não podem ser apagados ou cancelados diretamente.
- Todos os cancelamentos guardam data, usuário, justificativa e identificador idempotente. Repetição idêntica devolve a operação original; IDs reaproveitados para outra alteração são rejeitados.
- O cancelamento de um pedido **não reabre a solicitação original para novo pedido**. A solicitação continua `PEDIDO_GERADO` para evitar duplicidade comercial; para fazer uma nova compra, gera-se outra solicitação.
- O módulo Compras exibe botões de cancelamento apenas quando o estado e a permissão autorizam. Data e motivo permanecem visíveis na linha do histórico.
- `tests/compras_v4621/60_cancelamentos_comerciais_rollback.sql` confirmou os três cancelamentos, impossibilidade de emissão com cotação cancelada, bloqueio de pedido com recebimento e conservação do saldo físico.
- `tests/compras_v4621/70_permissoes_cancelamento_rollback.sql` validou os níveis 03 (solicitação), 04 (almoxarife sem cancelamento), 05 (cotação/pedido), 06, 07 e 08 (sem cancelamento).
- As **seis propostas SQL** e os **sete cenários SQL** de Compras foram executados em `ewgest-restauracao-teste` dentro de transações `BEGIN/ROLLBACK`; não houve aplicação no banco de produção.
- A ordem de bloqueios no cancelamento de cotação foi padronizada (primeiro solicitação, depois cotação), reduzindo risco de deadlock com cancelamento da solicitação.

### Regressão crítica de estornos e unidades — 24/11/2026

Foram encontrados, corrigidos e testados dois problemas da proposta v46.21 **antes de sua publicação**:

1. **Bloqueio indevido de estornos encadeados**: o estorno do recebimento 2 gerava uma movimentação negativa `ESTORNO` que era interpretada como saída de consumo no estorno do recebimento 1. Da mesma forma, duas transferências de empresa para a mesma obra, estornadas de trás para frente, podiam ficar bloqueadas por outro `ESTORNO`. A checagem de dependências agora **ignora apenas movimentos de estorno efetivos** (`ESTORNO`, `ESTORNO_PEDIDO`, `ESTORNO_TRANSFERENCIA`); continua bloqueando saídas não revertidas e valida saldo físico do mesmo local/galpão/unidade.
2. **Ordem de travas no estorno fiscal**: `ew_compras_vincular_nfe_pedido` bloqueava pedido → recebimento, mas `ew_compras_estornar_recebimento` bloqueava no sentido inverso. O estorno agora lê preliminarmente o recebimento, trava **pedido → recebimento**, relê e valida o estado sob bloqueio, reduzindo o risco de deadlock entre essas operações. Não foi executada corrida real de sessões; este ajuste é preventivo e tem teste sequencial.
3. **Unidades de compra**: a versão existente do EWGEST possui o trigger `ew_validar_mt_movimento_material`, que **exige MT inteiros** nas movimentações de material, inclusive transferências e fornecimento à produção. A proposta de MT fracionário foi descartada ao ser detectada a incompatibilidade. Permanecem inteiros `MT`, `BARRA`, `PC`, `PR`, `CJ` e `UN`. A unidade **KG** admite até três casas decimais no banco e nos formulários, com validação de precisão e rejeição da quarta casa.

**Novos cenários de teste**:

- `tests/compras_v4621/80_estorno_ordenado_nfe_rollback.sql`: pedido com dois recebimentos, um conciliado com NF e outro sem nota; estorno do vinculado bloqueado; estorno do outro permitido e idempotente; desfazimento da conciliação libera estorno do primeiro; saldos e histórico preservados.
- `tests/compras_v4621/90_estorno_transferencias_sucessivas_rollback.sql`: duas transferências independentes do estoque empresarial para a mesma obra, reversão em ordem inversa, estorno da entrada empresarial original e saldo final zero nas duas pontas.
- `tests/compras_v4621/100_quantidades_mt_kg_fracionadas_rollback.sql`: MT inteiro obrigatório, KG fracionado em compra/recebimento/transferência/estorno, valores com mais de três casas rejeitados e saldo final zero.

**Evidências**: os **dez testes SQL (10 a 100)** foram executados separadamente em `ewgest-restauracao-teste`, precedidos pelas seis propostas SQL da v46.21 e encerrados com `ROLLBACK`. Todos passaram. O GitHub Actions na branch também passou, incluindo as novas verificações estáticas das unidades e da ordem dos bloqueios. Nada foi alterado no banco de produção.

### Conciliação fiscal, capacidade da nota e smoke test visual — 24/11/2026

- `ew_compras_proteger_recebimento_nfe` passou a comparar **variação, unidade e comprimento físico** ao procurar recebimentos de pedido potencialmente duplicados. No teste da NF-e, outra barra do mesmo perfil com **7000 mm** foi recebida sem ser bloqueada pelo pedido de **6000 mm**, enquanto a tentativa de entrada duplicada de 6000 mm continuou bloqueada.
- `assets/compras-conciliacao-nfe.js` consulta os vínculos fiscais filtrados pelos **itens da nota e recebimentos do pedido**, em vez de buscar indiscriminadamente o histórico fiscal da empresa. Em caso de possível truncamento da API, interrompe a operação sem afirmar que os saldos estão completos.
- A lista de itens da nota apresenta a **quantidade fiscal ainda disponível** por linha, convertendo BARRA ↔ MT mediante o comprimento real do item quando a nota utiliza metros. Para várias entregas associadas à mesma linha, a interface soma as quantidades e impede confirmar total superior à nota. A RPC continua sendo a validação obrigatória de segurança.
- A seção empresarial permanece separada das despesas das obras e segue registrando custo fiscal sem nova movimentação.
- Foi adicionado o teste isolado `scripts/test-compras-browser-v4621.mjs` com Playwright/Chromium no CI do PR. Simula compra em obra com **duas entregas parciais e NF com saldo insuficiente/suficiente**, operação não enviada quando há excesso, registro correto quando o saldo basta, nota do estoque empresarial com **subtotais em centavos** e validação de campo em visão móvel e desktop. Sem credenciais, dados ou chamadas ao Supabase real.
- Os controles e CSS da conciliação receberam limites de largura; o navegador confirmou ausência de overflow horizontal no painel de simulação mobile (390 px). Esse smoke test **não é homologação visual completa do site** com navegação real e base de homologação.
- O workflow fixa Ubuntu 24.04 para Playwright 1.56.1, separado dos testes Node. Os parâmetros de versão dos scripts e CSS de Compras no `app.html` foram atualizados para evitar conteúdo antigo em cache.
- Evidências: `tests/compras_v4621/20_conciliacao_nfe_rollback.sql` aprovado após caso 6000/7000 mm, `scripts/test-compras-v4621.mjs` aprovado, e **Chromium mobile/desktop aprovado** no PR após correção do HTML de teste para reproduzir o identificador real do painel.

### Limitações dos testes

- Testes de transação executados em ambiente isolado com dados sintéticos. **Não** equivalem à homologação visual nem à verificação de fluxos de notas fiscais reais.
- Não foi feita execução de compra, recebimento, estorno ou transferência na produção.
- O smoke test do Chromium utiliza respostas simuladas. A integração ponta a ponta com uma sessão autorizada no banco de homologação e a comparação visual completa de telas ainda são pendentes.

### Validação inicial efetuada

- Verificação sintática do JavaScript novo na branch.
- Conferência dos IDs do novo módulo com o HTML principal.
- Migração SQL compilada no ambiente `ewgest-restauracao-teste` dentro de transação encerrada com **ROLLBACK**, sem persistir mudanças.

### Pendências antes da publicação

1. **Publicação / migrações**: revisar as seis propostas SQL, backups, dependências e políticas RLS; homologar em base isolada atualizada. As migrações não foram aplicadas em produção e a `main` não foi alterada.
2. **Transferências / documentos**: revisar documentação do deslocamento empresa ↔ obra, sem disparar romaneios de transferência entre obras de forma incorreta; testar estorno de obra e relatórios com compras vinculadas.
3. **Concorrência e permissões**: testes com requisições simultâneas reais, falha de rede/retry, unidades MT/KG/PC/BARRA, galpões distintos, fornecedores inativos e perfis 03/04/05/06/07/08; verificar idempotência em cada RPC.
4. **Regressões / navegador**: homologar visualmente em desktop/mobile, itens NF-e XML e notas manuais, consumo de produção, notas empresariais e relatórios financeiros. Conferir envio de número, valores, vínculos de nota e estornos pela interface.
5. **Relatórios e centros de custo**: incluir o livro `ew_compras_notas_empresa` nos relatórios de despesas **empresariais**, sem duplicar custos financeiros de obra. Definir centro de custo empresarial para notas globais.
6. **Migração do ESTOQUE GVG**: execução em produção ainda depende de autorização específica, backup e conferência do roteiro `docs/MIGRACAO_ESTOQUE_GVG_V4621.md`; o ensaio sintético de 4 MT foi validado, sem transferência real.
7. **Operação comercial**: cancelamentos com justificativa foram implementados e testados; ainda falta definir política formal de **aprovação** de pedidos e eventual confirmação do fornecedor.

**Decisão de segurança:** manter o PR #78 em **draft**, sem merge ou deploy até finalizar as pendências de documentação fiscal, relatórios, regressões de navegador e homologação. Os novos estornos e vínculos fiscais estão implementados e testados com dados sintéticos; a publicação exige validação operacional adicional.
