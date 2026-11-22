# EWGEST — Plano de categorias, precificação por m² e histórico

**Issue:** #63. **Estado:** fase 1 implementada no GitHub, **não publicada**, **sem escrita no Supabase**.

## O fluxo atual e onde entrar

Na v46.8 a importação de novas obras segue:
1. CEM ZIP: leitura, análise, comparação de esquadrias/materiais.
2. Modal `cemQuoteOverlay`, controlado por `assets/orcamento-niveis.js`: cadastro de níveis, grupos e valores.
3. O submit cria `cemParsed.orcamentoDraft`, oculta modal e chama `cemImportarSelecionados()`, que grava obra, esquadrias, estoque previsto e orçamento atomicamente via `ew_importar_obra_cem_financeiro`.

**Nova etapa obrigatória apenas para obras com valores de fabricação/instalação:**
3.1. Conferência e categorias de precificação antes de qualquer gravação (novo modal).
3.2. Usuário revisa categorias por item, cria/renomeia categorias; padrões por tipologia do banco só sugerem categoria, sem alterar a ficha da obra antiga.
3.3. Define preço-base por m² por categoria e a divisão (%) de fabricação/instalação; a porcentagem vem inicialmente dos totais originais do orçamento.
3.4. Recalcular imediatamente preços/m² finais, valor por item e os subtotais em centavos; mostrar diferença e bloquear erros de áreas/pesos.
3.5. Confirmar importação **uma única vez**, gravando orçamento e revisão aprovada da precificação na mesma transação.

Para importação apenas de materiais de obra já existente, **não** abrir nova precificação nem substituir histórico.

## Modelo financeiro

Não misturar `preco_base_m2` com o preço final contratado. O primeiro define o **peso relativo** da categoria. A razão entre os preços-base por m² é preservada quando se redistribui o valor contratado entre todas as categorias.

`peso_item = largura_mm × altura_mm × quantidade × preco_base_m2_categoria`.

A área física e quantidade vêm do arquivo CEM e devem ser conferidas; não assumir área estimada quando as medidas estão inválidas.

Os valores originais **separados** de fabricação e instalação são preservados do orçamento da obra. O sistema sugere sua porcentagem; ao alterar a porcentagem, redistribui o total **combinado** e registra o novo percentual/valor como precificação ajustada, não altera a referência orçamentária original.

`fabricacao_distribuida + instalacao_distribuida = fabricacao_original + instalacao_original`.

`valor_item_fabricacao + valor_item_instalacao = valor_total_item`.

A soma de todos os itens/categorias, em centavos, é **exatamente** igual aos totais calculados pelo ajuste. O motor `assets/precificacao-core.js` distribui centavos pelo maior resto com desempate por ID, sem números monetários fracionários.

**Valores/m² efetivos por categoria** derivados do total atribuído à categoria / sua área são valores **informativos arredondados para exibição**, pois a igualdade exata está nos valores inteiros das linhas. Nunca reconstruir um faturamento multiplicando um preço/m² exibido (arredondado) pela área: usar o preço individual aprovado e a fração expedida.

## Categorias e histórico

Categorias iniciais sugeridas (o administrador pode corrigir): ESQUADRIAS (janelas/portas), GUARDA-CORPO (guarda-corpo e split), GRADIL, FACHADAS e OUTROS. A sugestão lê a descrição e, futuramente, a categoria **associada ao ID da tipologia técnica**, nunca o código local `EAxx`. A pessoa pode alterar a categoria do item sem mudar os vínculos de tipologia no banco.

Proposta SQL: `database/proposals/20261122_precificacao_categorias_historico_fase1.sql`.

- `ew_precificacao_categorias`: catálogo por empresa.
- `ew_precificacao_tipologias_padrao`: vínculo de preferência, sem reclassificar obras antigas.
- `ew_precificacao_revisoes`: versão aprovada, orçamento original, distribuição ajustada, usuário/data.
- `ew_precificacao_revisoes_categorias`: foto de categorias, áreas, pesos e valores em cada versão.
- `ew_precificacao_revisoes_itens`: foto de cada item (código/descrição/linha/tipologia/área) e valores exatos.

O novo modelo **não substitui o orçamento nem o faturamento atuais** e não altera o conteúdo antigo. Uma revisão aprovada não será editada; alterações futuras geram nova versão. O código propõe políticas RLS de leitura por empresa e deixa a escrita para uma RPC futura de aprovação auditável e atômica, com checagem de permissão administrativa.

## Integração futura no faturamento

Ao faturar o marco (50%) ou as folhas (50% / número de folhas físicas), sugerir valores proporcionais ao valor **individual aprovado** de fabricação ou instalação. Não editar o preço aprovado só porque a fatura teve um preço ajustado; guardar o preço praticado na fatura, separado da referência.

Como os valores são em centavos, documentos fracionários precisam de regra determinística para ajustar o centavo remanescente no último componente, sem exceder o total contratado da esquadria nem gerar receitas automáticas.

## Relatórios futuros

A revisão deve permitir séries históricas de preço/m² por obra, tipologia, linha, categoria, volume/área e data. Não inferir causalidade a partir de diferenças de preço: fatores como complexidade, linha, composição de mão de obra e custo real exigirão registros posteriores.

Para indicadores de galpão, registrar fábrica designada, liberação, início e conclusão de fabricação, envio, funcionários equivalentes no mês, horas produtivas e custos por galpão; não confundir liberação→expedição com horas efetivas de produção.

## Pendências para tornar a versão utilizável

1. Fase 2: implementar a interface e os vínculos de categorias/valores, incluindo criação e edição de categoria, ajustes de preço, revisão por item e modalização.
2. Fase 3: criar RPC transacional integrada com importação, auditar, autenticar e testar repetição/idempotência. Aprovar proposta de esquema em ambiente de testes compatível antes de qualquer migração de produção.
3. Fase 4: integrar aos faturamentos como **sugestão** (editável), reconciliação por centavos e relatórios históricos.
4. Validar com obra de treinamento recém-importada sem apagar histórico indevidamente.

**Não excluir a obra atual apenas para desenvolver ou validar o núcleo de cálculo.**

## Atualização — etapa visual e integração preparada (22/11/2026)

- [x] Modal `assets/precificacao-importacao.js` e CSS: categorias individuais, criar/renomear/remover categorias sem itens, preço por m², percentual editável, resumos por categoria e item, comparação com orçamento original e fechamento exato.
- [x] Etapa de orçamento por níveis (`assets/orcamento-niveis.js`) encaminha obras com fabricação/instalação para a precificação, antes de qualquer gravação. Obras sem esses níveis conservam o fluxo anterior; transferências de materiais de obras existentes não abrem a etapa.
- [x] O frontend (`app.html`) chama a RPC nova `ew_importar_obra_cem_precificacao` apenas com rascunho aprovado e exige `precificacao_gravada=true` na resposta. Nada é gravado apenas por abrir a prévia.
- [x] Proposta `database/proposals/20261122_precificacao_importador_mapeamento_v469.sql`: adicionar à resposta de importação os UUIDs das esquadrias na **ordem exata do CEM**, sem confundir códigos EA repetidos. DDL original preservado em `20261122_rollback_importador_original_v469.sql`.
- [x] Proposta `database/proposals/20261122_precificacao_importacao_rpc_v469.sql`: recalcular o rateio determinístico por maiores restos **no servidor** e exigir confirmação de todos os totais, categorias, quantidades, áreas, usuário/empresa e orçamento antes de chamar a importação transacional; persistir somente depois da validação.
- [x] Testes integrados à suíte do GitHub (static integration, sintaxe JS, motor de cálculo, regressões anteriores).
- [ ] Validar DDL e execução no Supabase de **homologação compatível com produção**. Não considerar testes estáticos prova de que a RPC funciona no PostgreSQL real.
- [ ] Aplicar as 3 migrações na ordem, com backup, revisão de segurança, testes de repetição/cancelamento e plano de recuperação. **Não foram aplicadas a produção.**
- [ ] Adequar o faturamento: usar os valores individuais aprovados como sugestão editável e conciliar os **limites por categoria** com a distribuição ajustada, mantendo original contratual intacto. Sem isso, mudar 70/30 para 60/40 poderia divergir do teto financeiro legado.
- [ ] Homologar experiência em desktop/celular e importação completa com ZIP de treinamento. **Nenhuma obra foi apagada/reimportada.**

**Restrição de publicação:** o PR permanece em rascunho e não deve ser integrado à `main` antes de ter backend compatível e fluxo financeiro ajustado; caso contrário o botão final encontraria RPC inexistente.

## Atualização — integração financeira e pré-homologação de SQL

- [x] Na importação, esquadrias são exibidas **agrupadas por categoria**, com transferência individual entre elas; categorias e preços são editáveis no rascunho.
- [x] `finLoad` busca a revisão aprovada mais recente, os preços individuais e os subtotais históricos por categoria, com consulta restrita à empresa/obra.
- [x] Financeiro apresenta tabela histórica por categoria: área, preço-base/m², fabricação, instalação e preço efetivo por m². Os valores originais do orçamento são mantidos separados dos ajustados.
- [x] O formulário de faturamento sugere automaticamente **preços distintos** para fabricação e instalação, calculados do preço aprovado de cada item dividido pela quantidade original. A sugestão continua editável. Para a última fração, considera o valor já faturado para evitar perda de centavos.
- [x] Limites exibidos e validados pela interface seguem a revisão aprovada (fallback para orçamento original nas obras sem revisão).
- [x] `20261122_precificacao_tetos_faturamento_v469.sql`: proposta de alteração da RPC financeira preservando todas as permissões, exigência de instalação e limites por quantidade/romaneios; altera apenas o teto para usar a distribuição aprovada, sem afetar obras antigas.
- [x] Operação de importação agora tem ID e hash do conteúdo na revisão, protegidos por restrição única e trava transacional. Repetição com o mesmo conteúdo devolve a mesma obra; reutilização com dados diferentes é rejeitada.
- [x] **Ensaio SQL transacional** em produção (criação de cinco tabelas e compilação das rotinas, seguida de ROLLBACK, sem persistir dados); verificação após ensaio confirmou zero tabelas de precificação em produção.
- [x] CTE de rateio testada em consulta somente leitura: 3 itens distribuídos em R$ 55.000,00 de fabricação e R$ 45.000,00 de instalação, com soma exata de R$ 100.000,00.
- [x] Testes automáticos de regressão, incluindo cálculo com 75% do EA2, revisão aprovada, tetos, edição manual, agrupamento e idempotência, passaram no GitHub Actions.

**Permanece pendente:** homologação em banco independente com autenticação real, permissões e RLS por empresa, importação de obra de teste e faturamento/cancelamento ponta a ponta. O ensaio transacional verifica estrutura e compilação, **não** substitui isso. Somente depois fazer migração de produção (com backup), revisão final do PR e publicação da interface. O ambiente de produção continua na v46.8 e a obra existente não foi removida.
