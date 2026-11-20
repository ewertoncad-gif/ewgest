# Regras protegidas do EWGEST

**Regras versão 2.5** · **Site versão 40.0**

## Tipologia principal e variações
1. Código principal identifica o modelo da tipologia, **não** a quantidade de módulos.
2. INV-VNZN00 é a tipologia principal; EA14_1 é a configuração legada com descrição de **2 folhas** vinculada a ela. **Folhas não comprovam quantidade de módulos**.
3. Manter todos os IDs legados, croquis individuais, descrições de origem, vínculos das esquadrias, liberações e históricos.
4. A relação é tipologia_principal_id e quantidade_modulos na tabela tipologias. Em esquadrias, quantidade_modulos está reservada para o número de módulos individual da obra.
5. Agrupamento só pelo administrador e somente dentro da mesma empresa/fabricante. Jamais renomear registros para duplicar código principal nem alterar IDs para unir configurações.

## Filtros e classificação
- FACHADA UNITIZADA e FACHADA STICK têm prioridade sobre FIXO e MAXIM-AR, mesmo com MÓDULO FIXO/MAXIM-AR.
- MAXIM-AR tem filtro próprio, separado de JANELA.
- JANELA DE CORRER COM PEITORIL FIXO permanece em JANELA; PEITORIL FIXO da porta não classifica a porta como FIXO.
- Busca, tipo e fabricante funcionam em conjunto e a classificação deve ser única.

## Reconhecimento de tipologias em novas obras (proteção v31)
- O código da esquadria é **local à obra**: o mesmo EA14_1 pode representar fixo veneziana na Casa Boa Viagem e uma porta de correr em outra obra.
- Para sugerir tipologia, usar **descrição + classe técnica**, nunca código de esquadria isolado. Similaridade é sugestão, não prova de identidade.
- Em **Banco de tipologias → Conferência do administrador**, mostrar grupos pendentes por **obra + origem + descrição**; o ADM compara relatório e cadastro antes de escolher.
- Para associações com descrição diferente, exigir aceite adicional explícito. Exigir sempre confirmação do ADM.
- Associar uma tipologia existente não cria vínculo global de origem e modifica apenas esquadrias pendentes da obra selecionada com mesma origem e descrição. Guardar auditoria.
- Cadastrar nova tipologia pendente também fica limitado à obra escolhida e não ativa reconhecimento automático global de origem. Históricos, croquis e outras obras permanecem intactos.
- A importação automática de novas obras **ainda não está implementada**: ao criar esse importador, ele deve preservar as garantias acima e deixar dados ambíguos pendentes de conferência.
- Antes de permitir importação de relatórios em lote, testar colisões de códigos entre obras e coincidência de descrições com configurações distintas.

## Pendências de cadastro e modulações internas (v32)
- Ao chegar uma nova obra, se o código de tipologia estiver ausente/incorreto (ex.: EA05), ou houver configuração diferente, a esquadria precisa ficar **pendente**. O importador automático de novas obras ainda não existe.
- O **ADM escolhe a tipologia técnica**, independentemente do código EA da obra, e seleciona uma modulação **MOD-xxxxxx já cadastrada** ou cria outra a partir da descrição.
- O código MOD é um identificador interno gerado pelo banco, único; não substitui código técnico nem código de esquadria.
- A descrição de origem orienta sugestões. Vinculação sempre precisa de confirmação explícita, divergências precisam de aceite adicional.
- Um vínculo confirmado associa somente esquadrias pendentes da mesma obra, origem e descrição, com auditoria; não ativa reconhecimento universal do código EA.
- Quantidade de **FOLHAS não é quantidade de MÓDULOS**: não deduzir a segunda da primeira. Quantidade de módulos pode ficar pendente de conferência.
- Os registros legados INV-VNZN00 e EA14_1 continuam com seus IDs, croquis e obras associados. MOD-000001 e MOD-000002 geram os códigos INV-VNZN00-01 e INV-VNZN00-02; a quantidade de módulos continua não confirmada.
- Se a tipologia técnica não existir, o ADM a cadastra informando o código técnico correto; o processo cria um MOD interno para ela. Não sugerir EA05/EA14_1 como novos códigos técnicos.

## Correção de identificação técnica existente (v33)
- Quando um código da obra (por exemplo EA14) foi cadastrado como tipologia, o ADM pode usar **Editar tipologia → Corrigir identificação técnica** para apontá-lo à tipologia principal correta já existente, como INV-PGR207.
- Essa alteração não renomeia o código histórico, nem modifica os IDs, as esquadrias, os croquis, a descrição ou a origem. A lista passa a mostrar o código técnico principal com o código original como referência.
- O destino deve ser uma tipologia técnica principal **da mesma empresa e fabricante**. Nunca oferecer EA como novo destino técnico. O usuário sempre escolhe e confirma; descrições divergentes precisam de confirmação adicional.
- Não permitir operação de identificação em cadastros com filhos ou modulações internas vinculadas enquanto suas relações não forem revisadas. Nunca presumir que descrição igual garante croqui/configuração idêntica.
- Registrar a alteração em tipologias_identificacoes_historico; permitir desfazer quando não houver relações de modulação incompatíveis. Evitar migrações destrutivas.
- As diferenças de abertura interna/externa e veneziana cega/ventilada serão abordadas separadamente; não alterar croquis nesta etapa.

## Sufixos automáticos de configuração (v34)
- Cada configuração de tipologia recebe um código visual `<codigo-principal>-01`, `-02`, `-03` etc. O sufixo **não é quantidade de módulos/folhas** nem codifica diretamente tipo de veneziana/abertura. A descrição e o croqui identificam o que muda.
- O código interno global `MOD-000001`, `MOD-000002` etc. e o ID UUID continuam sendo as chaves estáveis de banco. O código principal pode ser alterado administrativamente, então o código visual é composto com o prefixo atual.
- Sufixo numérico sequencial é **por família técnica**, alocado pelo banco com contador transacional e índice único; o sistema não deve reutilizar numeração antiga. Reassociar identificação histórica a outra família recebe o próximo número disponível na família de destino, com registro de auditoria.
- Em cada cadastro legado criou-se uma configuração inicial, sem alterar o croqui ou o código original. Mesmo com **descrição idêntica**, duas configurações legadas podem ter croquis diferentes; não devem ser fundidas automaticamente.
- Na migração inicial, somente esquadrias com descrição exatamente igual à do cadastro receberam vínculo MOD. As demais ficam **modulação a conferir** e o ADM pode escolher existente ou criar outra pelo fluxo de Pendências de cadastro; sem alterar a tipologia técnica já vinculada.
- O fluxo de criação de nova configuração confere a descrição e alerta se já houver descrição equivalente, para evitar duplicações acidentais. Para variantes de mesma descrição mas geometria diferente, é preciso uma identificação técnica adicional no futuro; **não inferir pelo texto sozinho**.
- Catálogo e consultas mostram os códigos técnicos sufixados; todos os membros autorizados da mesma empresa podem consultar, mas apenas ADM pode classificar.
- Croquis históricos continuam pertencendo aos registros legados. Croquis novos para uma configuração inédita precisam de rotina dedicada em melhoria futura; não sobrescrever croqui de outra configuração.
- A importação automática de novas obras continua não implementada; confirmações seguem restritas à obra e à descrição de origem.

## Conferência de descrição sem bloqueio (v35)
- Para esquadria já ligada à tipologia correta, porém sem MOD confirmado, o ADM vê duas descrições lado a lado e responde: **Sim, é a mesma configuração** / **Não, existe diferença técnica**.
- **Sim** vincula à configuração já existente da mesma família, sem reescrever a descrição original da obra. Registrar aprovação nos vínculos de classificação; nunca buscar módulo pelo código EA isoladamente.
- **Não** abre três opções: (1) nova configuração com sufixo automático, exigindo descrição que a diferencie das existentes; (2) corrigir a descrição da esquadria para a da configuração escolhida, gravando a descrição original em auditoria; (3) conferir depois, registrando adiamento e preservando a pendência.
- A correção da descrição altera apenas a esquadria, ou grupo idêntico de esquadrias pendentes, **dentro da mesma obra, mesma tipologia, mesma origem e mesma descrição**, e vincula à configuração explicitamente escolhida. Não corrige o catálogo principal nem substitui croquis.
- A opção **conferir depois** não altera produção/liberação, não descarta a pendência e registra a decisão do administrador.
- Não confundir diferenças de escrita com diferenças construtivas. O ADM decide; o sistema nunca cria nova configuração apenas porque a descrição difere em texto.
- Nova configuração só com descrição distinta das anteriores e confirmação do ADM; número de módulos é opcional e não se deduz do número de folhas.
- Somente ADM executa as ações, com autorização no banco e políticas de leitura auditada. Preservar histórico das esquadrias e croquis anteriores.
- O importador automático de novas obras permanece fora de escopo; o fluxo de conferência não pode impedir liberação/fabricação.

## Clareza visual da conferência (v35.1)
- Na tela **Conferência de descrição**, ocultar o sufixo técnico `-01/-02...` do seletor e das descrições comparadas, para o ADM se concentrar no significado técnico. Não apagar ou alterar o identificador no banco nem sua exibição no catálogo.
- Exibir **Descrição da obra** e **Descrição do catálogo** em duas caixas separadas, com tipografia legível, contraste e adaptação ao celular.
- O seletor deve continuar usando o UUID da configuração, não o texto visível, inclusive quando houver descrições repetidas. As ações Sim/Não e a trilha de auditoria continuam inalteradas.

## Identificação de tipologias na comparação (v35.2)
- Cada caixa da conferência mostra **o código da tipologia** antes da descrição: na obra, `esquadrias.rotulo_tipologia_relatorio` (código exatamente recebido do relatório, como EA6A_1); no catálogo, código da **tipologia principal** já reconhecida (como WINFAC-JCR203).
- Nunca confundir o código da esquadria (EA6A) com o código de tipologia informado pela obra; quando o código de tipologia de origem não existir, indicar **Não informado no relatório**, sem inventá-lo.
- O sufixo `-01` permanece oculto nesta tela, não é removido do banco. As duas descrições continuam em caixas separadas e as opções Sim/Não não mudam.
- O código original informado pela obra nunca é alterado durante a comparação.

## Clareza na criação de configuração (v35.3)
- A opção "Criar outra configuração" explica explicitamente que **o código da tipologia principal é preservado**; apenas o sufixo identifica a nova configuração.
- Ao selecionar esta opção, mostrar o código técnico principal atual como confirmação. Nunca renomear a tipologia ou o código da esquadria por essa ação.
- Mudança exclusivamente de interface; nenhuma alteração em códigos ou vínculos existentes.

## Simplificação da quantidade de módulos na tela de comparação (v35.4)
- Somente na **caixa do catálogo** da tela "Conferência de descrição", substituir a quantidade numérica imediatamente anterior a `MÓDULO`, `MÓDULOS`, `MÓDULO(S)` (com ou sem acento) por `N`. A caixa da obra preserva o texto original. Ex.: "GRADIL 6 MÓDULO(S)" e "GRADIL 8 MÓDULO(S)" exibem "GRADIL N MÓDULO(S)".
- **Não** modificar números de folhas, dimensões, quantidade de esquadrias, códigos técnicos, sufixos ou outras características.
- Não persistir `N` no banco, relatórios, descrições originais, auditoria ou croquis; o seletor só aparece quando o ADM escolhe corrigir a descrição, com números reais para distinguir configurações.
- A transformação é **somente visual**. Manter confirmação Sim/Não e opções de revisão do ADM; a igualdade aparente de textos com `N` não confirma equivalência técnica nem cria vínculos automáticos.

## Comparação correta da tipologia padrão (v35.5)
- A tela de conferência **não tem seletor de configuração no topo**. À esquerda exibir a descrição **exatamente como veio da obra**, incluindo o número real de módulos. À direita exibir a **descrição padrão do cadastro principal da tipologia**, substituindo somente a quantidade de módulos por N para leitura simplificada.
- Não utilizar `tipologias_modulacoes.descricao` na caixa da direita; usar `tipologias.descricao` do registro principal. Não alterar textos armazenados no banco ou nos croquis.
- A pergunta **Sim** confirma que é a **mesma tipologia técnica**, não que uma esquadria de 6 módulos tenha exatamente a mesma configuração de 1 ou 8 módulos.
- Ao confirmar Sim, reutilizar somente a modulação existente com descrição completa equivalente; se ainda não existe, criar configuração independente sob o mesmo código de tipologia, preservando a descrição original da obra e quantidade explícita de módulos quando inequívoca. Nunca confundir quantidade de folhas com módulos.
- Se responder **Não**, conservar as escolhas de nova configuração, corrigir descrição e conferir depois. O seletor de uma modulação específica aparece **somente dentro de Corrigir descrição**, porque aí a seleção é necessária para saber qual descrição concreta aplicar.
- Manter histórico, código técnico principal, registros de obra, croquis e aprovações do ADM; sem associação silenciosa com configuração de quantidade diferente.

## Sufixo oculto na listagem principal de tipologias (v35.6)
- Em **Consultar tipologias cadastradas**, mostrar somente o código técnico **principal** (ex.: GOL-FIXN00, GOLS-JCR20), sem o sufixo -01/-02 que representa cada configuração.
- Não modificar os identificadores MOD, o código técnico principal, as descrições, croquis ou vínculos no banco. O vínculo do item com sua configuração própria continua intacto.
- No painel **Modulações internas cadastradas**, manter os códigos sufixados para permitir identificação técnica da configuração, quando necessário.
- Não alterar a exibição nas obras nem a comparação administrativa neste ajuste. A busca por códigos de configuração deve continuar funcional.

## Sufixo oculto nos agrupamentos da obra (v35.7)
- Em **Liberações para corte** e **Saídas para obra**, mostrar apenas o código principal da tipologia no título do agrupamento.
- Esquadrias de variações `-01`, `-02` etc. da mesma família devem ser exibidas juntas no mesmo grupo, com contagem de códigos de esquadria consistente.
- Não mudar o `modulacao_id`, o UUID da esquadria, os dados de liberação, os lançamentos de saída ou os croquis.
- O sufixo técnico completo continua disponível no cadastro de modulações e pesquisável no filtro de tipologia das obras, ainda que o título não o mostre.
- Essa é uma melhoria da apresentação operacional, aplicável às duas abas da obra, não uma fusão de configurações no banco.

## Romaneios, expedição e fábricas (v36)
- Toda **nova liberação para corte** deve registrar fábrica `AFOGADOS` ou `IMBIRIBEIRA`, no próprio lançamento, inclusive em liberações parciais. A RPC legada sem fábrica não deve ficar acessível ao cliente; usar `registrar_liberacao_corte_fabrica`.
- As **10 liberações anteriores** não possuíam fábrica; manter `NULL` e jamais inventar valores. Nenhuma saída anterior foi apagada ou alterada.
- Cada romaneio possui identificação sequencial interna `RM00001`, data, cliente/obra, motorista, placa e itens. O número é gerado no banco, diferente da numeração dos comprovantes antigos feitos fora do EWGEST.
- O modelo toma a planilha `RM042 - MIRAGE.xlsx` como referência: colunas item, código, descrição ampliada, medida, quantidade, unidade e m²; sem localização e sem valor no impresso. Cabeçalho com logotipos Artefal/GVG, ícone de entrega, data, código, cliente/obra, motorista/placa, total de área e três assinaturas. Para linhas curtas que caibam no espaço disponível (até nove, conforme estimativa de altura), imprimir **duas vias no mesmo A4**; para listas longas, **uma via por página**, com continuação quando necessário.
- **Emitir romaneio confirma expedição física**, e registra automaticamente saídas do tipo `completo` para todas as esquadrias vinculadas. Materiais avulsos constam no romaneio mas não afetam os saldos das esquadrias.
- **Saída parcial (marco/folha)** continua pelo fluxo existente. A emissão do romaneio usa a mesma validação de quantidade, liberação, composição de folhas e permissões via `registrar_saida_producao`.
- Todos os itens de um romaneio são confirmados **na mesma transação**. Se algum item não tiver saldo ou for inválido, nada do romaneio ou das saídas é salvo. `chave_operacao` UUID impede emissão dupla por repetição de requisição.
- A numeração do romaneio é sequencial, mas lacunas podem existir após tentativas/transações desfeitas. Não interpretar lacunas como romaneios excluídos.
- Exibir na obra lista de romaneios com **reimpressão**, usando dados congelados no momento da emissão (inclusive descrição, medida, quantidade e motorista). Não atualizar o comprovante impresso quando o cadastro técnico for alterado depois.
- Métrica de produção por fábrica: **prazo em dias corridos entre liberação para corte e expedição**, ponderado por unidades e por liberações cronológicas. Só calcular quando as liberações daquele código possuírem uma **única fábrica conhecida** e não houver ambiguidades. Não confundir com horas reais de fabricação.
- Segurança: tabelas `romaneios` e `romaneios_itens` com RLS, leitura apenas por membros da empresa, inserção apenas por RPC que exige ADMINISTRADOR ou SUPERVISOR; nenhuma operação de emissão é permitida ao usuário anônimo.
- **Melhoria futura recomendada:** um fluxo controlado para cancelar/estornar romaneios antes de implantar o módulo em escala; na primeira versão, revisar antes de confirmar, pois a emissão já registra as saídas.
- A conferência de romaneios antigos impressos fora do EWGEST e o rastreio completo de produção dentro das duas fábricas ainda não foram automatizados.

## Romaneios flexíveis, transporte e cancelamento (v37)
- **Motoristas e placas** ficam em cadastros próprios por empresa: `romaneios_motoristas` e `romaneios_veiculos`, acessíveis ao ADM/SUPERVISOR por RPC `cadastrar_transporte_romaneio`. Na emissão, a seleção é feita por listas; novos nomes/placas podem ser cadastrados pela própria tela.
- **Busca de esquadrias** por código, descrição ou localização antes da escolha na lista. A filtragem não altera o UUID nem vincula automaticamente outros códigos parecidos.
- Cada item de esquadria no romaneio possui `tipo_saida`: `completo`, `marco` ou `folha`. A opção “+ Adicionar esquadria” é genérica. “Somente folhas” registra quantidade de **folhas físicas**, não unidades de esquadria; folhas por unidade deve ser informado ou reaproveitado de configuração anterior.
- O romaneio chama a função original `registrar_saida_producao` para as três modalidades, mantendo saldo de marcos e de folhas separado. Imprimir `MARCO —` ou `FOLHA —` na descrição das linhas parciais; não estimar m² de uma peça parcial com a área da esquadria completa.
- **Cancelar/estornar** é permitido apenas ao ADM, com confirmação explícita e motivo escrito de 10–400 caracteres. O romaneio permanece no banco com status `cancelado`, usuário, data e motivo, e a reimpressão exibe claramente **CANCELADO**.
- Saídas de produção vinculadas ao romaneio cancelado recebem `cancelado_em`/`cancelado_por` e **não entram mais em saldos, estatísticas ou médias**. Não apagar a saída histórica nem afetar outras expedições; todos os movimentos do mesmo romaneio são estornados na mesma transação.
- A função `registrar_saida_producao` só soma movimentos não cancelados e rejeita reativação de identificadores de operação cancelados. A chave original de emissão permanece reservada.
- A média da fábrica usa apenas romaneios ativos e somente saídas completas com atribuição de fábrica inequívoca. Envio de marco/folha é evento operacional, **não** equivale a conclusão do conjunto.
- Cancelamento administrativo **não confirma devolução física**. Antes de emitir novamente após cancelar uma entrega já expedida, conferir retorno dos materiais com a expedição.
- Preservar as regras anteriores de romaneio atômico, impressão em duas vias quando couber, permissões e código de tipologia principal sem sufixo em listas operacionais.
- Testes devem cobrir o ciclo: emitir marco, estornar, emitir folhas, estornar, emitir completo, com a transação de teste revertida.

## Saída completa sem perguntar folhas e MAXIM-AR sem desmembramento (v37.1)
- Se a opção selecionada for **esquadria completa**, ocultar e **não exigir** “Folhas por esquadria”, tanto no romaneio quanto na saída individual. O parâmetro `p_folhas_por_unidade` vai como `null`; **não presumir 1 folha** nem gravar composição técnica não confirmada.
- O banco `registrar_saida_producao` aceita composição ausente somente no tipo `completo`. Continua debitando o saldo de conjuntos pelo marco e conserva a contabilização de folhas quando a composição já é conhecida. Se houver configuração anterior, o banco a utiliza sem perguntar.
- Na primeira saída **desmembrada** (`marco` ou `folha`), exigir a composição apenas caso ela ainda não esteja cadastrada; nesse momento, usar a quantidade confirmada para recomputar também as folhas de conjuntos completos anteriores.
- **MAXIM-AR nunca pode ter saída parcial**: impedir a escolha de marco/folha na interface e rejeitar no servidor para proteger contra chamadas diretas. Não proibir o desmembramento de janelas ou portas; continuam com as opções habituais quando houver saldo.
- A consulta de saldos, o cancelamento de romaneios, a reversão das saídas, a impressão e as relações de obras permanecem inalterados. Nenhuma composição é inventada em cadastros anteriores.
- Regressão obrigatória: MAXIM-AR completo sem composição passa; tentativa de saída parcial falha; janela completa com composição desconhecida e posterior saída de marco com confirmação permite histórico e saldo corretos.

## Romaneio impresso alinhado ao modelo original (v38.0)
- Em **Imprimir/Reimprimir romaneio**, omitir as colunas Localização e Valor. Manter sete colunas: Item, Cód., **Descrição (50%)**, Medida, Quant., Un. e M².
- O cabeçalho usa as imagens dos logotipos **Artefal e GVG** e do caminhão de entrega fornecidas na referência visual; imagens incorporadas no HTML impresso, sem depender de downloads externos.
- A **Medida** da esquadria deve aparecer em **metros**, com vírgula decimal e duas casas: `400,00 × 1.100,00 mm` → `0,40 × 1,10 m`. Converter **somente valores que indicam explicitamente mm**; preservar medidas de materiais avulsos quando não há indicação clara da unidade.
- O rótulo de rodapé deve indicar `Total M²`. Não alterar dados salvos nas esquadrias, itens do romaneio, área, motorista, histórico, cancelamentos ou vínculos de produção.
- Manter a estratégia de **duas vias no mesmo A4 quando o conteúdo couber** e uma via por página com continuação para listas extensas. O cabeçalho de reimpressões de documentos cancelados continua mostrando a marcação de cancelamento.
- Testes devem cobrir cabeçalho, colunas presentes/ausentes, conversão de formatações de milímetros com vírgula/ponto, preservação de materiais avulsos, duas vias e paginação.

## Área do almoxarifado e cabeçalho de impressão (v39)
- No romaneio impresso, exibir o **ícone de caminhão em uma coluna própria** entre o título e o quadro de data/código, sem sobreposição. Definir `@page { size: A4 portrait; margin: 0 }` e **9 mm de recuo interno** no papel para reduzir a impressão dos cabeçalhos do Chrome sem deixar o conteúdo junto à borda. A configuração de cabeçalhos/rodapés do navegador não é controlável de modo garantido pelo site.
- Criar uma **área de Romaneios e expedição** disponível no painel principal para ADM/SUPERVISOR, com seleção de obra, emissão de romaneio, histórico e reimpressão.
- Perfil `almoxarife`: login direcionado **diretamente à área exclusiva de romaneios**, sem navegação pelo painel de gestão, tipologias, fabricantes, usuários, liberações ou saídas individuais; manter acesso a **Minha senha** e **Sair**. Ao emitir, atualizar ou restaurar sessão, continuar no espaço dedicado.
- Permissão de servidor: `almoxarife` ativo e com vínculo à empresa pode chamar apenas as RPCs apropriadas para **emissão de romaneios** e **cadastro de motorista/placa**. **Cancelar/estornar romaneio** continua reservado ao ADM. Liberação para corte e saída individual continuam reservadas aos perfis já autorizados.
- A gestão de usuários do ADM oferece o perfil `almoxarife` tanto na criação quanto na edição, e mantém **Redefinir senha** e **Desativar acesso**. O usuário altera a senha inicial por **Minha senha**. Não colocar senha padrão nem qualquer senha em código-fonte, arquivos do site, banco de usuários ou log de auditoria.
- Trocar uma senha **não garante encerramento imediato de sessões já abertas**; para interromper o acesso, o ADM deve usar **Desativar acesso**.
- O usuário de exemplo `Almoxarife01` deve ser criado pelo ADM no fluxo normal de criação de usuários do EWGEST; não declarar conta ativa sem verificar o registro em `usuarios_login` e o Auth.

## Consulta de romaneios e caminhão alinhado (v39.1)
- Cada romaneio no histórico da obra e no painel exclusivo oferece **Consultar** e **Reimprimir**.
- **Consultar** abre nova guia do navegador com o documento em formato A4, mantendo as duas vias conforme o tamanho do romaneio, sem disparar impressão automática. Na visualização, há ações **Imprimir** e **Fechar**, sendo a barra oculta na impressão. Nenhum dado ou saída é alterado pela consulta.
- **Reimprimir** continua abrindo a nova guia e a caixa de impressão automaticamente; manter o fluxo de emissão de romaneio inalterado, sem duplicar saídas.
- O caminhão deve ficar **integrado ao mesmo quadro do título**, usando uma célula interna dedicada de cerca de 17 mm, sem empurrar o código e a data e sem sobrepor o título. Cabeçalho geral passa a quatro colunas: Artefal, título/caminhão, documento, GVG.
- A consulta funciona igualmente para romaneios **emitidos ou cancelados**, inclusive no acesso do perfil Almoxarife. Documento cancelado mantém a sinalização de cancelamento.
- Respeitar margens de 9 mm no A4 na visualização e impressão; a opção nativa de cabeçalho/rodapé do Chrome não pode ser desligada à força pelo site.

## Romaneio: texto abreviado, edição antes da emissão e caminhão sem linha (v39.2)
- As descrições das **esquadrias** no formulário de emissão devem ser sugeridas de maneira resumida, sem alterar o cadastro técnico nem a tipologia. Exemplo: `JANELA DE CORRER - 2 FOLHAS - LINHA GOLD SLIM - HYDRO` → `JANELA CORRER 2F GOLD SLIM (COMPLETA)`. Conservar detalhes relevantes, como PEITORIL FIXO, BANDEIRA, ABERTURA EXTERNA e VENEZIANA.
- O sufixo operacional indica a modalidade efetiva da linha: `(COMPLETA)`, `(MARCO)` ou `(FOLHAS)`. A descrição da esquadria é **editável antes da emissão**, item a item (2–350 caracteres), e a edição não modifica `esquadrias.descricao`.
- A RPC `emitir_romaneio_com_saidas` recebe `descricao_romaneio` opcional em cada item de esquadria e salva o texto informado em `romaneios_itens.descricao`, marcando `descricao_impressao_definida=true`. Reimpressão e consulta respeitam essa descrição congelada. Não aceitar descrição vazia, não textual ou acima do limite.
- Para **romaneios antigos** com `descricao_impressao_definida=false`, abreviar apenas **na apresentação** da consulta/reimpressão; a descrição histórica original permanece no banco. Os materiais avulsos permanecem com as descrições exatas informadas pelo emissor.
- Na impressão, permitir quebra de linha explícita (`white-space:pre-line`) e quebra de palavras longas (`overflow-wrap:anywhere`) na coluna Descrição; dimensionar a paginação pelo texto realmente exibido. Não sobrepor células nem cortar conteúdo em A4.
- O caminhão antigo, que continha **uma linha preta incorporada à imagem**, foi substituído por um SVG simples, limpo, do mesmo tema visual (caminhão azul e marca de entrega). Preservar a estrutura do cabeçalho e a impressão em duas vias quando couber.
- Não permitir alteração silenciosa de documentos **já emitidos**; correções posteriores de comprovantes exigem processo com auditoria (ou cancelamento autorizado e nova emissão).
- Não modificar permissões, saldos, liberações, saídas, áreas, cancelamentos ou códigos técnicos para realizar esses ajustes de apresentação.

## Abreviações administráveis, observações e acesso do almoxarife (v40.0)
- **Banco de tipologias → Abreviações de romaneios** é um painel de edição exclusivo do ADM: pesquisa e seleciona a tipologia exata (`tipologia_id`) e define uma descrição-base de 2 a 300 caracteres, sem sufixo. O sistema acrescenta `(COMPLETA)`, `(MARCO)` ou `(FOLHAS)` conforme o tipo de saída. O usuário pode restaurar a abreviação automática.
- Persistência em `tipologias_abreviacoes` (apenas leitura RLS para integrantes ativos da empresa), alteração por RPC `salvar_abreviacao_tipologia` restrita ao ADM e histórico em `tipologias_abreviacoes_historico`, com descrição anterior, nova, autor e data. Nenhuma edição desse painel altera `tipologias.descricao`, croquis, vínculos ou movimentos.
- A sugestão na emissão resolve a abreviação pelo `esquadrias.tipologia_id`. Sem associação/sugestão personalizada, usa o algoritmo de abreviação anterior; o operador ainda pode editar a descrição só daquele romaneio. A configuração nova vale para **próximas emissões**, não sobrescreve descrições registradas em romaneios já emitidos.
- **Observações da entrega** agora são preenchidas em `textarea` ao final do formulário, depois de esquadrias e materiais e antes da confirmação de saída. Reutiliza `romaneios.observacoes` (até 1000 caracteres) e imprime ao fim da lista, antes das assinaturas, respeitando quebras de linha. Para textos longos, reavaliar o espaço das duas vias e a paginação.
- **Falha de almoxarife corrigida:** a RPC `emitir_romaneio_com_saidas` já permitia o papel, mas a RPC aninhada `registrar_saida_producao` negava esse papel. A emissão cria um contexto transacional `ewgest.romaneio_emissao_id` **após validar a empresa e inserir o novo romaneio**. A função aninhada permite ALMOXARIFE somente se o contexto aponta para romaneio novo na **mesma transação**, da mesma empresa e obra, criado pelo mesmo usuário ativo. Fora desse contexto, saída individual de ALMOXARIFE continua bloqueada.
- A conta Almoxarife01 está ativa e vinculada à empresa, conforme verificado em novembro de 2026. Testes de emissão como Almoxarife01, saída avulsa negada, criação/edição/restauração de abreviações e tentativa de edição pelo almoxarife foram executados em **transações revertidas**, sem movimentos fictícios persistentes.
- Não conceder INSERT/UPDATE/DELETE diretos nas tabelas de abreviações a `authenticated`; nem ampliar permissões da rota de liberação de corte ou do cancelamento de romaneios ao almoxarife.
- Testes futuros: descrição padrão cadastrada prevalece ao algoritmo; desmembramento recebe sufixo correto; IDs de tipologia de outras obras não são confundidos; observações longas não invadem assinaturas; emissão de ALMOXARIFE transacional e saída avulsa rejeitada.

## Verificação obrigatória nas atualizações
1. Ler as regras acima antes de mexer no sistema.
2. Executar node scripts/test-regressoes.mjs.
3. Conferir navegação do catálogo e painel inicial, consultas aos vínculos, croquis e registros históricos.
4. Mudanças estruturais exigem verificações de segurança e banco; evitar operações destrutivas.
5. O cadastro/importação de novas obras com edição do número de módulos por esquadria continua como etapa futura; a nova coluna foi criada sem afetar as obras existentes.

## Histórico
- v27: FIXO; v28: prioridade das fachadas sobre FIXO; v29: MAXIM-AR próprio e prioridade das fachadas; v30: agrupamento das variações e painel de regras; v31: revisão administrativa por obra, sugestões pela descrição e auditoria de confirmação; v32: pendências visíveis, códigos MOD internos, criação ou associação manual pelo ADM; v33: correção administrativa de identificações técnicas existentes, com comparação, confirmação e auditoria; v34: códigos sufixados por família, numeração transacional, catalogação de 46 configurações legadas e pendências de modulação; v35: confirmação Sim/Não, criação/correção/adiamento e auditoria sem bloquear obras; v35.1: comparação em duas caixas e sufixo oculto somente na tela de conferência; v35.2: exibir tipologia informada na obra versus tipologia técnica do catálogo, sem misturar com código de esquadria. v35.3: explicitar código principal preservado ao criar nova configuração; v35.4: substituir quantidade de módulos por N apenas nas caixas comparativas da obra/catálogo. v35.5: descrição da obra intacta, padrão principal com N e seletor somente na correção de texto. v35.6: ocultar sufixos somente na lista principal do catálogo; v35.7: agrupar liberações e saídas por tipologia principal sem sufixos e preservar busca completa; v36: fábrica obrigatória em novas liberações, romaneio A4 em duas vias, expedição atômica e média por fábrica; v37: transportes cadastrados, busca de esquadrias, saídas completas/parciais em romaneios, cancelamento com estorno auditável; v37.1: esconder a composição na saída completa e restringir MAXIM-AR ao conjunto completo. v38.0: romaneio sem localização/valor, descrição ampliada, cabeçalho fiel à referência e medidas em metros só na impressão; v39.0: ícone de caminhão em coluna separada, A4 e área exclusiva de romaneios; v39.1: caminhão integrado ao título e consulta em nova guia sem abrir impressão; v39.2: caminhão SVG sem linha, descrição curta sugerida e editável na emissão, quebra de linha e texto histórico protegido; v40.0: painel ADM de abreviações por tipologia com histórico, observações finais e liberação segura de romaneios ao almoxarife.


## Estoque físico por galpão (versão 42.5)
- \`ew_estoques_locais\` representa a **existência/arquivamento do estoque de uma obra**; não representa o galpão.
- \`ew_locais_fisicos\` registra os galpões, inicialmente IMBIRIBEIRA e AFOGADOS. O ADM pode cadastrar novos.
- Cada movimentação em \`ew_estoque_obras_movimentos\` possui \`local_estoque\`. Registros históricos receberam **IMBIRIBEIRA** sem alterar quantidade, variação, cor ou obra.
- O saldo é calculado por **empresa + obra + variação/cor + comprimento + unidade + galpão**. O total da obra é a soma dos galpões.
- Não alterar o galpão diretamente em um movimento com baixa ou entrada. Transferir por **duas movimentações auditadas de sinais opostos** na mesma transação, com \`transferencia_id\`, preservando o total.
- Cadastro manual solicita local físico, e a lista dispõe de filtro. Ajustes de quantidade e liberações com baixa não podem tornar o saldo do galpão negativo.
- Somente ADM pode cadastrar local, ajustar saldo e transferir. O histórico e os saldos de estoques arquivados ficam preservados para recuperação; obra sem esquadrias e sem romaneios não aparece na seleção de expedição.

## Liberação em lote a partir do arquivo CEM (versão 42.5)
- Arquivo técnico **não** deve ser interpretado dentro da ação de liberar uma única esquadria; o botão de lote fica na tela **Liberações para corte** da obra.
- Conferir o código da obra, mostrar cada esquadria calculada no ZIP e associar por **código de esquadria da obra + largura + altura**. Havendo ambiguidade, exigir escolha explícita.
- Exibir espelho editável de quantidade a liberar, não permitindo superar o saldo aguardando corte nem incluir a mesma esquadria duas vezes.
- O material do ZIP deve ser conferido no espelho antes de qualquer baixa; usar **OBAPROV para barras comerciais**, sem confundir peças de corte com barras inteiras, e **OBACES para acessórios**. Linhas sem vínculo ou saldo no galpão não devem ser debitadas automaticamente.
- A fábrica que **produz** não determina automaticamente o **galpão de origem** do material; confirmar o galpão por linha de material, inclusive quando o mesmo perfil está em dois locais.
- Confirmar o lote de forma **atômica, idempotente, com UUID de operação**, registrando individualmente as esquadrias liberadas e debitando cada material **uma única vez por lote**, em \`ew_liberacoes_lotes\` e movimentos \`PLANO_CORTE_LOTE\`.
- Antes da confirmação, destacar a quantidade de linhas de material **não selecionadas para baixa**. Permitir liberação técnica sem baixa quando confirmada expressamente.
- Permanecem preservados romaneios, saídas, histórico de tipologias, liberações anteriores e permissões dos usuários.


## Histórico de acessos dos usuários (versão 42.6)
- A tela **Administração → Usuários** oferece o botão **Histórico de acessos**, com filtros por usuário e últimos 7, 15 ou 30 dias. Horários apresentados em **America/Recife**.
- O controle usa \`ew_historico_acessos\`: usuário, empresa, identificador aleatório de sessão, início, última comunicação, saída confirmada e origem. **Não são gravados senha, token, IP ou dados de navegação**.
- **Entrada**: após autenticação e carregamento do painel, o cliente registra um evento com identidade obtida do próprio JWT, nunca de nome/usuário informado no formulário.
- **Última comunicação**: atualizada enquanto a sessão está aberta e a página está visível, em intervalos de aproximadamente 2 minutos; não significa que uma pessoa esteja trabalhando ativamente ou necessariamente online.
- **Saída**: registrada apenas quando o usuário seleciona **Sair** e a requisição é confirmada pelo servidor. Fechamento da aba, desconexão ou expiração não devem gerar saída fictícia; essas sessões permanecem com **saída não registrada**.
- Sessões reabertas de versões antigas ficam marcadas como **SESSAO_RECUPERADA**: a data corresponde à primeira observação pelo novo monitoramento, não necessariamente ao login original.
- Na implantação, foram aproveitados apenas os horários de criação de sessão que ainda estavam disponíveis em \`auth.sessions\` durante os 7 dias anteriores, identificados como **AUTENTICACAO_ANTERIOR** e sem inventar horário de saída.
- A tabela não autoriza INSERT/UPDATE/DELETE pela API. A leitura é protegida por **RLS apenas para administradores da mesma empresa**. Eventos são gravados somente via \`ew_registrar_evento_acesso\`, com verificação de \`auth.uid()\` e vínculo da empresa, sem timestamps informados pelo navegador.
- O histórico de liberações, estoque, expedição, cadastro e permissões existentes não é alterado.


## Sessão única para todos os perfis (versão 42.7)
- Nenhum perfil, inclusive o administrador, pode manter duas sessões de autenticação do EWGEST ativas simultaneamente.
- O controle usa o \`session_id\` assinado pelo Supabase Auth e a tabela \`ew_sessoes_unicas\` (somente leitura interna por RPC e por políticas), indexada por usuário.
- No login, a RPC \`ew_controlar_sessao_unica('consultar')\` reserva uma sessão se a conta estiver livre. Se já houver outra sessão, o EWGEST pergunta se a pessoa quer **substituir a sessão anterior**. Cancelar NÃO altera a sessão antiga; confirmar substitui por operação atômica.
- O navegador anterior é avisado e retorna à tela de login no monitoramento periódico (aproximadamente 15 segundos). Mesmo antes do aviso, políticas RLS e as operações privilegiadas negam acesso ao banco para o \`session_id\` que perdeu a titularidade.
- O botão **Sair** libera somente a sessão atual. Sessão antiga não pode excluir ou substituir a titularidade da sessão nova.
- O controle está no banco: todos os vínculos usados pelas políticas RLS exigem sessão atual, e todas as RPCs privilegiadas de operação do EWGEST verificam explicitamente a sessão. A Edge Function de contas, que utiliza service-role, também compara o \`session_id\` validado com a sessão ativa da tabela.
- O mecanismo não depende de IP, identificação da máquina, nome do navegador, localização, user-agent ou armazenamento de senhas.
- Para acesso simultâneo com o mesmo JWT em múltiplas abas do mesmo navegador, continua se tratando da mesma sessão autenticada, não de logins independentes.
- Novos dispositivos podem obter tokens pelo Auth ao validar a senha, mas **não** podem usar o EWGEST sem assumir explicitamente a titularidade no servidor; tokens antigos perdem autorização no sistema após substituição.
- Não apagar histórico nem alterar movimentações existentes. O histórico de acessos continua distinguindo **Sair** confirmado de saídas forçadas sem registro de logout.

## Correção de acesso à tela Usuários (versão 42.7.1 — 18/11/2026)
- Causa diagnosticada em logs: a Edge Function `ewgest-acesso` reconhecia o usuário e sua sessão, mas a leitura de `ew_sessoes_unicas` pelo perfil `service_role` retornava **403 (42501)**. Essa falha era tratada como sessão substituída, e o navegador interpretava o **401** resultante como expiração do login.
- Conceder somente **SELECT a `service_role`** na tabela de sessões; `anon` e `authenticated` continuam sem acesso direto, assim como todos os perfis comuns. Não conceder UPDATE/DELETE a `service_role` desnecessariamente.
- Na Edge Function, distinguir erro técnico ao consultar a tabela de sessão de efetiva substituição de sessão. Em erro técnico, não emitir 401 de credencial revogada.
- No navegador, só invalidar a sessão quando a resposta 401 identifica autenticação realmente inválida ou substituída. Demais falhas exibem erro, sem limpar o login.
- Validar regressão ao abrir **Usuários** após assumir sessão em outro computador. Não modificar obras, estoques, romaneios ou histórico.


## Perfil Gerenciador e visualização de senhas (v42.8 — 18/11/2026)
- O nível \`gerenciador\` fica imediatamente abaixo de \`administrador\`; tem acesso à administração operacional, obras, cadastro técnico, importações CEM, tipologias, fabricantes, estoque e galpões, romaneios, histórico de acessos e gestão de usuários não ADM.
- Um Gerenciador **não pode** alterar a conta de um Administrador: nome/login, senha, perfil, bloqueio, reativação ou qualquer outro dado do ADM. Também não pode criar um novo ADM nem promover alguém a ADM. Essas regras são validadas na Edge Function, independentemente dos controles visuais.
- ADM continua autorizado a gerenciar todas as contas e conceder perfis, inclusive Gerenciador. Gerenciadores podem criar e gerenciar Gerenciadores, Técnicos, Almoxarifes e usuários de Consulta.
- \`usuarios_login\` e \`usuarios_empresas\` aceitam o perfil novo; políticas RLS e RPCs operacionais com privilégios administrativos incluem Gerenciador, preservando os demais perfis.
- \`usuarios_login\` e \`usuarios_empresas\` não concedem UPDATE direto a \`authenticated\`. Gerenciamento de contas passa exclusivamente pela Edge Function, que verifica o usuário autenticado e o vínculo com a empresa.
- Adicionados botões **Mostrar/Ocultar** exclusivamente para ver a senha que está sendo digitada pelo operador em cadastro, login, redefinição e Minha senha. A senha antiga de outro usuário não pode ser visualizada nem recuperada.
- A versão v42.8 não cria automaticamente nenhuma nova conta, e preserva sessões, esquadrias, estoques e romaneios.


## Exclusão de usuários e F5 (v42.9 — 18/11/2026)
- Em **Administração → Usuários → Editar usuário**, o botão **Excluir usuário** solicita confirmação e digitação do login. Conta ADM e conta de quem realiza a operação não podem ser excluídas.
- **Exclusão administrativa não é exclusão física de \`auth.users\`**: a conta é banida do Auth, desvinculada de \`usuarios_empresas\`, marcada como inativa e arquivada em \`usuarios_login.excluido_em\` e \`excluido_por\`. Deixa de aparecer na listagem padrão e não pode ser reativada via API comum. O histórico de acessos, estoque, liberações e romaneios continua íntegro. O gerente também não pode excluir contas ADM.
- Não eliminar em cascata entidades vinculadas a \`auth.users\`; várias tabelas usam \`ON DELETE RESTRICT\`. Não inventar horário de saída para acesso arquivado.
- Ao pressionar **F5 na mesma aba**, a sessão armazenada em \`sessionStorage\` será lida novamente. Se o access token estiver perto do vencimento, renovar com refresh token antes da verificação da sessão única.
- Se houver falha transitória de rede, serviço ou consultas, manter o token armazenado e oferecer **Tentar restaurar sessão sem informar senha**. Só eliminar tokens em autenticação comprovadamente inválida, revogada ou substituída.
- A regra de **uma sessão por usuário** continua ativa; se houver outra sessão de Auth, a confirmação explícita de substituição permanece necessária.
- Exclusão administrativa nunca é feita automaticamente na implantação e só ocorre após confirmação dentro do EWGEST.


## Exclusão controlada de obras antes de operações (v43.0 — 18/11/2026)
- **Administração → Gerenciar obras** lista todas as obras da empresa, inclusive obras com somente estoque.
- ADM e Gerenciador podem **verificar** se uma obra é excluível. A consulta retorna motivo do bloqueio e contadores.
- A exclusão só pode acontecer se NÃO EXISTIR:
  - Liberação de corte (incluindo individual, legado, lote CEM e liberação técnica sem baixa).
  - Quantidade liberada/fabricada ou saída de produção.
  - Romaneio ou item de romaneio associado, inclusive cancelado.
  - Qualquer movimentação de estoque, incluindo abertura, ajuste, transferência, baixa ou estorno.
  - Vínculo externo de outra obra às esquadrias da obra em questão.
- Se a obra ainda estiver sem qualquer dessas operações, o usuário pode excluí-la para corrigir uma exportação CEM e importar outra vez.
- Exige motivo de 8 a 300 caracteres, digitação exata do código da obra e confirmação adicional. O banco verifica tudo novamente durante a transação, sob bloqueio da obra e das esquadrias; a verificação na tela é apenas informativa.
- Exclusão física de dados **exclusivos da obra**: cabeçalho da obra, esquadrias, histórico de classificação/descrição dessas esquadrias, espelho de materiais e importações da obra, configurações de saída ainda não utilizadas e vínculo do estoque vazio. Não apagar fabricantes, tipologias, origem/vínculos globais, croquis, abreviações, perfis, acessórios, cores, comprimentos comerciais, galpões, motoristas, veículos ou contas.
- Registrar o evento em \`ew_obras_exclusoes_historico\`, com empresa, obra original, motivo, resumo e responsável, sem chave estrangeira de volta à obra excluída.
- Nunca forçar a exclusão em uma obra bloqueada — nem por ADM. Para correções após iniciar operações, usar processo futuro de revisão com trilha de auditoria e conciliação, não apagar a obra.
- As obras existentes não foram alteradas na implantação, e o recurso só executa a exclusão após confirmação explícita no navegador.


## Reversão por etapas e histórico de operações (v43.1 — 18/11/2026)
A regra da v43.0 (bloqueio por qualquer lançamento histórico) foi substituída, para obras com histórico, por **reconciliação antes do arquivamento**.

- Primeiro cancelar os romaneios emitidos pela tela de Expedição (inclusive as saídas associadas); saídas avulsas de produção ainda ativas bloqueiam o processo e exigem conferência específica.
- Depois em **Gerenciar obras** cancelar as liberações da obra. Esse cancelamento é atômico, só é permitido se não houver expedição ativa nem unidades fabricadas; preserva cada registro original em \`liberacoes_corte\` com \`cancelado_em\`, \`cancelado_por\`, \`motivo_cancelamento\`; marca os lotes CEM cancelados e ajusta \`esquadrias.qtd_liberada\` a zero. Não apaga planos, liberações ou históricos.
- Em seguida **estornar o estoque** (após conferência física do material e galpões). Cada movimento histórico recebe uma contrapartida \`origem='ESTORNO'\`, ligada por \`estorno_de_id\` único. Somente com saldo final zero por código, acabamento, comprimento, unidade e galpão a obra fica apta.
- Se houver fabricação registrada, saída não cancelada, saldo inconsistente, vínculos externos ou outras pendências, a exclusão é bloqueada. Não zerar esses dados artificialmente.
- Concluída a reconciliação, **Remover obra do acompanhamento** marca \`obras.arquivada_em\` com responsável e motivo, preservando integralmente a obra, seus lançamentos e todos os cadastros. Ela desaparece da tela inicial, estoque e seletores operacionais; uma nova importação do CEM com mesmo código cria obra nova. A obra anterior permanece histórica, não será fisicamente excluída.
- As antigas RPCs \`ew_excluir_obra_sem_operacoes\` e \`ew_verificar_exclusao_obra\` passam a delegar às rotinas seguras, impedindo um cliente antigo de executar exclusão física.
- A tabela de auditoria \`ew_auditoria_operacoes\` registra operador, empresa, obra/código, data/hora, ação, motivo, dados originais e detalhes do estorno/cancelamento/remoção. O cancelamento de romaneio é capturado por trigger. A tabela tem RLS, sem INSERT/UPDATE/DELETE direto para usuários.
- Em **Usuários → Relatório de operações**, ADM e Gerenciador podem filtrar período (7/30/90/365 dias), usuário, tipo de evento, nome/código da obra, visualizar detalhes e exportar CSV. **Histórico de acessos** continua separado.
- Não existe exclusão automática, nem restauração física implícita, nem anulação de movimentação por apagar linhas. Testes transacionais são feitos com ROLLBACK.


### Reversão de saídas sem romaneio e histórico legado
- Se a saída foi registrada manualmente, sem estar vinculada a um romaneio, uma ação separada **Cancelar saídas avulsas** só aparece depois dos romaneios. Requer confirmação explícita de devolução física, motivo e validação no servidor.
- Saídas vinculadas a romaneio **nunca** podem ser canceladas por essa ação; devem ser estornadas usando o próprio romaneio para manter a correspondência.
- A auditoria também importa romaneios cancelados anteriormente, apenas quando os campos reais de data, motivo e responsável estão preenchidos. Não cria horários fictícios e impede importações duplicadas.


### Consulta e estorno na aba Estoque (v43.2 — 18/11/2026)
- Em **Estoque → Saldos e estornos** ou **Gerenciar estoques**, listar também estoques arquivados, inclusive com prazo de restauração vencido; eles seguem fora do seletor operacional de movimentações normais.
- Mostrar totais de movimentos históricos, movimentos ainda sem contrapartida e saldos diferentes de zero. A conferência detalha código/descrição do material, cor, acabamento, comprimento, galpão, unidade e saldo por combinação.
- Permitir estorno **total dos movimentos ainda pendentes** por ADM/Gerenciador, mesmo quando o estoque local estiver arquivado, desde que a obra não esteja arquivada e romaneios, saídas e liberações já tenham sido conciliados. Usar exclusivamente as RPCs transacionais `ew_inspecionar_reversao_obra` e `ew_estornar_estoque_obra` com motivo e uma confirmação descritiva, sem digitação de palavra-chave; nunca apagar lançamentos, editar saldos diretamente ou reativar estoque.
- Ao concluir, atualizar o resumo e informar o histórico em **Usuários → Relatório de operações**. A saída do controle de obras continua independente em **Gerenciar obras**.


### Estoque arquivado selecionável e estorno por lançamento (v43.3 — 18/11/2026)
- Exibir no seletor **Estoque → Obra** também as obras com estoque arquivado, marcadas **ESTOQUE ARQUIVADO**. Nessa situação, a listagem de materiais é exclusivamente de consulta: não permitir novos lançamentos, ajustes comuns ou transferências pelo painel operacional.
- Com uma obra selecionada, **Movimentações da obra** abre consulta aos saldos por galpão e histórico de lançamentos, com filtros para pendentes ou todos, indicando origem, data, material, local, quantidade e estado do estorno.
- Cada lançamento original pendente pode receber **Estornar lançamento** com motivo e confirmação; **Estornar todos os lançamentos pendentes** continua disponível e usa a função transacional anterior.
- O estorno individual é uma nova contrapartida, nunca deleção/edição do lançamento anterior; lançamento já estornado é imutável. Transferências entre galpões devem ser revertidas pelas duas pernas na mesma transação. Proibir saldo negativo e exigir cancelamento das operações dependentes antes de estornar.
- Autor, momento, motivo e movimento original ficam preservados em `ew_auditoria_operacoes`, com RLS e sem permissão de escrita direta para o cliente. O estoque arquivado pode ser consultado sem reativação do prazo de restauração.


### Confirmação simplificada de estornos (v43.4 — 18/11/2026)
- Para estorno individual e estorno total de estoque, usar **uma única confirmação** (Tem certeza?) com descrição explícita do efeito na quantidade/saldo, identificação da obra e preservação da auditoria. Eliminar a segunda caixa que exige digitar `ESTORNAR`.
- Essa regra vale tanto para **Estoque → Movimentações da obra** quanto para o estorno de estoque em **Gerenciar obras**. Motivo, validações, autor, data, histórico e bloqueios transacionais permanecem obrigatórios.
- A confirmação adicional de devolução física de **saídas avulsas** é procedimento independente e não é alterada nesta versão.


### Exclusão de obra sem obrigar reimportação (v43.5 — 18/11/2026)
- O botão final em **Gerenciar obras** é **Excluir obra**, sem mencionar reimportação, que poderá ou não ocorrer de forma independente no futuro.
- Quando todas as operações ativas estiverem conciliadas, o gestor registra um **motivo de 10 a 300 caracteres** e recebe **uma única confirmação descritiva** ("Tem certeza que deseja excluir esta obra?"). Não existe mais campo para digitar o código da obra.
- A RPC `ew_arquivar_obra_reconciliada` mantém sua validação de código e controles transacionais; o código é fornecido automaticamente pela obra selecionada, sem pedir digitação ao operador. Permanecem bloqueios de dependências, autenticação, autorização, idempotência e auditoria.
- **Excluir obra** a remove das telas operacionais; o registro permanece arquivado no banco para auditoria, sem eliminação física de históricos. A ação não reimporta, recria ou altera outra obra.


### Saldos, nomenclatura e motivos (v43.6 — 18/11/2026)
- O histórico de estoque mostra **Não estornado** para lançamento original já realizado que ainda não recebeu contrapartida. Filtragem por **Não estornadas** / Todo o histórico; remover a palavra "pendente" das etiquetas dos lançamentos e do botão de estorno total.
- Ampliação do modal de estoque, caixas de motivo de exclusão e estorno. Motivo mínimo reduzido para **5 caracteres** nas rotinas de estorno individual/total, exclusão/arquivamento auditado, cancelamento de liberações e saídas avulsas (backend e frontend correspondentes).
- Paginação visual de saldos e movimentações na consulta (70 saldos, 60 lançamentos iniciais; botão mostrar mais). O banco preserva e valida integralmente os dados; só a renderização inicial é limitada.
- **Estorno não liberado** enquanto houver liberações ou outras operações ativas. Mostrar motivo claro com a quantidade de liberações ativas e oferecer acesso direto a Gerenciar obras; não interpretar botão desabilitado como processamento lento, nem remover proteção.


### Alerta visual de estorno bloqueado (v43.7 — 18/11/2026)
- Em **Estoque → Movimentações da obra**, após verificação no servidor, se houver liberações de corte ativas ou outra dependência, mostrar mensagem **⚠ ESTORNO BLOQUEADO** em caixa vermelha com pulsação suave (com `prefers-reduced-motion` para acessibilidade), informando que é necessário cancelar primeiro essas liberações.
- O botão **Estornar todos** continua realmente desabilitado, mas exibe **Bloqueado: cancele as liberações** quando esse for o impedimento, e o cursor **não deve girar como se estivesse carregando** (usar `not-allowed`). Explicar o motivo com `aria-describedby` e manter o atalho para Gerenciar obras.
- Ao reabrir/reverificar uma obra sem impedimentos, remover o alerta e restaurar o texto/estado normais do botão. A regra de bloqueio permanece no Supabase; nenhuma alteração de saldo é feita por esse aviso.


### Acesso direto a Obras pelo menu lateral (v43.8 — 19/11/2026)
- Em **Espaço de trabalho**, o menu lateral passa a apresentar **Obras** abaixo de **Tela inicial**, antes de **Romaneios e expedição**.
- Ao clicar em **Obras**, se houver uma única obra técnica ativa com esquadrias, abre diretamente a tela detalhada da obra. Se houver várias, abre uma listagem de obras com nome, código, área total, liberada, a liberar e progresso para escolha; sem obras, informa a ausência.
- Obras cadastradas apenas para controle manual de estoque continuam exclusivamente na tela **Estoque**, não na listagem técnica de obras.
- Na tela detalhada, o botão **Voltar** retorna à listagem Obras se a entrada tiver ocorrido pelo menu lateral; as entradas feitas pela Tela inicial continuam voltando ao painel. O botão **Tela inicial** sempre permanece disponível.
- O atalho não é exibido para o usuário restrito de almoxarifado e não altera permissões de obra, liberações ou expedição.


### Cancelar liberações na tela da obra (v43.9 — 19/11/2026)
- Dentro de **Obras → obra → Liberações para corte**, mostrar **Cancelar liberações** ao lado de **Liberar a partir do arquivo CEM**, somente a ADM e Gerenciador quando a obra tiver registros ativos de liberação.
- Abre diálogo com a obra, lista dos registros e totais conferidos em `ew_inspecionar_reversao_obra`. Exige motivo entre 5 e 400 caracteres e uma confirmação explícita de que **todas** as liberações da obra serão canceladas. Não é cancelamento individual.
- Se houver romaneios ativos, saídas de produção ou fabricação registrada, o banco impedirá o cancelamento e a tela indicará qual dependência conciliar primeiro.
- O botão usa a RPC existente `ew_cancelar_liberacoes_obra`, preserva registros e auditoria, atualiza os totais da obra e informa que o estoque deve ser estornado **separadamente**. A interface nunca exclui a obra nem realiza estornos de estoque como efeito colateral.
- Supervisores continuam aptos a fazer liberações, mas não recebem o botão administrativo de cancelamento em massa.


### Local correto do cancelamento de liberações (v44.0 — 19/11/2026)
- **Cancelar liberações** fica em **Gerenciar obras → Verificar exclusão**, ao lado de **Excluir obra**, mesmo quando a exclusão da obra ainda estiver bloqueada.
- O botão de cancelamento sai da tela **Obras → detalhe**. Não duplicar a ação nem confundi-la com a exclusão definitiva da obra.
- Cancelar liberações exige motivo (5–400 caracteres), consulta das operações dependentes, confirmação e uso da RPC auditada `ew_cancelar_liberacoes_obra`. Liberações canceladas não alteram automaticamente o estoque; a obra permanece ativa.
- O botão Excluir obra só é habilitado depois de resolver as pendências e informar seu próprio motivo de exclusão.


### Botão Cancelar liberações na linha da obra (v44.1 — 19/11/2026)
- Em **Gerenciar obras → Obras da empresa**, mostrar **Cancelar liberações** na própria linha de cada obra, imediatamente ao lado de **Verificar exclusão**, sem depender de abrir a inspeção de exclusão.
- Clicar em Cancelar liberações abre o diálogo para aquela obra, verifica no banco as liberações e dependências, exige motivo (5–400 caracteres) e confirmação. Sem liberações ativas, exibe aviso e não permite confirmar.
- O cancelamento não exclui a obra nem estorna o estoque. Remover os botões duplicados do painel interno e da tela de detalhe; Excluir obra continua após Verificar exclusão e segue bloqueado enquanto houver pendências.


### Limpar prévia de importação ao sair (v44.2 — 19/11/2026)
- **Analisar arquivo** apenas lê o ZIP em memória e consulta a existência da obra; não cadastra nem persiste obras ou esquadrias. O formulário informa explicitamente que o cadastro de novas obras/esquadrias está indisponível nessa tela; apenas os materiais de obras já cadastradas podem ser gravados, mediante confirmação.
- **Sair**, expiração/substituição de sessão e cancelamento de nova sessão descartam o ZIP selecionado, a análise da obra, as decisões de conciliação, o identificador de operação e os resultados temporários da prévia. O próximo acesso começa com campos vazios e opções padrão, mesmo sem recarregar a página.
- O botão **Limpar análise** permite iniciar outro ZIP sem sair. A limpeza jamais remove, altera ou arquiva obras e materiais já confirmados no banco. Importações que chegaram a ser confirmadas no servidor não são revertidas ao sair.
- A leitura assíncrona do arquivo é invalidada por contador de geração ao sair ou escolher outro arquivo, evitando que uma análise antiga volte a preencher a tela após logout/troca de ZIP. Isso não cancela uma gravação já enviada ao servidor.


### Acesso único a Gerenciar obras (v44.3 — 20/11/2026)
- Retirar o botão **Gerenciar obras** do cabeçalho da **Tela inicial**, pois a ação já existe na barra lateral em **Administração → Gerenciar obras**.
- Manter inalterada a navegação lateral, permissões, conferência e cancelamento de liberações e exclusão de obras. Sem alteração de dados ou operações no Supabase.


### Croquis exclusivamente por edição individual (v44.4 — 20/11/2026)
- Remover do cabeçalho de **Banco de tipologias → Consultar tipologias cadastradas** o indicador `Croquis: X de Y` e o botão `Importar croquis` (pacotes JSON). Remover seu input e lógica de importação em lote para evitar referências inválidas.
- No cadastro, o usuário administrador encontra a tipologia pela busca/filtros e clica em **Editar**. Ali, se a tipologia não tem croqui, mostrar **Adicionar croqui**; se já tem, mostrar **Trocar croqui**. O seletor aceita PNG/JPG/WebP e grava o croqui da tipologia individualmente com a rotina existente.
- Preservar croquis existentes, a visualização/ampliação, permissões e a persistência no Supabase. Não alterar, apagar ou reinicializar croquis no banco.


### Limpeza da navegação na tela Fabricantes (v44.5 — 20/11/2026)
- Na tela **Cadastro de fabricantes**, remover os dois botões redundantes do cabeçalho: **← Tela inicial** e **Banco de tipologias**.
- Preservar o título, os campos e a listagem de fabricantes, as permissões e os acessos equivalentes pela barra lateral (**Tela inicial**, **Banco de tipologias**, **Fabricantes**).
- Não alterar os cadastros nem a navegação das demais páginas neste ajuste.


### Recarregamento sem piscar a tela de login (v44.6 — 20/11/2026)
- Ao abrir/recarregar `/app`, mostrar primeiro uma tela neutra **Carregando EWGEST…**. O HTML do login inicia oculto para evitar a exibição do formulário de senha enquanto a sessão do navegador é validada.
- Se há sessão válida em `sessionStorage`, manter a interface na tela de carregamento até restaurar a sessão, consultar permissões e carregar o painel; então exibir o painel/área autorizada diretamente, sem mostrar o login no meio do caminho.
- Se não há sessão ou ela foi revogada/expirada irrecuperavelmente, apresentar o login normalmente. Em falhas de rede recuperáveis, preservar as credenciais e apresentar o controle de recuperação de sessão já existente.
- Em caso de exceção inesperada de inicialização, revelar o login com o erro para evitar carregamento infinito. O indicador de carregamento respeita a preferência do sistema por movimento reduzido. Não guardar credenciais novas, burlar a validação de sessão única, modificar permissões ou alterar o backend.


### Remover atalhos redundantes de navegação dos cabeçalhos (v44.7 — 20/11/2026)
- Remover **← Tela inicial** dos cabeçalhos de **Romaneios e expedição**, **Banco de tipologias**, **Banco de materiais**, **Estoque**, **Importar arquivo técnico**, **Usuários** e **Gerenciar obras**. O acesso correspondente permanece na barra lateral.
- Remover também **Cadastro de fabricantes** do cabeçalho do **Banco de tipologias**, pois o menu **Fabricantes** já está na barra lateral. A página Fabricantes já não possui botões redundantes desde v44.5.
- Remover os eventos JavaScript e ajustes de visibilidade dos botões excluídos, sem afetar os demais botões (Histórico de acessos, Relatório de operações, atualização, cadastro, importação, filtros etc.). Ajustar as margens dos títulos após a remoção.
- **Não remover** o botão de retorno da tela **Minha senha**: usuários restritos ao almoxarifado não dispõem do botão Tela inicial na lateral; o retorno deve continuar levando à área autorizada.
- Não alterar dados do Supabase, esquadrias, saldos, autenticação nem permissões.


### Seleção de ZIP mais limpa (v44.8 — 20/11/2026)
- Em **Importar arquivo técnico → 1. Arquivo de exportação**, retirar o rótulo **Arquivo ZIP de exportação técnica** e esconder o controle nativo de seleção de arquivo (que parecia um botão dentro de outro).
- Exibir um único botão visual **Importar obra** que abre o seletor de arquivos ZIP e um texto discreto com o nome do arquivo escolhido (ou **Nenhum arquivo selecionado**). Manter os botões independentes **Analisar arquivo** e **Limpar análise**.
- A seleção do ZIP **não grava obra no banco**. Permanece a limitação do módulo atual: análise de esquadrias e importação de materiais de obras cadastradas, com confirmação separada. Nunca interpretar o texto do botão como autorização para alterar essa regra de importação.
- O arquivo e o nome exibido devem ser descartados ao limpar a análise, trocar de sessão ou sair, sem afetar obras salvas.


### Conferência de barras e comprimentos no ZIP CEM (v44.9 — 20/11/2026)
- Na etapa **Importar arquivo técnico → Conferência antes de importar → Perfis identificados**, substituir a coluna **Linhas de cálculo** por **Barras (qtd. × comprimento)**, usando `OBAPROV.NUMBARRAS` e `OBAPROV.BARRA` (mm). Ex.: **12 barra(s) × 6.000 mm**. Mesmos código/cor/comprimento somam quantidade; comprimentos diferentes são apresentados separadamente.
- Exibir cor/tratamento ao lado do conjunto quando houver acabamentos diferentes para o mesmo código. Se OBAPROV não tiver dado para um perfil, escrever **Não informado no ZIP**, nunca zero fictício. Dados inválidos devem ser sinalizados para conferência.
- Esses números representam **barras comerciais calculadas pelo CEM**, não saldo físico de almoxarifado. `OBCALCP` permanece como cálculo de peças/cortes e não deve ser usado para inferir barras. Não lançar movimentação de estoque nem alterar dados do banco por essa conferência.
- A tabela de acessórios continua com seu indicador de linhas de cálculo por enquanto; o ajuste solicitado é exclusivo dos perfis.
