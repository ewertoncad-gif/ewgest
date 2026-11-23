# EWGEST v46.20 — Níveis 01 a 08 e permissões por flags

## Regras de acesso

Cada empresa recebe uma matriz independente de oito níveis, com 28 flags agrupadas em **Navegação, Obras, Liberação, Romaneios, Estoque, Financeiro, Cadastros e Administração**.

| Nível | Papel inicial | Regra padrão |
|---|---|---|
| 01 | Administrador (EWERTON) | Todas as 28 flags, **protegido** para não bloquear o ADM |
| 02 | Gerência (HANANI, HIGOR) | Gestão geral; edita contas 03–08 se a flag estiver ativa; sem reconfigurar matriz nem cancelar financeiro por padrão |
| 03 | Técnico | Consultar obras, liberar fabricação, consultar romaneios, cadastros e relatórios operacionais |
| 04 | Almoxarifado (EDINHA, MARCIO) | Consulta de obras, recebimento, baixa, transferências e emissão de romaneios |
| 05 | Financeiro | Faturamento, despesas, cancelamentos e relatórios financeiros |
| 06 | Consulta completa | Navegação e relatórios operacionais **e financeiros**, sem alteração |
| 07 | Consulta operacional | Navegação, relatórios operacionais, sem financeiro, sem alteração |
| 08 | Sem permissão | Todas as flags desligadas (consegue apenas fazer login e acessar a própria senha) |

Todos os níveis 02–08 são editáveis via **Cadastros do sistema → Usuários → Níveis de acesso** somente por nível 01. Cada alteração gera histórico em `ew_niveis_auditoria`. Usuários apontam para o número do nível e **não** guardam flags copiadas; uma mudança passa a valer imediatamente no servidor para todos do nível. Recarregar página para menus refletirem alterações.

## Segurança e compatibilidade

- `ew_pode` verifica banco com conta ativa, membership compatível, nível e sessão atuais.
- `ew_exigir_permissao` é usado nas 47 principais rotinas RPC de escrita: obra, liberação, romaneio, estoque e financeiro. Os antigos testes de perfil são preservados quando compatíveis e substituídos por flag em pontos necessários a níveis 03/04/05.
- RLS limita leitura de dados financeiros a `financeiro.consultar` **ou** `relatorios.financeiros`. Nível 07 não possui nenhuma das duas por padrão.
- RLS restringe dados operacionais segundo as flags, e cadastro de usuários só ao próprio usuário ou a quem tem permissão de gestão/auditoria/relatório operacional.
- Edge Function `ewgest-acesso` deriva o perfil de compatibilidade do nível solicitado **no servidor**. Somente nível 01 pode criar/atribuir níveis 01 e 02; nível 01 protegido contra arquivamento/alteração por não ADM. A gestão de usuários exige a flag, não apenas um nome de perfil.
- O ADM Nível 01 não pode alterar sua própria classificação para evitar perda de acesso. Não enviar credenciais ou service-role key à interface.
- Nível 08 não possui autorização de leitura operacional, mesmo se digitar a URL do PostgREST.
- RLS/PRCs continuam funcionando para contas desativadas/excluídas e identidades inválidas com a sessão atual.

## Operação de liberação

A página de usuário possui seletor de nível 01–08. Na edição, alterar o nível e salvar. Depois usar a matriz para ativar/desativar as flags. Não é preciso alterar código para mudar o conjunto de atividades da matriz. As permissões são a fonte da verdade; a UI serve para exibir, não para autorizar.

## Arquivos e recuperação

- `database/proposals/20261122_niveis_acesso_v4620.sql`: estrutura, níveis, 28 flags e RPCs
- `database/proposals/20261122_niveis_guardas_rpc_v4620.sql`: verificações de 47 rotinas
- `database/proposals/20261122_niveis_rls_v4620.sql`: RLS dos dados de alto valor
- `database/rollback/20261122_pre_v4620_funcoes.sql`: snapshot do código original das funções, **apenas para incidentes**. Reinstalação indiscriminada das funções antigas desfaz as proteções de níveis, portanto exige análise e manutenção da trilha de auditoria.

## Testes

Banco staging antigo não possui todas as tabelas financeiras, portanto migração da estrutura e teste de flags feitos em staging, e **compilação conjunta das três migrações verificada na estrutura real de produção com `BEGIN...ROLLBACK`**, sem aplicar dados nem executar movimentações. Teste de regras em staging `tests/niveis_v4620/teste_staging.sql` aprovado: nível 01 protegido, 07 sem financeiro, níveis e 28 flags e consulta não altera matriz.

**Homologar no navegador em obra de treinamento**, usando ADM e conta específica de cada nível: alteração em matriz, relogin, acesso aos relatórios, negar RPC de escrita, edição segura, nome do responsável no histórico. Não testar com estoque ou documentos financeiros reais.
