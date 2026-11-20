# EWGEST — Instruções para Claude

Este arquivo orienta o uso do **Claude Code** e de outros assistentes Claude no repositório privado `ewertoncad-gif/ewgest`.

## Instrução principal: ler as regras compartilhadas

**Antes de trabalhar, leia integralmente `AGENTS.md` na raiz do repositório e siga suas regras.** Ele é a referência comum para os três desenvolvedores e suas IAs (ChatGPT, Claude e outras).

Se estiver usando Claude em uma conversa sem acesso ao repositório, peça ao desenvolvedor para conectar o GitHub ou fornecer o conteúdo atualizado de `AGENTS.md`. **Não afirme que leu o arquivo sem tê-lo acessado.**

Havendo divergência entre orientações, implementação real e pedidos do usuário, explique o conflito e peça decisão antes de agir. Este documento complementa, mas não substitui, `AGENTS.md`.

## Rotina obrigatória antes de cada tarefa

1. Confirmar repositório, branch atual e se há mudanças locais não commitadas; sincronizar com o remoto sem sobrescrever trabalho existente.
2. Ler `AGENTS.md`, revisar commits recentes, pull requests e issues relevantes; consultar documentação de alterações compartilhadas que existir no repositório.
3. Identificar os arquivos e funções envolvidos, além das dependências. O aplicativo usa atualmente `app.html` para grande parte da interface; esse arquivo exige atenção especial a edições simultâneas.
4. Confirmar com o solicitante escopo, regra de negócio e critérios de aceite quando houver ambiguidade.
5. Trabalhar em **branch própria**, sem editar diretamente a `main` ou publicar em produção por conta própria.
6. Implementar mudanças pontuais; não reformular telas ou fluxos fora do escopo e não apagar histórico de dados.
7. Testar os fluxos alterados e os relacionados, registrando o que foi de fato executado e os testes pendentes.
8. Abrir pull request para revisão humana, explicando riscos e plano de reversão.

## Supabase e segurança

- **Produção (`ewgest-producao`) não é ambiente de testes.** O ambiente `ewgest-restauracao-teste` pode não estar disponível; verificar antes de usá-lo.
- Consultar o esquema real e permissões antes de sugerir ou executar SQL. Não realizar alterações destrutivas, migrações ou mudanças de RLS/grants em produção sem autorização específica.
- Versionar propostas de migração SQL no GitHub e registrar onde foram aplicadas. Separar claramente propostas de alterações efetivamente executadas.
- Nunca compartilhar nem publicar senhas, tokens, secrets, `service_role`, connection strings secretas ou documentos fiscais completos.
- Usar o menor privilégio necessário e preservar auditoria, saldos de estoque, faturamentos e integridade das obras.

## Comunicação obrigatória com as outras IAs

Cada tarefa deve deixar um registro verificável **no GitHub**, preferencialmente em issue e pull request. Usar este formato:

```text
EWGEST — REGISTRO DE ALTERAÇÃO
Objetivo:
Responsável:
Branch / commits:
Arquivos ou módulos alterados:
Banco (tabelas/funções/migrações; aplicado em teste/produção ou apenas proposto):
Riscos e funcionalidades relacionadas:
Testes executados e resultados:
Testes pendentes:
Rollback / como reverter:
Próximo passo:
```

Ao iniciar outro trabalho, consultar os registros atualizados, inclusive os feitos pelos colaboradores que utilizam ChatGPT. **Não presumir comunicação automática, memória compartilhada entre plataformas nem atualização em tempo real.**

Se a tarefa coincidir com a de outro desenvolvedor, informar o conflito e combinar a divisão antes de modificar os mesmos trechos.

## Critério de conclusão

Ao responder que terminou uma tarefa, informe o commit ou PR, exatamente o que mudou, como foi validado, quais limites permanecem e se houve implantação. **Nunca apresentar código alterado como produção implantada, nem testes não executados como aprovados.**

Para decisões sensíveis sobre segurança, dados reais, publicação e prioridades, solicitar a aprovação do responsável pelo EWGEST.
