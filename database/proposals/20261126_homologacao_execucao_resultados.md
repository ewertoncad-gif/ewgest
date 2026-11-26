# Atualização efetiva da homologação — custos por lote

- Reutilizado o ambiente de restauração, sem criar branch de banco, sem contratar novos recursos.
- Reaplicadas migrações selecionadas de compras, estornos, locais, faturamento, expedição, cotação, grupos, documentos fiscais e sessões; catálogo completado com três flags de romaneios.
- A estrutura de testes passou de 52 a 82 tabelas base nos schemas public e ew_compras_interna: 78 das 92 tabelas de produção e 4 tabelas novas do motor. Restam 14 tabelas da produção ausentes; paridade de colunas, RLS, triggers, constraints e funções ainda não é integral.
- O piloto de oito scripts foi instalado apenas no banco de homologação.
- Ensaio com dados fictícios: aquisição preparada de 3 barras a R$ 100,00; RPC real de transferência de uma barra entre obras, consulta financeira e RPC de estorno passaram. Ajuste da obra destino = 3333 centavos; após estorno = 0. Não foi testada a RPC de aquisição nesse ensaio.
- Ensaio de autorização: 376 combinações da matriz de níveis/flags com função ew_pode instalada, oito chamadas da RPC financeira sob papel authenticated e claims sintéticos, bloqueios entre empresas e sessão inválida. Todos aprovados após completar catálogo. Não equivale a testar todas as RPCs nem logins pelo navegador.
- Dados fictícios revertidos: zero obras, zero lotes e zero eventos de custo após testes; conta de teste preexistente preservada. Produção continua sem motor instalado.

## Bloqueios
- Numeração de romaneios requer função histórica consultar_proximo_romaneio ausente na restauração.
- As demais tabelas e diferenças de esquema requerem restauração seletiva e verificação.
- Piloto ainda não rastreia operações posteriores à primeira transferência de uma aquisição inequívoca. Conectar recebimentos, movimentações internas, consumo e cancelamento fiscal; preservar pendências e validar toda a cadeia.
- Não publicar até validar cenários operacionais e permissões restantes. Não aplicar o razão paralelo antigo.
