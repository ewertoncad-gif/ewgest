# Regras protegidas do EWGEST

**Regras versão 1.8** · **Site versão 36.0**

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
- O modelo segue a planilha `RM042 - MIRAGE.xlsx`: colunas item, código, localização, descrição, medida, quantidade, unidade, m² e valor (em branco), cliente/obra, motorista/placa, total de área e três assinaturas. Para até oito linhas curtas, imprimir **duas vias no mesmo A4**; para listas longas, **uma via por página**, com continuação quando necessário.
- **Emitir romaneio confirma expedição física**, e registra automaticamente saídas do tipo `completo` para todas as esquadrias vinculadas. Materiais avulsos constam no romaneio mas não afetam os saldos das esquadrias.
- **Saída parcial (marco/folha)** continua pelo fluxo existente. A emissão do romaneio usa a mesma validação de quantidade, liberação, composição de folhas e permissões via `registrar_saida_producao`.
- Todos os itens de um romaneio são confirmados **na mesma transação**. Se algum item não tiver saldo ou for inválido, nada do romaneio ou das saídas é salvo. `chave_operacao` UUID impede emissão dupla por repetição de requisição.
- A numeração do romaneio é sequencial, mas lacunas podem existir após tentativas/transações desfeitas. Não interpretar lacunas como romaneios excluídos.
- Exibir na obra lista de romaneios com **reimpressão**, usando dados congelados no momento da emissão (inclusive descrição, medida, quantidade e motorista). Não atualizar o comprovante impresso quando o cadastro técnico for alterado depois.
- Métrica de produção por fábrica: **prazo em dias corridos entre liberação para corte e expedição**, ponderado por unidades e por liberações cronológicas. Só calcular quando as liberações daquele código possuírem uma **única fábrica conhecida** e não houver ambiguidades. Não confundir com horas reais de fabricação.
- Segurança: tabelas `romaneios` e `romaneios_itens` com RLS, leitura apenas por membros da empresa, inserção apenas por RPC que exige ADMINISTRADOR ou SUPERVISOR; nenhuma operação de emissão é permitida ao usuário anônimo.
- **Melhoria futura recomendada:** um fluxo controlado para cancelar/estornar romaneios antes de implantar o módulo em escala; na primeira versão, revisar antes de confirmar, pois a emissão já registra as saídas.
- A conferência de romaneios antigos impressos fora do EWGEST e o rastreio completo de produção dentro das duas fábricas ainda não foram automatizados.

## Verificação obrigatória nas atualizações
1. Ler as regras acima antes de mexer no sistema.
2. Executar node scripts/test-regressoes.mjs.
3. Conferir navegação do catálogo e painel inicial, consultas aos vínculos, croquis e registros históricos.
4. Mudanças estruturais exigem verificações de segurança e banco; evitar operações destrutivas.
5. O cadastro/importação de novas obras com edição do número de módulos por esquadria continua como etapa futura; a nova coluna foi criada sem afetar as obras existentes.

## Histórico
- v27: FIXO; v28: prioridade das fachadas sobre FIXO; v29: MAXIM-AR próprio e prioridade das fachadas; v30: agrupamento das variações e painel de regras; v31: revisão administrativa por obra, sugestões pela descrição e auditoria de confirmação; v32: pendências visíveis, códigos MOD internos, criação ou associação manual pelo ADM; v33: correção administrativa de identificações técnicas existentes, com comparação, confirmação e auditoria; v34: códigos sufixados por família, numeração transacional, catalogação de 46 configurações legadas e pendências de modulação; v35: confirmação Sim/Não, criação/correção/adiamento e auditoria sem bloquear obras; v35.1: comparação em duas caixas e sufixo oculto somente na tela de conferência; v35.2: exibir tipologia informada na obra versus tipologia técnica do catálogo, sem misturar com código de esquadria. v35.3: explicitar código principal preservado ao criar nova configuração; v35.4: substituir quantidade de módulos por N apenas nas caixas comparativas da obra/catálogo. v35.5: descrição da obra intacta, padrão principal com N e seletor somente na correção de texto. v35.6: ocultar sufixos somente na lista principal do catálogo; v35.7: agrupar liberações e saídas por tipologia principal sem sufixos e preservar busca completa; v36: fábrica obrigatória em novas liberações, romaneio A4 em duas vias, expedição atômica e média por fábrica.
