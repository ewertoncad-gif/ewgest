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
