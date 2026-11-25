# Composição de expedição por tipologia — tarefa #84

## Regra de negócio
- Catálogo de tipologias: composição configurável, componentes com identificador estável, nome, quantidade física por esquadria e percentual em pontos-base; total 100%.
- Exemplo 2F: marco 1 × 50%, folhas 2 × 50% (25% por folha). MAXIM-AR com peitoril: marco+vidro 50% / folha 50%, ou marco 50% / folha 40% / vidro do peitoril 10%. São duas composições alternativas; não somar as duas.
- Liberação técnica integral; expedição completa ou por componente. MAXIM-AR sem regra configurada permanece completo. Configuração explícita permite desmembrar.
- Saldo de componente = unidades liberadas × quantidade por unidade − saídas ativas daquele componente. Completa consome todos os componentes atomicamente. Cancelamento desfaz as mesmas quantidades, jamais a regra atual do catálogo.
- Área equivalente = largura × altura / 1e6 × quantidade física enviada × peso do componente / (10000 × quantidade física por unidade). Banco calcula com NUMERIC; não arredondar cada componente antes de somar. Limitar faturamento ao saldo expedido e aos tetos de contrato. Preservar fabricação/instalação separadas.
- Sugestão por estrutura, ignorando linha/fabricante quando identificáveis. Nunca aplicar sem seleção explícita. Exibir código, descrição completa, fabricante, linha/modulação, regra atual e divergências. Permitir busca manual; não sobrescrever regras existentes sem aviso.

## Integração pendente
1. Criar revisões de composição por empresa/tipologia, componentes e vínculos de revisão a esquadrias. Manter versões históricas imutáveis; regra aplicável à primeira saída deve ser congelada. Alteração em obra já expedida somente após conferência e estorno das dependências. Não recalcular histórico.
2. Editor no cadastro de tipologias (fora do formulário de identificação/croqui), validação de 100%, sugestão de similares com caixas desmarcadas, confirmação e auditoria do conjunto de alterações. Permissões e isolamento no servidor.
3. Adicionar registro de componente/revisão e área equivalente precisa às saídas e linhas de romaneio; preservar as funções antigas durante migração e compatibilidade dos documentos emitidos. Não usar somente descrição textual como chave.
4. Atualizar emissão, estorno, relatórios, faturamento e limites de concorrência na mesma transação; impedir saída/faturamento acima do saldo. Bloquear mistura de revisões incompatíveis. Compatibilidade com romaneios antigos mediante dados históricos persistidos.
5. Homologar catálogo, seleção múltipla, 2F, 3F, maxim-ar com/sem peitoril, completa+parciais, cancelamento, arredondamento acumulado, duas empresas e usuários concorrentes, antes de integrar à main e aplicar SQL de produção.

## Estado
Núcleo puro JS e testes unitários adicionados nesta branch. Testados com casos sintéticos em execução JS isolada. Ainda não integrado à interface nem ao banco. A correção EA2 #83 está em branch separada. Não aplicar mudanças em produção a partir deste documento.
