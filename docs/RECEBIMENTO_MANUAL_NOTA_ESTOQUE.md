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

- A coluna **Barra (mm)** é apenas informativa. O usuário não escolhe medida comercial nem digita comprimento de perfil.
- Código, cor e comprimento são resolvidos pelo item da obra e pelo histórico de barras importadas do CEM; havendo duas medidas, cada combinação aparece como uma opção própria no seletor de materiais.
- A necessidade em barras vem de `NUMBARRAS`, agrupada por variação e comprimento. Quantidades recebidas por NF são consultadas separadamente em `ew_nfe_recebimentos`.
- Os indicadores são calculados **depois** de definir a medida selecionada; não exibem traços por simples ordem de execução.
- Sem barra planejada, a tela mostra **Não importado** e impede registrar o perfil com medida inventada. Isso não altera nem apaga estoque ou notas.

**Limitação verificada em leitura somente no banco de produção:** há obras com vínculos em `ew_cem_obras_materiais` sem movimentos `IMPORTACAO_CEM` de barras. A importação técnica conserva dados de cortes, mas não um cadastro próprio persistente do plano de barras. É necessária uma segunda correção estrutural para armazenar `NUMBARRAS`/`BARRA` por obra, perfil, cor e comprimento **sem gerar estoque físico**. Os registros antigos que não guardaram essas medidas precisam ser confrontados com o ZIP original, pois não é correto inferi-las dos cortes ou de tamanhos genéricos.

**Banco de dados:** nenhuma alteração de esquema ou saldos nesta correção de interface.
**Testes:** validação local das rotinas puras para medida importada e medida ausente; regressões completas do repositório e teste em navegador permanecem dependentes do CI e homologação.
