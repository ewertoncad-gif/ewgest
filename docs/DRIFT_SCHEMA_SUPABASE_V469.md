# EWGEST v46.9 — Diferenças de estrutura: produção x Supabase Free de testes

Levantamento **somente leitura** do catálogo PostgreSQL em 22/11/2026. Somente metadados, sem registros comerciais, usuários, tokens ou credenciais. A produção não foi alterada.

| Objeto | Produção | Testes | Diferença relevante |
|---|---:|---:|---|
| Colunas públicas | 601 | 320 | 75 ausentes em tabelas comuns; 32 diferentes |
| Funções públicas | 98 | 44 | 54 ausentes; 4 com corpo diferente |
| Políticas RLS | 83 | 16 | 69 ausentes; 5 divergentes |
| Triggers de usuário | 19 | 6 | 13 ausentes |
| Índices públicos | 172 | 67 | 109 ausentes |

## 24 tabelas que não existem no ambiente de testes
`classificacoes_tipologias_auditoria`, `esquadrias_descricoes_revisoes`, `esquadrias_saida_config`, `ew_cem_importacoes_materiais`, `ew_comprimentos_comerciais`, `ew_estoque_importacoes_cem`, `ew_historico_acessos`, `ew_obra_faturamentos_itens`, `ew_obras_exclusoes_historico`, `ew_sessoes_unicas`, `romaneios`, `romaneios_itens`, `romaneios_motoristas`, `romaneios_numeracao_historico`, `romaneios_veiculos`, `saidas_producao`, `tipologias_abreviacoes`, `tipologias_abreviacoes_historico`, `tipologias_croquis`, `tipologias_edicoes`, `tipologias_identificacoes_historico`, `tipologias_modulacoes`, `tipologias_modulacoes_contadores`, `tipologias_origens`.

## Colunas faltantes em tabelas existentes
**esquadrias**: `tipologia_id uuid`; `rotulo_tipologia_relatorio text`; `quantidade_modulos integer`; `modulacao_id uuid`.
**ew_acessorios**: `linha text NOT NULL DEFAULT ''::text`; `prenativo text NOT NULL DEFAULT ''::text`; `unidade_embalagem text NOT NULL DEFAULT ''::text`; `quantidade_por_embalagem numeric`; `observacoes text NOT NULL DEFAULT ''::text`; `ativo boolean NOT NULL DEFAULT true`; `criado_por uuid`; `atualizado_por uuid`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `atualizado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_cem_obras_materiais**: `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `atualizado_em timestamp with time zone NOT NULL DEFAULT now()`; `origem_quantitativos text`.
**ew_estoque_movimentacoes**: `tipo text NOT NULL`; `unidade text NOT NULL`; `observacao text NOT NULL DEFAULT ''::text`; `criado_por uuid NOT NULL`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_estoques_locais**: `criado_por uuid`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `excluido_por uuid`; `restauravel_ate timestamp with time zone`.
**ew_fornecedores**: `criado_por uuid NOT NULL`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_locais_fisicos**: `criado_por uuid`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_materiais_alias**: `criado_por uuid NOT NULL`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_materiais_variacoes**: `acabamento text NOT NULL DEFAULT 'NÃO INFORMADO'::text`; `cor text NOT NULL DEFAULT 'NÃO INFORMADA'::text`; `codigo_cor text NOT NULL DEFAULT ''::text`; `observacoes text NOT NULL DEFAULT ''::text`; `criado_por uuid`; `atualizado_por uuid`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `atualizado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_obra_despesas**: `chave_nfe text`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`.
**ew_obra_faturamentos**: `data_faturamento date NOT NULL`; `numero_documento text NOT NULL DEFAULT ''::text`; `observacoes text NOT NULL DEFAULT ''::text`; `criado_por uuid NOT NULL`; `cancelado_por uuid`; `cancelado_em timestamp with time zone`; `operacao_id uuid`.
**ew_perfis**: `linha text NOT NULL DEFAULT ''::text`; `prenativo text NOT NULL DEFAULT ''::text`; `peso_kg_m numeric`; `comprimento_comercial_mm integer`; `unidade_referencia text NOT NULL DEFAULT 'BARRA'::text`; `observacoes text NOT NULL DEFAULT ''::text`; `ativo boolean NOT NULL DEFAULT true`; `criado_por uuid`; `atualizado_por uuid`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `atualizado_em timestamp with time zone NOT NULL DEFAULT now()`.
**fabricantes**: `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `criado_por uuid`.
**liberacoes_corte**: `registrada_em timestamp with time zone NOT NULL DEFAULT now()`; `cancelado_por uuid`; `motivo_cancelamento text`; `tipo_componente text NOT NULL DEFAULT 'completo'::text`.
**obras**: `arquivada_por uuid`; `motivo_arquivamento text`.
**tipologias**: `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `provisoria boolean NOT NULL DEFAULT false`; `quantidade_modulos integer`.
**usuarios_login**: `login_chave text`; `criado_em timestamp with time zone NOT NULL DEFAULT now()`; `atualizado_em timestamp with time zone NOT NULL DEFAULT now()`; `excluido_por uuid`.

## Tipos, defaults ou nulidade diferentes em colunas compartilhadas
- `ew_acessorios.fabricante`: produção `text` nullable=`NO` default=``; teste `text` nullable=`NO` default=`''::text`.
- `ew_acessorios.unidade_item`: produção `text` nullable=`NO` default=`'PC'::text`; teste `text` nullable=`NO` default=``.
- `ew_auditoria_operacoes.obra_nome`: produção `text` nullable=`NO` default=``; teste `text` nullable=`NO` default=`''::text`.
- `ew_auditoria_operacoes.motivo`: produção `text` nullable=`NO` default=``; teste `text` nullable=`NO` default=`''::text`.
- `ew_estoque_movimentacoes.quantidade_delta`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`YES` default=``.
- `ew_estoque_obras_movimentos.operacao_id`: produção `uuid` nullable=`NO` default=``; teste `uuid` nullable=`YES` default=``.
- `ew_estoque_obras_movimentos.observacao`: produção `text` nullable=`NO` default=`''::text`; teste `text` nullable=`YES` default=``.
- `ew_estoque_obras_movimentos.usuario_id`: produção `uuid` nullable=`NO` default=``; teste `uuid` nullable=`YES` default=``.
- `ew_estoque_obras_movimentos.local_estoque`: produção `text` nullable=`NO` default=`'IMBIRIBEIRA'::text`; teste `text` nullable=`NO` default=``.
- `ew_liberacoes_lotes.itens_confirmados`: produção `jsonb` nullable=`NO` default=``; teste `jsonb` nullable=`NO` default=`'[]'::jsonb`.
- `ew_liberacoes_lotes.materiais_confirmados`: produção `jsonb` nullable=`NO` default=``; teste `jsonb` nullable=`NO` default=`'[]'::jsonb`.
- `ew_locais_fisicos.ativo`: produção `boolean` nullable=`NO` default=`true`; teste `boolean` nullable=`YES` default=`true`.
- `ew_materiais_alias.tipo`: produção `text` nullable=`NO` default=``; teste `text` nullable=`YES` default=``.
- `ew_materiais_alias.fabricante`: produção `text` nullable=`NO` default=``; teste `text` nullable=`YES` default=``.
- `ew_materiais_alias.codigo_alternativo`: produção `text` nullable=`NO` default=``; teste `text` nullable=`YES` default=``.
- `ew_materiais_variacoes.ativo`: produção `boolean` nullable=`NO` default=`true`; teste `boolean` nullable=`YES` default=`true`.
- `ew_obra_despesas.origem`: produção `text` nullable=`NO` default=`'manual'::text`; teste `text` nullable=`NO` default=``.
- `ew_obra_despesas.fornecedor`: produção `text` nullable=`NO` default=`''::text`; teste `text` nullable=`YES` default=``.
- `ew_obra_despesas.numero_documento`: produção `text` nullable=`NO` default=`''::text`; teste `text` nullable=`YES` default=``.
- `ew_obra_despesas_itens.codigo_fornecedor`: produção `text` nullable=`NO` default=`''::text`; teste `text` nullable=`NO` default=``.
- `ew_obra_despesas_itens.descricao`: produção `text` nullable=`NO` default=`''::text`; teste `text` nullable=`NO` default=``.
- `ew_obra_despesas_itens.unidade`: produção `text` nullable=`NO` default=`''::text`; teste `text` nullable=`NO` default=``.
- `ew_obra_orcamento.aluminio`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`NO` default=`0`.
- `ew_obra_orcamento.acessorios`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`NO` default=`0`.
- `ew_obra_orcamento.vidros`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`NO` default=`0`.
- `ew_obra_orcamento.outros`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`NO` default=`0`.
- `ew_obra_orcamento.fabricacao`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`NO` default=`0`.
- `ew_obra_orcamento.instalacao`: produção `numeric` nullable=`NO` default=``; teste `numeric` nullable=`NO` default=`0`.
- `ew_perfis.fabricante`: produção `text` nullable=`NO` default=``; teste `text` nullable=`NO` default=`''::text`.
- `liberacoes_corte.usuario_id`: produção `uuid` nullable=`NO` default=``; teste `uuid` nullable=`YES` default=``.
- `usuarios_login.login`: produção `text` nullable=`NO` default=``; teste `text` nullable=`YES` default=``.
- `usuarios_login.nome`: produção `text` nullable=`NO` default=``; teste `text` nullable=`YES` default=``.

## Funções de produção faltantes no staging
- `adiantar_numero_romaneio(p_proximo_numero integer, p_justificativa text)`
- `atribuir_numero_variacao_tipologia()`
- `cadastrar_fabricante_admin(p_empresa_id uuid, p_nome text)`
- `cadastrar_transporte_romaneio(p_tipo text, p_valor text)`
- `cancelar_romaneio_com_estorno(p_romaneio_id uuid, p_motivo text)`
- `classificar_tipologia_pendente_admin(p_esquadria_id uuid, p_codigo text, p_descricao text, p_manter_vinculo_origem boolean)`
- `configurar_variacao_tipologia_admin(p_tipologia_id uuid, p_tipologia_principal_id uuid, p_quantidade_modulos integer)`
- `consultar_proximo_romaneio()`
- `corrigir_identificacao_tipologia_admin(p_tipologia_id uuid, p_tipologia_principal_id uuid, p_principal_anterior_id uuid)`
- `corrigir_identificacao_tipologia_admin(p_tipologia_id uuid, p_tipologia_principal_id uuid, p_principal_anterior_id uuid, p_confirmar_divergencia boolean)`
- `editar_tipologia_admin(p_tipologia_id uuid, p_codigo text, p_descricao text, p_manter_vinculo_origem boolean)`
- `editar_tipologia_com_fabricante_admin(p_tipologia_id uuid, p_codigo text, p_descricao text, p_fabricante text, p_manter_vinculo_origem boolean)`
- `editar_tipologia_fabricante_catalogo_admin(p_tipologia_id uuid, p_codigo text, p_descricao text, p_fabricante text, p_manter_vinculo_origem boolean, p_criar_fabricante boolean)`
- `emitir_romaneio_com_saidas(p_chave_operacao uuid, p_obra_id uuid, p_data_saida date, p_motorista text, p_placa text, p_observacoes text, p_itens jsonb)`
- `ew_arquivar_obra_reconciliada(p_obra_id uuid, p_confirmacao text, p_motivo text, p_operacao_id uuid)`
- `ew_auditar_cancelamento_romaneio()`
- `ew_bloquear_insercao_obra_arquivada()`
- `ew_cadastrar_comprimento_comercial(p_empresa_id uuid, p_comprimento_mm integer)`
- `ew_cadastrar_material_manual_estoque(p_empresa_id uuid, p_obra_id uuid, p_tipo text, p_codigo text, p_descricao text, p_fabricante text, p_acabamento text, p_cor text, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid)`
- `ew_cadastrar_material_manual_estoque_local(p_empresa_id uuid, p_obra_id uuid, p_tipo text, p_codigo text, p_descricao text, p_fabricante text, p_acabamento text, p_cor text, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid, p_local_estoque text)`
- `ew_cancelar_faturamento_financeiro(p_empresa_id uuid, p_faturamento_id uuid, p_motivo text)`
- `ew_cancelar_liberacoes_obra(p_obra_id uuid, p_motivo text)`
- `ew_cancelar_saidas_avulsas_obra(p_obra_id uuid, p_motivo text)`
- `ew_conciliar_codigo_cem(p_empresa_id uuid, p_tipo text, p_material_id uuid, p_codigo_cem text, p_usar_codigo_cem boolean)`
- `ew_controlar_sessao_unica(p_acao text)`
- `ew_criar_obra_estoque(p_empresa_id uuid, p_nome text, p_codigo text)`
- `ew_estornar_transferencia_entre_obras(p_empresa_id uuid, p_transferencia_id uuid, p_motivo text, p_operacao_id uuid)`
- `ew_excluir_estoque_local(p_empresa_id uuid, p_obra_id uuid)`
- `ew_excluir_obra_sem_operacoes(p_obra_id uuid, p_confirmacao text, p_motivo text, p_operacao_id uuid)`
- `ew_importar_cem_conciliado(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb)`
- `ew_importar_saldo_obra_cem(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_nome_arquivo text, p_operacao_id uuid)`
- `ew_liberar_plano_corte_componente(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text, p_materiais jsonb, p_fonte text, p_arquivo_nome text, p_operacao_id uuid, p_componente text)`
- `ew_movimentar_estoque_obra(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid)`
- `ew_proteger_arquivamento_obra()`
- `ew_registrar_evento_acesso(p_empresa_id uuid, p_sessao_id uuid, p_evento text)`
- `ew_registrar_faturamento_financeiro(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_data_faturamento date, p_numero_documento text, p_observacoes text, p_itens jsonb, p_operacao_id uuid, p_instalacao_confirmada boolean)`
- `ew_registrar_liberacao_componente(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text, p_componente text)`
- `ew_restaurar_estoque_local(p_empresa_id uuid, p_obra_id uuid)`
- `ew_revisar_nfe_almox(p_empresa_id uuid, p_despesa_id uuid, p_acao text, p_justificativa text)`
- `ew_sessao_eh_atual()`
- `ew_submeter_nfe_almox(p_empresa_id uuid, p_obra_id uuid, p_categoria text, p_valor numeric, p_fornecedor text, p_numero_documento text, p_data_documento date, p_chave_nfe text, p_itens jsonb, p_observacoes text, p_operacao_id uuid)`
- `ew_transferir_estoque_entre_obras(p_empresa_id uuid, p_origem_obra_id uuid, p_destino_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)`
- `ew_transferir_estoque_obra(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem_local text, p_destino_local text, p_observacao text, p_operacao_id uuid)`
- `ew_verificar_exclusao_obra(p_obra_id uuid)`
- `ew_vincular_item_nfe(p_empresa_id uuid, p_item_id uuid, p_tipo text, p_material_id uuid)`
- `importar_materiais_cem(p_empresa_id uuid, p_codigo_obra text, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid)`
- `movimentar_estoque_ewgest(p_empresa_id uuid, p_variacao_id uuid, p_tipo text, p_quantidade numeric, p_unidade text, p_observacao text)`
- `registrar_liberacao_corte(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date)`
- `registrar_saida_producao(p_registro_id uuid, p_esquadria_id uuid, p_tipo text, p_quantidade integer, p_data_saida date, p_folhas_por_unidade integer)`
- `resolver_modulacao_pendente_admin(p_esquadria_id uuid, p_tipologia_id uuid, p_modulacao_id uuid, p_criar_modulacao boolean, p_descricao_modulacao text, p_quantidade_modulos integer, p_confirmar_divergencia boolean)`
- `revisar_descricao_configuracao_admin(p_esquadria_id uuid, p_acao text, p_modulacao_id uuid)`
- `salvar_abreviacao_tipologia(p_tipologia_id uuid, p_descricao_base text)`
- `salvar_croqui_tipologia_admin(p_tipologia_id uuid, p_imagem_base64 text, p_origem text, p_codigo_esquadria_referencia text)`
- `vincular_tipologia_existente_admin(p_esquadria_id uuid, p_tipologia_id uuid, p_confirmar_divergencia boolean)`

## Funções compartilhadas, mas com implementação diferente
- `ew_exigir_sessao_atual()`
- `ew_importar_obra_cem(p_empresa_id uuid, p_codigo_obra text, p_nome_obra text, p_cliente text, p_esquadrias jsonb, p_perfis jsonb, p_acessorios jsonb, p_operacao_id uuid, p_decisoes jsonb)`
- `ew_movimentar_estoque_obra_local(p_empresa_id uuid, p_obra_id uuid, p_variacao_id uuid, p_comprimento_mm integer, p_unidade text, p_quantidade numeric, p_origem text, p_observacao text, p_operacao_id uuid, p_local_estoque text)`
- `registrar_liberacao_corte_fabrica(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text)`

## Políticas RLS faltantes (por tabela)
- **classificacoes_tipologias_auditoria**: `Administrador consulta confirmacoes da empresa`
- **esquadrias_descricoes_revisoes**: `ADM consulta historico de revisao de descricoes`
- **esquadrias_saida_config**: `Consultar composição das esquadrias da empresa`
- **ew_acessorios**: `ADM atualiza acessórios`, `ADM insere acessórios`, `Consultar acessórios da empresa`
- **ew_auditoria_operacoes**: `Gestores consultam auditoria da propria empresa`
- **ew_cem_importacoes_materiais**: `ADM registra importações CEM`, `Empresa consulta importações CEM`
- **ew_cem_obras_materiais**: `ADM atualiza materiais por obra CEM`, `ADM vincula materiais por obra CEM`, `Empresa consulta materiais por obra CEM`
- **ew_comprimentos_comerciais**: `Equipe consulta comprimentos comerciais da empresa`
- **ew_estoque_importacoes_cem**: `Empresa consulta importações de estoque CEM`
- **ew_estoque_movimentacoes**: `Consultar movimentações estoque da empresa`
- **ew_estoque_obras_movimentos**: `Registrar movimentos de estoque por ADM ou supervisor`, `Visualizar movimentos do estoque por empresa`
- **ew_estoques_locais**: `Equipe da empresa consulta locais do estoque`
- **ew_fornecedores**: `ADM atualiza fornecedores da empresa`, `ADM cadastra fornecedores da empresa`, `Equipe consulta fornecedores da empresa`
- **ew_historico_acessos**: `Somente ADM consulta historico de acessos da empresa`
- **ew_liberacoes_lotes**: `Equipe consulta lotes da empresa`
- **ew_locais_fisicos**: `ADM cadastra galpoes`, `Equipe consulta galpoes da empresa`
- **ew_materiais_alias**: `Consultar codigos alternativos`
- **ew_materiais_variacoes**: `ADM atualiza variações`, `ADM insere variações`, `Consultar variações da empresa`
- **ew_nfe_recebimentos**: `ew_nfe_recebimentos_insert`, `ew_nfe_recebimentos_select`
- **ew_obra_despesas**: `ew_despesas_insert`, `ew_despesas_select`, `ew_despesas_update`
- **ew_obra_despesas_itens**: `ew_despesas_itens_insert`, `ew_despesas_itens_select`, `ew_despesas_itens_update_admin`
- **ew_obra_faturamentos**: `ew_faturas_insert`, `ew_faturas_select`, `ew_faturas_update`
- **ew_obra_faturamentos_itens**: `ew_faturas_itens_insert`, `ew_faturas_itens_select`
- **ew_obra_orcamento**: `ew_orcamento_insert`, `ew_orcamento_select`, `ew_orcamento_update`
- **ew_obras_exclusoes_historico**: `ADM e Gerenciador consultam exclusoes de sua empresa`
- **ew_perfis**: `ADM atualiza perfis`, `ADM insere perfis`, `Consultar perfis da empresa`
- **ew_planos_liberados**: `Consultar planos da empresa`, `Liberar plano pela equipe tecnica`
- **fabricantes**: `Administrador consulta fabricantes da empresa`
- **liberacoes_corte**: `Consultar liberações da empresa`
- **romaneios**: `Membros consultam romaneios da empresa`
- **romaneios_itens**: `Membros consultam itens de romaneios da empresa`
- **romaneios_motoristas**: `Membros da empresa consultam motoristas`
- **romaneios_numeracao_historico**: `Consultar ajustes de romaneio`
- **romaneios_veiculos**: `Membros da empresa consultam placas`
- **saidas_producao**: `Consultar saídas da empresa`
- **tipologias**: `Consultar tipologias da empresa`
- **tipologias_abreviacoes**: `Membros ativos consultam abreviacoes`
- **tipologias_abreviacoes_historico**: `ADM consulta historico de abreviacoes`
- **tipologias_croquis**: `Administrador consulta croquis da empresa`
- **tipologias_edicoes**: `Administrador consulta revisoes de tipologias`
- **tipologias_identificacoes_historico**: `Administrador consulta correcoes de identificacao`
- **tipologias_modulacoes**: `Membros consultam modulacoes da empresa`
- **tipologias_origens**: `Administrador consulta vinculos de origem`
- **usuarios_login**: `Apenas sessao unica consulta cadastro`, `Usuario consulta proprio login e administrador consulta empresa`

## Situação após proteção de permissões anônimas
A **correção foi aplicada apenas no staging**: 35/35 tabelas públicas com RLS habilitado; 0 tabelas públicas com `SELECT` ou `INSERT` concedido ao papel `anon`. O staging já possuía 1 usuário Auth e 1 empresa, mantidos; não existem obras/esquadrias ali. A produção tem 59/59 tabelas com RLS e zero grants anônimos.

**Importante:** o staging permanece insuficiente para homologar a v46.9. As tabelas antigas com RLS mas sem políticas ficam inacessíveis ao perfil comum até a recriação de políticas corretas. Não copiar dados reais; não implantar a nova precificação em produção antes da integração e do ensaio de restauração.

## Ordem de reconstrução proposta
1. Conferir constraints/FKs, triggers e políticas das 35 tabelas existentes; aplicar apenas alterações aditivas após backup do projeto de teste.
2. Recriar dependências de cadastro, tipologias, romaneios, histórico e estoque ausentes, com schema e permissões equivalentes à produção e sem dados comerciais.
3. Recuperar funções de controle de sessão, criação e importação CEM, materiais e faturamento na ordem das dependências; verificar assinaturas, GRANT e RLS.
4. Aplicar SQL de precificação propostos no teste e validar importação/romaneios com usuários fictícios na API real; testar backup e rollback, então considerar deploy v46.9.
