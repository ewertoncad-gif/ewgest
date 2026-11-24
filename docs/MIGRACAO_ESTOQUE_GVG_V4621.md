# EWGEST v46.21 — migração auditada do ESTOQUE GVG

**Status:** procedimento validado com dados fictícios, **não executado em produção**.  
**Data da conferência:** 24/11/2026.  
**Issue:** #77 · **PR:** #78.

## Situação real conferida — somente leitura

- O cadastro `ESTOQUE GVG` ainda existe como **obra artificial** (`MAN-21B122DE38`).
- Seu movimento físico registrado é **+4,000 MT**, no galpão **IMBIRIBEIRA**, com origem `TRANSFERENCIA`.
- A contrapartida desse movimento é uma **saída de 4,000 MT** da obra de treinamento ESSENCE CONSTRUÇÕES, também no galpão Imbiribeira.
- O movimento da obra artificial não está vinculado diretamente a um recebimento de NF-e.
- Não foram encontradas despesas financeiras associadas ao cadastro artificial `ESTOQUE GVG`.
- O histórico original é uma transferência entre obras e **não pode ser apagado** para "corrigir" o nome do local.

## Objetivo

Converter a titularidade futura desse material para o local empresarial **ESTOQUE GVG**, sem criar obra fictícia, sem lançar nova compra e sem duplicar saldo. O galpão físico continua sendo IMBIRIBEIRA.

## Procedimento previsto — executar só após homologação e autorização

1. Conferir backup/reversão e registrar a foto dos saldos de produção por **variação + unidade + comprimento + galpão** e dos movimentos históricos.
2. Cadastrar um novo local de estoque da **empresa** com nome `ESTOQUE GVG`, independente de obra.
3. Usar **Estoque → Transferir entre locais**: origem `Obra · ESTOQUE GVG`, destino `Empresa · ESTOQUE GVG`, galpão de origem `IMBIRIBEIRA`, destino `IMBIRIBEIRA`, material `FIT2130PTO`, quantidade `4 MT`, justificativa identificando a conversão histórica.
4. A função de transferência gera **-4 MT** no estoque antigo e **+4 MT** no estoque empresarial, em operação atômica, sem alterar valores financeiros ou criar nota.
5. Conferir: saldo do estoque de obra artificial **0 MT**; saldo da empresa **4 MT**; soma preservada, sem novo recebimento fiscal; os dois movimentos originais de transferência entre obras continuam registrados.
6. Registrar a operação no histórico e somente após conferência avaliar ocultar/arquivar a obra artificial dos seletores operacionais. Não excluir o histórico nem forçar o arquivamento.
7. Para desfazer a conversão, usar o **estorno da nova transferência**, que restaura +4 MT no antigo local e -4 MT no empresarial, se o material ainda estiver disponível e não tiver sido consumido/movimentado adiante.

## Pontos de atenção

- A transferência de titularidade não resolve automaticamente centros de custo e relatórios antigos. Nenhuma despesa deve ser criada só para acompanhar os 4 MT: não havia despesa financeira vinculada ao cadastro artificial.
- A operação original de ESSENCE CONSTRUÇÕES continua histórica, com seus dois lados referenciados. O estorno dela permanece sujeito às regras próprias de transferência entre obras, e poderá exigir antes o estorno da nova transferência da empresa.
- Transferir para o local empresarial não deve gerar um novo romaneio de *transferência entre duas obras*. Revisar documentação de transporte físico entre locais antes de publicar.
- Movimentos posteriores no estoque empresarial podem impedir o estorno: devem ser revertidos antes, preservando auditoria.
- Conferência realizada em produção **apenas por consultas de leitura**. Nenhum lançamento real foi modificado.

## Ensaio automatizado

`tests/compras_v4621/40_migracao_estoque_legado_rollback.sql`: cenário sintético de estoque legado com saldo 4 MT recebido de outra obra, transferência para local empresarial, conferência de saldos e histórico, seguido de estorno. Executado em `ewgest-restauracao-teste` com `BEGIN/ROLLBACK`, aprovado em 24/11/2026.

**Critério de aceite de produção:** operação autorizada, comprovante do saldo antes/depois, nenhuma duplicidade física/fiscal, histórico preservado e rollback documentado.
