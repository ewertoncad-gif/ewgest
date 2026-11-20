# EWGEST — Orçamento por níveis na importação — registro de implantação

**Status (20/11/2026):** SQL aplicado ao **Supabase de produção**; código integrado à **`main`** no PR #13 (commit `cb382772`). **Publicação efetiva na hospedagem e testes com usuário real ainda não puderam ser verificados por este ambiente.**

## Pedido do responsável

- A ação de conferência da nova obra passa a indicar **Próxima etapa**, sem importar ainda.
- Na etapa seguinte, permitir adicionar/remover linhas, escolher nível, valor, percentual automático, empresa comercial e indicação de faturamento.
- Criar catálogos reutilizáveis de níveis e empresas comerciais por empresa usuária do EWGEST.
- A obra e os novos cadastros serão efetivados somente após a confirmação final.

## Regras implementadas

1. **Níveis 100% opcionais e escolhidos pelo usuário:** nenhuma categoria é obrigatória. Uma obra pode ter somente ACM, somente Manutenção, ou qualquer combinação de níveis novos e já cadastrados. A soma **apenas das linhas selecionadas** deve igualar **100% do valor total da obra**, inclusive níveis marcados somente para controle de gastos. Regra confirmada pelo responsável.
2. Valor por nível = dinheiro positivo ou zero, com centavos; total da obra deve ser positivo. **Não pré-criar linhas** de alumínio, componentes ou vidros na obra; iniciar com uma única linha vazia para escolha e permitir adicionar/remover livremente.
3. Cada nível possui nome livre, grupo financeiro **interno de compatibilidade** (alumínio, acessórios, vidros, outros, fabricação, instalação), empresa comercial, valor e `faturar`. Exemplos novos: **ACM, Manutenção, Limpeza**. O grupo interno é uma limitação dos relatórios legados; um novo nível personalizado ficará vinculado por padrão a **Outros**, sem renomear sua identificação comercial. **Não apresentar Outros como se fosse o nível escolhido pelo usuário.** A futura contabilização individual por nível requer evolução do módulo financeiro.
4. A empresa comercial da linha **não é** a organização autenticada na plataforma (tabela `empresas`).
5. A importação grava orçamento resumido legado e linhas detalhadas em uma **única transação**. O formato legado de seis valores ainda é aceito na RPC.
6. Novos registros de catálogos são realizados junto com a importação final; apenas clicar em “Adicionar” na conferência não grava nada.
7. Orçamentos de obras antigas seguem sem detalhamento de níveis até que haja um processo próprio de migração.

## Arquivos envolvidos

- `app.html`: modal de níveis, novos campos e exibição de níveis no resumo financeiro.
- `assets/orcamento-niveis.js`: captura da etapa de valores, edição e validação das linhas, leitura de catálogos.
- `assets/orcamento-niveis.css`: tabela adaptativa e edição dos níveis.
- `supabase/migrations/20261120223000_orcamento_niveis_e_empresas.sql`: migração versionada e **aplicada à produção** como `orcamento_niveis_empresas_20261120`; tabelas, RLS, RPC e proteção do teto de faturamento.
- `database/rollback/20261120_funcao_importacao_financeira_anterior.sql`: definição anterior da RPC preservada. **Não é backup completo do banco.**
- `database/proposals/2026-11-20_orcamento_niveis.sql`: registro da proposta original aprovada.

## Limitações explícitas

- O **faturamento efetivo** hoje registra por esquadria apenas fabricação ou instalação. Marcar outros níveis como faturáveis guarda intenção, mas **não habilita emissão de notas por esses níveis** nesta versão.
- O controle real de despesas mantém os grupos antigos. Evoluir despesas e faturamentos para nível individual e empresa faturadora requer um fluxo adicional.
- O ambiente `ewgest-restauracao-teste` foi reativado e recebeu **estruturas de suporte simuladas** porque ainda não possuía o módulo financeiro atual. Os ensaios não equivalem a uma restauração integral da produção.
- SQL foi aplicado em produção **sem importar obras** e o orçamento anterior permaneceu preservado. Não foi realizada importação com ZIP real no navegador; essa validação continua pendente.

## Implantação realizada e verificações restantes

1. **Concluído:** níveis livres conforme escolha do usuário; flag faturamento começa desmarcada; soma de todas as linhas deve atingir 100%.
2. **Concluído em banco de testes com estruturas simuladas:** gravação de níveis personalizados e empresas, soma válida, rejeição de soma inválida, formato legado e teste de RLS de usuário autorizado/não vinculado, sempre com rollback dos registros fictícios.
3. **Concluído:** revisão e aplicação da migração ao banco de produção; verificação de três tabelas novas, seis políticas e preservação do orçamento já existente.
4. **Concluído:** integração do frontend na `main` e testes automatizados do GitHub aprovados.
5. **Pendente:** confirmar publicação na hospedagem e validar o fluxo visual com ZIP real e usuário autorizado.
6. **Pendente:** teste integral do banco com cópia atual e backup/restauração completo. O projeto de teste era anterior ao módulo financeiro, portanto **não foi homologação de produção**.
7. **Futuro:** evolução do faturamento individual para todos os níveis personalizados, além de fabricação/instalação.

## Checklist de regressão pendente

- [x] Ensaio transacional da importação com níveis múltiplos e empresas distintas em banco de teste simulado
- [x] Soma divergente de 100% rejeitada sem cadastrar obra (ensaio em banco de testes)
- [ ] Nível marcado só para gastos não permite faturamento de fabricação/instalação indevido
- [x] Importação antiga de seis categorias permanece compatível (ensaio em banco de testes)
- [ ] Obra existente só importa materiais e não duplica esquadrias/orçamento
- [x] Usuário sem vínculo à empresa não visualiza níveis do catálogo (ensaio de RLS)
- [x] Chamada da RPC sem perfil ADM não permite importação (ensaio em banco de testes)
- [ ] Resumo financeiro mostra os níveis corretos e preserva os lançamentos antigos
- [ ] Falhas de rede não geram importações duplicadas
- [ ] Verificação visual no desktop e no celular
- [x] Migração SQL aplicada em teste e produção; testes automatizados estáticos do frontend aprovados (não substitui teste de ponta a ponta).

## Registro compartilhado

Antes de prosseguir, qualquer outra IA deve consultar `AGENTS.md`, `CLAUDE.md` quando pertinente, o histórico dos commits desta branch e o Pull Request. Evitar editar os mesmos trechos de `app.html` sem combinar.
