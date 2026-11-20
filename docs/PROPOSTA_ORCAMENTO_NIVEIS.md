# EWGEST — Alteração proposta: orçamento por níveis na importação

**Status:** implementação em branch para revisão, **não implantada**. Base do trabalho: `feature/orcamento-por-niveis-cem`.

## Pedido do responsável

- A ação de conferência da nova obra passa a indicar **Próxima etapa**, sem importar ainda.
- Na etapa seguinte, permitir adicionar/remover linhas, escolher nível, valor, percentual automático, empresa comercial e indicação de faturamento.
- Criar catálogos reutilizáveis de níveis e empresas comerciais por empresa usuária do EWGEST.
- A obra e os novos cadastros serão efetivados somente após a confirmação final.

## Regras previstas no protótipo

1. Soma de todos os valores dos níveis deve igualar **100% do valor total da obra**, inclusive os níveis assinalados somente para controle de gastos. Esta interpretação precisa de aceite do responsável.
2. Valor por nível = dinheiro positivo ou zero, com centavos; total da obra deve ser positivo.
3. Cada nível possui nome, grupo financeiro de compatibilidade (alumínio, acessórios, vidros, outros, fabricação, instalação), empresa comercial, valor e `faturar`.
4. A empresa comercial da linha **não é** a organização autenticada na plataforma (tabela `empresas`).
5. A importação grava orçamento resumido legado e linhas detalhadas em uma **única transação**. O formato legado de seis valores ainda é aceito na RPC.
6. Novos registros de catálogos são realizados junto com a importação final; apenas clicar em “Adicionar” na conferência não grava nada.
7. Orçamentos de obras antigas seguem sem detalhamento de níveis até que haja um processo próprio de migração.

## Arquivos envolvidos

- `app.html`: modal de níveis, novos campos e exibição de níveis no resumo financeiro.
- `assets/orcamento-niveis.js`: captura da etapa de valores, edição e validação das linhas, leitura de catálogos.
- `assets/orcamento-niveis.css`: tabela adaptativa e edição dos níveis.
- `database/proposals/2026-11-20_orcamento_niveis.sql`: **proposta ainda não aplicada**. Cria catálogos, relação obra-níveis, RLS, compatibilidade da RPC de importação e proteção do teto de fabricação/instalação para níveis não faturáveis.

## Limitações explícitas

- O **faturamento efetivo** hoje registra por esquadria apenas fabricação ou instalação. Marcar outros níveis como faturáveis guarda intenção, mas **não habilita emissão de notas por esses níveis** nesta versão.
- O controle real de despesas mantém os grupos antigos. Evoluir despesas e faturamentos para nível individual e empresa faturadora requer um fluxo adicional.
- O ambiente `ewgest-restauracao-teste` estava pausado na última verificação. **Não utilizar produção como substituto de testes.**
- Não houve execução de SQL em produção, nem criação de obra, nem validação do fluxo real de importação.

## Ordem obrigatória para implantação após aprovação

1. Confirmar a interpretação da soma de 100% com níveis apenas de gastos e discutir o futuro faturamento por nível.
2. Preparar backup verificável e ambiente de teste (incluindo permissões).
3. Revisar e testar o SQL proposto em ambiente isolado. Analisar grants/RLS e impacto da RPC atual.
4. Validar EWGEST no ambiente de testes: importação de nova obra, lançamentos, catálogos, estorno em falha, acesso de outros perfis e reimportação de obra existente.
5. Aplicar a estrutura aprovada ao banco de produção em janela controlada.
6. Somente depois publicar a interface correspondente na hospedagem. Verificar /app, importação, financeiro e responsividade.
7. Registrar resultado no PR. Não declarar implantado antes de conferir a produção.

## Checklist de regressão pendente

- [ ] Importação de obra nova com níveis múltiplos e empresas distintas
- [ ] Soma divergente de 100% rejeitada sem cadastrar obra
- [ ] Nível marcado só para gastos não permite faturamento de fabricação/instalação indevido
- [ ] Importação antiga de seis categorias permanece compatível
- [ ] Obra existente só importa materiais e não duplica esquadrias/orçamento
- [ ] Registros de outra empresa não aparecem no catálogo
- [ ] Usuário sem perfil ADM não consegue incluir níveis ou orçamento
- [ ] Resumo financeiro mostra os níveis corretos e preserva os lançamentos antigos
- [ ] Falhas de rede não geram importações duplicadas
- [ ] Verificação visual no desktop e no celular
- [ ] SQL e frontend passam por validação real em teste antes da produção

## Registro compartilhado

Antes de prosseguir, qualquer outra IA deve consultar `AGENTS.md`, `CLAUDE.md` quando pertinente, o histórico dos commits desta branch e o Pull Request. Evitar editar os mesmos trechos de `app.html` sem combinar.
