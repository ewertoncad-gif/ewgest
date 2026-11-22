# Homologação operacional — EWGEST v46.9

**Estado:** PR #64 em rascunho. **Não executar importações de teste na produção.** A execução dos scripts SQL em `BEGIN ... ROLLBACK` no banco de produção testou sintaxe/compatibilidade, **não** a importação ponta a ponta.

## Pré-requisitos para prosseguir

- [ ] Aprovação expressa do custo de um ambiente isolado, após orçamento do Supabase: o custo consultado em 22/11/2026 para uma ramificação (Micro) é **US$ 0,01344/h de computação**, sujeito a outros itens de uso. Não criar sem consentimento.
- [ ] Ramificação de desenvolvimento criada do projeto `ewgest-producao`, **sem dados de produção** por padrão. Não usar projeto de restauração defasado como prova de compatibilidade.
- [ ] Verificar existência e possibilidade de restaurar backup real de produção antes de migrar. Não assumir backup apenas porque o painel apresenta um serviço.
- [ ] Identificar versão das migrações e estado dos dados (obras/importações já cadastradas). Coletar evidências de segurança/ACL/RLS.
- [ ] Criar usuário, empresa e sessão de teste **somente no ambiente isolado**. Não utilizar identidades de produção.

## Ordem de migração — apenas na ramificação isolada

1. `database/proposals/20261122_precificacao_categorias_historico_fase1.sql` — categorias, padrões, revisões imutáveis, snapshot por item e RLS.
2. `database/proposals/20261122_precificacao_importador_mapeamento_v469.sql` — adiciona o vetor `esquadrias_ids` à resposta de importação, sem mudar os resultados antigos.
3. `database/proposals/20261122_precificacao_importacao_rpc_v469.sql` — nova RPC transacional, autorização ADM, validação server-side, idempotência `operacao_id`+hash, gravação histórica.
4. `database/proposals/20261122_precificacao_tetos_faturamento_v469.sql` — tetos de fabricação/instalação seguem a última revisão aprovada; obras legadas seguem orçamento original.

Nunca publicar `app.html` v46.9 antes da instalação validada de todos os quatro componentes. Se houver falha de migração, não continuar até obter uma reversão/solução segura.

## Cenários obrigatórios na homologação

| Cenário | Resultado esperado |
|---|---|
| Nova obra com 2 categorias, janela + guarda-corpo | Obra + orçamento + revisão + categorias + itens gravados juntos |
| Orçamento R$ 70 mil / R$ 30 mil, usuário muda para 55%/45% | Fab R$ 55 mil, instalação R$ 45 mil, mesma soma global R$ 100 mil |
| Categoria alterada somente na obra | Catálogo padrão de tipologia permanece intacto |
| `Usar depois` marcado para tipologia única | Preferência atualizada para novas obras; snapshots antigos inalterados |
| Mesmo código técnico EA repetido no ZIP | Itens distintos vinculados pelos UUIDs na ordem do CEM; preço correto em cada item |
| Repetir mesma `operacao_id` e payload | Mesma obra/revisão, sem registros duplicados |
| Reutilizar `operacao_id` com payload alterado | Erro e nenhuma nova obra/revisão |
| Arquivo com categoria sem preço, área 0 ou nível não faturável | Operação rejeitada sem qualquer gravação |
| ADM da empresa A tentando gravar obra da B | Operação rejeitada; nenhum vazamento de dados |
| Visitante, almoxarife ou sessão inválida | Gravação e leitura financeira privilegiada negadas |
| Faturar 50% marco + 25% uma folha (2F) | Sugestão 75% de fabricação **ou** instalação, independentes, dentro do teto ajustado |
| Faturar mais que 100% expedido, ou acima do teto financeiro | Bloqueio pela RPC; nenhuma fatura gravada |
| Cancelar romaneio e tentar faturar fração sem saída ativa | Bloqueio |
| Fatura anterior e valor alterado manualmente | Histórico da fatura preservado; preço aprovado não sobrescrito |
| Uma esquadria sem snapshot, categoria divergente ou soma de itens incorreta | Financeiro bloqueia o lançamento e aponta necessidade de correção |
| Erro na última inserção da revisão (FK/constraint) | PostgreSQL desfaz **toda** a obra/orçamento/estoque previsto da transação |

Além do resultado das tabelas, confirmar a resposta JSON, o log de auditoria e o comportamento dos RLS e GRANT, usando credenciais/teste por perfil no ambiente isolado.

## Faturamento histórico e centavos

- Preço-base/m² por categoria é **peso comercial**; os valores individuais em centavos, congelados na revisão, prevalecem.
- As áreas e preços/m² apresentados no painel são informativos e arredondados; nunca usar o preço/m² exibido para recompor a fatura.
- O total de fabricação/instalação por item e por categoria deve fechar exatamente com a distribuição aprovada.
- Preços ajustados manualmente em uma fatura não alteram a referência contratual original.
- Em mudança futura de revisão, verificar que o novo teto não fique abaixo de valores já faturados; exigir conciliação antes de novos lançamentos.

## Critério para publicar

Só marcar PR #64 como pronto e fundir à `main` quando:
1. Migrações homologadas e consultas de integridade 100% aprovadas.
2. Teste autenticado da RPC de importação de obra concluído no ambiente isolado.
3. Limites do Financeiro aprovados também no servidor para obras novas e antigas.
4. Auditoria e ausência de alterações em estoque físico confirmadas.
5. Backup e procedimento de rollback de produção validados.
6. GitHub Actions passando no commit final.

**Após testes e com autorização prévia de cobrança:** excluir a ramificação temporária para interromper custo de computação. Nunca usar `merge_branch` automaticamente para produção: migrar scripts revisados e versionados um por vez, registrar verificações e só depois publicar o frontend.

## Evidências existentes (sem dados reais)

- PR #64 contém testes de mais de 220 distribuições, teste de interface com VM, fluxo de classificação e sugestões financeiras.
- Migrações compiladas dentro de transação revertida em produção; isso não exerce permissões autenticadas nem estado persistente.
- Projeto `ewgest-restauracao-teste` tem apenas 35 tabelas públicas contra 59 em produção e não serve como ambiente compatível sem sincronização completa.
- Changelog Supabase de 16/11/2026: a mesclagem de branch via API/MCP passou a exigir permissão explícita de escrita em produção — evitar automatizar essa etapa.


## Resultado real da homologação isolada (22/11/2026)

**Supabase Branching indisponível neste projeto:** a solicitação de criar
\`homologacao-v469-precificacao-20261122\` foi recusada pelo Supabase com:
\`PaymentRequiredException: Branching is supported only on the Pro plan or above\`.
O ID de confirmação de custo havia sido autorizado, mas **nenhuma ramificação foi criada**,
**nenhum upgrade foi solicitado** e **nenhuma nova cobrança horária de ramificação foi iniciada**.

**Alternativa executada sem Supabase adicional:** nova GitHub Action
\`.github/workflows/homologar-precificacao-v469.yml\`, com serviço
\`postgres:17\` descartável em runner isolado. Os testes usam apenas
identidades/obras fictícias declaradas em:
- \`tests/homologacao_pg17/00_fixture_minima.sql\`: empresas, usuários, tipologias,
  obras, esquadrias, orçamento e **stub explicitamente identificado** para a RPC
  pré-existente \`ew_importar_obra_cem_financeiro\`.
- \`tests/homologacao_pg17/05_fixture_faturamento.sql\`: tabelas mínimas
  para executar a **RPC real** de faturamento, com perfis simulados.
- \`tests/homologacao_pg17/10_cenarios.sql\`: executa a nova RPC **real**
  \`ew_importar_obra_cem_precificacao\` sobre a fixture e comprova:
  orçamento original de 70/30, distribuição aprovada 60/40, histórico por
  categoria/esquadria/ID, opção explícita de tipologia padrão, idempotência,
  rejeição de payload modificado e centavos adulterados, RLS para almoxarifado,
  permissão administrativa e imutabilidade das revisões aprovadas.
- \`tests/homologacao_pg17/20_faturamento_real.sql\`: executa a **RPC real**
  \`ew_registrar_faturamento_financeiro\`, cobrando 75% após saída de
  marco + uma folha física; respeita limite de fabricação de 60%, instalação
  de 40% e confirmação explícita de instalação; aceita preço editado sem mudar
  histórico; rejeita exceder área expedida, tetos financeiros, item sem
  preço aprovado e perfil de almoxarifado. Confirma fallback para obra legada
  sem revisão de precificação.

**Defeito corrigido pelo teste real:** a soma da área dos itens no
\`INSERT INTO ew_precificacao_revisoes\` não usava alias de coluna JSONB.
Foi corrigido em \`20261122_precificacao_importacao_rpc_v469.sql\`; compilar
o DDL sem executar a função não detectava o defeito.

**Proteção adicional implementada:** a RPC financeira agora verifica no
servidor a existência da esquadria na última revisão aprovada, com
quantidade coerente, antes de faturar. Os snapshots passaram a exigir
\`esquadria_id NOT NULL\` e unicidade \`(revisao_id,esquadria_id)\`.
Obras sem revisão continuam com comportamento legado.

**Resultado final:** [GitHub Actions #45020195584](https://github.com/ewertoncad-gif/ewgest/actions/runs/45020195584)
com **sucesso** no commit \`72b0e9d7b\`.

### Cobertura e limites — não confundir com homologação Supabase completa

A Action exerce SQL verdadeiro em PostgreSQL 17, incluindo as funções novas e
a função financeira, mas a **RPC legada de importação é um stub com contrato
mínimo**, e autenticação/sessões são emuladas por variáveis de configuração
Postgres. Ainda faltam:
1. Exercitar a RPC real pré-existente de importação com suas dependências,
   fluxo de materiais/estoque previsto e relação com obra/financeiro.
2. Executar a importação pelo REST/PostgREST, com sessão real do Supabase,
   papéis, permissões, RLS e leituras isoladas por empresa.
3. Homologar execução no esquema completo da produção, backup e
   plano de recuperação antes de aplicar novas migrações permanentes.
4. Revisar o PR #64 para merge/publicação, garantindo que as migrações
   antecedam a interface e que não se quebrem obras já cadastradas.

**Não criar nem pagar por um ambiente adicional sem nova autorização específica.**
**Não aplicar migrações permanentemente em produção apenas com esta evidência.**


### Revisão adicional: proteção de saldo e cancelamento

- A RPC de faturamento passou a exigir **no servidor** que a esquadria conste na revisão aprovada e que a quantidade continue coerente, mesmo quando alguém chama a API diretamente, sem passar pela interface.
- A tabela de itens do histórico agora exige `esquadria_id` não nulo e proíbe duplicação do mesmo item numa revisão.
- Testes específicos no PostgreSQL isolado comprovaram que **um item expedido sem preço aprovado é rejeitado**, uma obra sem precificação continua seguindo as regras legadas e **romaneios cancelados não permitem faturar**.
- **Última execução verde:** [GitHub Actions #45020360348](https://github.com/ewertoncad-gif/ewgest/actions/runs/45020360348), incluindo as regressões de importação, faturamento, autorização e cancelamento.

As ressalvas sobre a RPC legada simulada e autenticação Supabase real continuam válidas.


## Ampliação de cobertura — 22/11/2026, continuação

No PostgreSQL 17 descartável, `tests/homologacao_pg17/15_casos_criticos.sql`
adiciona verificações de:
- **Mesmo código EA repetido:** duas linhas de CEM com código igual precisam receber UUIDs diferentes, manter `indice_importacao` e seus preços/snapshots individuais.
- **Falha tardia + atomicidade:** categorias padrão conflitantes na mesma tipologia provocam erro **após o início da gravação**, sem deixar obra, revisão ou esquadria extra; o teste compara contagens antes/depois.
- **RLS multiempresa:** ADM da empresa fictícia B não enxerga categorias/revisões da A nem pode importar no nome da A.
- **Sem sessão:** chamada sem `auth.uid()` é rejeitada.

O script inicia uma transação externa e faz `ROLLBACK` após os cenários,
não deixando obras fictícias adicionais nem na própria fixture. O GitHub
Actions executa esse arquivo **entre** os cenários de importação e os de
faturamento.

**Evidência do commit `e2122e5f`:** [homologação isolada #45020664258](https://github.com/ewertoncad-gif/ewgest/actions/runs/45020664258)
concluída com **success**. As verificações gerais do EWGEST também passaram.

**Atenção:** esta ampliação confirma o comportamento da RPC nova em PostgreSQL
com os contratos mínimos do teste. O importador financeiro **legado continua
representado por stub**. Não comprova os materiais planejados do CEM real nem
autenticação/Supabase REST de produção; é insuficiente para autorizar o merge.
O PR permanece rascunho e o site publicado permanece v46.8.


## Integração do importador legado REAL com a precificação — 22/11/2026

**GitHub Actions aprovado:** [run #45021389167](https://github.com/ewertoncad-gif/ewgest/actions/runs/45021389167), branch `feature/categorias-precificacao-fase1-v469`, commit `d77ae314`. Ambos os jobs de PostgreSQL 17 passaram. Os testes geraram somente tabelas e dados **fictícios em runner descartável**; não houve Supabase adicional, migração em produção ou reimportação de obra real.

A antiga ressalva de que **todo** o importador seria stub não se aplica mais a esta nova suíte independente. Ela executa o **código verdadeiro** que estava instalado no Supabase de produção em 22/11/2026, congelado para CI em:
- `31_importador_legado_real_snapshot.sql`: `ew_criar_obra_estoque`, `ew_importar_obra_cem_financeiro`;
- `20261122_precificacao_importador_mapeamento_v469.sql`: importador CEM v46.9 baseado na função legada real, adicionando IDs de esquadrias na ordem do ZIP;
- `34_materiais_legado_real_snapshot.sql`: `importar_materiais_cem`, `ew_importar_cem_conciliado`, `ew_conciliar_codigo_cem`.

A fixture de contratos `30_fixture_legado_real.sql` acrescenta esquema de obras, esquadrias, níveis e locais; `33_fixture_material_real.sql` acrescenta tabelas **mínimas** de perfis, acessórios, variações e vínculos de materiais do CEM. Todas usam identidades sintéticas.

### O que passou com as funções reais
- Criação de obra, local de estoque, esquadrias, cliente, orçamento e níveis de fabricação e instalação (original 70/30) junto de preço aprovado 60/40, com soma exata;
- Código técnico de esquadria repetido (EA01) conservando UUID distinto e seus snapshots;
- Repetição idempotente de `operacao_id`: mesma obra e nenhum cadastro duplicado;
- Erro tardio de grupo financeiro incompatível: a obra e suas esquadrias já haviam sido criadas dentro da função, mas toda a operação foi revertida;
- Importação real de **perfil, barras previstas e acessório**, suas variações, códigos, quantidades planejadas e vínculos à obra, sem reportar baixa no estoque físico;
- Reutilização dos mesmos perfis e acessórios em outra obra: não duplica cadastro, mas cria os vínculos previstos da nova obra;
- Plano de barras com comprimento duplicado: falha e rollback sem deixar cadastros de obra ou importação parcial.

### Pendências restantes — não publicar ainda

1. As tabelas da suíte são contratos **mínimos**, não um dump do schema completo com seus triggers, RLS e extensão de autenticação. Testar no Supabase de homologação realmente compatível ainda é necessário.
2. A autenticação é simulada por `request.jwt.claim.sub` do PostgreSQL: não há login real via Supabase Auth/PostgREST, nem execução de requisições HTTP autenticadas por perfis distintos.
3. Os testes de materiais usam listas sem decisões de conciliação. Embora o código real da função `ew_conciliar_codigo_cem` esteja no snapshot, ainda falta validar seus **efeitos** em um teste de código existente/alias escolhido na interface.
4. Os testes usam objetos fictícios construídos no SQL, não um arquivo ZIP real do CEM na interface gráfica.
5. O projeto `ewgest-restauracao-teste` continua defasado; não sobrescrever sem plano de proteção, nem inferir que já é backup restaurável.
6. Verificar backup restaurável, políticas RLS/GRANT reais, autorização multiempresa por PostgREST e rollback de deploy antes de integrar na `main`.

### Checagem read-only de segurança do projeto de produção

O Supabase Advisor (22/11/2026) sinalizou uma função `public.rls_auto_enable()` do tipo `SECURITY DEFINER` executável por `anon` (WARN); verificar cuidadosamente concessões `EXECUTE` e finalidade antes de qualquer eventual ajuste. Há ainda 8 tabelas com RLS ligado, mas **sem políticas** (INFO): isso normalmente bloqueia acesso direto para papéis comuns; investigar se foi proposital, sem abrir automaticamente políticas permissivas. Alertas genéricos de funções `SECURITY DEFINER` para `authenticated` exigem auditoria da autorização interna caso a caso, não revogação em massa.

**Nenhuma permissão foi alterada em produção nesta análise.**

### Estado ao fim desta etapa

- v46.9 ainda não publicada; PR #64 permanece **draft**.
- v46.8 publicada permanece sem alterações.
- Não foi realizado upgrade Supabase, contratação de ambiente pago nem alteração de dados reais.


### Conciliador CEM real + confirmação de backup — 22/11/2026

- **[GitHub Actions #45021592973](https://github.com/ewertoncad-gif/ewgest/actions/runs/45021592973)**: os dois jobs em PostgreSQL 17 descartável terminaram com **success** no commit `6fba49d3`.
- O novo `tests/homologacao_pg17/36_conciliacao_alias_real.sql` executa a rotina real `ew_conciliar_codigo_cem`, associando código alternativo **CG179** ao perfil fictício **CG1016** sem substituir o código principal; confirma que outra obra reutiliza o alias sem duplicar perfil e que uma decisão sem correspondência no ZIP aborta a operação.
- Cobre agora também o caminho antes pendente de **decisão manual de conciliação**. Permanece pendente o teste da interface gráfica com ZIP real e sessão Supabase Auth/PostgREST.

**Backup existente, verificado sem baixar dados:** a rotina agendada `EWGEST - Backup criptografado` teve execução **success** em [22/11/2026, run #44988018681](https://github.com/ewertoncad-gif/ewgest/actions/runs/44988018681). O artefato criptografado `ewgest-backup-19` existe no GitHub, com **411.517 bytes**, `expired=false` e retenção indicada até 22/12/2026. Esse resultado comprova que a geração/cifra/upload ocorreram, **não** comprova que o backup restaura integralmente o projeto; exigir ensaio de restauração isolada antes de migrar produção.

Sem alteração em Supabase, obras, backup existente, custo, deploy ou main.


## Etapa complementar — CEM real apenas leitura, ZIP sintético e PostgREST local (22/11/2026)

### Conferência do ZIP real fornecido anteriormente
O arquivo `ALU-3195-GVG-PE.zip` da biblioteca do usuário foi **somente lido em ambiente de análise local**. Não foi incluído, enviado ou copiado para este repositório, nem submetido ao site ou banco. Sem expor dados comerciais do arquivo, observou-se:

- 7 entradas ZIP; `ExpObras.xml` possui cerca de 6,56 MB descomprimidos e compressão DEFLATE;
- 94 linhas da tabela de itens, das quais **70** pertencem ao conjunto calculado (822 unidades e **2.848,278 m²**);
- **24** linhas fora do cálculo, que o importador deve ignorar;
- **103** códigos distintos de perfis necessários e **132** códigos distintos de acessórios necessários;
- **105** referências de plano de barras, 8 comprimentos comerciais distintos;
- 3.179 registros SQL relevantes conferidos sem inconsistências de separação Flds1/Flds2; sem medidas de esquadrias inválidas e sem medidas/quantidades inválidas no planejamento de barras.

**Limitação:** esta inspeção utilizou leitura local em Python, reproduzindo as validações essenciais; não é uma importação autenticada nem teste integral do navegador sobre o arquivo real. Nenhum valor de orçamento foi retirado do arquivo.

### Regressão de ponta a ponta com dados 100% fictícios
`scripts/test-cem-zip-precificacao-v469.mjs` executa o parser JS **real do site**: lê ZIP (armazenado e DEFLATE), identifica `ExpObras.xml`, extrai dados, cria esquadrias e materiais previstos e chama o motor real de rateio. Há ainda uma massa volumétrica **fictícia** de 70 esquadrias, 24 itens não calculados, 103 perfis, 132 acessórios e 105 planos de barras, refletindo somente a cardinalidade observada no arquivo técnico (sem copiar cliente, códigos, nomes ou geometrias reais).

O rateio do cenário volumétrico fecha a distribuição 55% fabricação / 45% instalação em todos os 70 itens, com diferença zero. [CI de regressões #45022402643](https://github.com/ewertoncad-gif/ewgest/actions/runs/45022402643) **success**.

### Teste RPC HTTP e RLS sem contratar Supabase
`scripts/test-precificacao-postgrest-v469.mjs` e a Action de homologação usam PostgREST v12.2.3 e PostgreSQL 17 em serviços locais e descartáveis do GitHub Actions, com JWT **assinado por chave completamente fictícia**. Verificam:
- chamada anônima à RPC privilegiada negada;
- almoxarife autenticado negado;
- administrador sintético aprova criação da obra + revisão;
- repetição da operação preserva a obra e a revisão (idempotência);
- alteração de payload com mesmo ID de operação é recusada;
- leitura via HTTP por RLS oculta dados financeiros do almoxarife e permite consulta do administrador.

A fixture `auth.uid()` agora aceita `request.jwt.claims` do PostgREST além da chave individual usada nos testes SQL diretos. Isso **não altera auth.uid no Supabase de produção**.

**Essa verificação exercita requisições HTTP reais para PostgREST e as regras locais do banco, mas não substitui uma sessão Supabase Auth real nem garante compatibilidade integral das extensões, triggers, políticas e permissões do schema de produção.**

### Portões ainda necessários antes da publicação
1. Homologação em um Supabase de teste com estrutura/versões fiéis à produção (o projeto `ewgest-restauracao-teste` possui 35 tabelas públicas e a produção possuía 59 na conferência).
2. Autenticação real de usuário de teste no Supabase com PostgREST e RLS completo, incluindo importação/faturamento.
3. Ensaio da interface completa no navegador com ZIP de treinamento real e conferência de categorias, níveis e preços por m².
4. Restauração efetiva de backup criptografado em ambiente independente e revisão final de segurança.
5. Somente depois disso aplicar migrações versionadas, revisar PR #64, publicar e validar v46.9.

**Sem upgrade do Supabase, sem alteração de dados/obras em produção e sem merge.**
