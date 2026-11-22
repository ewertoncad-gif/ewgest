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
