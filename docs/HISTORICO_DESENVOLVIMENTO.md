# EWGEST — Histórico compartilhado de desenvolvimento

Este é o **ponto de entrada** que ChatGPT, Claude e os desenvolvedores devem consultar antes de mexer no EWGEST. O registro oficial e atualizado fica no **histórico do próprio GitHub**, não em uma conversa isolada.

## Onde acompanhar as alterações de verdade

| Fonte | Link | Para que serve |
|---|---|---|
| Tarefas e decisões | [Issues](https://github.com/ewertoncad-gif/ewgest/issues) | Registrar pedidos, responsável, riscos, decisões e aceite |
| Alterações em andamento | [Pull Requests abertos](https://github.com/ewertoncad-gif/ewgest/pulls?q=is%3Apr+is%3Aopen) | Ver exatamente o que cada pessoa está modificando antes de integrar |
| Alterações integradas | [Pull Requests concluídos](https://github.com/ewertoncad-gif/ewgest/pulls?q=is%3Apr+is%3Amerged) | Histórico revisável das alterações integradas via PR |
| Todas as alterações da branch principal | [Commits da main](https://github.com/ewertoncad-gif/ewgest/commits/main/) | Inclui alterações diretas que não passaram por PR |
| Regras comuns | [AGENTS.md](../AGENTS.md) | Regras compartilhadas das IAs e dos desenvolvedores |
| Instruções do Claude | [CLAUDE.md](../CLAUDE.md) | O Claude deve seguir as mesmas regras |

**Importante:** esta página é um índice; ela **não se atualiza com resumos escritos automaticamente**. Os links acima abrem as fontes atualizadas do GitHub. Se alguém fizer alterações sem PR, elas aparecerão nos commits, mas poderão não ter o contexto de testes e decisões. Por isso o PR é o registro preferido.

## Rotina para os três desenvolvedores

1. **Antes:** ler `AGENTS.md` e este índice; consultar commits recentes, PRs abertos e issues. Quem usa Claude também deve ler `CLAUDE.md`.
2. **Distribuir:** uma tarefa por issue, com responsável definido; avisar quando a mudança afeta módulos ou arquivos em uso por outra pessoa.
3. **Desenvolver:** atualizar cópia local, trabalhar em branch individual (`feature/<assunto>` ou `fix/<assunto>`) e executar testes relevantes. A `main` é a referência oficial, não um espaço compartilhado de testes.
4. **Registrar:** abrir PR para `main`; o GitHub preenche o modelo em `.github/PULL_REQUEST_TEMPLATE.md`. Informar objetivo, arquivos/tabelas, riscos, testes, mudanças no Supabase e rollback.
5. **Revisar:** responsável pelo EWGEST revisa e autoriza a integração e eventual publicação, principalmente quando envolve dados reais.
6. **Depois:** outra IA lê o PR e os commits atualizados antes de iniciar ou continuar sua tarefa.

## Padrão de resumo rápido para um colega

```text
EWGEST | Atualização de desenvolvimento
Pessoa / IA:
Issue:
Branch / PR / commit:
O que mudou:
Arquivos e tabelas afetados:
Testes feitos (ou não feitos):
Há alteração no banco? Foi aplicada onde?
Riscos para outros módulos:
Status: proposto / em desenvolvimento / aguardando revisão / integrado / publicado
```

## Proteção de dados, sincronização e limitações

- **Nunca enviar** tokens, senhas, secrets, chaves administrativas ou dados pessoais para issues, PRs ou arquivos.
- **Não aplicar SQL perigoso em produção** sem aprovação e validação adequadas. Migrar o banco não é o mesmo que alterar o código.
- Os três assistentes **não se comunicam automaticamente** entre plataformas; cada um precisa abrir GitHub, ler os registros novos e trabalhar com o estado real dos arquivos.
- A existência destes modelos **não obriga tecnicamente** ninguém a abrir PR e **não bloqueia** commits diretos na `main`. Proteção de branch, revisões obrigatórias, backups e deploy controlado exigem configuração separada.
- Se o ambiente de testes estiver indisponível, não usar produção como substituto e declarar os testes pendentes.
- Ao trabalhar no extenso `app.html`, evitar alterações paralelas nos mesmos trechos.

## Arquivos que configuram este processo

- `AGENTS.md` — regras compartilhadas.
- `CLAUDE.md` — orientações do Claude.
- `.github/ISSUE_TEMPLATE/tarefa.md` — formulário de abertura de tarefa.
- `.github/PULL_REQUEST_TEMPLATE.md` — formulário de registro/revisão de alteração.
- `docs/HISTORICO_DESENVOLVIMENTO.md` — este índice.

**Objetivo:** qualquer IA ou desenvolvedor consegue identificar quem alterou o quê, por quê, se foi testado, e o que pode afetar o trabalho dos outros, consultando os registros atuais do repositório.
