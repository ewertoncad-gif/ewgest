# EWGEST — Recebimento manual com nota e estoque

**Situação (20/11/2026):** a migração `nota_manual_entrada_estoque_20261120` foi aplicada no Supabase de **produção** após ensaios isolados; dados e saldos anteriores foram preservados. A interface ainda depende do merge do PR #17 e da publicação automática no Cloudflare Pages. Qualquer outro desenvolvedor deve conferir o PR e os commits antes de modificar `app.html`, financeiro ou estoque.

## Escopo solicitado

- Retirar, **por enquanto**, a opção de carregar XML da tela **Financeiro das obras → Entrada de materiais**.
- Para perfis e acessórios, escolher um ou vários materiais já cadastrados, variação/cor, quantidade, comprimento de barra (perfis), galpão, fornecedor, número/data da nota e valor total.
- Permitir valor por item quando a nota contém vários materiais; a soma deve corresponder ao total, preservando custo unitário real.
- Confirmar a nota **e a entrada física** no estoque da obra numa única operação atômica; registrar vínculos e prevenir duplicidade.
- Vidros e outros insumos continuam como **despesas sem entrada física automática**, porque não possuem catálogo de variações e regra de estoque adequados a este recebimento.
- Corrigir o resumo para incluir **todos os níveis marcados para faturamento**; exibir separadamente o que pode ser emitido pelo módulo atual por esquadria e o que ainda depende do faturamento por nível.

## Interfaces e arquivos

- `app.html`: substitui formulário financeiro com XML pela conferência manual; **não remove** o recebimento por XML do módulo exclusivo do almoxarifado.
- `assets/recebimento-manual.js`: linhas de materiais, opções, conferência de valor, envio da operação e resumo de faturamento.
- `assets/recebimento-manual.css`: layout da tabela de entrada.
- `supabase/migrations/20261120235000_nota_manual_entrada_estoque.sql`: nova RPC e bloqueio do cancelamento simples de despesa com estoque físico vinculado.
- `database/proposals/20261120_recebimento_manual_estoque.sql`: proposta revisável.

## Regras de segurança e consistência

1. Somente ADM com vínculo à empresa pode registrar esse recebimento.
2. Perfis exigem número inteiro de barras e comprimento comercial (mm); acessórios usam a unidade do catálogo, com até 3 casas decimais.
3. O estoque da obra deve existir, não estar arquivado e o galpão deve estar cadastrado e ativo.
4. A nota deve conter valor em centavos e seus subtotais devem conferir **exatamente** com o total informado.
5. A operação grava despesa, itens, movimentos `COMPRA` e recibos `ew_nfe_recebimentos` na mesma transação Postgres.
6. Em falha, o banco reverte **tudo**. Em repetição do mesmo identificador da operação, devolve registro existente e não multiplica saldo.
7. Cancelar nota após receber materiais exige **estorno físico apropriado**. O cancelamento simples é bloqueado para evitar divergência entre financeiro e estoque. Estorno integrado de nota e estoque ainda não foi implementado.
8. A opção faturamento de qualquer nível continua respeitada para o **orçamento**; a emissão de notas fora de fabricação/instalação exige implementação posterior.

## Evidência dos ensaios

O banco `ewgest-restauracao-teste` possui estruturas simuladas criadas exclusivamente para ensaiar esta nova função, porque é mais antigo do que o módulo financeiro de produção.

- Ensaio de perfil: 5 barras de 6.000 mm e nota de R$ 1.500,00; criado 1 recebimento e 1 movimento de 5 barras.
- Repetição com mesmo identificador: retornou `ja_registrado=true` sem duplicar saldo.
- Nota R$ 1.200,00 com item R$ 1.000,00: rejeição antes da gravação.
- Despesa com recebimento físico: cancelamento simples bloqueado.
- Acessório: entrada de 100 PC e nota de R$ 225,40; unidade e quantidade corretas.
- Conta sem vínculo ADM: tentativa de receber material rejeitada.
- **Todos os ensaios envolveram transações revertidas com `ROLLBACK`**, sem saldos simulados permanentes.

**Limitação dos testes:** a base de teste utiliza versões simuladas das funções auxiliares de despesa e movimentação, e não uma restauração íntegra da produção. Validar também com as funções reais, permissões RLS e dados sintéticos antes de declarar homologação completa.

## Verificações pendentes

- [ ] Testar interface completa de ponta a ponta no navegador em ambiente isolado.
- [ ] Testar a nova RPC invocada por uma sessão autenticada legítima da empresa em base compatível com produção.
- [ ] Garantir que uma nota com vários perfis e cores diferentes apareça corretamente no estoque e no histórico.
- [ ] Confirmar fluxo de cancelamento com estorno no futuro.
- [ ] Conferir se o galpão selecionado e os comprimentos das barras aparecem em relatórios de estoque.
- [ ] Conferir faturamento de Outros insumos na composição do orçamento; emissão de nota de Outros insumos não é parte desta entrega.
- [ ] Confirmar que a integração com outras IAs não alterou essas mesmas funções em paralelo.

**Não publicar apenas o frontend antes de aplicar e conferir a migração, pois o botão de recebimento depende da nova RPC.**

## Verificação de implantação do banco de produção

- Nova RPC disponível e concedida ao papel `authenticated`; papel `anon` **não** possui permissão de execução.
- A RPC exige, internamente, sessão válida e vínculo `administrador` com a empresa informada.
- Contagens antes/depois da migração: **4 obras**, **0 despesas**, **0 recebimentos** e **634 movimentos** de estoque. A migração não inseriu materiais nem alterou saldos.
- A função anterior de cancelamento foi salva em `database/rollback/20261120_cancelamento_despesa_antes_entrada_manual.sql`. Não representa backup físico completo.
- Ainda é necessária validação visual da Cloudflare e teste controlado com nota real conferida pelo operador; não foi feito lançamento de NF em produção durante a implantação.

## Ajuste da interface — plano de barras do CEM (20/11/2026)

**Status: em desenvolvimento, aguardando revisão e publicação.** PR da branch `fix/recebimento-barras-cem-20261120`.

- A coluna **Barra (mm)** possui campo numérico **editável**; o valor inicial vem da importação do CEM, quando disponível. O operador pode alterá-lo caso a compra seja recebida com outro comprimento.
- Código, cor e comprimento são resolvidos pelo item da obra e pelo histórico de barras importadas do CEM; havendo duas medidas, cada combinação aparece como uma opção própria no seletor de materiais.
- A necessidade em barras vem de `NUMBARRAS`, agrupada por variação e comprimento. Quantidades recebidas por NF são consultadas separadamente em `ew_nfe_recebimentos`.
- Os indicadores são calculados **depois** de definir a medida selecionada; não exibem traços por simples ordem de execução.
- Sem barra planejada, o campo fica vazio, sem presumir tamanho; exige informação do comprimento real para registrar a NF. Comprimento diferente do planejado pode ser recebido, com aviso de divergência, mas não altera a necessidade original.

**Limitação verificada em leitura somente no banco de produção:** há obras com vínculos em `ew_cem_obras_materiais` sem movimentos `IMPORTACAO_CEM` de barras. A importação técnica conserva dados de cortes, mas não um cadastro próprio persistente do plano de barras. É necessária uma segunda correção estrutural para armazenar `NUMBARRAS`/`BARRA` por obra, perfil, cor e comprimento **sem gerar estoque físico**. Os registros antigos que não guardaram essas medidas precisam ser confrontados com o ZIP original, pois não é correto inferi-las dos cortes ou de tamanhos genéricos.

**Banco de dados:** nenhuma alteração de esquema ou saldos nesta correção de interface.
**Testes:** validação local das rotinas puras para medida importada e medida ausente; regressões completas do repositório e teste em navegador permanecem dependentes do CI e homologação.

## Ajuste de regra — barra pré-preenchida e editável (20/11/2026)

- Quando uma opção do mesmo perfil/cor/medida for selecionada, o campo inicia no comprimento lido do CEM (`OBAPROV.BARRA`). Se o operador digitar outro comprimento, essa alteração deve permanecer durante a conferência.
- Com comprimento válido entre 100 e 20.000 mm e quantidade inteira positiva, a RPC atual permite gravar a barra de tamanho real no estoque físico e vincular à nota, inclusive sem medida planejada equivalente.
- A coluna **Necessário/Falta receber** é o plano daquela mesma medida, sem substituir pela contagem de cortes. A coluna **Já recebido** usa a soma de entradas por NF da mesma medida. Comprimento não planejado aparece como **Não planejado** (ou **Não importado** se não existe plano da variação) e não compensa o plano de outra medida.
- O usuário vê advertência antes da confirmação quando a nota inclui comprimento não planejado.
- Quando a importação anterior não preservou `NUMBARRAS/BARRA`, o sistema **não consegue** pré-preencher essa informação só com os cortes. O campo fica vazio e exige o tamanho real; persistir o plano separadamente continua registrado na issue #22.

## Correção de atualização do frontend — 21/11/2026

- A PR #23 foi integrada à `main`, porém o navegador ainda mostrava o seletor antigo em print de pós-merge. A URL do JavaScript permanecia `/assets/recebimento-manual.js?v=20261120e` desde antes da alteração, e o arquivo não tinha regra de cache específica no Cloudflare Pages.
- Alteração de implantação: atualizar somente as versões de `recebimento-manual.js` e `recebimento-manual.css` para `20261121a` em `app.html`, e adicionar `Cache-Control: no-store` para esses dois arquivos em `_headers`. Não modifica RPC, dados ou funcionamento dos demais módulos.
- Os testes automatizados agora impedem reutilizar a versão antiga ou remover a configuração de cache por acidente.
- Sem acesso autenticado ao painel Cloudflare nem leitura HTTP confiável do site nesse ambiente, o deploy e o comportamento do navegador ainda exigem conferência visual após o merge.

## Persistência do planejamento de barras — proposta 21/11/2026

**Raiz identificada no banco:** A importação técnica já analisa `OBAPROV.NUMBARRAS` e `OBAPROV.BARRA` no navegador, mas só grava cortes e metragem líquida de `OBCALCP` em `ew_cem_obras_materiais`. Assim, não existe quantidade de barras planejadas nas obras que não fizeram uma importação separada de estoque (que não deve ser necessária).

**Correção preparada no código e em `database/proposals/20261121_plano_barras_cem.sql`:**

- Preservar `barras_planejadas` como JSONB por obra/variação em `ew_cem_obras_materiais`, sem criar nenhuma movimentação de estoque. Cada linha é `{comprimento_mm, quantidade}` do CEM.
- Agregar `OBAPROV` por código + cor + comprimento; entregar dados como `perfis[].variacoes[].barras_planejadas`.
- Na função transacional `importar_materiais_cem`, validar os comprimentos (100–20.000 mm), quantidades inteiras positivas e comprimentos não repetidos; gravar o plano na mesma transação de importação técnica.
- Reimportar perfis de obra existente atualiza os dados técnicos por chave de variação, mas não cria NF, nem movimenta estoque, nem altera esquadrias existentes.
- No financeiro, preferir o novo plano (inclusive quando a variação tem array explicitamente vazio); caso a obra seja antiga com coluna NULL, manter leitura de `IMPORTACAO_CEM` como compatibilidade. Nunca somar plano novo e histórico antigo.
- O comprimento comprado na nota fiscal continua editável e independente do comprimento planejado.

**Limite das obras antigas:** nem todas preservaram `BARRA/NUMBARRAS`. Não é possível reconstruir o plano com base nas quantidades ou nos tamanhos dos cortes; é necessário **reanalisar o ZIP original** no módulo Importar arquivo técnico e importar somente perfis/acessórios para a mesma obra, sem excluí-la.

**Status de publicação:** proposta pendente de revisão, homologação do SQL e autorização antes de alterar banco de produção. A alteração de frontend aceita o esquema antigo (`select: '*'`) e não gera lançamentos de estoque por si só.

**Segurança adicional de reimportação (revisão 21/11):** se um ZIP não contiver `OBAPROV` para determinada variação, o payload **omite** o campo `barras_planejadas` e a função preserva o último planejamento daquela variação. Dados inválidos de OBAPROV dos perfis da obra interrompem a importação, sem gravar quantidades parciais. Somente um novo plano válido substitui os comprimentos/quantidades anteriores; sem plano nunca estimar barras pelos cortes.

## Implantação comprovada — Supabase produção (21/11/2026)

- Migração aplicada: `20261121004257_cem_barras_planejadas_por_obra_20261121` em `ewgest-producao`, SQL versionado em `supabase/migrations/`; `database/proposals/20261121_plano_barras_cem.sql` é a proposta de revisão.
- Arquivo de recuperação da **função anterior**: `database/rollback/20261121_importar_materiais_cem_anterior.sql`. Reverter a função não exige apagar a nova coluna; manter a coluna evita perda de planos novos.
- Antes/depois verificados por consultas somente leitura: **4 obras**, **499 materiais vinculados**, **634 movimentos de estoque**, **0 recebimentos de NF**, **0 despesas** — contagens inalteradas. Todas as 499 linhas existentes permaneceram com `barras_planejadas IS NULL` após a migração.
- Confirmado: `barras_planejadas` existe; função contém o código de persistência; RLS da tabela e privilégios de leitura/execução do papel autenticado mantidos.
- Teste funcional de SQL em `ewgest-restauracao-teste` com esquema temporário e dados sintéticos na mesma transação: salvar duas medidas, reimportar substituindo o plano, impedir duplicidade ao repetir identificador de operação e preservar plano na chamada legada sem novo campo. Finalizou com `ROLLBACK`; verificado que **nenhum objeto de teste permaneceu**.
- O frontend da PR #25 deve ser integrado à `main` para que o novo ZIP envie o plano. Sem essa publicação, o banco já aceita o plano, mas a importação antiga não o fornece.
- Para obras já registradas com plano NULL, usar **Importar arquivo técnico → Analisar ZIP → Perfis** (e Acessórios somente quando realmente necessário), deixando **Esquadrias desmarcado**. Sem apagar a obra, o fluxo atualizará os vínculos e o planejamento.
- Homologação final pendente: conferir o deploy Cloudflare e testar a reimportação real com o arquivo original CEM, que não está anexado nesta conversa.

## Recuperação assistida de plano antigo na tela financeira — 21/11/2026

**Causa reproduzida em banco:** na obra ativa `TESTE-TREINAMENTO` (`ESSENCE CONSTRUÇÕES`), o perfil GN096 tem `quantidade_prevista` em **cortes**, mas `barras_planejadas IS NULL` e não possui movimentos legados `IMPORTACAO_CEM` de barras. A importação original ocorreu antes da migração `20261121004257`; o backend não pode inferir o comprimento ou a necessidade comercial desses cortes. Não copiar necessidades de outras obras com o mesmo perfil.

**Interface corrigida:**
- Em item cujo plano de barras específico da obra esteja ausente, a coluna Barra (mm) deixa de pedir valor e exibe **Plano não importado → Recuperar do CEM**.
- Clicar no botão abre **Importar arquivo técnico**, com Esquadrias e Acessórios desmarcados e Perfis selecionado; permite carregar o ZIP original.
- O processo compara o **código da obra**, o **ID da obra** e o **perfil/cor** da solicitação com os dados analisados. Se o ZIP for de outra obra, ou não contiver `OBAPROV` do perfil/cor, a importação fica bloqueada com erro explicativo.
- Após importar, retorna ao Financeiro da mesma obra. Comprimento e quantidade serão preenchidos do novo plano, com comprimento ainda editável para compras diferentes.
- Entrada de NF de perfil **sem plano da obra** fica bloqueada neste formulário até recuperar o ZIP; não haverá comprimento presumido. Não há alteração em recebimento de acessórios, estoque físico, romaneio ou orçamento.

**Limite:** o sistema não armazena o ZIP original, apenas a estrutura processada. A recuperação não ocorre sem selecionar novamente o arquivo no navegador. Nenhuma exclusão de obra é necessária.

## Interface simplificada — 21/11/2026

Não criar botão adicional de recuperação do CEM no Financeiro. Para obras antigas sem plano de barras, mostrar somente **Plano de barras não importado**. A importação já está disponível no menu **Importar arquivo técnico**. Reimportar o ZIP original para a obra existente com somente **Perfis** marcado e Esquadrias/Acessórios desmarcados, sem excluir a obra. Quando o plano for salvo, comprimento predefinido e editável na compra. Não presumir comprimento a partir de cortes ou outras obras. Nenhuma movimentação de estoque físico nesta alteração.
