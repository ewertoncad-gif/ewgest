import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import './test-precificacao.mjs';
import './test-precificacao-media-ui.mjs';
import './test-financeiro-lotes.mjs';
import './test-precificacao-financeiro.mjs';
import './test-precificacao-ui.mjs';
import './test-cem-zip-precificacao-v469.mjs';
import './test-cancelamento-financeiro-nfe.mjs';
import './test-conciliacao-transferencias-nfe-v4611.mjs';
import './test-contador-liberacoes-gerenciar-obras-v4612.mjs';
import './test-aviso-motivo-exclusao-v4613.mjs';
import './test-estoque-zero-sem-galpao-v4614.mjs';
import './test-estornos-parcelas-ui-v4615.mjs';
import './test-relatorios-v4616.mjs';
import './test-relatorios-romaneios-v4617.mjs';
import './test-exclusao-definitiva-v4618.mjs';
import './test-niveis-acesso-v4620.mjs';
const source=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
// Issue #31 — Recebimento separado do Financeiro e operação por perfil.
const recebimentoSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_recebimento_almoxarife_seguro.sql',import.meta.url)),'utf8');
const cadastroSeguroSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_cadastros_dependencias.sql',import.meta.url)),'utf8');
const receiptIdx=source.indexOf('<section id="recebimento"');
const financeIdx=source.indexOf('<section id="financeiro"');
const receiptFormIdx=source.indexOf('id="finExpensePanel"');
assert.ok(receiptIdx>0&&financeIdx>receiptIdx&&receiptFormIdx>receiptIdx&&receiptFormIdx<financeIdx,
 'O formulário de recebimento deve pertencer à tela Recebimento, não ao Financeiro');
assert.ok(source.includes('id="navRecebimento"')&&source.includes("['navRecebimento','recebimento']")&&
 source.includes("setNavPermission('navRecebimento',temPermissao('estoque.receber'))"),
 'Menu Recebimento liberado por perfil, sem exibir o Financeiro ao almoxarife');
const recebimentoLoader=source.slice(source.indexOf('async function carregarRecebimento(){'),
 source.indexOf('function finOptionsObras(prefer){'));
assert.ok(recebimentoLoader.includes("if(temPermissao('financeiro.consultar')){")&&
 recebimentoLoader.includes('apiGet(\'ew_cem_obras_materiais\'')&&
 recebimentoLoader.includes('rpc/ew_quantidades_recebidas_obra')&&
 !recebimentoLoader.includes("apiGet('ew_obra_despesas'")&&
 !recebimentoLoader.includes("apiGet('ew_obra_orcamento'"),
 'Almoxarife consulta materiais e quantidades, sem buscar despesas ou orçamento');
assert.ok(recebimentoSQL.includes("u.perfil='almoxarife'")&&
 recebimentoSQL.includes("perform public.ew_exigir_sessao_atual()")&&
 recebimentoSQL.includes('insert into public.ew_obra_despesas')&&
 recebimentoSQL.includes('insert into public.ew_estoque_obras_movimentos')&&
 recebimentoSQL.includes('insert into public.ew_nfe_recebimentos')&&
 recebimentoSQL.includes('revoke execute on function public.ew_receber_materiais_almox')&&
 recebimentoSQL.includes('from anon;'),
 'RPC do almoxarife insere nota e estoque na mesma transação e bloqueia anon');
assert.ok(source.includes('id="cadastroEditPanel"')&&
 cadastroSeguroSQL.includes('from public.ew_estoque_obras_movimentos')&&
 cadastroSeguroSQL.includes('from public.ew_obra_despesas')&&
 cadastroSeguroSQL.includes("raise exception 'Cadastro em uso"),
 'Cadastros auxiliaries: edição e exclusão preservam notas e movimentações');
// Validar também a sintaxe do aplicativo principal (não apenas fragments).
const inlineJS=[...source.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)]
 .map(x=>x[1]);
assert.ok(inlineJS.length>=1,'Script principal da interface deve estar no HTML');
for(const js of inlineJS)assert.doesNotThrow(()=>new Function(js),
 'JavaScript principal da interface deve ser sintaticamente válido');
const receiptCacheHeaders=readFileSync(fileURLToPath(new URL('../_headers',import.meta.url)),'utf8');
assert.ok(source.includes('/assets/recebimento-manual.js?v=20261126a')&&
 source.includes('/assets/recebimento-manual.css?v=20261121g'),
 'O recebimento precisa de URLs versionadas para evitar assets antigos após deploy');
assert.match(receiptCacheHeaders,/\/assets\/recebimento-manual\.js\s+Content-Type: text\/javascript; charset=utf-8\s+Cache-Control: no-store/,
 'Cloudflare não deve manter o JavaScript de recebimento em cache');
assert.match(receiptCacheHeaders,/\/assets\/recebimento-manual\.css\s+Content-Type: text\/css; charset=utf-8\s+Cache-Control: no-store/,
 'Cloudflare não deve manter o CSS de recebimento em cache');
const start=source.indexOf('function normalizarDescricaoTipologia(t){');
const end=source.indexOf('function refreshVariationManager(){',start);
assert.ok(start>=0&&end>start,'Funções de classificação foram localizadas');
const amostras=[
  {id:'a',obra_id:'casa-boa-viagem',codigo:'EA14_1',rotulo_tipologia_relatorio:'EA14_1',descricao:'FIXO VENEZIANA - 2 FOLHAS'},
  {id:'b',obra_id:'obra-nova',codigo:'EA14_1',rotulo_tipologia_relatorio:'EA14_1',descricao:'PORTA DE CORRER - 2 FOLHAS'},
  {id:'c',obra_id:'casa-boa-viagem',codigo:'EA14_2',rotulo_tipologia_relatorio:'EA14_1',descricao:'FIXO VENEZIANA - 2 FOLHAS'}
];
const {classificarTipoTipologia,correspondeTipoTipologia,sugerirPorDescricao,gruposTipologiaPendente,normalizarReconhecimento}=
  new Function('elements',source.slice(start,end)+'\nreturn {classificarTipoTipologia,correspondeTipoTipologia,sugerirPorDescricao,gruposTipologiaPendente,normalizarReconhecimento};')(amostras);
const cases=[
 ['FACHADA UNITIZADA COM MÓDULO MAXIM-AR','FACHADA UNITIZADA'],
 ['FACHADA STICK COM MAXIM-AR','FACHADA STICK'],
 ['FACHADA UNITIZADA MÓDULO FIXO','FACHADA UNITIZADA'],
 ['FACHADA STICK VIDRO FIXO','FACHADA STICK'],
 ['FACHADA DE VIDRO - SISTEMA NÃO DEFINIDO','OUTROS'],
 ['PELE DE VIDRO - A DEFINIR','OUTROS'],
 ['MAXIM-AR 1 FOLHA','MAXIM-AR'],
 ['MAXIM AR - LINHA INOVA','MAXIM-AR'],
 ['MAXIMAR - LINHA INOVA','MAXIM-AR'],
 ['JANELA MAXIM-AR','MAXIM-AR'],
 ['MAXIM-AR COM PEITORIL FIXO','MAXIM-AR'],
 ['JANELA DE CORRER - PEITORIL FIXO','JANELA'],
 ['JANELA DE CORRER','JANELA'],
 ['FIXO VENEZIANA - 2 FOLHAS','FIXO'],
 ['PAINEL FIXO','FIXO'],
 ['PORTA DE GIRO - FIXO LATERAL','PORTA DE GIRO'],
 ['PORTA PIVOTANTE - 2 FOLHAS - GOLD IV - HYDRO','PORTA DE GIRO'],
 ['PORTA DE CORRER - 2 FOLHAS - GOLD SLIM - HYDRO','PORTA'],
 ['GRADIL FIXO','GRADIL'],
 ['GUARDA CORPO','GUARDA CORPO'],
 ['SPLIT TUBULAR','SPLIT'],
];
for(const [descricao,expected] of cases){
  assert.equal(classificarTipoTipologia({descricao}),expected,descricao);
  assert.ok(correspondeTipoTipologia({descricao},expected),descricao);
  if(expected==='FACHADA UNITIZADA'||expected==='FACHADA STICK'){
    assert.equal(correspondeTipoTipologia({descricao},'FIXO'),false);
    assert.equal(correspondeTipoTipologia({descricao},'MAXIM-AR'),false);
  }
}
assert.ok(!source.includes('<option value="FACHADA_NAO_DEFINIDA">'),
 'Não oferecer filtro isolado para fachadas não identificadas');
assert.ok(source.includes('<option value="OUTROS">OUTROS / NÃO IDENTIFICADOS</option>'),
 'Manter o filtro Outros para fachadas não classificadas');
const catalogo=[
  {id:'fixo',codigo:'INV-VNZN00',descricao:'FIXO VENEZIANA - 2 FOLHAS - LINHA INOVA - HYDRO'},
  {id:'porta',codigo:'INV-PCR202',descricao:'PORTA DE CORRER - 2 FOLHAS - LINHA INOVA - HYDRO'}
];
const fixo=sugerirPorDescricao(amostras[0].descricao,catalogo);
const porta=sugerirPorDescricao(amostras[1].descricao,catalogo);
assert.equal(fixo[0]?.tipologia.codigo,'INV-VNZN00','O fixo sugere sua familia, nao a porta');
assert.equal(porta[0]?.tipologia.codigo,'INV-PCR202','O mesmo EA14_1 da outra obra sugere porta');
assert.ok(!porta.some(x=>x.tipologia.id==='fixo'),'Nao sugerir fixo para uma porta');
assert.equal(gruposTipologiaPendente().length,2,'Mesmo codigo em obras diferentes nunca forma um grupo');
assert.equal(gruposTipologiaPendente().find(x=>x.item.obra_id==='casa-boa-viagem').total,2);
for(const token of [
 '<option value="MAXIM-AR">MAXIM-AR</option>',
 '<option value="FIXO">FIXO</option>',
 'id="systemRulesPanel"',
 'id="variationManager"',
 'id="variationForm"',
 'function saveVariationFamily(event)',
 'tipologia_principal_id,quantidade_modulos',
 'return classificarTipoTipologia(t)===tipo;',
 'EWGEST • v46.29.52',
 'id="pendingReviewPanel"',
 'id="recognitionOverlay"',
 'id="recognitionApproval"',
 'id="recognitionDivergence"',
 'ew_resolver_modulacao_com_regra',
 'id="recognitionModulation"',
 'id="recognitionNewModFields"',
 'id="modulationCatalogPanel"',
 'id="pendingReviewPanel" open',
 'function modulacoesDaTipologia(t)',
 'p_criar_modulacao:nova',
 'node(\'recognitionModCount\').value',
 'function renderModulacoesCadastradas()',
 'comparacaoEstritaDescricao',
 'id="recognitionDivergence"',
 'tipologia_principal_id||registro.id',
 'id="identityOverlay"',
 'id="identityOpen"',
 'id="identityTarget"',
 'id="identityApproved"',
 'corrigir_identificacao_tipologia_admin',
 'function salvarCorrecaoIdentificacao()',
 'function candidatosIdentificacaoTecnica(origem,catalogo)',
 'codigo_original_preservado',
 'Código original: ',
 'function codigoVariacaoTecnica(tipologia,modulacao)',
 'function proximoSufixoVisual(tipologia)',
 'numero_variacao',
 'MODULAÇÃO A CONFERIR',
 'proximoSufixoVisual(t)',
 'p_confirmar_divergencia:node(\'identityDifferent\').checked',
 'id="differenceOverlay"',
 'id="differenceConfig"',
 'id="differenceSecondStep"',
 'id="differenceCreateFields"',
 'id="differenceCorrectFields"',
 'id="differenceSave"',
 'id="differencePreserveCode"',
 'function descricaoComparacaoComModulosN(descricao)',
 'function modulacaoMesmaDescricao(tipologia,descricao)',
 'function quantidadeModulosExpressa(descricao)',
 'const codigoExibicao=principal.codigo;',
 'function typologyPrincipalCode(item)',
 'id="releaseFactory"',
 'AFOGADOS',
 'IMBIRIBEIRA',
 '/rest/v1/rpc/ew_liberar_plano_corte_componente',
 'p_fabrica:fabrica',
 'id="romaneioModal"',
 'id="romaneioForm"',
 'id="romaneioNewDriver"',
 'id="romaneioNewPlate"',
 'id="romaneioDriver"',
 'id="romaneioPlate"',
 'function cadastrarTransporteRomaneio(tipo)',
 'function buscarEsquadriasRomaneio(row)',
 'function romaneioSaldoPorTipo(item,tipo,folhas)',
 'function ehMaximArRomaneio(item)',
 'leaves.required=perguntaFolhas',
 "const folhas=tipo==='completo'?null:",
 "tipo!=='completo'&&ehMaximArRomaneio(item)",
 'id="shipmentMaximNote"',
 "tipoSelect.querySelector('option[value=\"parcial\"]').disabled=maxim",
 "node('shipmentLeaves').required=precisaComposicao",
 "const per=kind==='completo'?null:",
 'Folhas físicas (pode enviar uma de cada vez)',
 'data-rom-field="esquadria_search"',
 "p_motivo:texto",
 'cancelar_romaneio_com_estorno',
 'romaneioCancelPrint',
 'cancelado_em:',
 "tipo_saida:tipo",
 'id="romaneioHistoryPanel"',
 'id="openRomaneio"',
 'id="romaneioHistoryPanel"',
 'id="romaneioOverview"',
 'function emitirRomaneio(event)',
 'function construirHTMLRomaneio(header,linhas)',
 'function coletarItensRomaneio()',
 'emitir_romaneio_com_saidas',
 "natureza:'material'",
 "natureza:'esquadria'",
 'const code=typologyPrincipalCode(list[i])',
 'rows[i].dataset.tipologiaCompleta=typologyCode(list[i]);',
 "typology+' '+(item.dataset.tipologiaCompleta||'')",
 'const code=codigoVariacaoTecnica(t,m)||m.codigo_interno;',
 'Essa esquadria pertence à tipologia do catálogo?',
 'A descrição original da obra permanece como foi recebida.',
 'Somente no catálogo, N representa uma quantidade variável de módulos.',
 'Criar outra configuração da mesma tipologia (mantém o código e adiciona um sufixo).',
 'Código da tipologia preservado: ',
 'class="differenceComparisonGrid"',
 'differenceCompareCard',
 "card('TIPOLOGIA INFORMADA NA OBRA'",
 "card('TIPOLOGIA DO CATÁLOGO'",
 'function abrirConferenciaDescricao(item)',
 'function atualizarTelaDiferenca()',
 'function salvarConferenciaDescricao()',
 'revisar_descricao_configuracao_admin',
 "p_acao:opcao",
 "p_confirmar_divergencia:true"

]){
  assert.ok(source.includes(token),'Preservar: '+token);
}
assert.ok(!source.includes('const codigoExibicao=codigoVariacaoTecnica(t,modulo)||principal.codigo;'),
  'Não exibir sufixo na listagem principal das tipologias');
assert.ok(source.includes('const codigoExibicao=principal.codigo;'),
  'Manter somente código principal no catálogo');
assert.ok(source.includes('const code=codigoVariacaoTecnica(t,m)||m.codigo_interno;'),
  'Manter o código de variação na seção de modulações internas');
const principalId='familia-1';
const catalogoRaiz=[
  {id:principalId,codigo:'INV-VNZN00',tipologia_principal_id:null},
  {id:'legado-2',codigo:'EA14_1',tipologia_principal_id:principalId}
];
const fnInicio=source.indexOf('function codigoVariacaoTecnica(tipologia,modulacao){');
const fnFim=source.indexOf('function sortWorkItems(a,b){',fnInicio);
assert.ok(fnInicio>=0&&fnFim>fnInicio,'Identificacao tecnicas com sufixos presente');
const mods=[
 {id:'m1',tipologia_principal_id:principalId,codigo_interno:'MOD-000001',numero_variacao:1,tipologia_legada_id:principalId},
 {id:'m2',tipologia_principal_id:principalId,codigo_interno:'MOD-000002',numero_variacao:2,tipologia_legada_id:'legado-2'}
];
const formatos=new Function('typologyCatalog','modulationCatalog',
 source.slice(fnInicio,fnFim)+
 '\nreturn {codigoVariacaoTecnica,modulacaoCadastroLegado,proximoSufixoVisual,typologyCode,typologyPrincipalCode};'
)(catalogoRaiz,mods);
assert.equal(formatos.typologyCode({tipologia_id:principalId,modulacao_id:'m1'}),'INV-VNZN00-01');
assert.equal(formatos.typologyPrincipalCode({tipologia_id:principalId,modulacao_id:'m1'}),'INV-VNZN00',
  'Liberação deve mostrar família principal sem sufixo');
assert.equal(formatos.typologyPrincipalCode({tipologia_id:'legado-2',modulacao_id:'m2'}),'INV-VNZN00',
  'Saída deve agrupar a mesma tipologia ainda que sejam configurações diferentes');
assert.equal(formatos.typologyPrincipalCode({tipologia_id:'legado-2',modulacao_id:null}),'INV-VNZN00',
  'Sem modulação mantém o código principal');
assert.equal(formatos.typologyCode({tipologia_id:'legado-2',modulacao_id:'m2'}),'INV-VNZN00-02');
assert.equal(formatos.typologyCode({tipologia_id:'legado-2',modulacao_id:null}),'INV-VNZN00',
  'Sem classificacao de configuracao nao inventar sufixo');
assert.equal(formatos.proximoSufixoVisual(catalogoRaiz[1]),'INV-VNZN00-03',
  'Proximo sufixo previsivel (confirmacao definitiva do banco)');

const modInicio=source.indexOf('function modulacoesDaTipologia(t){');
const modFim=source.indexOf('function atualizarOpcoesModulacao(){',modInicio);
assert.ok(modInicio>=0&&modFim>modInicio,'Filtro das modulacoes por familia');
const modExemplo=[
 {id:'mod-um',tipologia_principal_id:principalId,codigo_interno:'MOD-000001',descricao:'FIXO VENEZIANA - 1 FOLHA(S)'},
 {id:'mod-dois',tipologia_principal_id:principalId,codigo_interno:'MOD-000002',descricao:'FIXO VENEZIANA - 2 FOLHA(S)'},
 {id:'outra-mod',tipologia_principal_id:'outra-familia',codigo_interno:'MOD-000003'}
];
const modsDaTipologia=new Function('modulationCatalog',source.slice(modInicio,modFim)+'\nreturn modulacoesDaTipologia;')(modExemplo);
assert.equal(modsDaTipologia(catalogoRaiz[1]).length,2,
  'Modulacoes filtradas pela tipologia principal, nao pelo codigo EA');
assert.equal(modsDaTipologia({id:'outra-familia'}).length,1);

const beginCorrecao=source.indexOf('function candidatosIdentificacaoTecnica(origem,catalogo){');
const endCorrecao=source.indexOf('function escolhaIdentificacao(){',beginCorrecao);
assert.ok(beginCorrecao>=0&&endCorrecao>beginCorrecao,'Funcao de correcao identificada');
const candidatos=new Function('normalizarReconhecimento','classificarTipoTipologia',
  source.slice(beginCorrecao,endCorrecao)+'\nreturn candidatosIdentificacaoTecnica;'
)(normalizarReconhecimento,classificarTipoTipologia);
const ea14={id:'ea14',codigo:'EA14',
  descricao:'PORTA DE GIRO - 2 FOLHAS - COM VENEZIANA VENTILADA - LINHA INOVA - HYDRO',fabricante:'HYDRO'};
const proposta=[
  ea14,
  {id:'pgr207',codigo:'INV-PGR207',descricao:ea14.descricao,fabricante:'HYDRO'},
  {id:'pgr107',codigo:'INV-PGR107',descricao:'PORTA DE GIRO - 1 FOLHA - LINHA INOVA - HYDRO',fabricante:'HYDRO'},
  {id:'ea05',codigo:'EA05',descricao:ea14.descricao,fabricante:'HYDRO'},
  {id:'outro',codigo:'INV-PGR999',descricao:ea14.descricao,fabricante:'PERFIL'},
  {id:'variacao',codigo:'INV-LEGADO',descricao:ea14.descricao,fabricante:'HYDRO',tipologia_principal_id:'pgr207'}
];
const corretos=candidatos(ea14,proposta);
assert.equal(corretos[0].codigo,'INV-PGR207','Mesma descricao primeiro');
assert.ok(!corretos.some(t=>t.id==='ea14'||t.id==='ea05'||t.id==='outro'||t.id==='variacao'),
  'Nao selecionar EA, outra empresa/fabricante ou variacao');
assert.ok(corretos.some(t=>t.codigo==='INV-PGR107'),
  'Permitir revisar descricao diferente com confirmacao extra');
// Verifica a tela de confirmação para as duas respostas e as três escolhas.
const state={choice:'',next:'',form:{
 differenceConfig:{value:''},differenceComparison:{
   children:[],replaceChildren(){this.children=[];},
   append(...children){this.children.push(...children);}
 },
 differenceSecondStep:{classList:{toggle(){}}},differenceCreateFields:{classList:{toggle(){}}},
 differenceCorrectFields:{classList:{toggle(){}}},differenceCorrectDescription:{textContent:''},
 differenceScope:{classList:{toggle(){}}},differenceScopeWork:{checked:true},differenceScopeFuture:{checked:false},
 differencePreserveCode:{textContent:''},
 differenceNewDescription:{value:'MODULO JANELA DE CORRER - SERIE 105'},
 differenceNewModules:{value:''},differenceSave:{disabled:true,textContent:''},
 differenceError:{textContent:''}
}};
const fakeDocument={
 querySelector(q){
  if(q.includes('differenceMatch'))return state.choice?{value:state.choice}:null;
  if(q.includes('differenceNext'))return state.next?{value:state.next}:null;
  return null;
 },
 createElement(tag){return {tag,textContent:'',className:'',children:[],
   append(...children){this.children.push(...children);}
 };}
};
const modReferencia={id:'m1',codigo_interno:'MOD-000045',numero_variacao:1,
 tipologia_principal_id:'fam',descricao:'FACHADA UNITIZADA - MODULO DE CORRER - SERIE 105'};
const fnInicio2=source.indexOf('function escolherDiferenca(){');
const fnFim2=source.indexOf('function abrirConferenciaTipologia(id){',fnInicio2);
assert.ok(fnInicio2>=0&&fnFim2>fnInicio2,'Funcoes de decisao presentes');
const normalizarTeste=v=>String(v||'').toUpperCase().replace(/[^A-Z0-9]+/g,' ').trim();
const functions=new Function('differencePendingItem','typologyCatalog','modulationCatalog',
 'document','node','modulacoesDaTipologia','codigoVariacaoTecnica','normalizarReconhecimento',
 source.slice(fnInicio2,fnFim2)+'\nreturn {atualizarTelaDiferenca};'
)(
 {id:'EA6A',tipologia_id:'fam',rotulo_tipologia_relatorio:'EA6A_1',
  descricao:'MODULO JANELA DE CORRER - SERIE 105'},
 [{id:'fam',codigo:'WINFAC-JCR203',
   descricao:'FACHADA UNITIZADA - MODULO DE CORRER - SERIE 105'}],[modReferencia],fakeDocument,
 id=>state.form[id],()=>[modReferencia],()=> 'WINFAC-JCR203-01',normalizarTeste
);
state.choice='sim';functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'SIM permite vincular configuração');
assert.equal(state.form.differenceComparison.children.length,2,'Descrições em duas caixas');
const boxes=state.form.differenceComparison.children;
assert.equal(boxes[0].children[0].textContent,'TIPOLOGIA INFORMADA NA OBRA');
assert.equal(boxes[1].children[0].textContent,'TIPOLOGIA DO CATÁLOGO');
assert.equal(boxes[0].children[1].textContent,'EA6A_1','Código original vem do relatório da obra');
assert.equal(boxes[1].children[1].textContent,'WINFAC-JCR203','Código principal do catálogo');
assert.equal(boxes[0].children[2].textContent,'Descrição');
assert.equal(boxes[1].children[2].textContent,'Descrição');
assert.ok(boxes[0].children[3].textContent.includes('JANELA DE CORRER'),'Descrição da obra intacta');
assert.ok(boxes[1].children[3].textContent.includes('FACHADA UNITIZADA'),'Descrição do catálogo intacta');
assert.ok(!boxes.some(b=>b.children[1].textContent.endsWith('-01')),'Sufixo técnico oculto da comparação');
state.choice='nao';state.next='nova';functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'NÃO permite cadastrar nova configuração');
assert.ok(state.form.differencePreserveCode.textContent.includes('WINFAC-JCR203'),
  'Confirma manter código da tipologia principal na nova configuração');
state.form.differenceNewDescription.value=modReferencia.descricao;
functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,true,'Impedir cadastrar descrição duplicada');
state.form.differenceNewDescription.value='MODULO JANELA DE CORRER - SERIE 105';
state.form.differenceScopeFuture.checked=true;
state.next='corrigir';state.form.differenceConfig.value='m1';
functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'Permitir corrigir descrição original somente após escolher configuração');
assert.equal(state.form.differenceScopeFuture.checked,false,'Correção não autoriza reconhecimento futuro');
state.next='adiar';functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'Permitir adiar e seguir obra');

// A transformação N é apenas visual: original e seletor permanecem intactos.
const displayStart=source.indexOf('function descricaoComparacaoComModulosN(descricao){');
const displayEnd=source.indexOf('function atualizarTelaDiferenca(){',displayStart);
assert.ok(displayStart>=0&&displayEnd>displayStart,'Função N somente de apresentação');
const helpers=new Function('modulacoesDaTipologia','normalizarReconhecimento',
 source.slice(displayStart,displayEnd)+
 '\nreturn {descricaoComparacaoComModulosN,modulacaoMesmaDescricao,quantidadeModulosExpressa};'
)(()=>[modReferencia],normalizarTeste);
const displayN=helpers.descricaoComparacaoComModulosN;
for(const n of [1,3,6,8,12]){
  assert.equal(displayN('GRADIL '+n+' MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO'),
    'GRADIL N MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO','Deve trocar somente numero de modulos');
}
assert.equal(displayN('GRADIL 3 MÓDULOS / 2 FOLHAS / 1600 x 2300'),
  'GRADIL N MÓDULOS / 2 FOLHAS / 1600 x 2300',
  'Não modificar folhas nem dimensões');
assert.equal(displayN('PORTA 1 MÓDULO + 2 MÓDULOS'),
  'PORTA N MÓDULO + N MÓDULOS','Formas singular e plural');
const modOriginal=modReferencia.descricao;
modReferencia.descricao='GRADIL 8 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
const obraOriginal='GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
const fakeState=[
  {id:'ob1',tipologia_id:'fam',descricao:obraOriginal},
  [{id:'fam',codigo:'UNIV-R08-GRADN00',
    descricao:'GRADIL - 8 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO'}],
  [modReferencia]
];
const renderN=new Function('differencePendingItem','typologyCatalog','modulationCatalog',
 'document','node','modulacoesDaTipologia','codigoVariacaoTecnica','normalizarReconhecimento',
 source.slice(fnInicio2,fnFim2)+'\nreturn {atualizarTelaDiferenca};'
)(fakeState[0],fakeState[1],fakeState[2],fakeDocument,
 id=>state.form[id],()=>[modReferencia],()=> 'UNIV-R08-GRADN00-01',normalizarTeste);
state.next='adiar';renderN.atualizarTelaDiferenca();
const rendered=state.form.differenceComparison.children;
assert.equal(rendered[0].children[3].textContent,'GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO',
  'A caixa da obra mostra o texto ORIGINAL sem substituir o número');
assert.equal(rendered[1].children[3].textContent,'GRADIL - N MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO',
  'A caixa do catálogo usa a descrição principal com N');
assert.equal(rendered[0].children[1].textContent,'Não informado no relatório');
assert.equal(rendered[1].children[1].textContent,'UNIV-R08-GRADN00');
assert.equal(fakeState[0].descricao,obraOriginal,'Descrição original da obra permanece inteira');
assert.equal(modReferencia.descricao,'GRADIL 8 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO',
  'Descrição original da modulação permanece inteira');
modReferencia.descricao=modOriginal;
assert.equal(helpers.quantidadeModulosExpressa('GRADIL 6 MODULO(S) - COM VIDRO'),6);
assert.equal(helpers.quantidadeModulosExpressa('PORTA 2 FOLHAS'),null,
  'Nunca deduzir número de módulos pelo número de folhas');
assert.equal(helpers.quantidadeModulosExpressa('GRADIL 2 MODULOS E 3 MODULOS'),null,
  'Não inferir número quando houver quantidades ambíguas');
modReferencia.descricao='GRADIL - 8 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
assert.equal(helpers.modulacaoMesmaDescricao({id:'fam'},'GRADIL 6 MODULO(S) - COM VIDRO'),null,
 'Não atribuir 6 módulos a configuração existente de 8 módulos');
assert.equal(helpers.modulacaoMesmaDescricao({id:'fam'},'GRADIL - 8 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO')?.id,'m1');
modReferencia.descricao=modOriginal;

// Romaneios: duas vias no A4 para poucos itens; uma via por página quando a lista cresce.
const iniciar=source.indexOf('function romaneioSaldoCompleto(item){');
const terminar=source.indexOf('function changeDetailMode(mode) {',iniciar);
assert.ok(iniciar>=0&&terminar>iniciar,'Funções de romaneios identificadas');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({
 '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
})[c]);
const montarRomaneio=new Function('works','escapeHTML','window','dispatchConfig',
 source.slice(iniciar,terminar)+'\nreturn construirHTMLRomaneio;'
)([{id:'obra',nome:'MIRAGE',cliente:'MOURA DUBEUX'}],esc,{},[]);
const cabecalho={id:'rm',obra_id:'obra',numero:'RM042',data_saida:'2026-07-08',
 motorista:'IRAN FRANCISCO',placa:'UHQ4A65',observacoes:''};
const linha=(n)=>({sequencia:n,codigo:'CG 1016',localizacao:'Ático',
 descricao:'CANTONEIRA 1x1',medida:'6 m',quantidade:10,unidade:'UNID.',area_m2:null});
const folhaTeste={...linha(1),codigo:'EA3',descricao:'MAXIM-AR',medida:'400,00 x 1.100,00 mm',area_m2:0.44};
const folhaFormato=montarRomaneio(cabecalho,[folhaTeste]);
assert.ok(folhaFormato.includes('0,40 × 1,10 m'),
 'Converter medidas de esquadrias expressas em milímetros para metros');
assert.ok(!folhaFormato.includes('400,00 x 1.100,00 mm'),
 'Não mostrar medida de esquadria em mm na impressão');
const medidaInicio=source.indexOf('function medidaRomaneioEmMetros(medida){');
const medidaFim=source.indexOf('function construirHTMLRomaneio(header,linhas){',medidaInicio);
const converter=new Function(source.slice(medidaInicio,medidaFim)+'\nreturn medidaRomaneioEmMetros;')();
assert.equal(converter('2.400,00 x 2.250,00 mm'),'2,40 × 2,25 m',
 'Formatação de origem com vírgula decimal');
assert.equal(converter('2400.00 x 2250.00 mm'),'2,40 × 2,25 m',
 'Formatação de origem com ponto decimal');
assert.equal(converter('6 m'),'6 m','Material em metros mantém unidade original');
assert.equal(converter('6'),'6','Não presumir unidade de material avulso');
const duas=montarRomaneio(cabecalho,[linha(1),linha(2),linha(3)]);
assert.equal((duas.match(/class="printPage two"/g)||[]).length,1,
 'Pequenos romaneios com duas vias em uma folha A4');
assert.equal((duas.match(/class="copy compact"/g)||[]).length,2,'Duas cópias idênticas');
assert.ok(duas.includes('MOURA DUBEUX')&&duas.includes('IRAN FRANCISCO'),
 'Modelo preserva campos cliente e motorista');
assert.ok(duas.includes('Quant.')&&duas.includes('Descrição')&&duas.includes('Entregue por'),
 'Romaneio mantém colunas e assinaturas do modelo enviado');
assert.ok(!duas.includes('<th>Localização</th>')&&!duas.includes('<th>Valor</th>'),
 'Localização e Valor não devem aparecer no impresso');
assert.ok(duas.includes('<col style="width:50%">'),'Descrição ganhou metade da largura');
assert.ok(duas.includes('>ARTEFAL<')||duas.includes('alt="Artefal"'),
 'Cabeçalho traz Artefal, como o modelo original');
assert.ok(duas.includes('alt="GVG"')&&duas.includes('class="headerTruck"'),
 'Cabeçalho traz GVG e ilustração de entrega');
assert.ok(duas.includes('Cód.:')||duas.includes('Cód.</strong>'),
 'Cabeçalho contém identificação do documento');
const doze=montarRomaneio(cabecalho,Array.from({length:12},(_,i)=>linha(i+1)));
assert.equal((doze.match(/class="printPage single"/g)||[]).length,2,
 'Listas longas usam uma via por página');
const quarenta=montarRomaneio(cabecalho,Array.from({length:40},(_,i)=>linha(i+1)));
assert.equal((quarenta.match(/class="printPage single"/g)||[]).length,6,
 'Paginar listas muito longas sem cortar itens');
assert.ok(!duas.includes('<script>'),'Impressão não injeta scripts');
const longas=Array.from({length:12},(_,i)=>({
 ...linha(i+1),descricao:'CANTONEIRA LONGA DE PERFIL EM ALUMINIO '.repeat(9)
}));
const saidaLonga=montarRomaneio(cabecalho,longas);
assert.ok((saidaLonga.match(/class="printPage single"/g)||[]).length>=4,
 'Textos longos devem gerar paginas de continuação para cada via');
assert.ok(saidaLonga.includes('@page{size:A4 portrait;margin:0}'),
 'A4 sem margem externa para reduzir cabeçalhos automáticos do navegador');
assert.ok(saidaLonga.includes('.printPage{height:297mm;padding:9mm;'),
 'Margens internas preservadas no A4');
assert.ok(duas.includes('class="truckSlot"')&&duas.includes('class="headerTruck"'),
 'Caminhão presente no cabeçalho');
assert.ok(duas.includes('<svg class="headerTruck"')&&
  !source.includes('UklGRgwDAABXRUJQVlA4IAADAABwEACdASou'),
 'Caminhão sem a linha preta do bitmap antigo, agora em SVG limpo');
assert.ok(/class="headerTitle"[\s\S]*?class="truckSlot"[\s\S]*?<\/div><\/div><div class="docNo">/.test(
 duas.replace(/\s+/g,' ')),
 'Caminhão fica DENTRO do mesmo quadro do título, antes da data');
assert.ok(duas.includes('grid-template-columns:18mm minmax(0,1fr) 30mm 18mm'),
 'Cabeçalho possui quatro áreas, sem coluna solta de caminhão');
const cancelado=montarRomaneio({...cabecalho,status:'cancelado',
 motivo_cancelamento:'Erro de carregamento; entrega não aconteceu'},[linha(1)]);
assert.ok(cancelado.includes('CANCELADO · SAÍDAS ESTORNADAS'),
 'Documento cancelado deve ser marcado também na impressão');
assert.ok(cancelado.includes('Erro de carregamento'),
 'Impressão cancelada deve mostrar motivo');
const extrair=source.slice(source.indexOf('function romaneioSaldoPorTipo(item,tipo,folhas){'),
 source.indexOf('function buscarEsquadriasRomaneio(row){'));
assert.ok(extrair.includes("if(tipo==='marco')return marcos")&&extrair.includes("if(tipo==='folha')return folhasRestantes"),
 'Envio parcial deve controlar os saldos de marcos e folhas separadamente');
assert.ok(source.includes("cancelado_em:'is.null'"),
 'Saldos e histórico devem ignorar saídas estornadas');
const ehInicio=source.indexOf('function ehMaximArRomaneio(item){');
const ehFim=source.indexOf('function buscarEsquadriasRomaneio(row){',ehInicio);
assert.ok(ehInicio>=0&&ehFim>ehInicio,'Validação de MAXIM-AR presente');
const {ehMaximArRomaneio,romaneioSaldoPorTipo}=new Function('shipmentStats','suggestedLeaves',
 source.slice(ehInicio,ehFim)+
 '\nreturn {ehMaximArRomaneio,romaneioSaldoPorTipo};'
)(x=>({released:Number(x.qtd_liberada),frames:Number(x.marcos||0),
 leaves:Number(x.folhas_enviadas||0),per:x.per||null,completas:0,
 marcosLiberados:Number(x.qtd_liberada),folhasLiberadas:Number(x.qtd_liberada)}),
  x=>Number((x.descricao||'').match(/(\d+)\s*FOLHA/i)?.[1]||0)||null);
assert.equal(ehMaximArRomaneio({descricao:'MAXIM-AR 1 FOLHA(S) - HYDRO'}),true);
assert.equal(ehMaximArRomaneio({descricao:'MAXIM AR 1 FOLHA(S)'}),true);
assert.equal(ehMaximArRomaneio({descricao:'MAXIMAR 1 FOLHA(S)'}),true);
assert.equal(ehMaximArRomaneio({descricao:'JANELA DE CORRER - 2 FOLHAS'}),false);
assert.equal(romaneioSaldoPorTipo({descricao:'MAXIM-AR 1 FOLHA',qtd_liberada:7,marcos:2},
 'completo',null),5,'Completa não exige composição de folhas');
assert.equal(romaneioSaldoPorTipo({descricao:'JANELA DE CORRER - 2 FOLHAS',qtd_liberada:7,marcos:2},
 'marco',null),5,'Janela permite expedir marco com saldo correto');
assert.ok(source.includes("leaves.closest('label').classList.toggle('hidden',!perguntaFolhas)"),
 'Campo de folhas escondido na saída completa do romaneio');
assert.ok(source.includes("node('shipmentCompositionSection').classList.toggle('hidden',!precisaComposicao)"),
 'Campo de folhas escondido na saída completa individual');

for(const expected of [
 'id="romaneiosPage"',
 'id="hubWorkSelect"',
 'id="hubEmitRomaneio"',
 'id="hubRomaneioList"',
 'id="openRomaneioHub"',
 'function isAlmoxarife()',
 'function podeEmitirRomaneio()',
 'function renderRomaneioHub()',
 'function abrirAreaRomaneios()',
 'const somenteRomaneios=isAlmoxarife()',
 "setView('romaneiosPage')",
 'Almoxarife — somente romaneios'
])assert.ok(source.includes(expected),'Área exclusiva precisa de '+expected);
const funcInicio=source.indexOf('function isAlmoxarife(){');
const funcFinal=source.indexOf('function invalidateAppSession(reason){',funcInicio);
assert.ok(funcInicio>=0&&funcFinal>funcInicio,'Guarda de navegação presente');
const evaluateRole=role=>new Function('membership','document','temPermissao',
 source.slice(funcInicio,funcFinal)+'\nreturn {isAlmoxarife,podeEmitirRomaneio};'
)({perfil:role},{querySelectorAll:()=>[]},key=>key==='romaneios.emitir'&&role==='almoxarife');
assert.equal(evaluateRole('almoxarife').isAlmoxarife(),true,'Reconhece perfil almoxarife');
assert.equal(evaluateRole('almoxarife').podeEmitirRomaneio(),true,'Permite emitir');
assert.equal(evaluateRole('consulta').podeEmitirRomaneio(),false,'Consulta não pode emitir');
for(const expected of [
  'function consultarRomaneio(id)',
  'function abrirRomaneioDocumento(id,{imprimir=false',
  'data-romaneio-consultar=',
  'data-hub-preview=',
  'button.addEventListener(\'click\',()=>consultarRomaneio',
  'b.addEventListener(\'click\',()=>consultarRomaneio',
  'barra.className=\'viewToolbar\'',
  'imprimirBotao.addEventListener(\'click\',()=>pagina.print())',
  "if(imprimir)pagina.setTimeout(()=>pagina.print(),350)"
])assert.ok(source.includes(expected),'Consulta sem impressão automática: '+expected);
const consultarStart=source.indexOf('function consultarRomaneio(id){');
const consultarEnd=source.indexOf('function imprimirRomaneio(id,janelaExistente=null){',consultarStart);
assert.ok(source.slice(consultarStart,consultarEnd).includes('imprimir:false'),
  'Consultar deve abrir sem solicitar impressão');
const descInicio=source.indexOf('function descricaoCurtaRomaneio(descricao,');
const descFim=source.indexOf('function dataRomaneioFormatada(value){',descInicio);
const descricaoCurta=new Function(source.slice(descInicio,descFim)+
 '\nreturn descricaoCurtaRomaneio;')();
assert.equal(descricaoCurta('JANELA DE CORRER - 2 FOLHAS - LINHA GOLD SLIM - HYDRO'),
  'JANELA CORRER 2F GOLD SLIM (COMPLETA)',
  'Descrição padrão solicitada pelo usuário');
assert.equal(descricaoCurta('PORTA DE CORRER - 2 FOLHAS - LINHA GOLD SLIM - HYDRO','marco'),
  'PORTA CORRER 2F GOLD SLIM (MARCO)','Desmembramento deve indicar marco');
assert.equal(descricaoCurta('MAXIM-AR 1 FOLHA(S) - LINHA INOVA - HYDRO'),
  'MAXIM-AR 1F INOVA (COMPLETA)','MAXIM-AR permanece conjunto completo');
const itemAntigo={...linha(1),natureza:'esquadria',
 descricao:'JANELA DE CORRER - 2 FOLHAS - LINHA GOLD SLIM - HYDRO',
 tipo_saida:'completo',descricao_impressao_definida:false};
assert.ok(montarRomaneio(cabecalho,[itemAntigo]).includes('JANELA CORRER 2F GOLD SLIM (COMPLETA)'),
 'Reimpressão de registros antigos também pode apresentar descrição abreviada');
const custom={...itemAntigo,descricao:'JANELA CORRER 2F GOLD SLIM - ABERTURA EXTERNA\n(COMPLETA)',
 descricao_impressao_definida:true};
const htmlCustom=montarRomaneio(cabecalho,[custom]);
assert.ok(htmlCustom.includes('ABERTURA EXTERNA\n(COMPLETA)'),
 'Descrição definida pelo usuário deve ter prioridade sobre abreviação automática');
assert.ok(htmlCustom.includes('white-space:pre-line')&&htmlCustom.includes('overflow-wrap:anywhere'),
 'Quebra de linha longa no A4 deve estar configurada');
for(const token of [
 'data-rom-field="descricao_romaneio"',
 'descricao_romaneio:descricaoRomaneio',
 'descricao_impressao_definida',
 'el.dataset.romaneioDescricaoChave',
 'textarea[data-rom-field="descricao_romaneio"]'
])assert.ok(source.includes(token),'Texto editável e persistente: '+token);
for(const expected of [
 'id="typologyAbbrevPanel"',
 'id="typologyAbbrevSearch"',
 'id="typologyAbbrevSelect"',
 'id="typologyAbbrevText"',
 'id="typologyAbbrevSave"',
 'id="typologyAbbrevReset"',
 'function renderAbreviacoesCatalogo()',
 'function salvarAbreviacaoCatalogo(restaurar=false)',
 'tipologias_abreviacoes',
 '/rest/v1/rpc/salvar_abreviacao_tipologia',
 'function descricaoPadraoRomaneio(item',
 'descricaoPadraoRomaneio(item,opcao.tipo)'
])assert.ok(source.includes(expected),'Painel de abreviação: '+expected);
const standardStart=source.indexOf('function descricaoPadraoRomaneio(item,');
const standardEnd=source.indexOf('function dataRomaneioFormatada(value){',standardStart);
const descricaoPadrao=new Function('typologyAbbreviations','descricaoCurtaRomaneio',
 source.slice(standardStart,standardEnd)+'\nreturn descricaoPadraoRomaneio;'
)([{tipologia_id:'tip1',descricao_base:'JANELA GOLD 2F - PEITORIL FIXO'}],descricaoCurta);
assert.equal(descricaoPadrao({tipologia_id:'tip1',descricao:'TEXTO COMPLETO'},'completo'),
 'JANELA GOLD 2F - PEITORIL FIXO (COMPLETA)',
 'Abreviação do catálogo deve prevalecer à sugestão automática');
assert.equal(descricaoPadrao({tipologia_id:'tip1',descricao:'TEXTO COMPLETO'},'marco'),
 'JANELA GOLD 2F - PEITORIL FIXO (MARCO)',
 'Mesmo padrão deve respeitar tipo de expedição');
assert.equal(descricaoPadrao({tipologia_id:'outra',descricao:'MAXIM-AR 1 FOLHA(S) - LINHA INOVA - HYDRO'},'completo'),
 'MAXIM-AR 1F INOVA (COMPLETA)','Fallback mantém padrão automático');
const formStart=source.indexOf('<form id="romaneioForm">');
const formEnd=source.indexOf('</form>',formStart);
const contentForm=source.slice(formStart,formEnd);
assert.ok(contentForm.indexOf('id="romaneioNotes"')>contentForm.indexOf('id="romaneioRows"'),
 'Observações devem ficar DEPOIS de todos os itens do romaneio');
assert.ok(contentForm.includes('class="romaneioSubmissionNote"'),
 'A emissão informa claramente que o botão executa a baixa das esquadrias');
assert.ok(!contentForm.includes('id="romaneioConfirm"'),
 'Não exigir checkbox redundante antes da emissão');
assert.ok(!source.includes("node('romaneioConfirm').checked"),
 'Validação do botão não deve exigir checkbox removido');
assert.ok(source.includes('id="workspaceNav"') && source.includes('id="navHome"')
 && source.includes('id="navRomaneios"'),
 'Nova navegação acessível permanece disponível');
assert.ok(!source.includes('id="romaneiosBack"')&&source.includes('id="navRomaneios"'),
 'Navegação dos romaneios permanece disponível exclusivamente na lateral');
assert.ok(source.includes('id="sentArea"')&&source.includes('function progressoExpedicao(list)'),
 'Indicadores de expedição preservados na tela inicial');
const observ=montarRomaneio({...cabecalho,observacoes:'ENTREGA PARCIAL\nCONFERIDO PELO ALMOXARIFE'},[linha(1)]);
assert.ok(observ.includes('ENTREGA PARCIAL\nCONFERIDO PELO ALMOXARIFE'),
 'Observações com quebra de linha preservadas no comprovante');
assert.ok(observ.includes('.notes{')&&observ.includes('white-space:pre-line'),
 'Observações aceitam linhas múltiplas na impressão');

const applicationScript=source.match(/<script>([\s\S]*?)<\/script>/);
assert.ok(applicationScript,'Script principal deve existir');
assert.doesNotThrow(()=>new Function(applicationScript[1]),'O script completo deve ser sintaticamente válido');
for(const id of ['navMaterials','materials','matCountPerfis','matCountAcessorios','matCountVariacoes',
 'matLista','matEditOverlay','matVarOverlay','matCemArquivo','matCemConferir']){
  assert.ok(source.includes('id="'+id+'"'),'Novo módulo de materiais deve conter '+id);
}
for(const token of ['ew_perfis','ew_acessorios','ew_materiais_variacoes',
 'function renderMateriais()','async function salvarMaterial(event)',
 'async function salvarVariacao(event)']){
  assert.ok(source.includes(token),'Cadastro de materiais deve conter '+token);
}
assert.ok(source.includes('Quantidade necessária')&&source.includes('Em estoque')&&
 source.includes('Comprimento da barra')&&source.includes('id="stockTransferPickWork"')&&
 !source.includes('data-stock-adjust')&&!source.includes('data-stock-open-new'),
 'Estoque mostra planejamento, saldo e transferência, sem cadastro direto de quantidade');
assert.ok(source.includes('async function abrirEstoque(modo)')&&source.includes('async function registrarMovimentoEstoque(e)'),
 'Estoque possui consulta real e movimentação auditável');
for(const id of ['navMaterials','navStock','navCem','materials','stock','cemImport',
 'cemFlagEsquadrias','cemFlagPerfis','cemFlagAcessorios','cemPreview','cemCommit']){
 assert.ok(source.includes('id="'+id+'"'),'Seções e flags CEM/estoque: '+id);
}
assert.ok(source.includes("const calc=new Set(tables.OBESQD.map"),
 'Importador deve separar calculados de itens desmarcados');
assert.ok(source.includes('function cemLerObra(xmlText)') && source.includes('async function cemExtrairXML(zip)'),
 'Leitura real local do XML exportado em ZIP do CEM');
assert.ok(source.includes('id="cemCommit" disabled'),
 'Importação real não pode ficar ativa antes da validação');
assert.ok(source.includes('A análise não altera o banco.'),
 'Análise do CEM não altera o banco antes da confirmação');

// Simula um ZIP real com ExpObras.xml compactado (método 8, DEFLATE).
const zipBegin=source.indexOf('function cemSqlValues(value){');
const zipEnd=source.indexOf('function cemLerObra(xmlText){',zipBegin);
assert.ok(zipBegin>=0&&zipEnd>zipBegin,'Leitor ZIP do CEM deve estar disponível');
const testZip=new Function(source.slice(zipBegin,zipEnd)+
 '\nreturn {cemSqlValues,cemExtrairXML};')();
assert.deepEqual(testZip.cemSqlValues("12,'PORTA, DUAS FOLHAS','JOAO''S',NULL"),
 ['12','PORTA, DUAS FOLHAS',"JOAO'S",''],'Campos SQL do CEM com vírgulas e apóstrofos');
const {deflateRawSync}=await import('node:zlib');
const xmlTeste='<ExportObras><Obra Codigo="TESTE-CEM"/></ExportObras>';
const member=Buffer.from('ExpObras.xml');
const raw=Buffer.from(xmlTeste);
const deflated=deflateRawSync(raw);
const localHeader=Buffer.alloc(30);localHeader.writeUInt32LE(0x04034b50,0);
localHeader.writeUInt16LE(20,4);localHeader.writeUInt16LE(8,8);
localHeader.writeUInt32LE(deflated.length,18);localHeader.writeUInt32LE(raw.length,22);
localHeader.writeUInt16LE(member.length,26);
const centralHeader=Buffer.alloc(46);centralHeader.writeUInt32LE(0x02014b50,0);
centralHeader.writeUInt16LE(20,6);centralHeader.writeUInt16LE(8,10);
centralHeader.writeUInt32LE(deflated.length,20);centralHeader.writeUInt32LE(raw.length,24);
centralHeader.writeUInt16LE(member.length,28);
const centralOffset=localHeader.length+member.length+deflated.length;
const centralSize=centralHeader.length+member.length;
const footer=Buffer.alloc(22);footer.writeUInt32LE(0x06054b50,0);
footer.writeUInt16LE(1,8);footer.writeUInt16LE(1,10);
footer.writeUInt32LE(centralSize,12);footer.writeUInt32LE(centralOffset,16);
const fakeZip=new Blob([localHeader,member,deflated,centralHeader,member,footer]);
assert.equal(await testZip.cemExtrairXML(fakeZip),xmlTeste,
 'Extrai corretamente ExpObras.xml compactado sem subir dados para servidor');


const mapStart=source.indexOf('function cemNome(v){');
const mapEnd=source.indexOf('function cemAtualizarBotao(){',mapStart);
assert.ok(mapStart>0&&mapEnd>mapStart,'Função de importação do CEM preservada');
const mapping=new Function(source.slice(mapStart,mapEnd)+'\nreturn cemMontarPayload;')();
const mapped=mapping({
 perfCatalog:[{CODPERF:'IN024',REF:'HYDRO',DESCRICAO:'MONTANTE LATERAL FOLHA',
  LINHA:'INOVA',PRENATP:'L. INOVA - T',PESO:'0.501'}],
 acesCatalog:[{CODACES:'NYL1900PTO',REF:'HYDRO',DESCRICAO:'BOTÃO DE NYL FIXAÇÃO',
  LINHA:'DIVERSOS',PRENATA:'PRETO',UNID:'PC',UNID_EMB:'PT'}],
 profMovs:[{CODPERF:'IN024',CODTRAT:'ANOD-1002-A13',CODTRATEXT:'ANOD-1002-A13',QTDE:'2',TAM:'1500'},
  {CODPERF:'IN024',CODTRAT:'ANOD-1002-A13',CODTRATEXT:'ANOD-1002-A13',QTDE:'3',TAM:'1000'},
  {CODPERF:'IN024',CODTRAT:'NATURAL',CODTRATEXT:'NATURAL',QTDE:'1',TAM:'1000'}],
 aceMovs:[{CODACES:'NYL1900PTO',PRENATA:'PRETO',QTDE:'8',UNID:'PC'}]
});
assert.equal(mapped.perfis.length,1,'Mesmo perfil deve ficar num único cadastro');
assert.equal(mapped.perfis[0].variacoes.length,2,'Anodizado e natural são variações');
assert.equal(mapped.perfis[0].variacoes[0].linhas_calculo,2,'Referências repetidas agrupadas');
assert.equal(mapped.acessorios[0].variacoes[0].cor,'PRETO','Cor do acessório mantida');
assert.equal(mapped.perfis[0].variacoes[0].quantidade_prevista,5,
 'Quantidades de perfis devem somar todos os cortes calculados');
assert.equal(mapped.perfis[0].variacoes[0].comprimento_total_m,6,
 'Comprimento total de perfil deve vir de QTDE × TAM (mm)');
assert.equal(mapped.acessorios[0].variacoes[0].quantidade_prevista,8,
 'Quantidade de acessórios deve considerar o campo QTDE do CEM');
assert.equal(mapped.acessorios[0].variacoes[0].unidade_prevista,'PC',
 'Unidade de acessórios deve respeitar o CEM');
assert.ok(source.includes('id="cemExistingNotice"'),'Mostra aviso de obra já cadastrada');
assert.ok(source.includes('id="cemCommitHint"'),'Explica quando a importação é habilitada');
assert.ok(source.includes("node('cemFlagEsquadrias').checked=!r.obraExistente"),
  'Seleciona esquadrias somente para obra nova, desmarcando para obra já existente');
assert.ok(source.includes('async function cemImportarSelecionados()')&&
 source.includes("r.precificacaoDraft?'ew_importar_obra_cem_precificacao':'ew_importar_obra_cem_financeiro'")&&
 source.includes("'ew_importar_cem_conciliado'"),
 'Importação usa RPC transacional de precificação para obra nova e preserva importação de materiais em obra existente');
assert.ok(!source.includes('rows.slice(0,6)'), 'Exibe a lista completa de materiais do CEM');


assert.ok(source.includes('id="stockManualForm"')&&source.includes('id="stockManualWork"')&&
 source.includes('id="stockNewMaterialCode"'), 'Cadastro manual de obra e material deve existir');
assert.ok(source.includes('class="releaseMirrorIntro hidden"')&&
 !source.includes('id="releaseComponent"')&&source.includes('id="releaseScopeNotice"')&&
 source.includes('id="releaseMirrorPanel" class="hidden"')&&
 source.includes("p_materiais:[],p_fonte:'SEM_BAIXA'"),
 'Liberação individual é somente técnica, completa e sem baixa');
assert.ok(source.includes('id="releaseBatchOpen"')&&source.includes('id="releaseBatchPreview"')&&
 source.includes("'/rest/v1/rpc/ew_liberar_lote_cem'")&&source.includes('function releaseBatchCollect()'),
 'Liberação em lote CEM deve ter espelho editável, validação e confirmação única');
assert.ok(source.includes('id="stockFactoryFilter"')&&source.includes('id="stockManualFactory"')&&
 source.includes('id="stockTransferPickLocal"')&&source.includes('id="stockTransferPickWork"')&&
 source.includes("stockTransferOpen(candidate.item.v.id")&&
 source.includes("stockObraTransferOpen(candidate.item.v.id")&&
 source.includes("'/rest/v1/rpc/ew_transferir_estoque_obra'")&&
 !source.includes('<th>Galpão</th><th>Ação</th>'),
 'Estoque transferível com seletor centralizado e tabela sem coluna Ação');
assert.ok(source.includes('const obrasParaRomaneio=works.filter'),
 'Romaneios escondem obra de estoque arquivado sem esquadrias e sem histórico');
assert.ok(source.includes("'/rest/v1/rpc/ew_liberar_plano_corte_componente'"),
 'Liberação confirma parte e quantidade em operação atômica');
assert.ok(source.includes("'/rest/v1/rpc/ew_movimentar_estoque_obra_local'")&&
 source.includes("'/rest/v1/rpc/ew_cadastrar_material_manual_estoque_local'"),
 'Cadastro existente e novos materiais exigem local físico do estoque');
assert.ok(source.includes('function cemEncontrarConciliacoes(r,perfis,acessorios)'),
 'Comparação de códigos importados com cadastro manual');
assert.ok(source.includes('ew_importar_cem_conciliado'),
 'Importação deve solicitar decisões do ADM em casos de equivalência');
assert.ok(!source.includes("rows.slice(0,6)"), 'Lista de materiais importados deve ser completa');

assert.ok(source.includes('id="stockCreateAnother"')&&
 source.includes("node('stockCreateAnother').addEventListener")&&
 source.includes('id="stockCreateEmptyForm"')&&
 source.includes("'/rest/v1/rpc/ew_criar_obra_estoque'"),
 'Criar estoque vazio sem registrar material ou saldo inicial');
assert.ok(source.includes('id="stockQuantityOverlay"')&&
 source.includes('id="stockQtyNew"')&&source.includes('function stockQtySubmit(e)'),
 'Ajustar quantidade altera saldo final pelo histórico de movimentos');
assert.ok(source.includes("p_origem:atual.informado?'AJUSTE':'ABERTURA'"),
 'Movimento de abertura e ajustes subsequentes separados');
const mmFnStart=source.indexOf('function mmOrNull(value){');
const mmFnEnd=source.indexOf('let stockQtySelected=',mmFnStart);
assert.ok(mmFnStart>=0&&mmFnEnd>mmFnStart,'Validador de comprimento comercial disponível');
const mmOrNullTeste=new Function(source.slice(mmFnStart,mmFnEnd)+'\nreturn mmOrNull;')();
assert.equal(mmOrNullTeste(6000),6000,'Comprimento comercial de 6000 mm é válido');
assert.equal(mmOrNullTeste(6500),6500,'Comprimento comercial de 6500 mm é válido');
assert.equal(mmOrNullTeste(''),null,'Comprimento vazio não deve gerar tamanho inventado');
assert.equal(mmOrNullTeste(6000.5),null,'Comprimento comercial deve ser inteiro em mm');
assert.ok(!source.includes('data-stock-manual='),'A tabela não pode exibir lançamento em cada linha');
assert.ok(!source.includes('data-stock-var='),'A tabela não pode exibir botão Físico geral');


assert.ok(source.includes('OBAPROV:[],OBACES:[]'),
 'Exportação de obra CEM deve ler OBAPROV e OBACES');
assert.ok(!source.includes('id="stockImportCem"')&&source.includes('id="stockManageLocations"'),
 'Remover botão de importar quantidades da tela de estoque, preservando administração');
assert.ok(!source.includes("'/rest/v1/rpc/ew_importar_saldo_obra_cem'")&&
 !source.includes("'/rest/v1/rpc/ew_excluir_estoque_local'")&&
 !source.includes("'/rest/v1/rpc/ew_restaurar_estoque_local'"),
 'Importação de saldo físico pelo CEM e arquivamento isolado estão desativados');
assert.ok(source.includes('id="stockManualNote" rows="2" maxlength="500"'),
 'Observação do cadastro manual deve ser opcional');
assert.ok(source.includes('id="stockManualQty" type="number" min="1" step="1"'),
 'Quantidade de barras no cadastro manual é sempre positiva e inteira');
const formKind=source.slice(source.indexOf('id="stockManualKind"'),
 source.indexOf('id="stockManualQty"'));
assert.ok(formKind.includes('value="ABERTURA"')&&formKind.includes('value="COMPRA"')
 &&!formKind.includes('value="AJUSTE"')&&!formKind.includes('value="SAIDA_MANUAL"'),
 'Cadastro inicial manual somente aceita quantidades positivas');
const stockReadStart=source.indexOf('function stockCemDados(r){');
const stockReadEnd=source.indexOf('function stockCemClose(){',stockReadStart);
const stockNameStart=source.indexOf('function cemNome(v){');
const stockNameEnd=source.indexOf('function cemVarPerfil(v){',stockNameStart);
assert.ok(stockReadStart>0&&stockReadEnd>stockReadStart&&stockNameEnd>stockNameStart,
 'Funções do analisador de estoque CEM encontradas');
const stockParser=new Function(source.slice(stockNameStart,stockNameEnd)+
 source.slice(stockReadStart,stockReadEnd)+'\nreturn stockCemDados;')();
const testStock=stockParser({
 barrasAproveitamento:[
 {CODPERF:'LG079',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'10',BARRA:'6000'},
 {CODPERF:'LG079',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'3',BARRA:'6000'},
 {CODPERF:'LG079',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'5',BARRA:'6500'}
 ],
 acessoriosObra:[{CODACES:'NYL1900PTO',PRENATA:'PRETO',QTDE:'12.5'}]
});
assert.equal(testStock.perfis.length,2,'Mesmo perfil com 2 comprimentos tem 2 saldos');
assert.equal(testStock.perfis[0].quantidade,13,'Soma barras da mesma cor e comprimento');
assert.equal(testStock.perfis[1].comprimento_mm,6500,'Preserva a barra comercial de 6500mm');
assert.equal(testStock.acessorios[0].quantidade,12.5,'Acessórios mantêm quantidades decimais');
assert.throws(()=>stockParser({barrasAproveitamento:[],acessoriosObra:[]}),/OBAPROV/);

const embalados=stockParser({
 barrasAproveitamento:[{CODPERF:'000633',CODTRAT:'ANOD-1002-A13',NUMBARRAS:'12',BARRA:'6000'}],
 acessoriosObra:[
  {CODACES:'PAR1032NAT',PRENATA:'NATURAL',QTDE:'23',EMBALAGEM:'100',UNID_EMB:'PT'},
  {CODACES:'GUA3660PTO',PRENATA:'PRETO',QTDE:'59',EMBALAGEM:'50',UNID_EMB:'RL'},
  {CODACES:'GUA5780PTO',PRENATA:'PRETO',QTDE:'2.736',EMBALAGEM:'50',UNID_EMB:'RL'},
  {CODACES:'LUV9900NAT',PRENATA:'NATURAL',QTDE:'47',EMBALAGEM:'1',UNID_EMB:'PC'}
 ]});
const bMap=new Map(embalados.acessorios.map(x=>[x.codigo,x]));
assert.equal(bMap.get('PAR1032NAT').quantidade,2300,'23 pacotes de 100 são 2300 peças');
assert.equal(bMap.get('GUA3660PTO').quantidade,2950,'59 rolos de 50 são 2950 metros');
assert.equal(bMap.get('GUA5780PTO').quantidade,136.8,'Metragem fracionada deve respeitar embalagem');
assert.equal(bMap.get('LUV9900NAT').quantidade,47,'Embalagem unitária não multiplica quantidade');
assert.ok(source.includes("node('stockManualContinue').checked")&&
 source.includes('stockManualOpen();')&&source.includes('id="stockManualContinue" checked'),
 'Cadastro em lote reutiliza a obra sem obrigar observação a cada item');



assert.ok(source.includes('const obrasComEsquadrias=works.filter(w=>w.cadastro_manual===true||elements.some(e=>e.obra_id===w.id));')&&
 source.includes('node(\'count\').textContent=obrasComEsquadrias.length;')&&
 source.includes('node(\'works\').innerHTML=obrasComEsquadrias.map('),
 'Tela inicial exibe apenas obras com esquadrias');
assert.ok(source.includes('id="stockReportIncludeEmpty"')&&
 source.includes('function stockReportRender(){')&&
 source.includes("node('stockReportIncludeEmpty').addEventListener('change',stockReportRender)"),
 'Resumo de estoque pode incluir ou excluir obras sem esquadrias');
assert.ok(source.includes("node('stockManualQty').min='1'")&&
 source.includes('quantidade<1'), 'Cadastro manual exige quantidade mínima de 1');
assert.ok(source.includes('id="stockManualCode"')&&
 source.includes('id="stockManualMaterial"')&&
 source.includes('id="stockManualLength"')&&
 source.includes('function stockManualColorPopulate(){'),
 'Cadastro manual separa código, cor/acabamento e comprimento');
assert.ok(source.includes('ew_cadastrar_comprimento_comercial')&&
 source.includes('function stockManualAddLength(){'),
 'Cadastro de novos tamanhos comerciais usa RPC com permissão ADM');
assert.ok(!source.includes('id="stockNewManual"')&&
 !source.includes('id="stockReceiveNfe"')&&
 !source.includes('id="stockFactoryCreate"')&&
 !source.includes("node('stockNewManual').addEventListener")&&
 !source.includes("node('stockFactoryCreate').addEventListener"),
 'Estoque não exibe entradas manuais, NF-e e cadastro de galpão redundantes');
assert.ok(source.includes('function stockCemReadMirror(){')&&
 source.includes('function stockCemMirrorRow(tipo,row={},index=-1){')&&
 source.includes('Importação de saldo físico pelo CEM desativada. Utilize Recebimento.')&&
 !source.slice(source.indexOf('async function stockCemCommit(){'),source.indexOf("node('stockCemAnalyze').addEventListener('click',stockCemAnalyze)")).includes('request('),
 'Espelho permanece disponível para conferência; importação CEM não registra saldo físico');
assert.ok(source.includes('stockCemMirrorUpdate')&&source.includes('data-stock-cem-add'),
 'Espelho de importação permite alterações e inclusão de linhas');
assert.ok(!source.includes('CEM Plus'),'Nome da marca não deve aparecer na interface nem em mensagens de erro');
const mirrorStart=source.indexOf('function stockCemReadMirror(){');
const mirrorEnd=source.indexOf('function stockCemMirrorUpdate(){',mirrorStart);
assert.ok(mirrorStart>0&&mirrorEnd>mirrorStart,'Função do espelho importável');
const mockNodes=[];
const mockRoot={querySelectorAll:()=>mockNodes};
const mockNode=()=>mockRoot;
const normalizar=v=>String(v||'').trim().toUpperCase();
const mirrorParsed={perfis:[{codigo:'LG079',cor:'ANODIZADO',quantidade:10,comprimento_mm:6000}],acessorios:[]};
const mirrorExtract=new Function('node','cemNome','stockCemParsed',
 source.slice(mirrorStart,mirrorEnd)+'\nreturn stockCemReadMirror;')(
 mockNode,normalizar,mirrorParsed
);
function fakeStockRow(kind,index,data){
 return {dataset:{stockCemKind:kind,stockCemIndex:String(index)},
 querySelector(sel){const values={
 '.stockCemSelect':{checked:data.enabled!==false},
 '.stockCemCode':{value:data.codigo},
 '.stockCemColor':{value:data.cor},
 '.stockCemQty':{value:data.quantidade},
 '.stockCemLength':{value:data.comprimento_mm??''}
 };return values[sel];}};
}
mockNodes.push(fakeStockRow('perfil',0,{codigo:'LG079',cor:'ANODIZADO',quantidade:'12',comprimento_mm:'6500'}));
mockNodes.push(fakeStockRow('acessorio',0,{codigo:'NYL1900PTO',cor:'PRETO',quantidade:'8',enabled:false}));
const mirrorResult=mirrorExtract();
assert.equal(mirrorResult.perfis[0].quantidade,12,'Quantidade editada deve chegar ao payload');
assert.equal(mirrorResult.perfis[0].comprimento_mm,6500,'Comprimento editado deve chegar ao payload');
assert.equal(mirrorResult.acessorios.length,0,'Itens desmarcados não podem ser enviados');
assert.equal(mirrorResult.edicoes,1,'Alteração do arquivo original fica identificada');
mockNodes.push(fakeStockRow('perfil',-1,{codigo:'LG079',cor:'ANODIZADO',quantidade:'1',comprimento_mm:'6500'}));
assert.throws(()=>mirrorExtract(),/repetido/, 'Linhas duplicadas precisam de conferência');

// Monitoramento de acessos: a senha e os tokens nunca são guardados no histórico.
for(const id of ['userAccessHistoryToggle','userAccessHistoryPanel',
 'userAccessHistoryUser','userAccessHistoryPeriod','userAccessHistoryRefresh',
 'userAccessHistoryList','userAccessHistoryStatus'])
 assert.ok(source.includes('id="'+id+'"'), 'Campo de auditoria ausente: '+id);
for(const fragment of ["'/rest/v1/rpc/ew_registrar_evento_acesso'",
 "accessLogRegister('entrada')","accessLogRegister('saida',5000)",
 "accessLogRegister('atividade')","function accessHistoryLoad()",
 "timeZone:'America/Recife'","AUTENTICACAO_ANTERIOR",
 "'Últimos 7 dias'"])
 assert.ok(source.includes(fragment)||fragment==="'Últimos 7 dias'"&&source.includes('Últimos 7 dias'),
  'Funcionalidade de histórico ausente: '+fragment);
assert.ok(source.includes("select:'usuario_id,entrada_em,saida_em,ultima_atividade_em,origem'"),
 'Histórico não deve exibir senhas, tokens ou IPs');
const auditFmtStart=source.indexOf('function accessHistoryDate(raw){');
const auditFmtEnd=source.indexOf('function accessHistoryPopulateUsers(){',auditFmtStart);
assert.ok(auditFmtStart>0&&auditFmtEnd>auditFmtStart);
const formatTest=new Function(source.slice(auditFmtStart,auditFmtEnd)+'return accessHistoryDate;')();
assert.match(formatTest('2026-11-12T12:00:00Z'),/09:00:00/,
 'Horário de Recife deve ser UTC-3');

assert.ok(source.includes('async function sessaoUnicaEntrar()')&&
 source.includes("sessaoUnicaRPC('consultar')")&&source.includes("sessaoUnicaRPC('assumir')")&&
 source.includes("sessaoUnicaRPC('validar')")&&source.includes("sessaoUnicaRPC('sair')"),
 'Uma conta pode manter apenas uma sessão ativa, com substituição consciente');
assert.ok(source.includes("sessaoUnicaMonitorar()")&&source.includes("setInterval(()=>{if(session)sessaoUnicaValidar(true)"),
 'A sessão substituída deve ser identificada com monitor periódico');
assert.ok(source.includes("if(!await sessaoUnicaEntrar())")&&
 source.includes("const permitido=await sessaoUnicaEntrar();")&&
 source.includes("async function restaurarSessaoSalva()"),
 'Login e restauração de sessão devem passar pelo controle de sessão única');
// Não derrubar o usuário por falhas temporárias ou de permissão da função de contas.
assert.ok(source.includes('const invalidAuth=/Acesse sua conta')&&
 source.includes('if(authenticated&&response.status===401&&invalidAuth)'),
 'Falha genérica da API de usuários não deve encerrar uma sessão válida');
// Perfil Gerenciador: mesmas ações operacionais do ADM, sem delegar privilégios ADM.
const edgeSource=readFileSync(fileURLToPath(new URL('../supabase/functions/ewgest-acesso/index.ts',import.meta.url)),'utf8');
const roleMigration=readFileSync(fileURLToPath(new URL('../supabase/migrations/20261118_perfil_gerenciador.sql',import.meta.url)),'utf8');
assert.ok(source.includes('function canAdministrate()')&&
 source.includes("['administrador','gerenciador']")&&
 source.includes("function isFullAdminUser()"),
 'Gerenciador deve acessar módulos ADM sem ser classificado como ADM');
assert.ok(source.includes('data-show-password="password"')&&
 ['createUserPassword','userResetPassword','myOldPassword','myNewPassword','myNewPasswordRepeat']
 .every(id=>source.includes('data-show-password="'+id+'"')),
 'Mostrar/Ocultar disponível em todas as telas de senha');
assert.ok(source.includes('const protectedAdm=!isFullAdminUser()')&&
 source.includes('Gerenciador não pode alterar ou conceder perfil ADM.'),
 'Interface não permite Gerenciador editar ADM ou conceder promoção');
assert.ok(edgeSource.includes('async function requireTargetEditable(caller, account)')&&
 edgeSource.includes("member?.perfil === 'administrador'")&&
 edgeSource.includes("!isFullAdmin(caller) && nivel<=2")&&
 edgeSource.includes('await requireTargetEditable(caller, data);'),
 'Servidor impede Gerenciador editar, redefinir senha, reativar/desativar contas ADM');
assert.ok(edgeSource.includes("'gerenciador'")&&
 edgeSource.includes('function requireManager(caller)'),
 'Gerenciador deve ser perfil válido e reconhecido no servidor');
assert.ok(roleMigration.includes('usuarios_login_perfil_check')&&
 roleMigration.includes('usuarios_empresas_perfil_check')&&
 roleMigration.includes('alter policy')&&roleMigration.includes('outdef'),
 'Banco precisa aceitar Gerenciador em RLS e em RPCs');
const startRole=source.indexOf('function isFullAdminUser(){');
const endRole=source.indexOf('function maskPassword(id){',startRole);
assert.ok(startRole>0&&endRole>startRole);
const checkRoles=new Function('membership','currentAccessLevel',source.slice(startRole,endRole)+
 'return {manager:canAdministrate(),admin:isFullAdminUser()};');
assert.deepEqual(checkRoles({perfil:'gerenciador'},2),{manager:true,admin:false});
assert.deepEqual(checkRoles({perfil:'administrador'},1),{manager:true,admin:true});
assert.deepEqual(checkRoles({perfil:'tecnico'},3),{manager:false,admin:false});

// Exclusão administrativa: sem remover identidade Auth nem o histórico dos autores.
assert.ok(source.includes('id="userDeleteButton"')&&
 source.includes("node('userDeleteButton').addEventListener('click'")&&
 source.includes("acao:'excluir'")&&
 source.includes("excluido_em:'is.null'"),
 'O cadastro deve oferecer exclusão e ocultar contas excluídas');
assert.ok(source.includes("target.perfil==='administrador'")&&
 source.includes("target.usuario_id===currentUser?.id"),
 'Bloquear exclusão de ADM e do próprio usuário');
assert.ok(edgeSource.includes("if (action === 'excluir')")&&
 edgeSource.includes("target.perfil === 'administrador'")&&
 edgeSource.includes("adminLink?.perfil === 'administrador'")&&
 edgeSource.includes("excluido_por:caller.user.id")&&
 edgeSource.includes("historico_preservado:true")&&
 edgeSource.includes("!account.ativo || account.excluido_em"),
 'Excluir deve bloquear Auth, preservar identidade e impedir logins');
const deleteAction=edgeSource.slice(edgeSource.indexOf("if (action === 'excluir')"),
 edgeSource.indexOf("if (action === 'reativar')"));
assert.ok(!deleteAction.includes('admin.auth.admin.deleteUser'),
 'Exclusão não pode apagar referências históricas a auth.users');
const removalMigration=readFileSync(fileURLToPath(new URL('../supabase/migrations/20261118_exclusao_administrativa_usuarios.sql',import.meta.url)),'utf8');
assert.ok(removalMigration.includes('excluido_em')&&removalMigration.includes('excluido_por'),
 'Exclusão precisa ficar registrada no banco');
assert.ok(source.includes('id="restoreSessionBtn"')&&
 source.includes("node('restoreSessionBtn').addEventListener('click',restaurarSessaoSalva)")&&
 source.includes("function erroDeSessaoIrrecuperavel(error)"),
 'Restaurar sessão no F5 sem pedir senha e sem limpar token por erro temporário');
const restoreFn=source.slice(source.indexOf('async function restaurarSessaoSalva(){'),
 source.indexOf("node('restoreSessionBtn').addEventListener"));
assert.ok(restoreFn.indexOf("'/auth/v1/token?grant_type=refresh_token'")<
 restoreFn.indexOf("sessaoUnicaEntrar()"),'Renovar credenciais antes de validar a sessão única');
assert.ok(restoreFn.includes('if(!session||erroDeSessaoIrrecuperavel(error))')&&
 restoreFn.includes("retry.classList.remove('hidden')"),
 'Falha de rede deve preservar a sessão, oferecendo botão de tentar novamente');


// Exclusão de obra segura somente antes de qualquer liberação/romaneio/estoque.
const worksMigration=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_exclusao_segura_obras_pre_operacao.sql',import.meta.url)),'utf8');
for(const id of ['manageWorks','cadastroJumpObras','worksCreateManual','manageWorksList',
 'manageWorksReview','manageWorksReason','manageWorksDelete',
 'manageWorksRefresh','manageWorksFeedback'])
 assert.ok(source.includes('id="'+id+'"'), 'Gestão de obras incompleta: '+id);
assert.ok(source.includes("abrirGerenciamentoObras")&&
 source.includes("request('/rest/v1/rpc/ew_inspecionar_reversao_obra'")&&
 source.includes("request('/rest/v1/rpc/ew_arquivar_obra_reconciliada'"),
 'Exclusão deve passar por consulta e revalidação no servidor');
assert.ok(source.includes('workDeleteOperationId=crypto.randomUUID()')&&
 source.includes("p_operacao_id:operation")&&source.includes('window.confirm(aviso)'),
 'Exclusão exige chave idempotente e uma confirmação expressa');
for(const t of ['public.liberacoes_corte','public.saidas_producao','public.romaneios',
 'public.ew_estoque_obras_movimentos','public.ew_liberacoes_lotes',
 'public.ew_planos_liberados','v_qtd_liberada>0','v_qtd_fabricada>0']){
 assert.ok(worksMigration.includes(t),'Banco precisa impedir exclusão com operações: '+t);
}
for(const t of ['delete from public.classificacoes_tipologias_auditoria',
 'delete from public.esquadrias_descricoes_revisoes','delete from public.ew_cem_obras_materiais',
 'delete from public.ew_estoques_locais','delete from public.esquadrias',
 'delete from public.obras']){
 assert.ok(worksMigration.includes(t),'Excluir somente dados da obra: '+t);
}
for(const master of ['public.tipologias','public.fabricantes','public.ew_perfis',
 'public.ew_acessorios','public.tipologias_abreviacoes']){
 assert.ok(!worksMigration.includes('delete from '+master+' '),
  'Não excluir cadastros gerais ao remover uma obra: '+master);
}
assert.ok(worksMigration.includes('pg_catalog.pg_advisory_xact_lock')&&
 worksMigration.includes('for update')&&
 worksMigration.includes('v_ver:=public.ew_verificar_exclusao_obra(p_obra_id)'),
 'Conferir bloqueios dentro da mesma transação antes de excluir');
assert.ok(worksMigration.includes('public.ew_obras_exclusoes_historico')&&
 worksMigration.includes('excluido_por'),
 'Registrar autoria da exclusão em auditoria fora da obra');


const migrationBase=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_base.sql',import.meta.url)),'utf8');
const migrationRelease=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_liberacoes.sql',import.meta.url)),'utf8');
const migrationStock=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_estoque_arquivamento.sql',import.meta.url)),'utf8');
const migrationReimport=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_importacoes_ativas.sql',import.meta.url)),'utf8');
const migrationCompat=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_compatibilidade.sql',import.meta.url)),'utf8');
assert.ok(source.includes('id="userOperationsToggle"')&&
 source.includes("apiGet('ew_auditoria_operacoes'")&&
 source.includes('id="userOperationsExport"')&&
 source.includes('function operationReportDisplay()'),
 'Relatório de auditoria por usuários, períodos e obras precisa estar ativo');
assert.ok(source.includes('data-work-cancel-releases=')&&
 source.includes('id="manageWorksReverseStock"')&&
 source.includes('id="manageWorksCancelShipments"')&&
 source.includes('id="manageWorksGoRomaneios"'),
 'Gerenciar obras oferece cancelamento de liberações por obra, saídas e estorno de estoque');
assert.ok(source.includes("'/rest/v1/rpc/ew_cancelar_liberacoes_obra'")&&
 source.includes("'/rest/v1/rpc/ew_estornar_estoque_obra'")&&
 source.includes('function executarReversaoObra(tipo)'),
 'UI preserva RPCs de cancelamento de liberação e reversão do estoque');
for(const term of ['public.ew_auditoria_operacoes','public.obras add column if not exists arquivada_em',
 'public.liberacoes_corte add column if not exists cancelado_em',
 'public.ew_liberacoes_lotes add column if not exists cancelado_em',
 'estorno_de_id uuid unique','create trigger ew_auditar_cancelamento_romaneio',
 'ew_bloquear_insercao_obra_arquivada']){
 assert.ok(migrationBase.includes(term),'Auditoria/proteção incompleta: '+term);
}
assert.ok(migrationRelease.includes('ew_cancelar_liberacoes_obra')&&
 migrationRelease.includes('ew_inspecionar_reversao_obra')&&
 migrationRelease.includes('CANCELAR_LIBERACOES')&&
 migrationRelease.includes('s.cancelado_em is null'),
 'Cancelamento deve bloquear saídas ativas e deixar auditoria');
assert.ok(migrationStock.includes('ew_estornar_estoque_obra')&&
 migrationStock.includes('-m.quantidade_delta')&&
 migrationStock.includes(",'ESTORNO',")&&
 migrationStock.includes('estorno_de_id')&&
 migrationStock.includes('ew_arquivar_obra_reconciliada')&&
 migrationStock.includes('ARQUIVAR_OBRA'),
 'Estorno e arquivamento devem preservar os movimentos e auditar atos');
const archiveSource=migrationStock.slice(migrationStock.indexOf('create or replace function public.ew_arquivar_obra_reconciliada'));
assert.ok(!archiveSource.includes('delete from public.')&&
 archiveSource.includes('update public.obras set arquivada_em=now()'),
 'Obra com histórico reconciliado só pode ser arquivada, não apagada');
assert.ok(migrationReimport.includes('arquivada_em IS NULL')&&
 source.includes("arquivada_em:'is.null'"),
 'Reimportar o CEM com mesmo código deve ignorar obras arquivadas');
assert.ok(migrationCompat.includes('select public.ew_arquivar_obra_reconciliada(')&&
 migrationCompat.includes('select public.ew_inspecionar_reversao_obra('),
 'Não permitir exclusão física pela RPC antiga');
assert.ok(source.includes("cancelado_em:'is.null'"),
 'Painel não deve tratar liberação cancelada como ativa');


const miscReversal=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_saidas_avulsas.sql',import.meta.url)),'utf8');
const retroAudit=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_reconciliacao_historico_antigo.sql',import.meta.url)),'utf8');
assert.ok(source.includes('CANCELAR_SAIDAS_AVULSAS')&&
 source.includes("'ew_cancelar_saidas_avulsas_obra'")&&
 source.includes('DEVOLVIDO'),
 'Saídas avulsas exigem devolução física confirmada e registro auditável');
assert.ok(miscReversal.includes('ew_cancelar_saidas_avulsas_obra')&&
 miscReversal.includes("ri.saida_producao_id=s.id")&&
 miscReversal.includes('CANCELAR_SAIDAS_AVULSAS'),
 'Não pode estornar uma saída vinculada a romaneio como se fosse avulsa');
assert.ok(retroAudit.includes("origem','cancelamento_anterior_a_v43_1")&&
 retroAudit.includes("r.cancelado_por is not null")&&
 retroAudit.includes('not exists'),
 'Migração de histórico deve preservar autor/data originais e evitar duplicidade');

// Estornos via Estoque não alteram cadastros gerais nem disponibilizam movimentação normal de estoque arquivado.
for(const id of ['stockArchivedReview','stockReversePanel','stockReverseTitle',
 'stockReverseSummary','stockReverseDetails','stockReverseReason',
 'stockReverseMessage','stockReverseApply','stockReverseBack']){
 assert.ok(source.includes('id="'+id+'"'),'Conferência de estornos em Estoque sem '+id);
}
assert.ok(source.includes('function stockReversalBalances(obraId)')&&
 source.includes('function stockReverseRevisar(id)')&&
 source.includes('function stockReverseExecutar()')&&
 source.includes(",'estorno_de_id'")===false&&
 source.includes('local_estoque,estorno_de_id')&&
 source.includes("request('/rest/v1/rpc/ew_estornar_estoque_obra'")&&
 source.includes("request('/rest/v1/rpc/ew_inspecionar_reversao_obra'"),
 'Estornos do estoque requerem saldo, conferência de pendências e RPC auditada');
assert.ok(source.includes('const ativas=new Set(stockLocais.filter(l=>!l.excluido_em)')&&
 source.includes('root.innerHTML=stockLocais.filter(loc=>!loc.excluido_em&&works.some(w=>w.id===loc.obra_id))')&&
 source.includes('stockReverseSelectedWorkId'),
 'Estoques de obras encerradas desaparecem da administração operacional; auditoria preservada');
// Obra com estoque arquivado permanece selecionável exclusivamente para consulta.
for(const id of ['stockWorkHistory','stockArchivedHint','stockReverseHistoryList','stockReverseHistoryFilter']){
 assert.ok(source.includes('id="'+id+'"'),'Histórico de estoque por obra precisa de '+id);
}
assert.ok(source.includes("locaisPorObra.get(w.id)?.excluido_em")&&
 source.includes("ESTOQUE ARQUIVADO")&&
 source.includes('Somente consulta')&&
 source.includes("stockLocais.some(l=>l.obra_id===origem&&l.excluido_em)"),
 'Estoque arquivado permanece consultável, mas não permite transferências');
assert.ok(source.includes('function stockReverseHistoryRender(id)')&&
 source.includes('async function stockReverseIndividual(movimentoId)')&&
 source.includes("'/rest/v1/rpc/ew_estornar_movimento_obra'")&&
 source.includes('data-stock-reverse-item'),
 'Histórico deve oferecer estorno individual pela RPC auditada');
const estornoUnitMigration=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_estorno_individual_movimentos_estoque.sql',import.meta.url)),'utf8');
for(const parte of ['ew_estornar_movimento_obra','estorno_de_id',
 'pg_catalog.pg_advisory_xact_lock','ew_inspecionar_reversao_obra','ESTORNAR_ESTOQUE',
 'count(distinct m.local_estoque)']){
 assert.ok(estornoUnitMigration.includes(parte),'RPC estorno individual incompleta: '+parte);
}
// A confirmação de estorno de estoque é única e explica o efeito da operação.
const confirmacaoUnica=source.slice(source.indexOf('async function stockReverseIndividual(movimentoId)'),
 source.indexOf("node('stockManageLocations').addEventListener('click',stockManageOpen);"));
assert.ok(confirmacaoUnica.includes('Tem certeza que deseja estornar esta movimentação?')&&
 confirmacaoUnica.includes('Tem certeza que deseja estornar todas as movimentações ainda não estornadas?')&&
 !confirmacaoUnica.includes('Digite ESTORNAR')&&
 !confirmacaoUnica.includes('digite ESTORNAR')&&
 !confirmacaoUnica.includes('window.prompt('),
 'Estorno no Estoque deve exigir somente confirmação descritiva, sem digitar ESTORNAR');
const revGerenciar=source.slice(source.indexOf('async function executarReversaoObra(tipo)'),
 source.indexOf("node('manageWorksGoRomaneios').addEventListener"));
assert.ok(revGerenciar.includes("const aviso=tipo==='estoque'?")&&
 !revGerenciar.includes("tipo==='estoque'?'ESTORNAR'"),
 'Gerenciar obras também não pode exigir palavra digitada para estornar estoque');
// v46.20: exclusão definitiva com motivo e somente uma confirmação, sem digitar código.
const formExcluir=source.slice(source.indexOf('<div id="manageWorksDeleteForm"'),
 source.indexOf('<section id="romaneiosPage"'));
const fluxoExcluir=source.slice(source.indexOf("node('manageWorksDelete').addEventListener"),
 source.indexOf("window.addEventListener('error'"));
assert.ok(formExcluir.includes('>Excluir obra definitivamente</button>')&&
 formExcluir.includes('faça uma nova importação')&&
 !formExcluir.includes('Restaurar obra'),
 'Exclusão exige aviso inequívoco, sem oferecer restauração');
assert.ok(fluxoExcluir.includes('ATENÇÃO: PROCESSO IRREVERSÍVEL. TEM CERTEZA QUE DESEJA ESTORNAR?')&&
 fluxoExcluir.includes('window.confirm(aviso)')&&
 !fluxoExcluir.includes('window.prompt(')&&
 !fluxoExcluir.includes('Digite exatamente o código da obra')&&
 fluxoExcluir.includes("p_confirmacao:confirmacao"),
 'Um único aviso de irreversibilidade; o backend recebe o código automaticamente');
assert.ok(source.includes("node('manageWorksDelete').disabled=!info?.permitido||workDeleteSubmitting")&&
 fluxoExcluir.includes("if(motivo.length<5||motivo.length>300)")&&
 fluxoExcluir.includes('window.alert(mensagem)')&&
 fluxoExcluir.includes('motivoCampo.focus()'),
 'Sem motivo válido o encerramento não pode prosseguir');
assert.ok(!source.includes('stockManageRestore(')&&
 !source.includes("data-stock-restore")&&
 !source.includes("romTransfIncludeArchived"),
 'Nenhuma tela deve oferecer restauração ou histórico operacional de obra encerrada');
// v43.6: motivo de 5 caracteres, estados claros e listas paginadas para obras grandes.
for(const id of ['stockReverseBalancesCount','stockReverseBalancesMore','stockReverseHistoryCount',
 'stockReverseHistoryMore','stockReverseOpenWorks']){
 assert.ok(source.includes('id="'+id+'"'),'Interface de estornos precisa de '+id);
}
assert.ok(source.includes('minlength="5" maxlength="400"')&&
 source.includes('motivo.length<5||motivo.length>400')&&
 source.includes('motivo.length>=5&&motivo.length<=300')&&
 source.includes("new Map(matVariacoes.map(v=>[v.id,v]))"),
 'Motivos de estorno e exclusão com mínimo de 5; índice de materiais evita buscas repetidas');
assert.ok(source.includes('stockReverseHistoryLimit=60')&&
 source.includes('stockReverseBalancesLimit=70')&&
 source.includes("filtrados.slice(0,stockReverseHistoryLimit)")&&
 source.includes("resumo.saldos.slice(0,stockReverseBalancesLimit)"),
 'As listagens extensas precisam ser exibidas progressivamente sem cortar histórico');
assert.ok(source.includes("m.origem==='ESTORNO'||m.estorno_de_id?'Contrapartida de estorno'")&&
 source.includes('Histórico conciliado pelo estorno da NF-e')&&
 source.includes('Histórico conciliado (saldo zero)')&&
 source.includes('Estornar todos os lançamentos sem estorno')&&
 source.includes('⚠ ESTORNO BLOQUEADO')&&
 source.includes("node('stockReverseOpenWorks').classList.remove('hidden')"),
 'Estorno não pode parecer pendente de processamento quando está bloqueado por liberações');
const motivoCincoMigration=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261118_motivos_cinco_caracteres.sql',import.meta.url)),'utf8');
for(const name of ['ew_estornar_movimento_obra','ew_estornar_estoque_obra',
 'ew_arquivar_obra_reconciliada','ew_cancelar_liberacoes_obra','ew_cancelar_saidas_avulsas_obra']){
 assert.ok(motivoCincoMigration.includes('FUNCTION public.'+name),
 'A rotina deve validar mínimo de cinco caracteres: '+name);
}
assert.ok(!motivoCincoMigration.includes('not between 10 and 400'),
 'Validação antiga de 10 caracteres permanece na migração');
// v43.7: mensagem pulsante indica bloqueio real, sem cursor de espera em botão desabilitado.
assert.ok(source.includes('@keyframes ewStockBlockedPulse')&&
 source.includes('@media(prefers-reduced-motion:reduce)')&&
 source.includes('#stockReverseApply:disabled{cursor:not-allowed')&&
 source.includes('⚠ ESTORNO BLOQUEADO')&&
 source.includes("'Bloqueado: cancele as liberações'")&&
 source.includes("setAttribute('aria-describedby','stockReverseMessage')"),
 'Estorno bloqueado deve ficar evidente e acessível, sem parecer processamento em andamento');
assert.ok(source.includes("node('stockReverseApply').textContent='Estornar todos os lançamentos sem estorno'")&&
 source.includes("node('stockReverseApply').removeAttribute('title')")&&
 source.includes("node('stockReverseMessage').classList.remove('stockReversalBlock')"),
 'Mensagem e botão precisam retornar ao estado normal quando a obra é reavaliada');
// v43.8: Obras no espaço de trabalho, sem depender de voltar ao painel inicial.
assert.ok(source.includes('id="navWorks"')&&
 source.includes('id="worksPage"')&&source.includes('id="worksPageList"')&&
 source.includes("abrirObrasPelaBarra(b.dataset.worksModo)")&&source.includes('id="navWorksSubmenu"')&&
 source.includes("setNavPermission('navWorks',temPermissao('obras.consultar'))")&&
 source.includes("['navWorks','worksPage']"),
 'A navegação Obras precisa respeitar permissões e destacar o menu ativo');
assert.ok(source.includes("function abrirObrasPelaBarra(modo='release')")&&
 source.includes('if(lista.length===1)')&&
 source.includes('function mostrarListaDeObras()')&&
 source.includes('detailBackTarget=\'worksPage\'')&&
 source.includes("if(detailBackTarget==='worksPage')mostrarListaDeObras()"),
 'Uma única obra deve abrir diretamente; múltiplas obras exigem lista e volta correta');
assert.ok(source.includes('function obrasComEsquadriasAtivas()')&&
 source.includes('return works.filter(w=>ids.has(w.id)||w.cadastro_manual===true)'),
 'Obras exclusivamente de estoque não devem poluir navegação de obras técnicas');
// v44.1: cancelamento visível em cada linha, independente de Verificar exclusão.
for(const id of ['manageWorksDeleteReasonBox','manageWorksDeleteBlockedMessage',
 'releaseCancelAllOverlay','releaseCancelAllSummary','releaseCancelAllItems',
 'releaseCancelAllReason','releaseCancelAllConfirm','releaseCancelAllClose',
 'releaseCancelAllStatus']){
 assert.ok(source.includes('id="'+id+'"'),'Gerenciar obras exige '+id);
}
assert.ok(source.includes('data-work-cancel-releases')&&
 source.includes('manageWorksRowActions')&&
 source.includes("b.addEventListener('click',()=>openReleaseCancelAll(b.dataset.workCancelReleases))")&&
 source.includes('async function openReleaseCancelAll(obraId)')&&
 !source.includes('id="manageWorksCancelReleasesDirect"')&&
 !source.includes('id="releaseCancelAllOpen"')&&
 !source.includes("const obraId=workDeleteInspection?.obra_id"),
 'Botão Cancelar liberações deve estar na lista visível antes de Verificar exclusão');
assert.ok(source.includes('async function confirmReleaseCancelAll()')&&
 source.includes("request('/rest/v1/rpc/ew_cancelar_liberacoes_obra'")&&
 source.includes('O estoque NÃO será estornado automaticamente.')&&
 source.includes("request('/rest/v1/rpc/ew_inspecionar_reversao_obra'")&&
 source.includes('if(!check||check.obra_id!==obraId)')&&
 source.includes('releaseCancelAllInspection=check')&&
 source.includes('check.obra_id!==obraId||node(\'releaseCancelAllConfirm\').disabled')&&
 source.includes("if(!window.confirm('Tem certeza que deseja cancelar TODAS as liberações")&&
 source.includes('Histórico preservado.')&&
 source.includes('CANCELAMENTO BLOQUEADO:')&&
 source.includes("node('releaseCancelAllConfirm').disabled=true")&&
 source.includes('motivo.length<5||motivo.length>400'),
 'Motivo, conferência, confirmação e histórico obrigatórios; sem exclusão de obra');
// v44.2: uma prévia de ZIP não pode reaparecer depois de Sair/reautenticar.
assert.ok(source.includes('id="matCemLimpar"')&&
 source.includes("node('matCemLimpar').addEventListener('click',cemDescartarRascunho)")&&
 source.includes('function cemDescartarRascunho()')&&
 source.includes("node('matCemArquivo').value=''")&&
 source.includes("node('cemPreview').replaceChildren()")&&
 source.includes("node('cemExistingNotice').replaceChildren()")&&
 source.includes("node('cemImportResult').textContent=''"),
 'A análise temporária do arquivo deve ser completamente descartável');
const sair=source.slice(source.indexOf("node('logout').addEventListener"),source.indexOf("node('refresh').addEventListener"));
const sessao=source.slice(source.indexOf("function invalidateAppSession(reason)"),source.indexOf("function throwFriendly(error)"));
const cancelamento=source.slice(source.indexOf("async function sessaoUnicaCancelarNova()"),source.indexOf("function saveSession(data)"));
assert.ok(sair.includes('cemDescartarRascunho()')&&sessao.includes('cemDescartarRascunho()')&&
 cancelamento.includes('cemDescartarRascunho()'),
 'Todos os caminhos de logout ou invalidação precisam descartar a prévia');
assert.ok(source.includes('let cemOperacaoId=null,cemAnaliseGeracao=0')&&
 source.includes('if(analise!==cemAnaliseGeracao||!session)return;')&&
 source.includes('currentCompany?.id!==empresaId')&&
 source.includes('if(analise===cemAnaliseGeracao)botao.disabled=false;'),
 'Análises assíncronas antigas não podem ressuscitar uma obra na interface após sair');
assert.ok(source.includes('Esquadrias e materiais serão cadastrados somente após sua confirmação.')&&
 source.includes('Esses itens serão cadastrados na nova obra após confirmação, aguardando liberação.'),
 'A conferência não pode sugerir cadastro antecipado de esquadrias no banco');
// v44.3: evitar duplicidade de navegação Gerenciar obras na Tela inicial.
assert.ok(!source.includes('id="openManageWorks"')&&
 !source.includes("node('openManageWorks')")&&
 !source.includes('id="navManageWorks"')&&
 source.includes("node('cadastroJumpObras').addEventListener('click',()=>{manageWorksUndoMode=false;abrirGerenciamentoObras();})")&&source.includes('id="releaseUndoAll"')&&source.includes('data-release-undo='),
 'Gerenciar obras não duplica o menu lateral e mantém acesso por Cadastros e estorno dentro de Obras');
// v44.4: sem contador/importação global de croquis; upload individual só ao editar a tipologia.
for(const deleted of ['croquiCatalogCount','croquiPackageButton','croquiPackageInput',
 'croquiImportStatus','importCroquiPackage(file)']){
 assert.ok(!source.includes(deleted),'Controle de croquis em lote não pode permanecer no catálogo: '+deleted);
}
assert.ok(source.includes('Para adicionar ou substituir um croqui, encontre a tipologia e clique em Editar.')&&
 source.includes('id="croquiReplaceButton"')&&
 source.includes('id="croquiReplaceInput"')&&
 source.includes('accept="image/png,image/jpeg,image/webp"')&&
 source.includes('function refreshCroquiPreview(tipologiaId)')&&
 source.includes("node('croquiReplaceButton').textContent=src?'Trocar croqui':'Adicionar croqui'")&&
 source.includes("node('croquiReplaceButton').addEventListener('click',()=>node('croquiReplaceInput').click())")&&
 source.includes('await salvarCroquiRemoto(id,base64'),
 'O cadastro individual deve permitir adicionar ou substituir imagens pelo editor');
// v44.5: tela Fabricantes sem botões de navegação redundantes no cabeçalho.
const manufacturersSection=source.slice(source.indexOf('<section id="manufacturers"'),
  source.indexOf('</section>',source.indexOf('<section id="manufacturers"')));
assert.ok(manufacturersSection.includes('<h1>Cadastro de fabricantes</h1>')&&
  !manufacturersSection.includes('id="backManufacturers"')&&
  !manufacturersSection.includes('id="goManufacturersToCatalog"')&&
  !source.includes("node('backManufacturers')")&&
  !source.includes("node('goManufacturersToCatalog')"),
  'A tela Fabricantes não deve ter atalhos de navegação duplicados no cabeçalho');
assert.ok(source.includes('id="navHome"')&&
  source.includes('id="navTypologies"')&&
  source.includes('id="navManufacturers"')&&
  source.includes("node('navManufacturers').addEventListener('click'"),
  'A navegação lateral deve continuar disponível');
// v44.6: recarregar página com sessão salva nunca mostra o formulário antes da restauração.
const initialMarkup=source.slice(source.indexOf('<main>'),source.indexOf('<section id="dashboard"'));
assert.ok(initialMarkup.includes('id="startup"')&&
 initialMarkup.includes('Carregando EWGEST')&&
 initialMarkup.includes('id="login" class="panel login hidden"')&&
 source.includes("node('startup').classList.add('hidden');"),
 'Inicialização exibe carregamento e mantém login oculto até a sessão ser conferida');
const restored=source.slice(source.indexOf('async function restaurarSessaoSalva()'),source.indexOf("node('restoreSessionBtn').addEventListener"));
assert.ok(restored.includes("const raw=sessionStorage.getItem('ewgest_session_v3')")&&
 restored.includes("if(!raw){\\n  retry.classList.add('hidden');\\n  setView('login');".replaceAll('\\n','\n'))&&
 restored.includes('await loadPanel();')&&
 restored.includes("setView('login');")&&
 source.includes("restaurarSessaoSalva().catch(e=>{\\n  // Não manter".replaceAll('\\n','\n')),
 'Sessão ausente ou inválida mostra login; sessão válida abre painel sem flash, erros não travam o carregamento');
assert.ok(/EWGEST <strong>· v\d+\.\d+(?:\.\d+)?<\/strong>/.test(source)&&
 source.includes('@media(prefers-reduced-motion:reduce){.startupSpinner'),
 'Indicador de carregamento acessível e versão presente no rodapé');
// v44.7: os sete atalhos marcados no cabeçalho devem desaparecer, sem eventos órfãos.
const obsoleteHeaderButtons=[
 'romaneiosBack','usersBack','materialsBack','stockBack',
 'cemBack','backTypologies','openManufacturersFromCatalog'
];
for(const id of obsoleteHeaderButtons){
 assert.ok(!source.includes('id="'+id+'"')&&!source.includes("node('"+id+"')"),
  'Atalho de navegação redundante ou evento órfão: '+id);
}
assert.ok(source.includes('id="manageWorksBack"')&&
 source.includes("node('manageWorksBack').addEventListener('click',()=>setView('cadastros'))")&&
 source.includes('id="detailWorksBack"')&&
 source.includes("node('detailWorksBack').addEventListener('click',mostrarListaDeObras)"),
 'Preservar retorno a Cadastros e à lista de Obras após remoção do menu Gerenciar obras');
for(const id of ['navHome','navRomaneios','navTypologies','navManufacturers',
 'navMaterials','navStock','navCem','navUsers']){
 assert.ok(source.includes('id="'+id+'"'),'Preservar acesso no menu lateral: '+id);
}
for(const id of ['userAccessHistoryToggle','userOperationsToggle',
 'matNovoHeader','stockRefresh','hubRefreshRomaneio']){
 assert.ok(source.includes('id="'+id+'"'),'Preservar ação operacional: '+id);
}
assert.ok(source.includes('id="myPasswordBack"')&&
 source.includes("node('myPasswordBack').addEventListener"),
 'Retorno da alteração de senha é necessário ao perfil Almoxarife e foi preservado');
// v44.8: seletor de ZIP com um botão limpo, sem controle nativo embutido.
const cemImportSection=source.slice(source.indexOf('<section id="cemImport"'),
 source.indexOf('</section>',source.indexOf('<section id="cemImport"')));
assert.ok(cemImportSection.includes('id="matCemEscolher"')&&
 cemImportSection.includes('>Importar obra</button>')&&
 cemImportSection.includes('id="matCemArquivo"')&&
 cemImportSection.includes('id="matCemNomeArquivo"')&&
 !cemImportSection.includes('Arquivo ZIP de exportação técnica')&&
 source.includes('.matImportBox #matCemArquivo{display:none}'),
 'Seletor ZIP exibe apenas o botão Importar obra e o nome do arquivo, sem botão nativo');
assert.ok(source.includes("node('matCemEscolher').addEventListener('click',()=>node('matCemArquivo').click())")&&
 source.includes('function cemAtualizarNomeArquivo()')&&
 source.includes("node('matCemNomeArquivo').textContent=nome")&&
 source.includes("node('matCemNomeArquivo').title=nome")&&
 source.includes("node('matCemConferir').addEventListener('click',matVerificarZip)")&&
 source.includes("node('matCemLimpar').addEventListener('click',cemDescartarRascunho)"),
 'Selecionar, analisar e limpar um ZIP devem manter ações distintas');
const cemReset=source.slice(source.indexOf('function cemDescartarRascunho(){'),
 source.indexOf('async function matVerificarZip(){'));
assert.ok(cemReset.includes("node('matCemArquivo').value=''")&&
 cemReset.includes('cemAtualizarNomeArquivo()'),
 'O nome do arquivo desaparece ao limpar análise ou encerrar sessão');
// v44.9: conferir quantidade e comprimento de barras do CEM, nunca linhas de corte como estoque.
const cemBarStart=source.indexOf('function cemBarrasConferencia(r){');
const cemBarEnd=source.indexOf('function cemTabelaHTML(tipo){',cemBarStart);
assert.ok(cemBarStart>0&&cemBarEnd>cemBarStart&&
 source.includes("tipo==='perfil'?'Barras (qtd. × comprimento)':'Quantidades'")&&
 source.includes("cemBarrasConferenciaHTML(barras.get(cemNome(p.codigo)))"),
 'A conferência dos perfis deve mostrar barras e comprimentos, preservando os acessórios');
const {cemBarrasConferencia,cemBarrasConferenciaHTML}=new Function('cemNome','escapeHTML',
 source.slice(cemBarStart,cemBarEnd)+
 'return {cemBarrasConferencia,cemBarrasConferenciaHTML};')(
 x=>String(x||'').trim().toLocaleUpperCase('pt-BR'),
 x=>String(x).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;'));
const amostraBarras={barrasAproveitamento:[
 {CODPERF:'060787',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'12',BARRA:'6000'},
 {CODPERF:'060787',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'3',BARRA:'6000'},
 {CODPERF:'060787',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'4',BARRA:'6500'},
 {CODPERF:'000633',NUMBARRAS:'x',BARRA:'6000'}
]};
const mapaBarras=cemBarrasConferencia(amostraBarras);
assert.equal(mapaBarras.get('060787').barras.get('ANOD-1002-A13|6000').quantidade,15,
 'Linhas repetidas da mesma barra/cor/comprimento devem somar as quantidades');
assert.equal(mapaBarras.get('060787').barras.size,2,
 'Comprimentos comerciais diferentes devem permanecer separados');
const htmlBarras=cemBarrasConferenciaHTML(mapaBarras.get('060787'));
assert.ok(htmlBarras.includes('15 barra(s)')&&htmlBarras.includes('6.000 mm')&&
 htmlBarras.includes('4 barra(s)')&&htmlBarras.includes('6.500 mm'),
 'Exibir pares quantitativo × comprimento, não linhas de cálculo');
assert.ok(cemBarrasConferenciaHTML(undefined).includes('Não informado no ZIP')&&
 cemBarrasConferenciaHTML(mapaBarras.get('000633')).includes('Conferir no CEM'),
 'Dados ausentes ou inválidos nunca devem ser apresentados como zero barras');
assert.ok(source.includes('não são confirmação de estoque físico')&&
 source.includes('OBCALCP é a lista de cortes'),
 'Quantidade do aproveitamento não pode ser confundida com estoque físico ou cortes');

// Orçamento por níveis: o usuário escolhe apenas as linhas pertinentes à obra.
const budgetScript=readFileSync(fileURLToPath(new URL('../assets/orcamento-niveis.js',import.meta.url)),'utf8');
const budgetCSS=readFileSync(fileURLToPath(new URL('../assets/orcamento-niveis.css',import.meta.url)),'utf8');
const budgetMigration=readFileSync(fileURLToPath(new URL(
 '../supabase/migrations/20261120223000_orcamento_niveis_e_empresas.sql',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(budgetScript),'Script de orçamento por níveis deve ser sintaticamente válido');
assert.ok(source.includes('id="cemQuoteRows"')&&source.includes('id="cemQuoteAddRow"')&&
 source.includes('id="cemQuoteNewLevel"')&&source.includes('id="cemQuoteNewCompany"')&&
 source.includes('id="cemQuoteSaveCompany"')&&source.includes('id="cemQuoteTotal"'),
 'Orçamento por níveis tem seleção e cadastro de níveis e empresas comerciais');
assert.ok(source.includes('<script src="/assets/orcamento-niveis.js?v=20261122b"></script>')&&
 source.includes('<link rel="stylesheet" href="/assets/orcamento-niveis.css?v=20261120c">')&&
 budgetCSS.includes('.cemBudgetTable'),
 'A interface deve carregar os arquivos versionados de orçamento, sem cache antigo');
const headers=readFileSync(fileURLToPath(new URL('../_headers',import.meta.url)),'utf8');
assert.ok(headers.includes('/assets/orcamento-niveis.js\n  Content-Type: text/javascript; charset=utf-8\n  Cache-Control: no-store')&&
 headers.includes('/assets/orcamento-niveis.css\n  Content-Type: text/css; charset=utf-8\n  Cache-Control: no-store'),
 'Os assets monetários precisam evitar cache persistente');
assert.ok(budgetScript.includes('normalizarValorTotalPreenchido()')&&
 budgetScript.includes('document.activeElement!==campo')&&
 budgetScript.includes("node('cemQuoteTotal').addEventListener('focus'"),
 'Formulário restaurado sem disparar input deve exibir a máscara monetária');
assert.ok(!source.includes('id="cemQuoteAluminio"')&&
 !source.includes('id="cemQuoteAcessorios"')&&!source.includes('id="cemQuoteVidros"'),
 'Nenhum nível tradicional será obrigatório ou criado como campo fixo');
assert.ok(budgetScript.includes('Próxima etapa')&&
 budgetScript.includes('adicionarLinha()')&&budgetScript.includes('faturar')&&
 budgetScript.includes('totalCentavos')&&
 budgetScript.includes('Os valores dos níveis devem somar exatamente 100% da obra.'),
 'Níveis personalizáveis exigem a soma exata dos valores do orçamento');
assert.ok(source.includes('id="cemQuoteTotal" type="text" inputmode="decimal"')&&
 budgetScript.includes('type="text" inputmode="decimal" autocomplete="off" required data-budget-field="valor"'),
 'Campos de orçamento devem utilizar texto com entrada decimal em vez de setas numéricas');
const moneyStart=budgetScript.indexOf(' function moedaPartes(');
const moneyEnd=budgetScript.indexOf(' const cadastroInfo=',moneyStart);
assert.ok(moneyStart>=0&&moneyEnd>moneyStart,'Funções monetárias estão disponíveis no script de níveis');
const moeda=new Function(budgetScript.slice(moneyStart,moneyEnd)+
 '\nreturn {moedaCentavos,moedaExibir,moedaMascaraAoDigitar};')();
for(const [entrada,centavos,exibido] of [
 ['183200',18320000,'R$ 183.200,00'],
 ['R$ 183.200,00',18320000,'R$ 183.200,00'],
 ['1.234,50',123450,'R$ 1.234,50'],
 ['183200,5',18320050,'R$ 183.200,50'],
 ['2500.75',250075,'R$ 2.500,75'],
 ['0,05',5,'R$ 0,05'],
 ['10.000',1000000,'R$ 10.000,00'],
 ['1,2,3',null,'1,2,3'],
 ['-5',null,'-5'],
 ['1000000000000',null,'1000000000000']
]){
 assert.equal(moeda.moedaCentavos(entrada),centavos,'Converter valor BRL '+entrada+' para centavos');
 assert.equal(moeda.moedaExibir(entrada,true),exibido,'Exibir valor BRL '+entrada);
}
const campoMonetario={value:'183200',selectionStart:6,setSelectionRange(a,b){this.caret=a;}};
moeda.moedaMascaraAoDigitar(campoMonetario);
assert.equal(campoMonetario.value,'R$ 183.200','Formatar milhar enquanto digita');
assert.equal(campoMonetario.caret,campoMonetario.value.length,'Manter cursor ao final após formatar');

// Teste da digitação sequencial no campo real: foi isto que causou
// "R$ 1.83200" no navegador ao teclar 183200 sem vírgula.
for(const [teclas,valorFinal,centavosFinais] of [
 ['183200','R$ 183.200',18320000],
 ['183200,50','R$ 183.200,50',18320050],
 ['1000000','R$ 1.000.000',100000000],
 ['1200,05','R$ 1.200,05',120005],
 ['0,05','R$ 0,05',5]
]){
 const campo={value:'',selectionStart:0,setSelectionRange(a,b){this.selectionStart=a;}};
 for(const tecla of teclas){
  const cursor=campo.selectionStart;
  campo.value=campo.value.slice(0,cursor)+tecla+campo.value.slice(cursor);
  campo.selectionStart=cursor+1;
  moeda.moedaMascaraAoDigitar(campo);
  assert.notEqual(moeda.moedaCentavos(campo.value),null,
   'Valor intermediário deve permanecer válido durante a digitação '+teclas+': '+campo.value);
 }
 assert.equal(campo.value,valorFinal,'Máscara correta ao digitar '+teclas);
 assert.equal(moeda.moedaCentavos(campo.value),centavosFinais,'Total correto após '+teclas);
 assert.equal(moeda.moedaExibir(campo.value,true),
  moeda.moedaExibir(teclas,true),'Centavos exibidos ao concluir '+teclas);
}
assert.equal(moeda.moedaExibir('R$ 1.83200',true),'R$ 183.200,00',
 'Formatação recupera valor anteriormente exibido com agrupamento quebrado');

assert.ok(budgetScript.includes('valor:valorCentavos/100')&&
 budgetScript.includes('valor_total:totalCentavos/100'),
 'A API recebe os valores como números, sem R$ nem pontuação brasileira');
for(const tabela of ['ew_niveis_orcamento_catalogo','ew_empresas_faturamento_catalogo','ew_obra_orcamento_niveis']){
 assert.ok(budgetMigration.includes('CREATE TABLE IF NOT EXISTS public.'+tabela),
  'Migração SQL deve registrar catálogo de níveis/empresas e composição por obra: '+tabela);
}
assert.ok(budgetMigration.includes('ENABLE ROW LEVEL SECURITY')&&
 budgetMigration.includes('ew_importar_obra_cem_financeiro')&&
 budgetMigration.includes('v_soma<>v_valor')&&
 budgetMigration.includes('v_faturar')&&
 budgetMigration.includes('v_result:=public.ew_importar_obra_cem('),
 'Migração precisa garantir isolamento por empresa, soma e importação transacional');


// Recebimento manual: nota e itens físicos devem ser vinculados na mesma transação.
const receiveScript=readFileSync(fileURLToPath(new URL('../assets/recebimento-manual.js',import.meta.url)),'utf8');
const receiveCSS=readFileSync(fileURLToPath(new URL('../assets/recebimento-manual.css',import.meta.url)),'utf8');
const receiveSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261120_recebimento_manual_estoque.sql',import.meta.url)),'utf8');
const planSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_plano_barras_cem.sql',import.meta.url)),'utf8');
assert.ok(planSQL.includes('ADD COLUMN IF NOT EXISTS barras_planejadas jsonb')&&
 planSQL.includes('v_barras_plan')&&planSQL.includes('jsonb_array_elements(v_barras_plan)')&&
 planSQL.includes('barras_planejadas=coalesce(excluded.barras_planejadas')&&
 !/INSERT INTO public\.ew_estoque_obras_movimentos/.test(planSQL),
 'SQL do plano de barras não deve movimentar estoque físico nem remover histórico');
assert.doesNotThrow(()=>new Function(receiveScript),'Recebimento manual deve ter JavaScript sintaticamente válido');
assert.ok(source.includes('<section id="recebimento"')&&
 source.includes('Recebimento de materiais')&&
 source.includes('id="finManualRows"')&&source.includes('id="finManualLocal"')&&
 source.includes('id="finManualAdd"')&&source.includes('id="finManualSum"')&&
 source.includes('id="finCostTotal" type="text" inputmode="decimal"'),
 'Formulário de nota manual deve ter galpão, materiais, quantidades e total monetário');
assert.ok(source.includes('id="finCostXML" class="hidden" disabled')&&
 !source.includes('<label>XML da nota fiscal (NF-e)')&&
 source.includes('id="finCostCategory" required'),
 'Entrada financeira não pode oferecer envio de XML; almoxarifado mantém fluxo próprio');
assert.ok(source.includes('recebimento-manual.js?v=20261126a')&&
 source.includes('recebimento-manual.css?v=20261121g')&&receiveCSS.includes('.finManualTable'),
 'HTML deve carregar arquivos de recebimento manual');
assert.ok(receiveScript.includes('ew_registrar_recebimento_manual_financeiro')&&
 receiveScript.includes('p_itens:items')&&receiveScript.includes('finCostOpId ||= crypto.randomUUID()')&&
 receiveScript.includes("'/rest/v1/rpc/ew_insumos_receber'")&&
 receiveScript.includes('const sum=items.reduce')&&
 receiveScript.includes('if(sum!==note)'),
 'Entrada física exige itens com subtotal correto e RPC específica para vidros/outros');
assert.ok(receiveScript.includes('A faturar: ')&&
 receiveScript.includes("levels.filter(n=>n.faturar)")&&
 receiveScript.includes('Orçamento por níveis e acompanhamento financeiro')&&
 !receiveScript.includes('Disponível no módulo por esquadria'),
 'O resumo deve incluir todos os níveis faturáveis e dispensar indicadores técnicos redundantes');
assert.ok(receiveSQL.includes("SECURITY INVOKER SET search_path TO ''")&&
 receiveSQL.includes('PERFORM public.ew_exigir_sessao_atual();')&&
 receiveSQL.includes("ue.perfil='administrador'")&&
 receiveSQL.includes("v_soma<>p_valor")&&
 receiveSQL.includes("v_mov:=public.ew_movimentar_estoque_obra_local")&&
 receiveSQL.includes("INSERT INTO public.ew_nfe_recebimentos")&&
 receiveSQL.includes('ja_registrado')&&
 receiveSQL.includes('pg_advisory_xact_lock'),
 'Operação SQL precisa de ADM, conferência, idempotência, compra de estoque e comprovante vinculados');
assert.ok(receiveSQL.includes('Estorne as entradas de estoque antes de cancelar')&&
 receiveSQL.includes('REVOKE ALL ON FUNCTION public.ew_registrar_recebimento_manual_financeiro')&&
 receiveSQL.includes('GRANT EXECUTE ON FUNCTION public.ew_registrar_recebimento_manual_financeiro'),
 'Cancelamento de despesa não pode deixar estoque físico sem estorno; função restrita a autenticados');


// O financeiro moderno apresenta uma tabela consolidada, sem duplicar níveis
// em "Grupos financeiros existentes". O formato legado permanece compatível.
const resumoStart=receiveScript.indexOf(' const oldResumo=finRenderResumo;');
const resumoEnd=receiveScript.indexOf(" byId('finExpenseForm').removeEventListener",resumoStart);
assert.ok(resumoStart>=0&&resumoEnd>resumoStart,'Localizar implementação financeira unificada');
const resumoPrelude=[
 "let finState=state,legacyCalls=0;",
 "const nodes={finTotals:{innerHTML:''},finSummary:{innerHTML:''}};",
 "const byId=id=>nodes[id];",
 "const finMoney=n=>Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});",
 "const escapeHTML=x=>String(x||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;');",
 "const initForm=()=>{},finRenderClassificacaoFiscal=()=>{};",
 "let finRenderResumo=function(){legacyCalls++;};"
].join('\n');
const renderResumo=new Function('state',resumoPrelude+'\n'+
 receiveScript.slice(resumoStart,resumoEnd)+
 '\nfinRenderResumo();return {nodes,legacyCalls};');
const niveisExemplo=[
 ['ALUMÍNIO','aluminio',73200,false,'GVG ESQUADRIAS'],
 ['COMPONENTES','acessorios',22000,false,'GVG ESQUADRIAS'],
 ['VIDROS','vidros',24000,false,'GVG ESQUADRIAS'],
 ['OUTROS INSUMOS','outros',24000,true,'ARTEFAL'],
 ['FABRICAÇÃO','fabricacao',32000,true,'GVG ESQUADRIAS'],
 ['INSTALAÇÃO','instalacao',8000,true,'GVG ESQUADRIAS']
].map(([nivel_nome,categoria_base,valor,faturar,empresa_faturamento_nome])=>({
 nivel_nome,categoria_base,valor,faturar,empresa_faturamento_nome,
 percentual:valor/183200*100
}));
const exemplo=()=>({
 orcamento:{valor_total:183200},
 orcamentoNiveis:niveisExemplo.map(n=>({...n})),
 despesas:[{categoria:'aluminio',status:'aprovada',valor:5000}],
 faturas:[{categoria:'fabricacao',status:'emitido',valor_total:2500}]
});
const unificado=renderResumo(exemplo());
const htmlResumo=unificado.nodes.finSummary.innerHTML.replace(/\u00a0/g,' ');
assert.equal(unificado.legacyCalls,0,'Orçamento por níveis não deve renderizar tabela legada');
assert.equal((htmlResumo.match(/<table\b/g)||[]).length,1,'Uma só tabela financeira por obra');
assert.ok(htmlResumo.includes('Orçamento por níveis e acompanhamento financeiro')&&
 !htmlResumo.includes('Grupos financeiros existentes')&&
 htmlResumo.includes('OUTROS INSUMOS')&&htmlResumo.includes('ARTEFAL')&&
 htmlResumo.includes('R$ 24.000,00')&&
 htmlResumo.includes('Faturamento (emissão pendente)')&&
 htmlResumo.includes('R$ 5.000,00')&&
 htmlResumo.includes('R$ 68.200,00'),
 'Tabela inclui empresa, previsto, custos realizados, faturamento especial e restante');
assert.ok(unificado.nodes.finTotals.innerHTML.replace(/\u00a0/g,' ').includes('A faturar: R$ 61.500,00'),
 'A faturar inclui outros insumos com flag faturamento e deduz apenas faturamentos emitidos');
assert.equal((unificado.nodes.finTotals.innerHTML.match(/<span>/g)||[]).length,4,
 'Resumo superior exibe quatro indicadores essenciais sem subtotais duplicados');
const duplicados=exemplo();
duplicados.orcamentoNiveis.push({
 nivel_nome:'ALUMÍNIO ADICIONAL',categoria_base:'aluminio',valor:1000,
 percentual:1,faturar:false,empresa_faturamento_nome:'GVG ESQUADRIAS'
});
const dupHtml=renderResumo(duplicados).nodes.finSummary.innerHTML.replace(/\u00a0/g,' ');
assert.equal((dupHtml.match(/<table\b/g)||[]).length,1);
assert.ok(dupHtml.includes('seus valores realizados não são distribuídos automaticamente (—)')&&
 dupHtml.includes('ALUMÍNIO ADICIONAL'),
 'Níveis repetidos não podem contabilizar o mesmo gasto duas vezes');
const comLotes=exemplo();
comLotes.compromissos=[{categoria:'aluminio',realizado_centavos:500000,ajuste_transferencias_centavos:150000,comprometido_pendente_centavos:100000}];
const integradoResumo=renderResumo(comLotes);
assert.ok(integradoResumo.nodes.finSummary.innerHTML.replace(/\u00a0/g,' ').includes('R$ 65.700,00'));
assert.ok(integradoResumo.nodes.finTotals.innerHTML.replace(/\u00a0/g,' ').includes('Custo apropriado: R$ 6.500,00'));
comLotes.compromissos[0].transferencias_custo_pendentes=1;
assert.ok(renderResumo(comLotes).nodes.finSummary.innerHTML.includes('Custo de transferência pendente'));
const legado=renderResumo({orcamentoNiveis:[],despesas:[],faturas:[],orcamento:{}});
assert.equal(legado.legacyCalls,1,'Obras antigas permanecem com resumo legado');


// Verificar que o XML OBAPROV se transforma em plano de compra sem usar cortes.
const cemPayloadStart=source.indexOf('function cemNome(v){');
const cemPayloadEnd=source.indexOf('function cemNormalizarDescricao(x){',cemPayloadStart);
assert.ok(cemPayloadStart>=0&&cemPayloadEnd>cemPayloadStart,'Parser do CEM disponível');
const montarPlanoCem=new Function(source.slice(cemPayloadStart,cemPayloadEnd)+
 '\nreturn cemMontarPayload;')();
const amostraPlano=montarPlanoCem({
 perfCatalog:[{CODPERF:'000633',REF:'HYDRO',DESCRICAO:'TRAVESSA INFERIOR 105'}],
 profMovs:[{CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',QTDE:'24',TAM:'1200'}],
 barrasAproveitamento:[
  {CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'3',BARRA:'6000'},
  {CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'2',BARRA:'6000'},
  {CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'1',BARRA:'6500'}],
 acesCatalog:[],aceMovs:[],acessoriosObra:[]
});
assert.deepEqual(amostraPlano.perfis[0].variacoes[0].barras_planejadas,[
 {comprimento_mm:6000,quantidade:5},{comprimento_mm:6500,quantidade:1}],
 'NUMBARRAS/BARRA agrega barras comerciais por perfil, cor e comprimento, não os 24 cortes');
const amostraSemPlano=montarPlanoCem({
 perfCatalog:[{CODPERF:'000633',REF:'HYDRO',DESCRICAO:'TRAVESSA INFERIOR 105'}],
 profMovs:[{CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',QTDE:'24',TAM:'1200'}],
 barrasAproveitamento:[],acesCatalog:[],aceMovs:[],acessoriosObra:[]
});
assert.equal(Object.hasOwn(amostraSemPlano.perfis[0].variacoes[0],'barras_planejadas'),false,
 'Quando o ZIP não tem OBAPROV, omitir plano para preservar dados anteriores');

assert.throws(()=>montarPlanoCem({
 perfCatalog:[{CODPERF:'000633',REF:'HYDRO',DESCRICAO:'TRAVESSA INFERIOR 105'}],
 profMovs:[{CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',QTDE:'24',TAM:'1200'}],
 barrasAproveitamento:[{CODPERF:'000633',CODTRATEXT:'ANOD-1002-A13',NUMBARRAS:'invalido',BARRA:'6000'}],
 acesCatalog:[],aceMovs:[],acessoriosObra:[]
}),/Plano de barras do CEM inválido/,
 'Não aceitar importação de plano de barras com quantidades inválidas');

// Recebimento manual: perfis usam exclusivamente NUMBARRAS/BARRA da
// importação específica da obra, nunca a contagem de cortes dos croquis.
assert.ok(source.includes("apiGet('ew_cem_obras_materiais'")&&
 source.includes("materiaisObra:materiaisObra||[]")&&
 source.includes("obra_id:obra,limit:'10000'"),
 'O catálogo é limitado aos materiais da obra selecionada');
assert.ok(source.includes("origem:'eq.IMPORTACAO_CEM'")&&
 source.includes("quantidade_delta,origem'")&&
 source.includes("barrasCem:barraCem||[]")&&
 receiveScript.includes('function plannedBarRows(')&&
 receiveScript.includes('Array.isArray(m.barras_planejadas)')&&
 receiveScript.includes('!modernIds.has(x.variacao_id)'),
 'Priorizar barras planejadas na importação da obra, sem somar com histórico legado');
assert.ok(receiveScript.includes('function quantityData(row)')&&
 !receiveScript.includes("needed:formatQty(cuts)")&&
 !receiveScript.includes("pendingSub:'metro linear"),
 'Cortes e metros não podem ser apresentados como barras necessárias ou pendentes');
const resolverStart=receiveScript.indexOf(' function stockCategory(){');
const resolverEnd=receiveScript.indexOf(' function unitFor(',resolverStart);
assert.ok(resolverStart>=0&&resolverEnd>resolverStart,
 'O filtro e os quantitativos devem estar disponíveis');
const mockResolver=new Function('state','selectedCategory',
 'let finState=state,category=selectedCategory;\n'+
 receiveScript.slice(resolverStart,resolverEnd)+
 '\nreturn {getMaterials,getVariations,selectOptions,quantityData,autoBarLength};');
const fixture={
 perfis:[{id:'p1',codigo:'GN097',descricao:'Folha colada',comprimento_comercial_mm:null},
  {id:'p2',codigo:'NAO-DA-OBRA',descricao:'Não vinculado',comprimento_comercial_mm:6000}],
 acessorios:[{id:'a1',codigo:'PARAFUSO',descricao:'Parafuso',unidade_item:'PC'},
  {id:'a2',codigo:'ACESS-EXTERNO',descricao:'Não vinculado'}],
 variacoes:[
  {id:'v1',tipo:'perfil',perfil_id:'p1',cor:'ANOD-1002-A13',acabamento:'ANODIZADO',ativo:true},
  {id:'v2',tipo:'perfil',perfil_id:'p2',cor:'BRANCO',ativo:true},
  {id:'va1',tipo:'acessorio',acessorio_id:'a1',cor:'NATURAL',ativo:true},
  {id:'va2',tipo:'acessorio',acessorio_id:'a2',cor:'NATURAL',ativo:true}
 ],
 // A obra de exemplo tem 24 cortes. NÃO são 24 barras.
 materiaisObra:[
  {tipo:'perfil',perfil_id:'p1',variacao_id:'v1',quantidade_prevista:24,unidade_prevista:'CORTE',comprimento_total_m:54.96,linhas_calculo:2},
  {tipo:'acessorio',acessorio_id:'a1',variacao_id:'va1',quantidade_prevista:58,unidade_prevista:'PC'}
 ],
 // Há duas medidas planejadas: não confundir no cálculo de saldo.
 barrasCem:[
  {variacao_id:'v1',comprimento_mm:6000,quantidade_delta:5,origem:'IMPORTACAO_CEM'},
  {variacao_id:'v1',comprimento_mm:6500,quantidade_delta:4,origem:'IMPORTACAO_CEM'}
 ],
 stockReceipts:[
  {variacao_id:'v1',unidade:'BARRA',quantidade:2,comprimento_mm:6000},
  {variacao_id:'v1',unidade:'BARRA',quantidade:3,comprimento_mm:6500},
  {variacao_id:'v2',unidade:'BARRA',quantidade:100,comprimento_mm:6000},
  {variacao_id:'va1',unidade:'PC',quantidade:20,comprimento_mm:null},
  {variacao_id:'va2',unidade:'PC',quantidade:400,comprimento_mm:null}
 ]
};
const perfil=mockResolver(fixture,'aluminio');
// Entrando agora (perfis): aceitar apenas barras inteiras positivas.
// Uma quantidade como "3,001" jamais pode virar "3001" ao digitar ou lançar a nota.
const naturalStart=receiveScript.indexOf(' function isNaturalBarQuantity(value){');
const naturalEnd=receiveScript.indexOf(' function stockCategory(){',naturalStart);
assert.ok(naturalStart>=0&&naturalEnd>naturalStart,'Validação de quantidade natural encontrada');
const isNaturalBarQuantity=new Function(receiveScript.slice(naturalStart,naturalEnd)+
 '\nreturn isNaturalBarQuantity;')();
for(const val of ['1','3','42','1000000','0003']){
 assert.equal(isNaturalBarQuantity(val),true,'Barra inteira permitida: '+val);
}
for(const val of ['','0','-2','+3','3,001','3.001','1e3','2.5','1000001','abc']){
 assert.equal(isNaturalBarQuantity(val),false,'Quantidade inválida rejeitada: '+val);
}
assert.ok(receiveScript.includes('type="text" inputmode="numeric" pattern="[0-9]*" maxlength="7"')&&
 receiveScript.includes("if(category==='aluminio'&&!/^[0-9]*$/.test(value))")&&
 receiveScript.includes("event.target.value=r.quantidade||''")&&
 receiveScript.includes("if(category==='aluminio'&&!isNaturalBarQuantity(rawQty))"),
 'Entrada de barras deve impedir decimais já na digitação e confirmar regra no envio');
const normalizeEnd=receiveScript.indexOf(' async function submit(',resolverStart);
assert.ok(normalizeEnd>resolverEnd,'Validador da NF encontrado');
const normalizeFixture=new Function('state','selectedCategory',
 'let finState=state,category=selectedCategory; const cents=()=>10000; const releaseUnidadeAcessorio=code=>code;\n'+
 receiveScript.slice(naturalStart,normalizeEnd)+
 '\nreturn normalizeItem;');
const normalizeBar=normalizeFixture(fixture,'aluminio');
const validRow={material:'p1',variacao:'v1',comprimento:'6000',quantidade:'3',valor:'R$ 100,00'};
assert.equal(normalizeBar(validRow,0).quantidade,3,'3 barras entram como 3 barras');
for(const invalid of ['0','-1','3,001','3.001','1e3','2.5']){
 assert.throws(()=>normalizeBar({...validRow,quantidade:invalid},0),
  /Quantidade de barras:/,'NF não deve aceitar '+invalid);
}
const normalizeAccessory=normalizeFixture(fixture,'acessorios');
assert.equal(normalizeAccessory({material:'a1',variacao:'va1',comprimento:'',
 quantidade:'2',valor:'R$ 100,00'},0).quantidade,2,
 'Peça inteira recebida na unidade PC');
assert.throws(()=>normalizeAccessory({material:'a1',variacao:'va1',comprimento:'',
 quantidade:'2.5',valor:'R$ 100,00'},0),/exigem quantidade inteira/,
 'Não receber 2,5 peças.');
const fixtureMT={...fixture,acessorios:fixture.acessorios.map(a=>
 a.id==='a1'?{...a,unidade_item:'MT'}:a)};
const normalizeAccessoryMT=normalizeFixture(fixtureMT,'acessorios');
assert.equal(normalizeAccessoryMT({material:'a1',variacao:'va1',comprimento:'',
 quantidade:'2',valor:'R$ 100,00'},0).quantidade,2,
 'Metro inteiro deve ser aceito no recebimento de acessórios');
assert.throws(()=>normalizeAccessoryMT({material:'a1',variacao:'va1',comprimento:'',
 quantidade:'2.5',valor:'R$ 100,00'},0),/exigem quantidade inteira/,
 'Acessório medido em MT não permite meio metro');

assert.deepEqual(perfil.getMaterials().map(x=>x.id),['p1'],
 'Não mostrar perfis externos à obra');
assert.deepEqual(perfil.getVariations('p1').map(x=>x.id),['v1'],
 'Somente a cor/variação existente na obra');
const sizes=perfil.selectOptions();
assert.deepEqual(sizes.map(x=>x.length),[6000,6500],
 'Mesmo perfil em duas medidas deve aparecer como duas opções distintas');
assert.deepEqual(sizes.map(x=>x.value),['v1|6000','v1|6500'],
 'Chave do seletor contém variação e comprimento da barra');
const q6=perfil.quantityData({material:'p1',variacao:'v1',selectionKey:'v1|6000',comprimento:'6000'});
assert.deepEqual([q6.needed,q6.received,q6.pending],['5 barras','2 barras','3 barras'],
 'CEM NUMBARRAS é 5, não os 24 cortes; recebido e faltante usam 6000 mm');
const q65=perfil.quantityData({material:'p1',variacao:'v1',selectionKey:'v1|6500',comprimento:'6500'});
assert.deepEqual([q65.needed,q65.received,q65.pending],['4 barras','3 barras','1 barra'],
 'Barras de 6500 mm não contam no saldo de 6000 mm');
assert.equal(perfil.autoBarLength({material:'p1',variacao:'v1',selectionKey:'v1|6000'}),6000,
 'O comprimento do CEM prevalece sobre o cadastro genérico do perfil');
assert.equal(perfil.autoBarLength({material:'p1',variacao:'v1',selectionKey:'v1|6500'}),6500,
 'Comprimentos comerciais múltiplos permanecem distintos');
const noImport=mockResolver({...fixture,barrasCem:[]},'aluminio');
const unknown=noImport.quantityData({material:'p1',variacao:'v1',comprimento:'6000'});
assert.equal(unknown.needed,'Não importado');
assert.equal(unknown.pending,'—');
assert.equal(unknown.received,'2 barras');
assert.ok(unknown.note.includes('não importadas'), 'Ausência de NUMBARRAS/BARRA deve ser explícita');
assert.equal(noImport.selectOptions()[0].length,null,'Sem barras do CEM não inventar tamanho');
const noPlanRow=noImport.quantityData({material:'p1',variacao:'v1',selectionKey:'v1|',comprimento:''});
assert.deepEqual([noPlanRow.needed,noPlanRow.received,noPlanRow.pending],
 ['Não importado','—','—'],
 'Sem plano CEM não exigir medida manual nem somar recebimentos de outras medidas');
const compraDiferente=perfil.quantityData({material:'p1',variacao:'v1',selectionKey:'v1|6000',comprimento:'5500'});
assert.deepEqual([compraDiferente.needed,compraDiferente.received,compraDiferente.pending],
 ['Não planejado','0 barras','—'],
 'Compra com medida diferente não altera a necessidade planejada da obra');
const compraSemPlano=noImport.quantityData({material:'p1',variacao:'v1',selectionKey:'v1|',comprimento:'6000'});
assert.deepEqual([compraSemPlano.needed,compraSemPlano.received,compraSemPlano.pending],
 ['Não importado','2 barras','—'],
 'Mesmo sem plano persistido, a compra real pode registrar comprimento sem inventar necessidade');
assert.ok(receiveScript.includes('class="finManualLength" type="number"')&&
 receiveScript.includes("r.comprimento=event.target.value;")&&
 receiveScript.includes('avisoMedidas')&&
 !receiveScript.includes('finManualLength[readonly]'),
 'Se há plano CEM, barra continua pré-preenchida, editável e confirma divergências');
assert.ok(receiveScript.includes('if(!plannedBarRows(row.variacao).length)')&&
 receiveScript.includes('Plano de barras não importado')&&
 receiveScript.includes('"Importar arquivo técnico"')&&
 !receiveScript.includes('data-manual-reimport')&&
 !receiveScript.includes('cemAbrirRecuperacaoPlano'),
 'Ausência de plano deve ter só aviso, sem novo botão de recuperação');
assert.ok(!source.includes('function cemAbrirRecuperacaoPlano(')&&
 !source.includes('cemRecuperacaoPlano')&&
 source.includes("node('navCem').addEventListener('click',()=>setView('cemImport'))"),
 'Manter o menu de importação técnica sem fluxo duplicado');
const cad=mockResolver({...fixture,barrasCem:[],
 perfis:[{...fixture.perfis[0],comprimento_comercial_mm:5500},fixture.perfis[1]]},'aluminio');
assert.equal(cad.autoBarLength({material:'p1',variacao:'v1',selectionKey:'v1|'}),null,
 'Comprimento comercial genérico não substitui o plano de barras do CEM');
const accessor=mockResolver(fixture,'acessorios');
assert.deepEqual(accessor.getMaterials().map(x=>x.id),['a1']);
const acc=accessor.quantityData({material:'a1',variacao:'va1'});
assert.deepEqual([acc.needed,acc.received,acc.pending],['58 PC','20 PC','38 PC'],
 'Acessórios continuam na unidade real e não dependem do plano de barras');
const empty=mockResolver({...fixture,materiaisObra:[]},'aluminio');
assert.deepEqual(empty.getMaterials(),[],'Não exibir catálogo global quando a obra não tem materiais');
// Se existir plano da obra, ele substitui inteiramente o legado da mesma
// variação e medida; não ocorre dupla contagem.
const comPlanoPersistido=mockResolver({...fixture,materiaisObra:[
 {...fixture.materiaisObra[0],barras_planejadas:[
  {comprimento_mm:6000,quantidade:7},{comprimento_mm:6500,quantidade:4}]},
 fixture.materiaisObra[1]]},'aluminio');
const plannedVsLegacy=comPlanoPersistido.quantityData({
 material:'p1',variacao:'v1',selectionKey:'v1|6000',comprimento:'6000'});
assert.deepEqual([plannedVsLegacy.needed,plannedVsLegacy.received,plannedVsLegacy.pending],
 ['7 barras','2 barras','5 barras'],
 'Priorizar o plano técnico de 7 barras e não somar 5 barras do histórico');
const semPlanoAtual=mockResolver({...fixture,materiaisObra:[
 {...fixture.materiaisObra[0],barras_planejadas:[]},fixture.materiaisObra[1]]},'aluminio');
assert.equal(semPlanoAtual.quantityData({material:'p1',variacao:'v1',comprimento:'6000'}).needed,
 'Não importado','Plano explícito vazio não herda importação anterior');
assert.ok(!receiveScript.includes('<td><select class="finManualVariation"'),
 'Cor vem automaticamente do CEM, sem segundo seletor');
assert.ok(receiveScript.includes('finManualReadonly')&&receiveCSS.includes('.finManualStat')&&
 source.includes('<th>Necessário</th><th>Já recebido</th><th>Falta receber</th>'),
 'Manter cor e barras em colunas visíveis');

// Gestão financeira: NF somada pelos valores dos materiais, sem dupla digitação.
assert.ok(source.includes('id="finSupplierAdd"')&&source.includes('id="finWarehouseAdd"')&&
 source.includes('<select id="finCostVendor"')&&source.includes('finRegistryPanel')&&
 source.includes("apiGet('ew_fornecedores'")&&
 source.includes("async function cadastrarGalpaoEmpresa(nome)"),
 'Financeiro deve cadastrar fornecedores e reutilizar galpões da empresa');
assert.ok(receiveScript.includes('function hojeLocalISO(){')&&
 receiveScript.includes("if(!byId('finCostDate').value)byId('finCostDate').value=hojeLocalISO()")&&
 !receiveScript.includes('new Date().toISOString().slice(0,10)'),
 'Data deve vir preenchida no dia local e continuar editável');
assert.ok(receiveScript.includes("byId('finCostTotal').readOnly=true;")&&
 receiveScript.includes("byId('finMiscBlock').classList.toggle('hidden',hasStock)")&&
 receiveScript.includes("totalField.value=soma>0?finMoney(soma/100):''")&&
 !receiveScript.includes('rows.length===1&&note!==null'),
 'Valor da NF de materiais deve vir da soma dos itens sem substituir um valor de linha');

// EWGEST #34 — estoque físico de vidros/insumos com contas isoladas por unidade e galpão.
const techSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_exclusao_cadastros_tecnicos.sql',import.meta.url)),'utf8');
const insumosSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_insumos_fisicos_recebimento.sql',import.meta.url)),'utf8');
const insumosCatalogoSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_insumos_fisicos_catalogo.sql',import.meta.url)),'utf8');
const insumosTransferSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_insumos_fisicos_transferencia_estorno.sql',import.meta.url)),'utf8');
const insumosGuardasSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261121_insumos_guardas_integridade.sql',import.meta.url)),'utf8');
const insumosClient=readFileSync(fileURLToPath(new URL('../assets/insumos-fisicos.js',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(insumosClient),'O script do estoque físico deve ter sintaxe válida');
assert.ok(source.includes('id="finMiscBlock"')&&source.includes('id="finMiscRows"')&&
 source.includes('id="finMiscSum"')&&source.includes('id="insumosStockPanel"')&&
 source.includes('id="insumosTransferForm"')&&source.includes('id="cadastroInsumosForm"')&&
 source.includes('insumos-fisicos.js?v=20261125c')&&
 receiveScript.includes('function miscNormalized(){')&&
 receiveScript.includes('function miscUpdateSum(){')&&
 receiveScript.includes("byId('finMiscRows').replaceChildren()")&&
 receiveScript.includes("byId('finManualRows').replaceChildren()")&&
 receiveScript.includes("'/rest/v1/rpc/ew_insumos_receber'")&&
 receiveScript.includes('p_local_estoque:location')&&
 receiveScript.includes('p_itens:items')&&
 receiveScript.includes("byId('finManualLocal').required=true;"),
 'NF de vidro/insumo deve ser recebida no estoque físico real por galpão');
assert.ok(insumosCatalogoSQL.includes('create table if not exists public.ew_insumos_catalogo')&&
 insumosCatalogoSQL.includes('create table if not exists public.ew_insumos_movimentos')&&
 insumosCatalogoSQL.includes('enable row level security')&&
 insumosCatalogoSQL.includes('ew_insumos_saldos_obra')&&
 insumosSQL.includes('insert into public.ew_obra_despesas_itens')&&
 insumosSQL.includes('insert into public.ew_insumos_movimentos')&&
 insumosSQL.includes("p_categoria not in ('vidros','outros')")&&
 insumosSQL.includes('revoke execute on function public.ew_insumos_receber')&&
 insumosTransferSQL.includes('v_saldo<p_quantidade')&&
 insumosTransferSQL.includes('ew_insumos_estornar_transferencia')&&
 insumosTransferSQL.includes('ew_insumos_cancelar_nota')&&
 insumosGuardasSQL.includes('saldos_insumos_nao_zerados')&&
 insumosGuardasSQL.includes("Nota com vidros/outros no estoque"),
 'Banco deve manter integridade de saldo, documento, permissões, estorno e exclusão');
assert.ok(techSQL.includes('ew_excluir_cadastro_tecnico_sem_vinculo')&&
 techSQL.includes('ew_obra_despesas_itens')&&
 techSQL.includes('ew_materiais_variacoes')&&
 techSQL.includes('ew_estoque_obras_movimentos')&&
 source.includes('data-mat-delete')&&source.includes('id="matVarDelete"')&&
 source.includes('id="typologyEditDelete"')&&
 source.includes('id="manufacturerManagePanel"'),
 'Exclusão de cadastros técnicos exige ausência de vínculo em obras, estoque e histórico');

const subtotalStart=receiveScript.indexOf(' function updateSum(){');
const subtotalEnd=receiveScript.indexOf(' function renderForm(){',subtotalStart);
assert.ok(subtotalStart>=0&&subtotalEnd>subtotalStart,'Rotina de total automático localizada');
const camposSimulados={
 finCostTotal:{value:''},
 finManualSum:{textContent:'',classList:{toggle() {}}}
};
const toCentsTest=v=>{
 if(!v)return null;
 const n=Number(String(v).replace(/^R\$\s*/,'').replace(/\./g,'').replace(',','.'));
 return Number.isFinite(n)?Math.round(n*100):null;
};
const autoTotal=new Function('itens','fields','cents','finMoney',
 'let rows=itens; const byId=id=>fields[id];const stockCategory=()=>true;\n'+
 receiveScript.slice(subtotalStart,subtotalEnd)+
 '\nreturn updateSum;');
const totalRows=[{valor:'R$ 525,50'},{valor:''}];
const totalUpdater=autoTotal(totalRows,camposSimulados,toCentsTest,
 n=>'R$ '+n.toFixed(2).replace('.',','));
totalUpdater();
assert.equal(camposSimulados.finCostTotal.value,'R$ 525,50',
 'Uma linha já deve alimentar o valor total da NF');
totalRows[1].valor='R$ 150,00';totalUpdater();
assert.equal(camposSimulados.finCostTotal.value,'R$ 675,50',
 'Duas linhas devem atualizar valor total automaticamente');
totalRows.splice(0,1);totalUpdater();
assert.equal(camposSimulados.finCostTotal.value,'R$ 150,00',
 'Remover linha deve reduzir valor total da nota');

const fornecedorSQL=readFileSync(fileURLToPath(
 new URL('../database/proposals/20261121_cadastro_fornecedores.sql',import.meta.url)),'utf8');
assert.ok(fornecedorSQL.includes('CREATE TABLE IF NOT EXISTS public.ew_fornecedores')&&
 fornecedorSQL.includes('ENABLE ROW LEVEL SECURITY')&&
 fornecedorSQL.includes('FOR INSERT TO authenticated')&&
 fornecedorSQL.includes("ue.perfil='administrador'")&&
 fornecedorSQL.includes('GRANT SELECT,INSERT,UPDATE')&&
 !fornecedorSQL.includes('SECURITY DEFINER'),
 'Fornecedor precisa de cadastro por empresa, RLS e escrita ADM');

const stockFunctionStart=source.indexOf('function stockNecessidade(item){');
const stockFunctionEnd=source.indexOf('function renderEstoque(){',stockFunctionStart);
assert.ok(stockFunctionStart>=0&&stockFunctionEnd>stockFunctionStart,
 'Função da necessidade de estoque disponível');
const estoqueNecessidade=new Function('releaseUnidadeAcessorio','escapeHTML',
 source.slice(stockFunctionStart,stockFunctionEnd)+'\nreturn stockNecessidade;')(
 unidade=>unidade,valor=>valor);
const stockProfile={
 v:{tipo:'perfil'},mat:{},comprimento:6000,
 link:{quantidade_prevista:10,comprimento_total_m:11.5,
  barras_planejadas:[{comprimento_mm:6000,quantidade:2},{comprimento_mm:6500,quantidade:1}]},
 perWork:[{comprimento_mm:6000,unidade:'BARRA',quantidade_delta:1}]
};
const estoqueBar=estoqueNecessidade(stockProfile);
assert.equal(estoqueBar.necessaria,'2 barras',
 'GN096: necessidade de 2 barras de 6000 mm, não 11,5 m/10 cortes');
assert.equal(estoqueBar.texto,'Recebimento parcial','1 de 2 barras é parcial');
assert.equal(estoqueNecessidade({...stockProfile,comprimento:6500}).necessaria,'1 barra',
 'Outro comprimento tem necessidade independente');
assert.equal(estoqueNecessidade({...stockProfile,link:{
 quantidade_prevista:10,comprimento_total_m:11.5,barras_planejadas:null}}).necessaria,
 'Não importado','Não inventar barras quando só há informação de cortes');
assert.ok(source.includes('const medidas=v.tipo')&&
 source.includes('barras_planejadas.map(b=>Number(b.comprimento_mm))')&&
 !source.includes('m em cortes'),
 'Estoque também deve listar tamanhos planejados sem saldo físico e não mostrar cortes como necessidade');

// Novo fluxo: o estoque só mostra saídas por transferência, sem entrada livre na tela.
const transferSQL=readFileSync(fileURLToPath(
 new URL('../database/proposals/20261121_transferencia_estoque_entre_obras.sql',import.meta.url)),'utf8');
const cadastroHubJS=readFileSync(fileURLToPath(
 new URL('../assets/cadastros-hub.js',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(cadastroHubJS),'Central de cadastros deve ser JavaScript válido');
for(const id of ['navCadastros','cadastros','navAccessories','cadastroFornecedorForm',
 'cadastroGalpaoForm','cadastroFornecedorNome','cadastroGalpaoNome','navMaterials',
 'navTypologies','navManufacturers','navUsers']){
 assert.ok(source.includes('id="'+id+'"'),'Cadastro central faltando '+id);
}
assert.ok(/cadastros-hub\.js\?v=\d{8}[a-z]/.test(source)&&
 source.includes("['navCadastros','cadastros']")&&
 cadastroHubJS.includes("apiGet('ew_fornecedores'")&&
 cadastroHubJS.includes("apiGet('ew_locais_fisicos'")&&
 cadastroHubJS.includes('cadastrarGalpaoEmpresa(nome)'),
 'Um único menu de cadastros reutiliza fornecedores e galpões já cadastrados');
assert.ok(source.includes('id="cadastroJumpGruposCompra"')&&source.includes('id="cadastroGruposCompra"')&&cadastroHubJS.includes('ew_compras_salvar_grupos_fornecedor'),'Cadastro central inclui os grupos de compra e vínculos por fornecedor');
const comprasNav=source.slice(source.indexOf('id="navCompras"'),source.indexOf('id="navRecebimento"'));
const comprasPanel=source.slice(source.indexOf('<section id="compras"'),source.indexOf('<section id="recebimento"'));
assert.ok(comprasNav.includes('id="navComprasSubmenu"')&&comprasNav.includes('id="comprasTabSolicitacao"')&&comprasNav.includes('id="comprasTabCotacao"')&&comprasNav.includes('id="comprasTabPedido"')&&comprasNav.includes('id="comprasTabAprovacao"')&&comprasNav.includes('>Pedidos de compra</button>')&&!comprasPanel.includes('comprasTabAprovacao')&&!comprasPanel.includes('comprasTabSolicitacao')&&!comprasPanel.includes('comprasTabCotacao')&&!comprasPanel.includes('comprasTabPedido'),'Compras possui as quatro etapas no menu lateral, sem abas duplicadas no painel');
const recebimentoPanel=source.slice(source.indexOf('<section id="recebimento"'),source.indexOf('<section id="financeiro"'));
const recebimentoNav=source.slice(source.indexOf('id="navRecebimento"'),source.indexOf('id="navEnviarNotas"'));
assert.ok(recebimentoNav.includes('id="navRecebimentoSubmenu"')&&['manual','pedido','historico'].every(m=>recebimentoNav.includes('data-recebimento-modo="'+m+'"'))&&!recebimentoPanel.includes('data-recebimento-modo=')&&recebimentoPanel.includes('id="recebimentoHistoricoNotas"'),'Recebimento separa as três operações no submenu lateral, sem botões duplicados no painel');
assert.ok(source.includes("node('navRecebimentoSubmenu').classList.add('hidden')")&&source.includes("void abrirRecebimento(null,modo)")&&source.includes("else recebimentoSelecionarModo(modo)"),'Navegação de recebimento recolhe o submenu e preserva obra selecionada ao trocar de etapa');
assert.ok(source.includes('function recebimentoRenderHistoricoNotas()')&&source.includes('Estornar nota e recebimentos ativos')&&source.includes('recebimentoHistoricoBusca')&&source.includes('ew_estornar_nfe_com_recebimentos'),'Histórico de notas tem busca e estorno integral usando RPC existente');
const estornoManualSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261125_estorno_nfe_manual_v46297.sql',import.meta.url)),'utf8');
assert.ok(estornoManualSQL.includes("v_doc.origem NOT IN ('nfe_xml','manual')")&&estornoManualSQL.includes('v_doc.obra_id IS DISTINCT FROM v_obra')&&estornoManualSQL.includes("ew_pode(p_empresa_id,'estoque.estornar')")&&estornoManualSQL.includes("ew_pode(p_empresa_id,'financeiro.cancelar_despesas')")&&estornoManualSQL.includes('ew_estornar_recebimento_nfe')&&estornoManualSQL.includes('ew_cancelar_despesa_financeira'),'Estorno integral aceita nota manual e XML com as mesmas travas físicas, financeiras e de empresa/obra');
const estoqueNav=source.slice(source.indexOf('id="navStock"'),source.indexOf('id="navFinanceiro"'));
const estoquePanel=source.slice(source.indexOf('<section id="stock"'),source.indexOf('<section id="cemImport"'));
assert.ok(estoqueNav.includes('id="navStockSubmenu"')&&['consulta','transferencias','producao','historico'].every(m=>estoqueNav.includes('data-stock-modo="'+m+'"'))&&!recebimentoNav.includes('data-recebimento-modo="producao"')&&!recebimentoPanel.includes('id="entregasProducaoPanel"')&&estoquePanel.includes('id="entregasProducaoPanel"')&&estoquePanel.includes('id="stockProducaoWork"'),'Entrega à produção pertence ao Estoque, com submenu independente do Recebimento');
const fornecedorPage=source.slice(source.indexOf('<section id="fornecedoresPage"'),source.indexOf('<section id="galpoesPage"'));
const gruposEditor=cadastroHubJS.slice(cadastroHubJS.indexOf(' async function abrirGrupos(){'));
assert.ok(fornecedorPage.includes('id="cadastroFornecedorGrupos"')&&cadastroHubJS.includes("async function abrirGruposFornecedor(")&&!gruposEditor.includes('cadastroGrupoSalvarFornecedor'),'Vínculos comerciais ficam exclusivamente no cadastro de fornecedores');
assert.ok(source.includes('id="stockTransferPickWork"')&&
 source.includes("stockObraTransferOpen(candidate.item.v.id")&&
 source.includes('id="stockObraTransferOverlay"')&&
 source.includes('id="stockObraTransferTarget"')&&
 source.includes('id="stockObraTransferToLocal"')&&
 source.includes('id="stockObraTransferQty"')&&
 source.includes('stockObraTransferOpen(')&&
 source.includes("'/rest/v1/rpc/ew_transferir_estoque_entre_obras'"),
 'Transferência entre obras deve indicar destino, galpão, quantidade e registrar RPC única');
assert.ok(source.includes("node('stockCreateEmptyOverlay').classList.remove('hidden')")&&
 source.includes("node('stockCreateEmptyForm').addEventListener('submit'")&&
 !source.includes("node('stockCreateAnother').addEventListener('click',()=>stockManualOpen())"),
 'Nova obra de estoque começa sem entrada de materiais');
for(const token of [
 'CREATE OR REPLACE FUNCTION public.ew_transferir_estoque_entre_obras',
 'PERFORM public.ew_exigir_sessao_atual();',
 "u.perfil IN ('administrador','gerenciador')",
 'pg_catalog.pg_advisory_xact_lock',
 'v_saldo<p_quantidade',
 "AND quantidade_delta=-p_quantidade AND origem='TRANSFERENCIA'",
 "AND quantidade_delta=p_quantidade AND origem='TRANSFERENCIA'",
 "'TRANSFERENCIA',gen_random_uuid(),v_observacao",
 "p_quantidade<>trunc(p_quantidade)",
 'REVOKE ALL ON FUNCTION',
 'GRANT EXECUTE ON FUNCTION'
]){
 assert.ok(transferSQL.includes(token),'Transferência SQL sem proteção: '+token);
}
const estornoCrossSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_estorno_transferencia_entre_obras.sql',import.meta.url)),'utf8');
const guardTotalSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_guard_estorno_estoque_transferencias_obras.sql',import.meta.url)),'utf8');
const guardArchiveSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_guard_arquivar_estoque_transferencias_obras.sql',import.meta.url)),'utf8');
assert.ok(estornoCrossSQL.includes('CREATE OR REPLACE FUNCTION public.ew_estornar_transferencia_entre_obras')&&
 estornoCrossSQL.includes('v_saldo<v_credito.quantidade_delta')&&
 estornoCrossSQL.includes("'ESTORNO',gen_random_uuid()")&&
 estornoCrossSQL.includes('v_credito.id')&&
 estornoCrossSQL.includes('v_debito.id')&&
 estornoCrossSQL.includes('REVOKE ALL ON FUNCTION'),
 'Estorno de transferência entre obras deve reverter ambas as pontas atomicamente e verificar saldo do destino');
assert.ok(guardTotalSQL.includes('Há transferência ativa entre obras')&&
 guardArchiveSQL.includes('Existe transferência entre obras ainda ativa')&&
 guardTotalSQL.includes('est.estorno_de_id=m.id')&&
 guardArchiveSQL.includes('est.estorno_de_id=m.id'),
 'Arquivar ou estornar o estoque inteiro não pode reverter apenas uma ponta de transferência');
assert.ok(source.includes('Estornar transferência entre obras')&&
 source.includes("'/rest/v1/rpc/ew_estornar_transferencia_entre_obras'")&&
 source.includes('p_transferencia_id:mov.transferencia_id'),
 'Histórico deve permitir estorno conjunto das duas obras');
assert.ok(!/DELETE\s+FROM\s+public\.ew_estoque_obras_movimentos/i.test(transferSQL)&&
 !/UPDATE\s+public\.ew_estoque_obras_movimentos/i.test(transferSQL),
 'Transferência deve registrar deltas de saída/entrada, nunca reescrever histórico');


// EWGEST v45.3 — GN096 só aparece após selecionar obra; estorno NF e
// entrega física do almoxarife são etapas distintas da liberação técnica.
const releaseDelayedSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_liberacao_sem_baixa_ate_entrega.sql',import.meta.url)),'utf8');
const deliverySQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_entrega_producao_almoxarife.sql',import.meta.url)),'utf8');
const receiptUndoSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_estorno_recebimento_nfe.sql',import.meta.url)),'utf8');
const deliveryClient=readFileSync(fileURLToPath(new URL(
 '../assets/entregas-producao.js',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(deliveryClient),'Script de entrega à produção precisa ser sintaticamente válido');
assert.ok(source.includes('v46.29.52')&&
 source.includes('id="entregasProducaoPanel"')&&
 source.includes('entregas-producao.js?v=20261125c')&&
 source.includes('entregas-producao.css?v=20261121a')&&
 source.includes("const anterior=prefer||sel.value||'';")&&
 source.includes("if(!obraId){msg.textContent='Selecione um local de estoque para iniciar o recebimento.';return;}")&&
 source.includes("if(obraId.startsWith('empresa:')){if(!['pedido','historico'].includes(node('recebimento').dataset.modo))recebimentoSelecionarModo('pedido');msg.textContent='Estoque da empresa: recebimento físico exclusivamente por pedido de compra.';return;}")&&
 source.includes("for(const id of ['finPendingPanel','finReceivePanel','recebimentoHistoricoNotas'])")&&
 source.includes("x.obraId!==node('recebimentoWork').value")&&
 source.includes("el.classList.add('hidden');el.replaceChildren();return;")&&
 source.includes("x.obraId!==selected")&&
 source.includes("state.obraId!==selected"),
 'Notas aprovadas/pedidas GN096 não podem aparecer sem seleção explícita da obra');
assert.ok(source.includes('finReceiveUndo')&&
 source.includes("ew_estornar_nfe_com_recebimentos")&&
 source.includes('estornado_em,estorno_motivo,estorno_detalhes')&&
 receiptUndoSQL.includes('ew_estornar_recebimento_nfe')&&
 receiptUndoSQL.includes('estorno_detalhes')&&
 receiptUndoSQL.includes("m.origem in ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE')")&&
 receiptUndoSQL.includes('m.local_estoque')&&
 receiptUndoSQL.includes('n.estornado_em is null')&&
 receiptUndoSQL.includes('Estorno de recebimento NF-e não pode ser revertido'),
 'Estorno de NF mantém histórico, aceita galpão alterado e bloqueia baixa de produção');
assert.ok(releaseDelayedSQL.includes('ew_liberar_plano_corte_revisado')&&
 releaseDelayedSQL.includes('ew_liberar_lote_cem')&&
 releaseDelayedSQL.includes("'linhas_baixadas',0")&&
 !/insert into public\.ew_estoque_obras_movimentos/i.test(releaseDelayedSQL)&&
 deliverySQL.includes('ew_entregas_pendentes_producao')&&
 deliverySQL.includes('ew_confirmar_entrega_producao')&&
 deliverySQL.includes("'PLANO_CORTE_LOTE'")&&
 deliverySQL.includes('v_stock<v_qty')&&
 deliverySQL.includes('p_operacao_id')&&
 deliveryClient.includes('entregaRelatorioCheck')&&
 deliveryClient.includes('ew_confirmar_entrega_producao'),
 'Liberação gera relação impressa sem baixa; só entrega física de almoxarife baixa estoque');



// EWGEST v45.4 — romaneios automaticos sem rebaixa ao imprimir/agrupar.
const transferDocsSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_romaneios_transferencias_galpoes_v454.sql',import.meta.url)),'utf8');
const transferDocsJS=readFileSync(fileURLToPath(new URL(
 '../assets/romaneios-transferencia.js',import.meta.url)),'utf8');
const transferDocsCSS=readFileSync(fileURLToPath(new URL(
 '../assets/romaneios-transferencia.css',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(transferDocsJS),
 'Novo script de romaneios entre galpoes deve ser JavaScript valido');
assert.ok(source.includes('id="stockTransferPickLocal">Transferência entre galpões')&&
 source.includes('id="romTransfSection"')&&
 source.includes('id="romTransfMerge"')&&
 source.includes('id="romTransfExtras"')&&
 source.includes('romaneios-transferencia.css?v=20261121c')&&
 source.includes('romaneios-transferencia.js?v=20261125a')&&
 source.includes("if(window.ewTransferRomaneiosReload)window.ewTransferRomaneiosReload()"),
 'Transferencia entre galpoes deve ter romaneio na guia de expedicao');
for(const token of [
 'ew_gerar_romaneio_de_transferencia','after insert on public.ew_estoque_obras_movimentos',
 "new.origem<>'TRANSFERENCIA'","new.quantidade_delta>=0",
 'transferencia_id uuid unique','romaneios_numero_seq',
 "tipo in ('TRANSFERENCIA','AVULSO')","status in ('RASCUNHO','EMITIDO','AGRUPADO','CANCELADO')",
 'ew_romaneios_transferencia_juntar','ew_romaneio_transferencia_emitir',
 'ew_romaneio_transferencia_salvar','ew_romaneios_transferencia_listar',
 'ew_exigir_sessao_atual','enable row level security',
 "revoke all on public.ew_romaneios_transferencia",
 'e.estorno_de_id in'
]){
 assert.ok(transferDocsSQL.includes(token),'Romaneio de transferencia sem requisito de seguranca: '+token);
}
assert.ok(!/insert into public\.ew_estoque_obras_movimentos/i.test(transferDocsSQL)&&
 !/update public\.ew_estoque_obras_movimentos/i.test(transferDocsSQL)&&
 !/delete from public\.ew_estoque_obras_movimentos/i.test(transferDocsSQL),
 'Gerar, editar, agrupar e imprimir romaneios de transferencia nunca deve movimentar estoque');
assert.ok(transferDocsJS.includes('data-t-edit')&&
 transferDocsJS.includes('data-t-print')&&
 transferDocsJS.includes('data-t-view')&&
 transferDocsJS.includes('data-transf-pick')&&
 transferDocsJS.includes('romTransfAddExtra')&&
 transferDocsJS.includes('Avulso (sem movimentação de estoque)')&&
 transferDocsCSS.includes('.romTransfExtra'),
 'Edicao e impressao de transferencia devem preservar itens avulsos e aviso sem baixa');


// EWGEST v45.5 — central de cadastros: destinos separados, sem edicao acidental.
const paginasCSS=readFileSync(fileURLToPath(new URL(
 '../assets/cadastros-pages.css',import.meta.url)),'utf8');
for(const id of [
 'fornecedoresPage','galpoesPage','insumosPage','cadastroFornecedorForm',
 'cadastroGalpaoForm','cadastroInsumosForm','cadastroInsumosCategory',
 'cadastroInsumosTitle','cadastroJumpFornecedores','cadastroJumpGalpoes',
 'navVidros','navOutrosInsumos','matPageTitle','matPageSubtitle',
 'matStatPerfis','matStatAcessorios','matTabPerfil','matTabAcessorio',
 'stockManageLocations','stockManageOverlay'
])assert.ok(source.includes('id="'+id+'"'),'Faltou elemento de cadastro: '+id);
assert.ok(source.includes("'fornecedoresPage','galpoesPage','insumosPage'")&&
 source.includes("'materials','typologies','manufacturers','users','fornecedoresPage','galpoesPage','insumosPage'")&&
 cadastroHubJS.includes("button.addEventListener('click',abrir)")&&
 cadastroHubJS.includes("abrirCategoria('fornecedor')")&&
 cadastroHubJS.includes("abrirCategoria('galpao')")&&
 source.includes('class="materialTabs hidden"')&&
 source.includes('class="btn secondary cadastrosBack"')&&
 source.includes('cadastros-pages.css?v=20261121b'),
 'Cadastros devem abrir paginas exclusivas com botao voltar e sem alternancia direta');
assert.ok(!source.includes('id="cadastroGerenciarEstoque"')&&
 !source.includes('id="cadastroInsumosJump"')&&
 !cadastroHubJS.includes("stockManageOpen()")&&
 source.includes('id="stockManageLocations" title=')&&
 paginasCSS.includes('#stockManageLocations'),
 'Administracao de estoque deve ficar no Estoque, nao como cadastro redundante');
assert.ok(insumosClient.includes("byId('navVidros').addEventListener('click'")&&
 insumosClient.includes("byId('navOutrosInsumos').addEventListener('click'")&&
 insumosClient.includes("categoriaAtual=categoria")&&
 insumosClient.includes("byId('cadastroInsumosCategory').value=categoriaAtual")&&
 source.includes('class="hidden">Categoria')&&
 !insumosClient.includes("byId('cadastroInsumosJump')"),
 'Vidros e outros insumos devem ser separadas sem trocar categoria silenciosamente');
assert.ok(source.includes("node('matPageTitle').textContent=")&&
 source.includes("node('matStatAcessorios').classList.toggle('hidden',perfil)")&&
 source.includes("node('matStatPerfis').classList.toggle('hidden',!perfil)"),
 'Resumo e titulo de materiais seguem o modulo escolhido');


// EWGEST v45.6 — unidades de medida cadastraveis e integracao com NF.
const unidadesSQL=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_unidades_medida_v456.sql',import.meta.url)),'utf8');
const unidadesJS=readFileSync(fileURLToPath(new URL(
 '../assets/unidades-medida.js',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(unidadesJS),'O cadastro de unidades deve ter JS válido');
for(const id of ['navUnidades','unidadesPage','unidadeForm','unidadeCodigo','unidadeNome',
 'unidadeLista','unidadeMessage','unidadeEdicao','unidadeNovoNome','unidadeEdicaoForm']){
 assert.ok(source.includes('id="'+id+'"'),'Unidades de medida: falta '+id);
}
assert.ok(source.includes('unidades-medida.js?v=20261125a')&&
 source.includes("'insumosPage','unidadesPage'")&&
 source.includes("'insumosPage','unidadesPage','cadastroLocaisEstoque','manageWorks'].includes(ativo)")&&
 source.includes('Voltar para cadastros')&&
 unidadesJS.includes("byId('navUnidades').addEventListener('click',abrir)")&&
 unidadesJS.includes('window.ewUnidadesMedida={lista,ativa,nome,carregar}')&&
 unidadesJS.includes('categoria')===false,
 'Unidades: menu individual, voltar e lista global, sem mexer em categoria');
assert.ok(receiveScript.includes("window.ewUnidadesMedida?.lista()")&&
 receiveScript.includes("window.ewUnidadesMedida?.ativa(r.unidade)")&&
 receiveScript.includes("window.ewRecebimentoAtualizarUnidades=")&&
 insumosClient.includes("window.ewUnidadesMedida?.nome(codigo)")&&
 source.includes('insumos-fisicos.js?v=20261125c'),
 'Unidades novas devem entrar no cadastro, NF e saldos do estoque');
for(const token of [
 'create table if not exists public.ew_unidades_medida',
 'ew_unidades_codigo_valido','ew_unidades_padrao_nova_empresa',
 'ew_insumos_catalogo_unidade_check',
 'ew_insumos_catalogo_unidade_fk',
 'ew_unidades_medida_listar','ew_unidades_medida_gerenciar',
 'ew_insumo_gerenciar_catalogo','ew_insumos_receber',
 'ew_receber_despesa_com_itens_almox',
 'revoke all on table public.ew_unidades_medida',
 'ew_exigir_sessao_atual', 'on update restrict on delete restrict',
 'Unidade já usada por material ou nota'
])assert.ok(unidadesSQL.includes(token),'Faltou proteção no catálogo de unidades: '+token);
assert.ok(unidadesSQL.includes("u.codigo=v_unit and u.ativo")&&
 unidadesSQL.includes("u.codigo=p_unidade and u.ativo")&&
 !/update\s+public\.ew_insumos_movimentos/i.test(unidadesSQL),
 'A nova unidade deve servir ao recebimento sem alterar saldo existente');


// EWGEST v45.7 — transferir perfis em barras inteiras, nunca 0,001 barra.
assert.ok(source.includes('id="stockTransferQty" type="number" min="1" step="1"')&&
 source.includes('id="stockObraTransferQty" type="number" min="1" step="1"')&&
 source.includes("function stockTransferPrepararQuantidade(id,tipo,saldo,unidade)")&&
 source.includes("campo.min=inteira?'1':'0.001'")&&
 source.includes("campo.step=inteira?'1':'any'")&&
 source.includes("campo.value=inteira?(saldoDisponivel>=1?'1':''):String(Number(Math.min(1,saldoDisponivel).toFixed(3)))")&&
 source.includes("stockTransferPrepararQuantidade('stockTransferQty',item.v.tipo,saldo,unit)")&&
 source.includes("stockTransferPrepararQuantidade('stockObraTransferQty',item.v.tipo,disponivel,unidade)")&&
 source.includes("'Quantidade para transferir (barras inteiras) '")&&
 source.includes("campo.max=String(saldoDisponivel)")&&
 source.includes("(!isBar&&!ewUnidadeEmMetroInteiro(selected.unit)&&Math.abs(qty*1000-Math.round(qty*1000))>0.00001)")&&
 source.includes("((barra||ewUnidadeEmMetroInteiro(sel.unidade))&&!Number.isSafeInteger(quantidade))")&&
 source.includes("node('stockTransferPickTitle').textContent=mode==='local'?")&&
 source.includes("'Transferência entre galpões':'Transferência entre obras'"),
 'Transferencias devem iniciar em 1 barra e respeitar saldo; acessorios continuam fracionaveis');
for(const id of ['stockTransferQtyLabel','stockObraTransferQtyLabel'])
 assert.ok(source.includes('id="'+id+'"'),'Label de quantidade nao identificado: '+id);
assert.ok(!source.includes('id="stockTransferQty" type="number" min="0.001" step="1"')&&
 !source.includes('id="stockObraTransferQty" type="number" min="0.001" step="1"'),
 'Minimo de 0,001 nao pode ser aplicado a barras inteiras');


// EWGEST v45.8 — acessórios em PC/UN/PR/CJ/CX não podem ser fracionados em NF.
const countableMigration=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_recebimento_quantidades_contaveis_v458.sql',import.meta.url)),'utf8');
assert.ok(source.includes('/assets/recebimento-manual.js?v=20261126a'),
 'Novas regras de quantidade devem invalidar o cache do JS anterior');
for(const marker of [
 "const unidadesContaveis=new Set(['PC','UN','PR','CJ','CX','MT'])",
 "const auto=autoBarLength(row),unit=unitFor(row.material),contavel=",
 "contavel?'type=\"number\" inputmode=\"numeric\" min=\"1\" max=\"1000000\" step=\"1\"'",
 "r.quantidade=category==='acessorios'&&r.material?'1':''",
 "category==='acessorios'&&unidadeContavel(unitFor(row.material))&&!validarQuantidadeContavel(rawQty)",
 "unidadeContavel(m.unidade)?'1':'any'",
 "if(unidadeContavel(item.unidade)&&item.quantidade&&",
]){
 assert.ok(receiveScript.includes(marker),'Recebimento deve tratar unidades contáveis: '+marker);
}
const contaveisInicio=receiveScript.indexOf(" const unidadesContaveis=new Set");
const contaveisFim=receiveScript.indexOf(" function stockCategory()",contaveisInicio);
assert.ok(contaveisInicio>0&&contaveisFim>contaveisInicio,
 'Funções de unidade contável devem existir');
const unidadeValidadores=new Function(receiveScript.slice(contaveisInicio,contaveisFim)+
 '\nreturn {unidadeContavel,validarQuantidadeContavel};')();
for(const unidade of ['PC','UN','PR','CJ','CX','MT'])
 assert.equal(unidadeValidadores.unidadeContavel(unidade),true,'Unidade contável '+unidade);
for(const unidade of ['KG','L','ML','M2'])
 assert.equal(unidadeValidadores.unidadeContavel(unidade),false,'Unidade fracionável '+unidade);
for(const qtd of ['1','2','15','1000000'])
 assert.equal(unidadeValidadores.validarQuantidadeContavel(qtd),true,'Quantidade inteira '+qtd);
for(const qtd of ['','0','0.001','0.005','0,005','-1','1.5','1e2','1000001'])
 assert.equal(unidadeValidadores.validarQuantidadeContavel(qtd),false,
  'Quantidade contável deve rejeitar '+qtd);
assert.ok(countableMigration.includes("v_unidade in ('PC','UN','PR','CJ','CX') and v_qty<>trunc(v_qty)")&&
 countableMigration.includes("v_unidade IN ('PC','UN','PR','CJ','CX') AND v_quantidade<>trunc(v_quantidade)")&&
 countableMigration.includes('ew_receber_materiais_almox')&&
 countableMigration.includes('ew_registrar_recebimento_manual_financeiro')&&
 !/update public\.ew_estoque_obras_movimentos/i.test(countableMigration),
 'As duas RPCs de recebimento devem validar inteiros sem regravar o estoque');


// EWGEST v45.9 — evitar incremento de milésimos no controle por metros/quilos.
assert.ok(
 receiveScript.includes("'type=\"number\" inputmode=\"decimal\" min=\"0.001\" max=\"1000000\" step=\"any\"'")&&
 receiveScript.includes("r.quantidade=category==='acessorios'&&r.material?'1':'';r.valor=''")&&
 receiveScript.includes("miscRows=[{descricao:'',quantidade:'1',unidade:'PC',valor:''}]")&&
 receiveScript.includes("miscRows.push({descricao:'',quantidade:'1',unidade:'PC',valor:''})")&&
 receiveScript.includes("unidadeContavel(m.unidade)?'1':'any'")&&
 receiveScript.includes("item.quantidade='1';")&&
 !receiveScript.includes("'type=\"number\" inputmode=\"decimal\" min=\"0.001\" max=\"1000000\" step=\"0.001\"'"),
 'Campos do recebimento devem iniciar em uma unidade, usar setas de 1 e permitir frações por digitação');
assert.ok(source.includes('recebimento-manual.js?v=20261126a')&&
 source.includes('EWGEST <strong>· v46.29.52</strong>'),
 'O novo JS de recebimento deve ter cache invalidado na versão 45.9');
const testarDecimais=(text)=>{
 const n=Number(text);
 return text.trim()!==''&&Number.isFinite(n)&&n>0&&n<=1000000&&
  Math.abs(n*1000-Math.round(n*1000))<=0.00001;
};
for(const t of ['0.5','1.25','2.75','0.001','1.005'])
 assert.equal(testarDecimais(t),true,'Permitir medição fracionada '+t);
for(const t of ['0','-1','2.1234','0.0001','1000001'])
 assert.equal(testarDecimais(t),false,'Impedir medição inválida '+t);


// EWGEST v46.0 — MT inteiro de ponta a ponta (NF, estoque, transferência e produção).
const mtMigration=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_metro_inteiro_v460.sql',import.meta.url)),'utf8');
for(const token of [
 'ew_validar_mt_despesa_item','ew_despesa_mt_inteiro',
 'ew_validar_mt_movimento_material','ew_movimento_material_mt_inteiro',
 'ew_validar_mt_movimento_insumo','ew_movimento_insumo_mt_inteiro',
 'new.estorno_de_id is null','metros inteiros'
])assert.ok(mtMigration.includes(token),'Protecao MT no banco ausente: '+token);
assert.ok(source.includes('function ewUnidadeEmMetroInteiro(unidade)')&&
 source.includes("quantInteira=isBar||ewUnidadeEmMetroInteiro(unit)")&&
 source.includes("((isBar||ewUnidadeEmMetroInteiro(unit))&&!Number.isSafeInteger(qty))")&&
 source.includes("((tipo==='perfil'||ewUnidadeEmMetroInteiro(unit))&&!Number.isSafeInteger(qty))")&&
 source.includes("stockTransferPrepararQuantidade('stockTransferQty',item.v.tipo,saldo,unit)")&&
 source.includes("stockTransferPrepararQuantidade('stockObraTransferQty',item.v.tipo,disponivel,unidade)")&&
 source.includes("ewUnidadeEmMetroInteiro(stockQtySelected.unidade)?'1':'0.001'")&&
 source.includes('step="any" placeholder="Qtd."'),
 'Interface de liberacao, entrada fisica, ajustes e transferencias deve exigir MT inteiro');
assert.ok(insumosClient.includes("'PR','MT'].includes(row.unidade)")&&
 insumosClient.includes("'PR','MT'].includes(item.unidade)")&&
 receiveScript.includes("new Set(['PC','UN','PR','CJ','CX','MT'])"),
 'Recebimento/transferencia de insumos em MT devem exigir inteiros');
const helperStart=source.indexOf('function ewUnidadeEmMetroInteiro(unidade){');
const helperEnd=source.indexOf('function releaseUnidadeAcessorio(value){',helperStart);
const validarMT=new Function(source.slice(helperStart,helperEnd)+
 '\nreturn ewUnidadeEmMetroInteiro;')();
for(const code of ['MT','M','METRO','METROS'])assert.equal(validarMT(code),true);
for(const code of ['KG','M2','L','UN'])assert.equal(validarMT(code),false);
assert.equal(unidadeValidadores.unidadeContavel('MT'),true,'MT usa inteiros no formulário de notas');
assert.equal(unidadeValidadores.unidadeContavel('KG'),false,'KG continua aceitando frações');


// EWGEST v46.1 — no romaneio de transferencia motorista e placa sao selecionados,
// nunca digitados: os dois cadastros ja existem para os romaneios de obra.
const transferTransport=readFileSync(fileURLToPath(new URL(
 '../assets/romaneios-transferencia.js',import.meta.url)),'utf8');
const transferTransportCSS=readFileSync(fileURLToPath(new URL(
 '../assets/romaneios-transferencia.css',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(transferTransport),
 'Romaneios de transferencia: script JavaScript valido');
for(const [id,placeholder] of [
 ['romTransfMotorista','Selecione um motorista cadastrado'],
 ['romTransfPlaca','Selecione uma placa cadastrada']
]){
 assert.ok(source.includes('<select id="'+id+'" required>')&&source.includes(placeholder),
  'Motorista e placa devem ser seletores obrigatorios de cadastro: '+id);
 assert.ok(!source.includes('<input id="'+id+'"'),
  'O romaneio de transferencia nao deve solicitar digitacao livre: '+id);
}
assert.ok(transferTransport.includes("apiGet('romaneios_motoristas'")&&
 transferTransport.includes("apiGet('romaneios_veiculos'")&&
 transferTransport.includes("ativo:'eq.true'")&&
 transferTransport.includes("empresa_id:'eq.'+empresa()")&&
 transferTransport.includes("selecionarTransporte('romTransfMotorista',motoristas,'nome',motoristaAtual)")&&
 transferTransport.includes("selecionarTransporte('romTransfPlaca',veiculos,'placa',placaAtual)")&&
 transferTransport.includes("!motoristas.some(x=>x.nome===motorista)")&&
 transferTransport.includes("!veiculos.some(x=>x.placa===placa)")&&
 transferTransport.includes("if(editVersion!==version||editId!==id)return")&&
 transferTransport.includes("void carregarTransporteEdicao(id,version,d.motorista||'',d.placa||'')"),
 'Romaneios de transferencia precisam carregar cadastros ativos, preservar valores validos e bloquear texto livre');
assert.ok(source.includes('romaneios-transferencia.js?v=20261125a')&&
 source.includes('romaneios-transferencia.css?v=20261121c')&&
 transferTransportCSS.includes('.romTransfFields select'),
 'O deploy da versao 46.1 precisa atualizar o cache e o estilo do seletor');


// EWGEST v46.2 — emitir abre a previa/caixa de impressao e mantem reimpressao.
assert.ok(transferTransport.includes('Emitir e imprimir</button>')&&
 transferTransport.includes('Imprimir / reimprimir</button>')&&
 transferTransport.includes('function avisoDocumento(id,message)')&&
 transferTransport.includes('data-t-status=')&&
 transferTransport.includes('return true;')&&
 transferTransport.includes('janela.document.getElementById(\'imprimirRomaneio\')'),
 'Emissao e reimpressao devem ser visiveis e seus erros apresentados junto ao documento');
const beginEmit=transferTransport.indexOf('async function emitir(id){');
const endEmit=transferTransport.indexOf('function visualizar(id){',beginEmit);
assert.ok(beginEmit>0&&endEmit>beginEmit,'Funcoes de emissao/impressao devem existir');
const emitirSource=transferTransport.slice(beginEmit,endEmit);
assert.ok(emitirSource.indexOf("window.open('about:blank','_blank')")<
 emitirSource.indexOf("await rpc('ew_romaneio_transferencia_emitir'"),
 'A aba de impressao deve ser aberta no clique, antes da RPC, evitando bloqueio de popup');
assert.ok(emitirSource.indexOf("await rpc('ew_romaneio_transferencia_emitir'")<
 emitirSource.indexOf("d.status='EMITIDO'")&&
 emitirSource.indexOf("d.status='EMITIDO'")<emitirSource.indexOf('imprimir(id,aba)'),
 'A impressao so pode acontecer depois que o banco confirma a emissao');
async function simularEmissao(falhar){
 const chamadas=[];
 const doc={id:'d',numero:'RM009',status:'RASCUNHO',motorista:'Motorista QA',
  placa:'ABC1D23',origem:'AFOGADOS',destino:'IMBIRIBEIRA',data:'2026-11-21',
  itens:[{tipo:'TRANSFERENCIA',codigo:'GN096',descricao:'FOLHA COLADA',
   quantidade:1,unidade:'BARRA',comprimento_mm:6000,origem_obra_id:'obraQA'}]};
 const tab={closed:false,document:{body:{textContent:''},open(){chamadas.push('doc.open');},
  write(){chamadas.push('doc.write');},close(){chamadas.push('doc.close');},
  getElementById(){return {addEventListener(){}}}},
  focus(){},print(){chamadas.push('print');},close(){chamadas.push('tab.close');this.closed=true;}};
 const ctx={docs:[doc],empresa:()=> 'empresaQA',window:{
   confirm:()=>true,open:()=>{chamadas.push('open');return tab;},
   ewConstruirHTMLRomaneioTransferencia:()=>{
    chamadas.push('template');return '<!doctype html><html><body><p>Romaneio QA</p></body></html>';
   }},
   rpc:async()=>{chamadas.push('rpc');if(falhar)throw Error('Erro QA');},
   render:()=>chamadas.push('render'),
   carregar:async()=>{chamadas.push('refresh')},
   erro:()=>{},avisoDocumento:()=>{},estaEstornado:()=>false,
   editar:()=>{},obra:()=> 'ESSENCE CONSTRUÇÕES',esc:x=>String(x??''),num:x=>String(x),
   itemResumo:()=>'',el:()=>({textContent:''})};
 const harness=new Function('ctx',
  'let docs=ctx.docs,busy=false;const window=ctx.window,empresa=ctx.empresa,'+
  'rpc=ctx.rpc,render=ctx.render,carregar=ctx.carregar,erro=ctx.erro,'+
  'avisoDocumento=ctx.avisoDocumento,estaEstornado=ctx.estaEstornado,'+
  'editar=ctx.editar,obra=ctx.obra,esc=ctx.esc,num=ctx.num,itemResumo=ctx.itemResumo,el=ctx.el;\n'+
  emitirSource+'\nreturn {emitir,imprimir};')(ctx);
 await harness.emitir('d');
 return {chamadas,doc,tab};
}
const emissaoOK=await simularEmissao(false);
assert.equal(emissaoOK.doc.status,'EMITIDO');
assert.ok(emissaoOK.chamadas.indexOf('open')<emissaoOK.chamadas.indexOf('rpc'));
assert.ok(emissaoOK.chamadas.indexOf('rpc')<emissaoOK.chamadas.indexOf('doc.write'));
assert.ok(emissaoOK.chamadas.includes('print'));
const emissaoFalhou=await simularEmissao(true);
assert.equal(emissaoFalhou.doc.status,'RASCUNHO');
assert.ok(emissaoFalhou.tab.closed);
assert.ok(!emissaoFalhou.chamadas.includes('doc.write'));


// v46.3 — transferência usa o exato modelo visual do romaneio de esquadrias.
const printStart=source.indexOf('function areaRomaneioEmM2(linha){');
const printEnd=source.indexOf('function abrirRomaneioDocumento(',printStart);
assert.ok(printStart>0&&printEnd>printStart);
const factorySource=source.slice(printStart,printEnd);
for(const phrase of [
 'window.ewConstruirHTMLRomaneioTransferencia=','Comprovante de Transferência de Materiais',
 'alt="Artefal"','alt="GVG"','printPage two','Transportado por:',
 "transferencia?'Obra origem':'M²'","header.origem_galpao||'—'",
 "header.destino_galpao||'—'"
])assert.ok(factorySource.includes(phrase),'Layout de transferência faltando '+phrase);
const printWin={};
const factories=new Function('window','works','escapeHTML','dataRomaneioFormatada',
 'medidaRomaneioEmMetros','descricaoCurtaRomaneio','dispatchConfig',factorySource+
 '\nreturn [construirHTMLRomaneio,window.ewConstruirHTMLRomaneioTransferencia,areaRomaneioEmM2];')(
 printWin,[{id:'obraQA',nome:'Obra QA',cliente:'Cliente QA'}],
 x=>String(x??''),x=>String(x).split('-').reverse().join('/'),
 x=>String(x??''),x=>String(x??''),[{esquadria_id:'ea2qa',folhas_por_unidade:2}]);
const printHeader={numero:'RM009',obra_id:'obraQA',data_saida:'2026-11-21',
 motorista:'IRAN',placa:'ABC1D23',status:'EMITIDO'};
const printLines=[
 {sequencia:1,natureza:'material',codigo:'GN096',descricao:'FOLHA COLADA',
  medida:'6,00 m',quantidade:1,unidade:'BARRA',obra_origem:'ESSENCE CONSTRUÇÕES'},
 {sequencia:2,natureza:'material',codigo:'GUA0070PTO',descricao:'GUARNIÇÃO PINGADEIRA',
  medida:'',quantidade:1,unidade:'MT',obra_origem:'ESSENCE CONSTRUÇÕES'}
];
// v46.5 — RM011 com marco expedido deve mostrar 50% da área tanto na linha quanto no total.
const parcialBase={sequencia:1,natureza:'esquadria',esquadria_id:'ea2qa',codigo:'EA2',
 descricao:'JANELA CORRER 2F GOLD SLIM (MARCO)',medida:'1200.00 x 1150.00 mm',
 quantidade:1,unidade:'UNID.',area_m2:null,tipo_saida:'marco'};
const htmlMarco=factories[0]({...printHeader,numero:'RM011'},[parcialBase]);
assert.ok(htmlMarco.includes('<td class="right">0,69</td>')&&
 htmlMarco.includes('Total M²:</strong> 0,69'),
 'EA2 só marco: a reimpressão mostra 0,69 m² e não 0,00');
assert.equal(factories[2](parcialBase),0.69);
assert.equal(factories[2]({...parcialBase,tipo_saida:'folha',quantidade:1}),0.345,
 'Uma folha física de janela 2F equivale a 25% da área total');
assert.equal(factories[2]({...parcialBase,tipo_saida:'folha',quantidade:2}),0.69,
 'Duas folhas físicas somam 50% da área');
assert.equal(factories[2]({...parcialBase,tipo_saida:'completo'}),1.38,
 'Completa = 100% da área');
assert.equal(factories[2]({...parcialBase,tipo_saida:'completo',quantidade:2}),2.76,
 'Múltiplas esquadrias completas respeitam a quantidade');
assert.equal(factories[2]({...parcialBase,medida:'1.200,00 × 1.150,00 mm'}),0.69,
 'Medidas com formatação brasileira são aceitas');
assert.equal(factories[2]({...parcialBase,area_m2:1.4}),1.4,
 'Área histórica positiva já gravada não deve ser recalculada');
assert.equal(factories[2]({...parcialBase,tipo_saida:'folha',esquadria_id:'sem-config'}),null,
 'Sem número cadastrado de folhas não inventar área por folha física');
assert.equal(factories[2]({...parcialBase,natureza:'material'}),null,
 'Materiais não recebem M² de esquadrias');
const htmlFolhas=factories[0](printHeader,[{...parcialBase,tipo_saida:'folha',quantidade:2}]);
assert.ok(htmlFolhas.includes('<td class="right">0,69</td>')&&
 htmlFolhas.includes('Total M²:</strong> 0,69'),
 'Duas folhas de EA2: 0,69 m² no romaneio');
const padrão=factories[0](printHeader,printLines);
const transferenciaHTML=factories[1]({...printHeader,
 origem_galpao:'AFOGADOS',destino_galpao:'IMBIRIBEIRA'},printLines);
assert.ok(padrão.includes('Comprovante de Entrega de Materiais')&&
 padrão.includes('Total M²:')&&padrão.includes('<th>M²</th>')&&
 !padrão.includes('ORIGEM (GALPÃO):'),'Romaneio de esquadrias deve manter seu modelo');
for(const token of ['Comprovante de Transferência de Materiais','ORIGEM (GALPÃO):',
 'DESTINO (GALPÃO):','AFOGADOS','IMBIRIBEIRA','Obra origem',
 'ESSENCE CONSTRUÇÕES','alt="Artefal"','alt="GVG"',
 'Transportado por:','Via 1','Via 2']){
 assert.ok(transferenciaHTML.includes(token),'Romaneio de galpão faltando '+token);
}
assert.equal((transferenciaHTML.match(/<div class="printPage two">/g)||[]).length,1,
 'Duas vias de poucos itens devem ficar em uma folha A4');
assert.ok(!transferenciaHTML.includes('Total M²:')&&
 transferTransport.includes('window.ewConstruirHTMLRomaneioTransferencia({')&&
 transferTransport.includes("html.replace('<body>','<body>'+toolbar)")&&
 transferTransport.includes("imprimirBtn.addEventListener('click',()=>janela.print())"),
 'Impressão de transferência deve usar template comum, e não layout genérico');


// EWGEST v46.4: marco equivale a 50%, conjunto das folhas 50%, sem movimentar estoque.
const componentMigration=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261121_liberacao_por_partes_v464.sql',import.meta.url)),'utf8');
for(const token of [
 'tipo_componente text not null default',
 'ew_registrar_liberacao_componente',
 'ew_liberar_plano_corte_componente',
 'marcos_liberados','conjuntos_folhas_liberados',
 'v_marcos_liberados','v_folhas_liberadas',
 'ew_cancelar_liberacoes_obra',
 'CORRIGIR_ESCOPO_LIBERACAO',
 'TESTE-TREINAMENTO'
])assert.ok(componentMigration.includes(token),
 'Proteção de liberação/saída por componentes ausente: '+token);
assert.ok(!/insert into public\.ew_estoque_obras_movimentos/i.test(componentMigration)&&
 !/insert into public\.ew_insumos_movimentos/i.test(componentMigration),
 'Liberação parcial não pode movimentar estoque');
assert.ok(!source.includes('id="releaseComponent"')&&source.includes('id="releaseScopeNotice"')&&
 source.includes("p_materiais:[],p_fonte:'SEM_BAIXA'")&&
 source.includes('p_componente:componente')&&
 source.includes("shipping?list.filter(x=>Number(x.qtd_liberada)>0):list;")&&
 source.includes('groupRenderedItems(exibidos)')&&
 source.includes('Nenhuma esquadria liberada para fabricação nesta obra.'),
 'Saída somente exibe liberadas; nova liberação não baixa estoque');
const componentStart=source.indexOf('function releaseParts(item){');
const componentEnd=source.indexOf('function renderUnitCounters(',componentStart);
assert.ok(componentStart>0&&componentEnd>componentStart);
const componentCode=source.slice(componentStart,componentEnd);
const history=[{esquadria_id:'ea2',quantidade:1,tipo_componente:'marco'}];
const calculo=new Function('history',
 'const releaseHistory=history;'+
 'const area=(item,q)=>Number(item.largura_mm)*Number(item.altura_mm)*q/1000000;'+
 componentCode+'\nreturn {releaseParts,totals};')(history);
const esq={id:'ea2',quantidade:5,qtd_liberada:1,largura_mm:1200,altura_mm:1150,qtd_fabricada:0};
assert.ok(Math.abs(calculo.totals([esq]).released-0.69)<0.000001,
 'EA2 marco = 0,69m² (50% de 1,38m²)');
assert.equal(calculo.releaseParts(esq).saldoFolhas,5);
history.push({esquadria_id:'ea2',quantidade:1,tipo_componente:'folhas'});
assert.ok(Math.abs(calculo.totals([esq]).released-1.38)<0.000001,
 '1 marco + 1 conjunto de folhas = 1,38m²');
assert.equal(calculo.releaseParts(esq).saldoMarco,4);

// Caso de regressão real: 1 marco EA2 expedido; liberando as folhas depois, aparecem 2 físicas.
const parteFonte=source.slice(source.indexOf('function releaseParts(item){'),
 source.indexOf('function totals(',source.indexOf('function releaseParts(item){')));
const statsFonte=source.slice(source.indexOf('function shipmentStats(item){'),
 source.indexOf('function suggestedLeaves(item)',source.indexOf('function shipmentStats(item){')));
const folhasFonte=source.slice(source.indexOf('function suggestedLeaves(item)'),
 source.indexOf('function romaneioSaldoCompleto(item)',source.indexOf('function suggestedLeaves(item)')));
const saldoFonte=source.slice(source.indexOf('function romaneioSaldoPorTipo(item,tipo,folhas){'),
 source.indexOf('function mensagemSemSaldoRomaneio(',source.indexOf('function romaneioSaldoPorTipo(item,tipo,folhas){')));
const liberacoesEA2=[{esquadria_id:'ea2qa',quantidade:1,tipo_componente:'marco'}];
const saidasEA2=[{esquadria_id:'ea2qa',tipo:'marco',quantidade:1}];
const {romaneioSaldoPorTipo:saldoEA2}=new Function('releaseHistory','shipmentHistory','dispatchConfig',
 parteFonte+statsFonte+folhasFonte+saldoFonte+
 '\nreturn {romaneioSaldoPorTipo};')(liberacoesEA2,saidasEA2,
 [{esquadria_id:'ea2qa',folhas_por_unidade:2}]);
const itemEA2={id:'ea2qa',codigo:'EA2',descricao:'JANELA DE CORRER 2 FOLHAS',
 quantidade:5,qtd_liberada:1};
assert.equal(saldoEA2(itemEA2,'folha',2),0,
 'Após enviar apenas o marco, sem liberar folhas, impedir emissão das folhas');
liberacoesEA2.push({esquadria_id:'ea2qa',quantidade:1,tipo_componente:'folhas'});
assert.equal(saldoEA2(itemEA2,'folha',2),2,
 'Após liberar o conjunto das folhas, permitir enviar duas folhas físicas');
assert.equal(saldoEA2(itemEA2,'completo',2),0,
 'Não permitir completa quando o marco já saiu');
saidasEA2.push({esquadria_id:'ea2qa',tipo:'folha',quantidade:1});
assert.equal(saldoEA2(itemEA2,'folha',2),1,
 'Expedir uma folha física deixa uma folha física pendente');

// v46.5 — explicar a indisponibilidade de folhas quando só o marco foi liberado.
const semSaldoStart=source.indexOf('function mensagemSemSaldoRomaneio(tipo,candidatos){');
const semSaldoEnd=source.indexOf('function buscarEsquadriasRomaneio(row){',semSaldoStart);
assert.ok(semSaldoStart>=0&&semSaldoEnd>semSaldoStart,'Diagnóstico de saldo presente');
const avaliarSaldo=new Function('ehMaximArRomaneio','releaseParts',
 source.slice(semSaldoStart,semSaldoEnd)+'\nreturn mensagemSemSaldoRomaneio;')(
 x=>/MAXIM-AR/i.test(x.descricao||''),
 x=>({marcos:Number(x.marcosLiberados||0),folhas:Number(x.folhasLiberadas||0)})
);
const ea2SemFolhas=[{codigo:'EA2',qtd_liberada:1,marcosLiberados:1,folhasLiberadas:0}];
assert.ok(avaliarSaldo('folha',ea2SemFolhas).includes('folhas ainda não foram liberadas'),
 'EA2 com só marco liberado deve mostrar pendência de liberação das folhas');
assert.ok(avaliarSaldo('completo',ea2SemFolhas).includes('marco e folhas liberados'),
 'Expedição completa requer dois componentes');
assert.ok(avaliarSaldo('folha',[{...ea2SemFolhas,folhasLiberadas:1}]).includes('já foram expedidas'),
 'Distinguir folha sem liberação de folha já expedida');
assert.ok(avaliarSaldo('marco',[{...ea2SemFolhas,marcosLiberados:0}]).includes('marco ainda não foi liberado'),
 'Marco ainda não liberado tem aviso claro');
assert.ok(source.includes("row.dataset.mensagemSemSaldo=disponiveis.length?'':")&&source.includes("Nenhuma esquadria com saldo de expedição.")&&
 source.includes("summary.textContent=el.dataset.mensagemSemSaldo||")&&
 source.includes("if(elements.some(x=>x.obra_id===selectedWork.id))"),
 'Romaneio exibe linha de seleção e explica pendência mesmo quando não há saldo');
const areaSql=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261122_area_componentes_romaneio_v465.sql',import.meta.url)),'utf8');
assert.ok(areaSql.includes("CREATE OR REPLACE FUNCTION public.emitir_romaneio_com_saidas")&&
 areaSql.includes("SECURITY DEFINER")&&
 areaSql.includes("SET search_path TO ''")&&
 areaSql.includes('PERFORM public.ew_exigir_sessao_atual();')&&
 areaSql.includes("when 'marco' then")&&
 areaSql.includes('v_item.largura_mm*v_item.altura_mm*v_qty/2000000.0')&&
 areaSql.includes("when 'folha' then")&&
 areaSql.includes('v_item.largura_mm*v_item.altura_mm*v_qty/(2000000.0*v_per)')&&
 areaSql.includes("when 'completo' then")&&
 areaSql.includes('v_item.largura_mm*v_item.altura_mm*v_qty/1000000.0'),
 'A proposta SQL deve preservar as guardas e persistir as áreas equivalentes por componente');

// Liberação completa obrigatória; expedição continua por componente.
assert.ok(source.includes("const fabrica=node('releaseFactory').value,componente='completo';")&&
 source.includes('if(pending<=0)')&&
 source.includes('A liberação deve ser da esquadria completa.')&&
 source.includes("const escopo='esquadria completa (100%)';")&&
 !source.includes('id="releaseComponent"')&&source.includes('p_componente:componente'),
 'A liberação deve ser completa; expedição por componentes permanece separada');
assert.ok(source.includes('Folhas físicas (pode enviar uma de cada vez)')&&
 source.includes("const chave=id+'|'+tipo;")&&
 source.includes('if(usados.has(chave))')&&
 !source.includes("if(usados.has(id))throw new Error('A esquadria"),
 'No mesmo romaneio, marco e folha são tipos distintos; repetição da mesma parte é bloqueada');
const migration466=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261122_romaneio_marco_folha_mesmo_doc_v466.sql',import.meta.url)),'utf8');
assert.ok(migration466.includes("CREATE OR REPLACE FUNCTION public.emitir_romaneio_com_saidas")&&
 migration466.includes('PERFORM public.ew_exigir_sessao_atual()')&&
 migration466.includes("SECURITY DEFINER")&&
 migration466.includes("SET search_path TO ''")&&
 migration466.includes('pg_catalog.pg_advisory_xact_lock')&&
 migration466.includes('AND esquadria_id=v_id AND tipo_saida=v_tipo_saida')&&
 migration466.includes("when 'marco' then")&&migration466.includes("when 'folha' then")&&
 migration466.includes('v_item.largura_mm*v_item.altura_mm*v_qty/(2000000.0*v_per)')&&
 !migration466.includes("WHERE romaneio_id=v_rom.id AND esquadria_id=v_id) THEN"),
 'RPC proposta v46.6 deve permitir duas linhas do mesmo código com componentes distintos e preservar guardas');
const codigoPartes466=source.slice(source.indexOf('function releaseParts(item){'),
 source.indexOf('function totals(',source.indexOf('function releaseParts(item){')));
const codigoStats466=source.slice(source.indexOf('function shipmentStats(item){'),
 source.indexOf('function suggestedLeaves(item)',source.indexOf('function shipmentStats(item){')));
const codigoFolhas466=source.slice(source.indexOf('function suggestedLeaves(item) {'),
 source.indexOf('function romaneioSaldoCompleto(item)',source.indexOf('function suggestedLeaves(item) {')));
const codigoSaldo466=source.slice(source.indexOf('function romaneioSaldoPorTipo(item,tipo,folhas){'),
 source.indexOf('function mensagemSemSaldoRomaneio(',source.indexOf('function romaneioSaldoPorTipo(item,tipo,folhas){')));
const liberacoes466=[{esquadria_id:'ea2v466',tipo_componente:'completo',quantidade:1}];
const expedicoes466=[];
const configuracao466=[{esquadria_id:'ea2v466',folhas_por_unidade:2}];
const regras466=new Function('releaseHistory','shipmentHistory','dispatchConfig',
 codigoPartes466+codigoStats466+codigoFolhas466+codigoSaldo466+
 '\nreturn {releaseParts,shipmentStats,romaneioSaldoPorTipo};')(
 liberacoes466,expedicoes466,configuracao466);
const ea2466={id:'ea2v466',codigo:'EA2',descricao:'JANELA DE CORRER 2 FOLHAS',
 largura_mm:1200,altura_mm:1150,quantidade:1,qtd_liberada:1};
assert.equal(regras466.releaseParts(ea2466).marcos,1,'Liberar completo libera marco');
assert.equal(regras466.releaseParts(ea2466).folhas,1,'Liberar completo libera o conjunto das folhas');
assert.equal(regras466.romaneioSaldoPorTipo(ea2466,'marco',2),1,'Marco disponível');
assert.equal(regras466.romaneioSaldoPorTipo(ea2466,'folha',2),2,'Duas folhas físicas disponíveis');
expedicoes466.push({esquadria_id:'ea2v466',tipo:'marco',quantidade:1});
assert.equal(regras466.romaneioSaldoPorTipo(ea2466,'folha',2),2,
 'Após enviar 1 marco, continuam 2 folhas físicas disponíveis');
expedicoes466.push({esquadria_id:'ea2v466',tipo:'folha',quantidade:1});
assert.equal(regras466.romaneioSaldoPorTipo(ea2466,'folha',2),1,
 'Marco+folha deixa só uma folha de saldo (25%)');
const progStart466=source.indexOf('function progressoExpedicao(list){');
const progEnd466=source.indexOf('function renderList(){',progStart466);
const progresso466=new Function('shipmentHistory','dispatchConfig','dispatchReady','area',
 source.slice(progStart466,progEnd466)+'\nreturn progressoExpedicao;')(
 expedicoes466,configuracao466,true,
 (x,q)=>Number(x.largura_mm)*Number(x.altura_mm)*q/1000000);
assert.ok(Math.abs(progresso466([ea2466]).areaEnviada-1.035)<1e-9,
 'Marco+uma folha de 2 folhas = 75% de 1,38m² = 1,035m²');
expedicoes466.push({esquadria_id:'ea2v466',tipo:'folha',quantidade:1});
assert.equal(regras466.romaneioSaldoPorTipo(ea2466,'folha',2),0,'Não aceitar terceira folha');
assert.ok(Math.abs(progresso466([ea2466]).areaEnviada-1.38)<1e-9,
 'Marco+duas folhas = 100% de 1,38m²');
expedicoes466.splice(0);
expedicoes466.push({esquadria_id:'ea2v466',tipo:'folha',quantidade:1});
assert.equal(regras466.romaneioSaldoPorTipo(ea2466,'marco',2),1,
 'Ordem inversa: enviar folha antes não bloqueia o marco');
assert.ok(Math.abs(progresso466([ea2466]).areaEnviada-0.345)<1e-9,
 'Folha primeiro equivale a 25% da esquadria');
expedicoes466.push({esquadria_id:'ea2v466',tipo:'marco',quantidade:1});
assert.ok(Math.abs(progresso466([ea2466]).areaEnviada-1.035)<1e-9,
 'Folha primeiro e marco depois equivale a 75%');
const duasPartesNoRomaneio466=factories[0](printHeader,[
 {...parcialBase,sequencia:1,tipo_saida:'marco',area_m2:null},
 {...parcialBase,sequencia:2,tipo_saida:'folha',area_m2:null}
]);
assert.ok(duasPartesNoRomaneio466.includes('Total M²:</strong> 1,04')&&
 duasPartesNoRomaneio466.includes('<td class="right">0,69</td>')&&
 duasPartesNoRomaneio466.includes('<td class="right">0,35</td>'),
 'Mesmo romaneio com marco e uma folha física calcula 1,035m² e exibe 1,04m² arredondado');

// EWGEST v46.7 — faturamento parcial de esquadria, sem exigir saída completa.
const finStart467=source.indexOf('function finEquivalentesExpedidos(linhas,composicoes){');
const finEnd467=source.indexOf('function finRenderFaturaveis(){',finStart467);
assert.ok(finStart467>=0&&finEnd467>finStart467,'Funções de equivalência financeira disponíveis');
const finCalc467=new Function(source.slice(finStart467,finEnd467)+
 '\nreturn {finEquivalentesExpedidos,finEquivDisponivel};')();
const cfg467=[{esquadria_id:'ea2-fat',folhas_por_unidade:2},
 {esquadria_id:'ea3-fat',folhas_por_unidade:3}];
const expedicao467=[];
const doc467=(id,tipo,q)=>({esquadria_id:id,natureza:'esquadria',tipo_saida:tipo,quantidade:q});
function equivalentes467(id){
 return finCalc467.finEquivalentesExpedidos(expedicao467,cfg467).get(id)||0;
}
expedicao467.push(doc467('ea2-fat','marco',1));
assert.equal(equivalentes467('ea2-fat'),0.5,
 'Marco 50% já deve aparecer como faturável antes de enviar folhas');
const precoIntegral467=1000;
const jaFaturado467=0.5;
assert.equal(finCalc467.finEquivDisponivel(equivalentes467('ea2-fat')-jaFaturado467),0,
 'Faturar 50% do marco consome apenas o saldo expedido correspondente');
expedicao467.push(doc467('ea2-fat','folha',1));
assert.equal(equivalentes467('ea2-fat'),0.75,
 'Marco + 1 folha física de 2 = 75%');
assert.equal(finCalc467.finEquivDisponivel(equivalentes467('ea2-fat')-jaFaturado467),0.25,
 'Restante faturável após marco faturado + uma folha expedida = 25%');
assert.equal(Math.round(jaFaturado467*precoIntegral467*100)/100,500);
expedicao467.push(doc467('ea2-fat','folha',1));
assert.equal(equivalentes467('ea2-fat'),1,
 'Marco + 2 folhas físicas representa 100% da esquadria');
assert.equal(finCalc467.finEquivDisponivel(equivalentes467('ea2-fat')-jaFaturado467),0.5,
 'Se foi faturado só o marco, restam 50% faturáveis após folhas');
expedicao467.splice(0);
expedicao467.push(doc467('ea2-fat','folha',1));
assert.equal(equivalentes467('ea2-fat'),0.25,'Folha pode ser faturada antes do marco');
expedicao467.push(doc467('ea2-fat','marco',1));
assert.equal(equivalentes467('ea2-fat'),0.75,'Ordem inversa mantém 75%');
expedicao467.splice(0);
expedicao467.push(doc467('ea3-fat','folha',1));
assert.equal(finCalc467.finEquivDisponivel(equivalentes467('ea3-fat')),0.166666,
 '1 de 3 folhas: disponibiliza valor aproximado por baixo (1/6) sem exceder expedição');
expedicao467.push(doc467('ea3-fat','folha',2));
assert.equal(finCalc467.finEquivDisponivel(equivalentes467('ea3-fat')),0.5,
 '3 folhas expedidas somam 50%');
expedicao467.splice(0);
expedicao467.push(doc467('ea2-fat','completo',1));
assert.equal(equivalentes467('ea2-fat'),1,
 'Romaneio completo legado continua equivalendo a uma unidade inteira');
assert.throws(()=>finCalc467.finEquivalentesExpedidos(
 [doc467('sem-folhas','folha',1)],cfg467),/Composição das folhas/,
 'Não inventar quantidade de folhas sem configuração conhecida');
assert.ok(source.includes("filter(x=>x.status==='emitido'&&!x.cancelado_em)")&&
 source.includes("const shipped=finEquivalentesExpedidos(romLinhas,composicoes);")&& source.includes("step=\"0.000001\"")&&
 source.includes("const disponivel=finEquivDisponivel("),
 
 'Somente romaneios emitidos e ativos compõem o faturamento parcial');
const financeiroSQL467=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261122_faturamento_parcial_esquadrias_v467.sql',import.meta.url)),'utf8');
for(const trecho467 of [
 'ALTER COLUMN quantidade TYPE numeric(14,6)',
 'CREATE OR REPLACE FUNCTION public.ew_registrar_faturamento_financeiro',
 "p_categoria='instalacao' AND p_instalacao_confirmada",
 "ue.perfil='administrador'",
 'pg_catalog.pg_advisory_xact_lock',
 'v_quantidade<>round(v_quantidade,6)',
 "WHEN 'marco' THEN ri.quantidade::numeric/2",
 "WHEN 'folha' THEN ri.quantidade::numeric/(2*cfg.folhas_por_unidade)",
 "rr.status='emitido' AND rr.cancelado_em IS NULL",
 'v_total_invoiced+v_quantidade>v_shipped',
 "v_quantidade,v_unit,round(v_quantidade*v_unit,2)"
])assert.ok(financeiroSQL467.includes(trecho467),'Proteção financeira ausente no SQL: '+trecho467);
assert.ok(!financeiroSQL467.includes('v_quantidade::integer,v_unit'),
 'Persistência de fração não pode truncar para unidade inteira');


// EWGEST v46.8 — data local automática e preço integral formatado em BRL.
const fnPrecoStart=source.indexOf('function finPrecoValor(texto){');
const fnPrecoEnd=source.indexOf('function finRenderFaturaveis(){',fnPrecoStart);
assert.ok(fnPrecoStart>=0&&fnPrecoEnd>fnPrecoStart,'Conversão BRL deve estar no módulo financeiro');
const {finPrecoValor:precoValor468,finPrecoFormatar:precoFormatar468,
 finPrecoEdicao:precoEdicao468}=new Function(source.slice(fnPrecoStart,fnPrecoEnd)+
 '\nreturn {finPrecoValor,finPrecoFormatar,finPrecoEdicao};')();
for(const [texto,numero] of [
 ['1500',1500],['1500,00',1500],['R$ 1.500,00',1500],
 ['1.500,25',1500.25],['1500,25',1500.25],['1500.25',1500.25],
 ['1500,1234',1500.1234],['0,0001',0.0001],['1.500',1500]
])assert.ok(Math.abs(precoValor468(texto)-numero)<1e-8,'Preço incorreto: '+texto);
for(const ruim of ['-10','1.000,12345','1.23.45','R$abc','1500x'])assert.ok(
 Number.isNaN(precoValor468(ruim)),'Não aceitar preço inválido: '+ruim);
assert.match(precoFormatar468(1500),/R\$\s*1\.500,00/,
 'Preço de R$ 1.500,00 deve usar separador de milhares e decimal brasileiro');
assert.match(precoFormatar468(1500.25),/1\.500,25/,
 'Centavos não podem ser perdidos');
assert.match(precoFormatar468(1500.1234),/1\.500,1234/,
 'Precisão de quatro casas permitida pela RPC não pode ser perdida pela máscara');
assert.equal(precoEdicao468(1500.25),'1500,25',
 'Ao focar, o preço deve retornar a formato fácil de editar');
assert.equal(precoValor468(precoFormatar468(1500)),1500,
 'Preço brasileiro deve voltar como número 1500 para a RPC');
assert.equal(Math.round(.75*precoValor468('R$ 1.500,00')*100)/100,1125,
 'EA2 75% × preço integral R$ 1.500,00 = R$ 1.125,00');
assert.ok(source.includes("const qtd=Number(row.querySelector('.finQty').value),preco=finPrecoValor(row.querySelector('.finPrice').value)")&&
 source.includes("const valor=finPrecoValor(row.querySelector('.finPrice').value)")&&
 source.includes("valor_unitario:preco")&&
 source.includes('type="text" inputmode="decimal" autocomplete="off" placeholder="R$ 0,00"'),
 'Valor formatado não deve ser transmitido à RPC: apenas o número validado');
assert.ok(source.includes(".finTable .finPrice{width:140px;min-width:130px;box-sizing:border-box}"),
 'Campo de preço deve exibir R$ 1.500,00 inteiro em vez de truncar');
assert.ok(source.includes("node('finBillingForm').reset();node('finBillingDate').value=todayLocal();")&&
 source.includes('id="finBillingDate" type="date" required')&&
 !source.includes('id="finBillingDate" type="date" readonly')&&
 !source.includes('id="finBillingDate" type="date" disabled'),
 'Data deve iniciar com hoje após reset e continuar editável');
const inicioHoje468=source.indexOf('function todayLocal(){'),fimHoje468=source.indexOf('let releaseOperationId=',inicioHoje468);
assert.ok(inicioHoje468>=0&&fimHoje468>inicioHoje468,'Data local deve ser calculada no navegador');
const calendario468=new Function('Date',source.slice(inicioHoje468,fimHoje468)+'\nreturn todayLocal();')(
 class DataFalsa{getFullYear(){return 2026;}getMonth(){return 10;}getDate(){return 22;}});
assert.equal(calendario468,'2026-11-22','Data local independente de UTC e meia-noite');


// EWGEST v46.9 — nova etapa de categorias e m², com backend fechado.
const precificacaoUI=readFileSync(fileURLToPath(new URL('../assets/precificacao-importacao.js',import.meta.url)),'utf8');
const precificacaoOrc=readFileSync(fileURLToPath(new URL('../assets/orcamento-niveis.js',import.meta.url)),'utf8');
const precificacaoSQL=readFileSync(fileURLToPath(new URL('../database/proposals/20261122_precificacao_importacao_rpc_v469.sql',import.meta.url)),'utf8');
const precificacaoMapeamento=readFileSync(fileURLToPath(new URL('../database/proposals/20261122_precificacao_importador_mapeamento_v469.sql',import.meta.url)),'utf8');
const precificacaoSchema=readFileSync(fileURLToPath(new URL('../database/proposals/20261122_precificacao_categorias_historico_fase1.sql',import.meta.url)),'utf8');
new Function(precificacaoUI);
new Function(precificacaoOrc);
assert.ok(source.includes('precificacao-core.js?v=20261126d')&&
 source.includes('precificacao-importacao.js?v=20261126d')&&
 source.includes('precificacao-importacao.css?v=20261126d')&&
 source.includes("ew_importar_obra_cem_precificacao")&&
 source.includes("r.precificacaoDraft&&answer.precificacao_gravada!==true")&&
 source.includes("Conclua a etapa de categorias e preços antes da importação."),
 'A importação nova não pode contornar a etapa nem aceitar resposta sem precificação gravada');
assert.ok(precificacaoOrc.includes("await window.ewPrecificacaoImportacao.abrir(r,values")&&
 precificacaoOrc.includes("node('cemQuoteOverlay').classList.remove('hidden')")&&
 precificacaoOrc.includes("const fabricacao=values.niveis.filter")&&
 precificacaoOrc.includes("r.precificacaoDraft=draft")&&
 precificacaoOrc.includes("await cemImportarSelecionados()"),
 'O orçamento precisa abrir a precificação antes da importação');
assert.ok(precificacaoUI.includes('data-item=')&&
 precificacaoUI.includes('data-price=')&&
 precificacaoUI.includes('ewPricePercent')&&
 precificacaoUI.includes('precoAjustadoFabricacaoM2')&&
 precificacaoUI.includes('precoAjustadoInstalacaoM2')&&
 precificacaoUI.includes("const resultado=motor.precificar(")&&
 precificacaoUI.includes("apiGet('ew_precificacao_categorias'")&&
 precificacaoUI.includes("apiGet('ew_precificacao_tipologias_padrao'")&&
 precificacaoUI.includes("apiGet('tipologias'")&&
 precificacaoUI.includes('marque os níveis de fabricação e instalação como faturáveis')&&
 precificacaoUI.includes('data-default=')&&
 precificacaoUI.includes('definir_padrao_tipologia:Boolean(')&&
 precificacaoUI.includes('ewPriceGroupRow')&&
 precificacaoUI.includes('s.categorias.map(cat=>'),
 'Tela deve permitir categorias e preços por m² e recalcular fabricação/instalação');
assert.ok(precificacaoSQL.includes('SECURITY DEFINER')&&
 precificacaoSQL.includes('PERFORM public.ew_exigir_sessao_atual()')&&
 precificacaoSQL.includes("ue.perfil='administrador'")&&
 precificacaoSQL.includes("p_precificacao jsonb")&&
 precificacaoSQL.includes("row_number() OVER(ORDER BY fr DESC,idx ASC)")&&
 precificacaoSQL.includes("row_number() OVER(ORDER BY ir DESC,idx ASC)")&&
 precificacaoSQL.includes("v_result:=public.ew_importar_obra_cem_financeiro(")&&
 precificacaoSQL.includes("RETURN v_result||jsonb_build_object('precificacao_gravada',true")&&
 precificacaoSQL.includes('REVOKE ALL ON FUNCTION public.ew_importar_obra_cem_precificacao')&&
 precificacaoSQL.includes("Níveis de fabricação e instalação precisam ser faturáveis.")&&
 precificacaoSQL.includes('ew_precificacao_tipologias_padrao(')&&
 precificacaoSQL.includes('ON CONFLICT (empresa_id,tipologia_id) DO UPDATE')&&
 precificacaoSQL.includes('não pode ter duas categorias padrão diferentes')&&
 precificacaoSQL.includes('v_request_hash:=md5(jsonb_build_object(')&&
 precificacaoSQL.includes('v_hash_existente IS DISTINCT FROM v_request_hash')&&
 precificacaoSQL.includes('pg_catalog.pg_advisory_xact_lock')&&
 precificacaoSQL.includes("'ja_importado',true")&&
 precificacaoSchema.includes('UNIQUE(empresa_id,operacao_id)')&&
 precificacaoSchema.includes('operacao_hash text NOT NULL'),
 'Proposta de RPC deve validar saldos e autorizar a gravação em uma só transação');
assert.ok(precificacaoMapeamento.includes("RETURNING id INTO v_esquadria_id")&&
 precificacaoMapeamento.includes("'esquadrias_ids',v_esquadrias_ids")&&
 precificacaoSchema.includes("ew_precificacao_revisoes_itens")&&
 precificacaoSchema.includes("ew_precificacao_no_update_delete")&&
 precificacaoSchema.includes("ENABLE ROW LEVEL SECURITY"),
 'A proposta de banco precisa mapear os IDs exatos e preservar históricos com RLS');

console.log('OK: '+cases.length+' classificações; cadastros, estoque, histórico e sessão única.');

const navHelper=source.slice(source.indexOf('function setNavPermission('),source.indexOf('function setView('));
const navClasses=new Set(['hidden','active']);
const navAttrs=new Map([['aria-current','page']]);
const navButton={disabled:false,classList:{remove:name=>navClasses.delete(name)},setAttribute:(k,v)=>navAttrs.set(k,v),removeAttribute:k=>navAttrs.delete(k)};
const applyNavPermission=new Function('node',navHelper+'\nreturn setNavPermission;')(()=>navButton);
applyNavPermission('navAccessLevels',false);
assert.equal(navButton.disabled,true);
assert.equal(navAttrs.get('aria-disabled'),'true');
assert.ok(!navClasses.has('hidden')&&!navClasses.has('active')&&!navAttrs.has('aria-current'));
applyNavPermission('navAccessLevels',true);
assert.equal(navButton.disabled,false);
assert.equal(navAttrs.get('aria-disabled'),'false');
assert.equal(navButton.title,'');
assert.ok(source.includes('.workspaceLink:disabled{opacity:.48;cursor:not-allowed'));
assert.ok(source.includes("setNavPermission('navAccessLevels',currentAccessLevel===1&&temPermissao('niveis.gerenciar'))"));
assert.ok(source.includes("node('navEnviarNotas').classList.add('hidden')"));
console.log('OK: módulos sem acesso permanecem visíveis e desabilitados, proteção do ADM preservada.');

assert.ok(source.includes('id="stockHideZero"')&&source.includes("node('stockHideZero').addEventListener('change',renderEstoque)"));
const stockZeroFilter=source.match(/const linhasVisiveis=([^;]+);/)[1];
const stockZeroRows=[{quantidade:0},{quantidade:2},{quantidade:-1},{quantidade:.001}];
const filterStockZero=new Function('node','linhas','return '+stockZeroFilter);
assert.equal(filterStockZero(()=>({checked:false}),stockZeroRows).length,4);
assert.deepEqual(filterStockZero(()=>({checked:true}),stockZeroRows).map(x=>x.quantidade),[2,-1,.001]);
assert.ok(insumosClient.includes("byId('stockHideZero').checked"));
const companyStockUI=readFileSync(fileURLToPath(new URL('../assets/compras-estoque.js',import.meta.url)),'utf8');
assert.ok(companyStockUI.includes("!$('stockHideZero').checked||Math.abs(x.quantidade)>1e-9"));
console.log('OK: filtro de saldo zero preserva saldos positivos e negativos.');

assert.ok(source.includes('#cadastroLocaisLista .btn:disabled')&&source.includes('opacity:.48;cursor:not-allowed;transform:none'));
const cadastroLocaisScript=readFileSync(fileURLToPath(new URL('../assets/cadastro-locais-estoque.js',import.meta.url)),'utf8');
assert.ok(cadastroLocaisScript.includes('b.disabled=!!r.impedimento')&&cadastroLocaisScript.includes('if(!allowed()||r.impedimento)return;'));

const undoReleaseScript=readFileSync(fileURLToPath(new URL('../assets/estorno-liberacao.js',import.meta.url)),'utf8');
assert.doesNotThrow(()=>new Function(undoReleaseScript));
assert.ok(undoReleaseScript.includes('ew_listar_estornos_liberacao')&&undoReleaseScript.includes('ew_estornar_liberacao_individual')&&undoReleaseScript.includes('btn.disabled=!!r.impedimento'));
assert.ok(source.includes('id="cadastroJumpObras"')&&source.includes('id="releaseUndoAll"')&&!source.includes('id="navManageWorks"'));

assert.ok(source.includes('id="worksManualForm"')&&source.includes('cadastro_manual===true')&&source.includes('id="worksManualName"'));

const areaSource4624=source.slice(source.indexOf('function finAreaDisponivel('),source.indexOf('function finRenderFaturaveis(){'));
const areaCalc4624=new Function(areaSource4624+'\nreturn {finAreaDisponivel,finPrecoM2Sugerido};')();
assert.equal(areaCalc4624.finAreaDisponivel(.5,1.38),.69);
assert.equal(areaCalc4624.finPrecoM2Sugerido({fabricacao_centavos:27600},'fabricacao',1,1.38,.69,0,0),200);
assert.ok(source.includes('area_m2:qtd,preco_m2:preco')&&source.includes('Área a faturar (m²)')&&source.includes('Preço (R$/m²)'));
assert.ok(source.includes('ew_estornar_nfe_com_recebimentos')&&source.includes('Todas as '));

// v46.28: sequência de romaneios específica por obra.
const romNum4627=readFileSync(fileURLToPath(new URL('../database/proposals/20261125_numeracao_romaneios_por_obra_v4627.sql',import.meta.url)),'utf8');
for(const x of ['pg_try_advisory_xact_lock','romaneios_obra_numero_key',"WHERE status<>'AGRUPADO'",'NUMERO_REUTILIZADO','itens_originais','romaneios.juntar','romaneios.adiantar_numeracao','romaneios.historico_numeracao'])assert.ok(romNum4627.includes(x),x);
assert.ok(source.includes('p_empresa_id:empresaId,p_obra_id:obraId')&&source.includes('historico_romaneios'));
assert.ok(transferDocsJS.includes('x.obra_id!==sel[0].obra_id')&&transferDocsJS.includes('result.proximo_codigo'));
console.log('OK v46.28: numeração por obra, flags e histórico de junções.');

// v46.29.16 — interface acompanha as autorizações e conserva o histórico legado.
assert.ok(source.includes("componente='completo';") && source.includes('p_componente:componente') && !source.includes('id="releaseComponent"') && !source.includes('Liberação parcial: somente o marco'));
assert.ok(deliveryClient.includes("temPermissao('estoque.baixar')") && !deliveryClient.includes("temPermissao('estoque.receber')"));
assert.ok(source.includes("function stockModoPermitido(modo)") && source.includes("Somente consulta: seu nível não permite estornar estoque."));
const stockModeSource=source.slice(source.indexOf('function stockModoPermitido(modo)'),source.indexOf('function stockSelecionarModo(modo)'));
const stockModeTest=flags=>new Function('temPermissao',stockModeSource+'return stockModoPermitido;')(f=>flags.includes(f));
assert.equal(stockModeTest(['estoque.consultar','estoque.receber'])('producao'),false);
assert.equal(stockModeTest(['estoque.consultar','estoque.baixar'])('producao'),true);
assert.equal(stockModeTest(['estoque.consultar'])('transferencias'),false);
assert.equal(stockModeTest(['estoque.consultar'])('historico'),true);
assert.equal(stockModeTest([])('consulta'),false);

// v46.29.16 — o módulo de insumos deve conservar o modo de navegação e ignorar respostas antigas.
assert.ok(insumosClient.includes('await abrirEstoqueOriginal(...args)'));
assert.ok(insumosClient.includes('seq===saldosEpoch&&currentCompany?.id===empresa&&byId(\'stockWork\').value===obra'));
assert.ok(insumosClient.includes("obra.startsWith('empresa:')"));
{
 const begin=insumosClient.indexOf(' const abrirEstoqueOriginal=abrirEstoque;');
 const end=insumosClient.indexOf(" byId('stockWork').addEventListener",begin);
 const calls=[];
 const wrap=new Function('calls',"let abrirEstoque=async (...args)=>calls.push(args);const byId=()=>({classList:{contains:()=>false}});const carregarSaldos=async()=>calls.push('saldos');"+insumosClient.slice(begin,end)+'return abrirEstoque;')(calls);
 await wrap('producao');await wrap('transferencias');
 assert.deepEqual(calls,[['producao'],'saldos',['transferencias'],'saldos']);
}

// v46.29.16 — autorização por flag nos cadastros e insumos.
assert.ok(!insumosClient.includes('isFullAdminUser()')&&!insumosClient.includes('canAdministrate()'));
assert.ok(insumosClient.includes("temPermissao('cadastros.editar')")&&insumosClient.includes("temPermissao('estoque.estornar')"));
assert.ok(receiveScript.includes("!hasStock&&!temPermissao('financeiro.despesas')"));
assert.ok(source.includes("insumosPage:'cadastros.consultar'")&&source.includes("unidadesPage:'cadastros.consultar'"));

// Cadastros técnicos: consulta independente da edição e do estoque.
assert.ok(source.includes("async function abrirMateriais(){\n  if(!temPermissao('cadastros.consultar'))return;"));
assert.ok(source.includes("function abrirEdicaoMaterial(id=null){\n  if(!temPermissao('cadastros.editar'))return;"));
assert.ok(source.includes("function adminCanManageManufacturers() {\n  return temPermissao('cadastros.consultar');"));
assert.ok(source.includes("if(!editingTypology||!temPermissao('cadastros.editar'))return;"));

// v46.29.16 — guarda da empresa e separação do planejamento e saldo físico.
assert.ok(source.includes('r.empresaId=empresaId;'));
assert.ok(source.includes("currentCompany?.id!==r.empresaId||!temPermissao('obras.importar')"));
assert.ok(source.includes('Somente obras sem histórico operacional podem atualizar materiais previstos.'));
assert.ok(!source.includes("'/rest/v1/rpc/ew_importar_saldo_obra_cem'"));

// v46.29.16 — faturamento precificado fecha os centavos aprovados, inclusive em parcelas.
{
 const inicio=source.indexOf('function finValorPrecificadoCentavos('),fim=source.indexOf('function finRenderFaturaveis(){',inicio);
 const calc=new Function(source.slice(inicio,fim)+'return finValorPrecificadoCentavos;')();
 const linha={area_m2:3,instalacao_centavos:7001,fabricacao_centavos:3000};
 assert.equal(calc(linha,'instalacao',1,0,0),2334);
 assert.equal(calc(linha,'instalacao',1,1,2334),2333);
 assert.equal(calc(linha,'instalacao',1,2,4667),2334);
 assert.equal(calc(linha,'instalacao',3,0,0),7001);
 assert.equal(calc(linha,'fabricacao',1,0,0),1000);
 assert.equal(calc(linha,'instalacao',2,2,4667),null);
 assert.equal(calc({area_m2:0.123456,instalacao_centavos:10001},'instalacao',0.123456,0,0),10001);
 assert.equal(calc({area_m2:1,instalacao_centavos:1},'instalacao',0.1,0,0),0);
 assert.ok(!source.includes("(r.precificacao?' readonly':'')")&&source.includes('finPrecoCompensado'));
 assert.ok(source.includes("finMoney(Number(data.valor_total??value))"));
}

// Transferências sem apropriação: a categoria não deve apresentar saldo definitivo.
assert.ok(source.includes("transferenciasPendentes.set(d.categoria,Number(d.transferencias_custo_pendentes||0))"));
assert.ok(source.includes("custoPendente?'Custo de transferência pendente':pendente?'Em conferência':finMoney(resto)"));
assert.ok(source.includes("Gastos realizados (notas)"));
assert.ok(source.includes("ajuste_transferencias_centavos??0"));
assert.ok(source.includes("total-real-ajuste-comprometidoCategoria"));
assert.ok(source.includes("Ajuste líquido de transferências"));

import './test-obras-modos.mjs';

import './test-reconhecimento-cem.mjs';

// v46.29.42 — compactação restrita à lista de liberação, sem fontes menores.
assert.ok(source.includes("node('items').classList.toggle('releaseCompact',detailMode==='release')"));
const compactCss=source.slice(source.indexOf('/* Lista de liberação compacta:'),source.indexOf('.catalogFilters{',source.indexOf('/* Lista de liberação compacta:')));
assert.ok(compactCss.includes('#items.releaseCompact .typologyGroup{margin:9px 0;padding:2px 16px 4px}'));
assert.ok(compactCss.includes('#items.releaseCompact .itemdescription{margin:5px 0}'));
assert.ok(!/font-size|font-family|font-weight/.test(compactCss),'Não diminuir nem alterar as fontes da lista');

// Pendências são operações das obras, sem duplicar o painel do catálogo.
assert.ok(source.includes('data-works-modo="pending"'));
assert.ok(source.includes('id="workPendingPage"'));
assert.equal((source.match(/id="pendingReviewPanel"/g)||[]).length,1);
assert.ok(source.includes("gruposTipologiaPendente().filter(g=>!filtro||g.item.obra_id===filtro)"));
assert.ok(source.includes("if(modo==='pending')return canAdministrate()&&temPermissao('cadastros.editar')"));

// Seletor de configurações: rótulos curtos, existentes primeiro e escolha explícita quando ambígua.
assert.ok(source.includes("op.textContent='Usar existente: '+codigoVariacaoTecnica(t,m)"));
assert.ok(source.includes("novo.textContent='+ Criar nova: '+proximoSufixoVisual(t)"));
assert.ok(source.includes("const codigoConfiguracao=codigoVariacaoTecnica(t,modulo)"));
assert.ok(source.includes('Configurações cadastradas:'));

// Descrições integrais em listas com quebra de linha, sem dropdown nativo visível.
assert.ok(source.includes('id="recognitionModulationChoices" class="descriptiveChoices"'));
assert.ok(source.includes('id="recognitionTargetChoices" class="descriptiveChoices"'));
assert.ok(source.includes('id="differenceConfigChoices" class="descriptiveChoices"'));
assert.ok(source.includes('desc.textContent=row.description'));
assert.ok(source.includes('overflow-wrap:anywhere;white-space:normal'));

// Filtro por tipo nas pendências usa exatamente o mesmo classificador do catálogo.
const tipoOpcoes=id=>source.match(new RegExp('<select id="'+id+'">([\\s\\S]*?)</select>'))[1].match(/<option[^>]*>[^<]*<\/option>/g);
assert.deepEqual(tipoOpcoes('recognitionTargetType'),tipoOpcoes('typologyTypeFilter'));
const filtroInicio=source.indexOf('function filtrarTiposReconhecimento(');
const filtroFim=source.indexOf('function abrirConferenciaTipologia(',filtroInicio);
const filtro=new Function('correspondeTipoTipologia',source.slice(filtroInicio,filtroFim)+'return filtrarTiposReconhecimento;')(correspondeTipoTipologia);
const tipos=[{id:'g',descricao:'GRADIL 6 MÓDULO(S)'},{id:'j',descricao:'JANELA DE CORRER'},{id:'f',descricao:'FACHADA UNITIZADA - MÓDULO FIXO'}];
const opcoes=tipos.map(t=>({value:t.id,code:t.id}));
assert.deepEqual(filtro(opcoes,tipos,'GRADIL').map(r=>r.value),['g']);
assert.deepEqual(filtro(opcoes,tipos,'FACHADA UNITIZADA').map(r=>r.value),['f']);
assert.deepEqual(filtro(opcoes,tipos,'FIXO'),[]);
assert.deepEqual(filtro(opcoes,tipos,''),opcoes);
assert.ok(source.includes("node('recognitionTargetType').addEventListener('change',atualizarListaTipologiasReconhecimento)"));
assert.ok(source.includes("renderListaDescritiva('recognitionTarget',rows,node('recognitionTargetSearch').value)"));

 // Adaptação da descrição oficial: conserva todo o texto, muda apenas módulos expressos.
 const inicioAdapt=source.indexOf('function descricaoAdaptadaModulos(');
 const fimAdapt=source.indexOf('function estadoAdaptacaoReconhecimento(',inicioAdapt);
 const inicioComp=source.indexOf('function comparacaoEstritaDescricao(');
 const fimComp=source.indexOf('function sugerirPorDescricao(',inicioComp);
 const adaptar=new Function(source.slice(inicioComp,fimComp)+source.slice(inicioAdapt,fimAdapt)+'return {descricaoAdaptadaModulos,decidirAdaptacaoModulos};')();
 const oito='GUARDA CORPO - 8 MÓDULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
 const seis='GUARDA CORPO - 6 MÓDULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
 assert.equal(adaptar.descricaoAdaptadaModulos(oito,6),seis);
 assert.equal(adaptar.descricaoAdaptadaModulos('JANELA 2 FOLHAS',6),'');
 assert.equal(adaptar.descricaoAdaptadaModulos('2 MODULOS - 3 MÓDULOS',6),'');
 for(const q of ['',0,1.5,101])assert.equal(adaptar.descricaoAdaptadaModulos(oito,q),'');
 const mSeis={id:'m6',descricao:seis,quantidade_modulos:6};
 assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[mSeis]).existente.id,'m6');
 assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[{...mSeis,quantidade_modulos:8}]).ambiguo,true);
 assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[mSeis,{...mSeis,id:'outro'}]).ambiguo,true);
 assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[{descricao:seis.replace('COM VIDRO','SEM VIDRO'),quantidade_modulos:6}]).existente,null);
 assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[{descricao:'GRADIL 6 MÓDULO(S) - COM VIDRO - UNIVERSAL - HYDRO',quantidade_modulos:6}]).existente,null);
 assert.ok(source.includes('id="recognitionAdaptCount"'));
 assert.ok(!source.includes('id="recognitionAdaptApply"'));
 assert.ok(source.includes('id="recognitionManualFields" class="hidden"'));
 assert.ok(source.includes("node('recognitionAdaptCount').addEventListener('input',()=>{node('recognitionApproval').checked=false;node('recognitionDivergence').checked=false;renderizarCamposModulacao();})"));
 assert.ok(source.includes("node('recognitionApproval').checked=false;"));
 const opInicio=source.indexOf('function descricaoOperacionalTipologia('),opFim=source.indexOf('function labeledDescription(',opInicio);
 const operacional=new Function('modulationCatalog','typologyCatalog','descricaoAdaptadaModulos','comparacaoEstritaDescricao','quantidadeModulosExpressa',source.slice(opInicio,opFim)+'return descricaoOperacionalTipologia;')([{...mSeis,tipologia_principal_id:'t'}],[{id:'t',descricao:oito}],adaptar.descricaoAdaptadaModulos,s=>String(s||'').trim().toUpperCase(),()=>null);
 assert.equal(operacional({modulacao_id:'m6',descricao:'GRADIL 6 MÓDULO(S)'}),seis);
 assert.equal(operacional({descricao:'ORIGINAL CEM'}),'ORIGINAL CEM');

 // v46.29.42: escolher a família e a quantidade basta; o seletor interno
 // permanece apenas como contrato com a RPC, sem decisão intermediária.
 {
  const cut=(start,end)=>source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start)));
  const funcs=cut('function comparacaoEstritaDescricao(','function sugerirPorDescricao(')+
   cut('function descricaoAdaptadaModulos(','function diferencaNoReconhecimento(')+
   cut('function modulacoesDaTipologia(','function atualizarOpcoesModulacao(')+
   cut('function validarReconhecimento(){','function fecharConferenciaTipologia(){');
  const ns=new Map();
  const n=id=>{if(!ns.has(id)){const flags=new Set();ns.set(id,{value:'',checked:false,disabled:false,textContent:'',classList:{toggle(k,v){v?flags.add(k):flags.delete(k);},contains:k=>flags.has(k)}});}return ns.get(id);};
  const catalog=[{id:'t',codigo:'UNIV-R08-GRADN00',descricao:oito},{id:'j',codigo:'JANELA',descricao:'JANELA DE CORRER - 2 FOLHAS'}];
  const mods=[{...mSeis,descricao:'GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO',tipologia_principal_id:'t',numero_variacao:3},{id:'gradil',tipologia_principal_id:'t',numero_variacao:1,descricao:'GRADIL 7 MÓDULO(S) - COM VIDRO - UNIVERSAL - HYDRO',quantidade_modulos:7},{id:'j1',tipologia_principal_id:'j',numero_variacao:1,descricao:'JANELA DE CORRER - 2 FOLHAS'}];
  const origin={descricao:'GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO'};
  const run=new Function('node','typologyCatalog','modulationCatalog','recognitionPendingItem','codigoVariacaoTecnica','diferencaNoReconhecimento',funcs+'\nconst atualizarComparacaoReconhecimento=validarReconhecimento;return renderizarCamposModulacao;')(n,catalog,mods,origin,(t,m)=>t.codigo+'-'+m.numero_variacao,()=>true);
  const hidden=id=>n(id).classList.contains('hidden');
  n('recognitionTarget').value='t';n('recognitionAdaptCount').value='6';run();
  assert.equal(n('recognitionModulation').value,'m6');
  assert.equal(n('recognitionModDescription').value,seis);
  assert.ok(hidden('recognitionManualFields')&&hidden('recognitionNewModFields'));
  assert.ok(!hidden('recognitionAdaptFields'));
  assert.ok(n('recognitionAdaptPreview').textContent.includes('Reutilizar'));
  assert.ok(n('recognitionAdaptPreview').textContent.includes('padronizar'));
  assert.equal(mods[0].descricao,origin.descricao,'Prévia não modifica o catálogo');
  assert.equal(n('recognitionConfirm').disabled,true);
  n('recognitionApproval').checked=true;n('recognitionDivergence').checked=true;run();
  assert.equal(n('recognitionConfirm').disabled,false);
  n('recognitionAdaptCount').value='7';run();
  assert.equal(n('recognitionModulation').value,'','Mesma quantidade sem descrição compatível exige revisão');
  assert.equal(n('recognitionConfirm').disabled,true);
  n('recognitionAdaptCount').value='8';run();
  assert.equal(n('recognitionModulation').value,'__CRIAR__');
  assert.equal(n('recognitionModDescription').value,oito);
  assert.equal(n('recognitionModCount').value,'8');
  assert.ok(hidden('recognitionNewModFields'));
  assert.ok(n('recognitionAdaptPreview').textContent.includes('Criar nova variação'));
  for(const q of ['','0','6.5','101']){
   n('recognitionAdaptCount').value=q;run();
   assert.equal(n('recognitionModulation').value,'');
   assert.equal(n('recognitionModDescription').value,'');
   assert.equal(n('recognitionConfirm').disabled,true);
  }
  mods.push({...mods[0],id:'duplicada'});
  n('recognitionAdaptCount').value='6';run();
  assert.equal(n('recognitionConfirm').disabled,true);
  assert.ok(n('recognitionAdaptPreview').textContent.includes('duplicadas'));
  n('recognitionTarget').value='j';n('recognitionModulation').value='j1';run();
  assert.ok(!hidden('recognitionManualFields')&&hidden('recognitionAdaptFields'));
  assert.equal(n('recognitionModulation').value,'j1');
  n('recognitionTarget').value='';n('recognitionModulation').value='';run();
  assert.ok(hidden('recognitionManualFields')&&hidden('recognitionAdaptFields'));
  assert.equal(n('recognitionConfirm').disabled,true);
  assert.equal(origin.descricao,'GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO');
  assert.equal(catalog[0].descricao,oito);
 }
 console.log('OK v46.29.42: modulação automática, reuso, criação, exceções e bloqueios.');

 // Reaproveita a descrição exata do CEM somente na família selecionada.
 {
  const origem='GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
  const legado={id:'m03',descricao:origem,quantidade_modulos:6};
  const d=adaptar.decidirAdaptacaoModulos(oito,6,[legado],origem);
  assert.equal(d.existente.id,'m03');
  assert.equal(d.descricao,seis);
  assert.equal(d.padronizar,true);
  assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[legado,mSeis],origem).ambiguo,true);
  assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[{...legado,quantidade_modulos:7}],origem).ambiguo,true);
  assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[{...legado,quantidade_modulos:null}],origem).existente.id,'m03');
  assert.equal(adaptar.decidirAdaptacaoModulos(oito,8,[legado],origem).existente,null);
  assert.equal(adaptar.decidirAdaptacaoModulos(oito,8,[legado],origem).ambiguo,false);
  assert.equal(adaptar.decidirAdaptacaoModulos(oito,6,[{...legado,descricao:origem.replace('COM VIDRO','SEM VIDRO')}],origem).ambiguo,true);
  assert.equal(legado.descricao,origem);
 }

// v46.29.42: composição independente e atalho sem reiniciar a liberação.
{
 const cut=(a,b)=>source.slice(source.indexOf(a),source.indexOf(b,source.indexOf(a)));
 const ns=new Map();const n=id=>{if(!ns.has(id)){const flags=new Set();ns.set(id,{value:'',disabled:false,textContent:'',focus(){},classList:{toggle(k,v){v?flags.add(k):flags.delete(k)},add(k){flags.add(k)},remove(k){flags.delete(k)},contains(k){return flags.has(k)}}});}return ns.get(id);};
 const t={id:'t',codigo:'GOLS-JCR200',descricao:'JANELA DE CORRER',fabricante:'HYDRO'};
 n('typologyEditCode').value=t.codigo;n('typologyEditDescription').value=t.descricao;n('typologyEditManufacturer').value=t.fabricante;
 const update=new Function('node','editingTypology','editingPendingItem','typologyEditingStep',cut('function atualizarAcaoEdicaoTipologia(){','function showTypologyEditStep(step)')+'return atualizarAcaoEdicaoTipologia;')(n,t,null,1);
 update();assert.equal(n('typologyEditSave').disabled,true);assert.equal(n('typologyEditCancel').textContent,'Fechar');assert.ok(n('typologyEditCancel').classList.contains('primary'));
 n('typologyEditDescription').value='ALTERADA';update();assert.equal(n('typologyEditSave').disabled,false);assert.equal(n('typologyEditCancel').textContent,'Cancelar');
 n('typologyEditDescription').value=t.descricao;update();assert.equal(n('typologyEditSave').disabled,true);
 const resolve=new Function('typologyCatalog','expCompPodeConsultar','temPermissao',cut('function expCompTipologiaLiberacao(item){',"node('releaseExpCompOpen').addEventListener")+'return expCompTipologiaLiberacao;');
 assert.equal(resolve([t],()=>true,()=>true)({tipologia_id:'t'}),t);
 assert.equal(resolve([t],()=>false,()=>true)({tipologia_id:'t'}),null);
 assert.equal(resolve([t],()=>true,()=>false)({tipologia_id:'t'}),null);
 assert.equal(resolve([{...t,provisoria:true}],()=>true,()=>true)({tipologia_id:'t'}),null);
 assert.equal(resolve([t],()=>true,()=>true)({tipologia_id:'outra'}),null);
 const close=new Function('node','session','currentCompany','currentUser','selectedItem','releaseOperationId', 'let expCompSeq=0;let expCompCtx={company:"c",user:"u",fromRelease:true,releaseItemId:"e",releaseOp:"op"};'+cut('function expCompClose(){','async function expCompOpen(')+'return expCompClose;');
 n('releaseModal').classList.add('hidden');n('releaseQty').value='2';n('releaseDate').value='2026-11-26';n('releaseFactory').value='AFOGADOS';
 close(n,{}, {id:'c'},{id:'u'},{id:'e'},'op')();assert.ok(!n('releaseModal').classList.contains('hidden'));
 assert.equal(n('releaseQty').value,'2');assert.equal(n('releaseDate').value,'2026-11-26');assert.equal(n('releaseFactory').value,'AFOGADOS');
 n('releaseModal').classList.add('hidden');close(n,{}, {id:'c'},{id:'u'},{id:'e'},'nova')();assert.ok(n('releaseModal').classList.contains('hidden'));
 assert.ok(source.includes('id="typologyEditSuccess"'));assert.ok(source.includes("ctx.fromRelease?'releaseExpCompStatus':ctx.fromPicker?'expCompPickerMessage':'typologyEditSuccess'"));
 assert.ok(source.includes("void expCompOpen(source.id,true)"));
 assert.ok(source.includes("node('expCompClose').textContent=fromRelease?'Voltar à liberação':'Voltar'"));
}
console.log('OK v46.29.42: fechar edição sem mudanças, permissões e retorno à liberação.');

// v46.29.42 — sem seletor; escopo completo fixo e saldo respeitado.
{
 const start=source.indexOf("node('releaseForm').addEventListener('submit'");
 const end=source.indexOf("p_componente:componente",start);
 assert.ok(start>=0&&end>start);
 const submit=source.slice(start,end);
 assert.ok(submit.includes("componente='completo'"));
 assert.ok(submit.includes('if(pending<=0)'));
 assert.ok(submit.includes('qty>pending'));
 assert.ok(!source.includes("node('releaseComponent')"));
 assert.ok(source.includes('A divisão por componentes é feita somente na saída para a obra.'));
 const i=source.indexOf('function releaseComponentSaldo('),j=source.indexOf('function openRelease(',i);
 const fields=new Map([['releaseQty',{value:'',max:''}],['releaseComponentBalance',{textContent:''}]]);
 const parts={saldoCompleto:3,marcos:2,folhas:2};
 const update=new Function('node','selectedItem','releaseParts',source.slice(i,j)+'return releaseComponentAtualizar;')(id=>fields.get(id),{quantidade:5},()=>parts);
 update();assert.equal(fields.get('releaseQty').max,'3');assert.equal(fields.get('releaseQty').value,'1');
 fields.get('releaseQty').value='2';update();assert.equal(fields.get('releaseQty').value,'2');
 parts.saldoCompleto=0;update();assert.equal(fields.get('releaseQty').value,'');assert.equal(fields.get('releaseQty').max,'0');
}
console.log('OK v46.29.42: liberação completa sem seletor, saldo e aviso de expedição.');

// v46.29.42: apenas opções disponíveis da composição, sem duplicar marco/folha legados.
{
 const i=source.indexOf('function opcoesExpedicaoRomaneio('),j=source.indexOf('function atualizarQuantidadeRomaneio(',i);
 assert.ok(i>=0&&j>i);
 const options=new Function('shipmentStats','suggestedLeaves','romaneioSaldoPorTipo','ehMaximArRomaneio',source.slice(i,j)+'return opcoesExpedicaoRomaneio;')(()=>({per:2}),()=>2,(_,tipo)=>tipo==='folha'?2:1,()=>false);
 const e={id:'ea2'};const parts={completas_disponiveis:1,partes:[{id:'m',nome:'Marco',quantidade:1,peso:5000,saldo:1},{id:'f',nome:'Folhas',quantidade:2,peso:5000,saldo:2},{id:'z',nome:'Sem saldo',quantidade:1,peso:100,saldo:0}]};
 const opts=options(e,parts);assert.deepEqual(opts.map(x=>[x.value,x.saldo,x.eq]),[['completo',1,1],['parte:m',1,.5],['parte:f',2,.25]]);
 parts.completas_disponiveis=0;parts.partes[0].saldo=0;assert.deepEqual(options(e,parts).map(x=>x.value),['parte:f']);
 assert.deepEqual(options(e,null).map(x=>x.tipo),['completo','marco','folha']);
 assert.ok(source.includes('data-rom-choice required disabled')&&!source.includes('Componente cadastrado na tipologia</option>'));
}
console.log('OK v46.29.42: opções diretas por composição, saldo e equivalência por peça.');

// v46.29.42: valor por linha, inclusive desmarcada, usa centavos da emissão.
{
 const i=source.indexOf('function finValorLinhaCentavos('),j=source.indexOf('function finXMLValor(',i);
 const k=source.indexOf('function finValorPrecificadoCentavos('),l=source.indexOf('function finRenderFaturaveis(){',k);
 assert.ok(i>=0&&j>i&&k>=0&&l>k);
 const fakeRow=(id,qty,price,max,checked,auto='1')=>{
  const fields={'.finPrice':{value:price},'.finQty':{value:qty},'.finSelected':{checked},'.finInvoiceValue':{textContent:''}};
  return {dataset:{esq:id,max:String(max),areaUnit:'1.38',autoPrice:auto},querySelector:key=>fields[key],fields};
 };
 const rows=[fakeRow('ea2','0.345','280',.345,true),fakeRow('manual','0.5','100',1,false,'0'),fakeRow('zero','','',0,false,'0'),fakeRow('residual','0.1','33.3',.1,false)];
 const state={precificacao:{fabricacao_distribuida_centavos:49640},faturas:[{status:'emitido',categoria:'fabricacao',valor_total:6.67}],precoPorEsquadria:new Map([['ea2',{area_m2:1.38,fabricacao_centavos:38640}],['manual',{area_m2:1,fabricacao_centavos:10000}],['residual',{area_m2:.3,fabricacao_centavos:1000}]]),billedAreas:{fabricacao:new Map([['residual',.2]])},billedValues:{fabricacao:new Map([['residual',667]])}};
 const sum={textContent:''};
 const nodes={finBillingCategory:{value:'fabricacao'},finBillingRows:{querySelectorAll:()=>rows},finBillingSum:sum};
 const money=v=>v.toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
 const update=new Function('node','finState','finMoney','finPrecoValor',source.slice(k,l)+source.slice(i,j)+'return finAtualizarSomaFatura;')(id=>nodes[id],state,money,Number);
 update();assert.equal(rows[0].fields['.finInvoiceValue'].textContent,money(96.6));assert.equal(rows[1].fields['.finInvoiceValue'].textContent,money(50));assert.equal(rows[2].fields['.finInvoiceValue'].textContent,money(0));assert.equal(rows[3].fields['.finInvoiceValue'].textContent,money(3.33));assert.ok(sum.textContent.includes(money(96.6)));
 rows[1].fields['.finSelected'].checked=true;rows[1].fields['.finQty'].value='0.25';update();assert.equal(rows[1].fields['.finInvoiceValue'].textContent,money(25));assert.ok(sum.textContent.includes(money(121.6)));
 rows[0].fields['.finQty'].value='0.346';update();assert.equal(rows[0].fields['.finInvoiceValue'].textContent,'—');assert.ok(sum.textContent.includes(money(25)));assert.ok(sum.textContent.includes('1 item(ns)'));
 assert.ok(source.includes('Valor a faturar (R$)')&&source.includes('const cents=finValorFaturamentoLinha(plano,row,qtd,preco)'));
}
console.log('OK v46.29.42: valor por linha, seleção, saldo e centavos residuais.');

// v46.29.42: seleção direta de obras sem abandonar a subdivisão e estorno protegido.
{
 const i=source.indexOf('function preencherSeletorObras('),j=source.indexOf('function mostrarListaDeObras(){',i);
 assert.ok(i>=0&&j>i);
 const obras=[{id:'b',nome:'Zeta',codigo:'Z'},{id:'a',nome:'Alfa',codigo:'A',cliente:'Cliente & obra'}];
 const select={innerHTML:'',value:''};let aberta=null,lista=false;
 const esc=x=>String(x).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
 const ctx=new Function('escapeHTML','obrasComEsquadriasAtivas','renderDetail','mostrarListaDeObras','modoObrasPermitido',
  'let detailMode="shipmentUndo",detailBackTarget="";'+source.slice(i,j)+'return {preencherSeletorObras,escolherObraTecnica};')(esc,()=>obras,w=>aberta=w,()=>lista=true,()=>true);
 ctx.preencherSeletorObras(select,obras,'b');assert.equal(select.value,'b');assert.ok(select.innerHTML.indexOf('Alfa')<select.innerHTML.indexOf('Zeta'));assert.ok(select.innerHTML.includes('Cliente &amp; obra'));
 ctx.escolherObraTecnica('a');assert.equal(aberta.id,'a');ctx.escolherObraTecnica('');assert.ok(lista);
 ctx.preencherSeletorObras(select,obras,'removida');assert.equal(select.value,'');
 const m=source.indexOf('function modoObrasPermitido('),n=source.indexOf('function atualizarPermissoesObras(',m);
 const acesso=new Set(['obras.consultar','cadastros.consultar','obras.estornar']);
 const permitido=new Function('temPermissao','isAlmoxarife','canAdministrate',source.slice(m,n)+'return modoObrasPermitido;')(p=>acesso.has(p),()=>false,()=>true);
 assert.equal(permitido('workUndo'),true);acesso.delete('obras.estornar');assert.equal(permitido('workUndo'),false);
 for(const id of ['detailWorkSelect','worksPageSelect','manageWorksSelect','workPendingFilter'])assert.ok(source.includes('id="'+id+'"'));
 assert.ok(source.includes('data-works-modo="workUndo"')&&source.includes("if(modo==='workUndo'){abrirEstornoObra();return;}")&&source.includes("view==='manageWorks'&&manageWorksUndoMode"));
 assert.ok(source.includes("manageWorksUndoMode&&node('manageWorksSelect').value!==id")&&source.includes("workDeleteSubmitting=true;node('manageWorksSelect').disabled=true"));
 assert.ok(source.includes("ew_inspecionar_reversao_obra")&&source.includes("ew_arquivar_obra_reconciliada"));
}
console.log('OK v46.29.42: seletores, troca de obra e estorno com autorização preservada.');

// Painel gerencial: documentos ativos, centavos, período e ausência de falsos lucros.
{
 const code=readFileSync(new URL('../assets/painel-gerencial.js',import.meta.url),'utf8');
 const i=code.indexOf('function cents('),j=code.indexOf('async function pages(',i);
 const calc=new Function(code.slice(i,j)+'return calc;')();
 const f=[{obra_id:'a',categoria:'fabricacao',data_faturamento:'2026-11-12',valor_total:'89.80',status:'emitido'},{obra_id:'a',categoria:'instalacao',data_faturamento:'2026-11-13',valor_total:'10.20',status:'emitido'},{obra_id:'a',categoria:'fabricacao',data_faturamento:'2026-11-14',valor_total:999,status:'cancelado'},{obra_id:'b',categoria:'fabricacao',data_faturamento:'2026-10-31',valor_total:999,status:'emitido'}];
 const d=[{obra_id:'a',data_documento:'2026-11-12',valor:20,status:'aprovada'},{obra_id:'a',data_documento:'2026-11-12',valor:999,status:'cancelada'},{obra_id:'a',data_documento:'2026-11-12',valor:999,status:'pendente'}];
 const n=[{data_documento:'2026-11-12',valor_centavos:1500,status:'ATIVA'},{data_documento:'2026-11-12',valor_centavos:900,status:'CANCELADA'}];
 const r=calc(f,d,n,[{id:'a',nome:'Obra A'}],'2026-11-01','2026-11-30');
 assert.equal(r.fab,8980);assert.equal(r.inst,1020);assert.equal(r.desp,2000);assert.equal(r.empresa,1500);assert.equal(r.pendentes,1);assert.equal(r.docs,2);assert.equal(r.grupos.length,1);assert.equal(r.meses[0].faturado,10000);assert.equal(r.meses[0].comprasEmpresa,1500);
 assert.equal(calc([],[],[],[],'2026-11-01','2026-11-30').docs,0);
 assert.ok(code.includes("temPermissao('financeiro.consultar')&&temPermissao('relatorios.financeiros')&&temPermissao('compras.consultar_valores')")&&code.includes('n===seq&&session&&currentCompany?.id===id&&currentUser?.id===uid&&auth()'));
 assert.ok(code.includes('Faturamento não equivale a recebimento')&&code.includes('Lucro, caixa e custos industriais ainda não são apurados'));
 assert.ok(source.includes('id="gerencialPanel"')&&source.includes('window.ewGerencial?.limpar()'));
}
console.log('OK: painel gerencial — centavos, documentos cancelados, período e permissões.');

// v46.29.42: compensação contratual independente por categoria e acerto final.
{
 const i=source.indexOf('function finArredondarRazao('),j=source.indexOf('function finRenderFaturaveis(){',i);
 const {finPlanoCompensacao:plano,finSugestaoCompensada:sug,finPrecoCompensado:preco,finValorManualCentavos:manual,finValidaFechamentoCompensado:valida}=new Function(source.slice(i,j)+'return {finPlanoCompensacao,finSugestaoCompensada,finPrecoCompensado,finValorManualCentavos,finValidaFechamentoCompensado};')();
 const state={precificacao:{fabricacao_distribuida_centavos:100000,instalacao_distribuida_centavos:20000},faturas:[],precoPorEsquadria:new Map([['a',{area_m2:1,fabricacao_centavos:50000,instalacao_centavos:10000}],['b',{area_m2:1,fabricacao_centavos:50000,instalacao_centavos:10000}]]),billedAreas:{fabricacao:new Map(),instalacao:new Map()}};
 let p=plano(state,'fabricacao');assert.equal(sug(p,'a',.25),12500);assert.equal(manual(.25,800),20000);assert.equal(valida(p,[{esquadria_id:'a',area_m2:.25}],20000),'');
 state.billedAreas.fabricacao.set('a',.25);state.faturas.push({status:'emitido',categoria:'fabricacao',valor_total:200});p=plano(state,'fabricacao');assert.equal(p.saldo,80000);assert.equal(p.ajuste,-7500);assert.equal(sug(p,'a',.75),34286);assert.equal(sug(p,'b',1),45714);assert.equal(preco(p,'a',.75),457.1467);assert.equal(sug(plano(state,'instalacao'),'a',1),10000);
 assert.notEqual(valida(p,[{esquadria_id:'b',area_m2:1}],80000),'');assert.notEqual(valida(p,[{esquadria_id:'b',area_m2:1},{esquadria_id:'a',area_m2:.75}],79999),'');assert.equal(valida(p,[{esquadria_id:'b',area_m2:1},{esquadria_id:'a',area_m2:.75}],80000),'');
 state.billedAreas.fabricacao.set('b',1);state.faturas.push({status:'emitido',categoria:'fabricacao',valor_total:457.14});p=plano(state,'fabricacao');assert.equal(sug(p,'a',.75),34286);
 state.faturas[1].status='cancelado';state.billedAreas.fabricacao.delete('b');assert.equal(plano(state,'fabricacao').saldo,80000);
 for(let n=1;n<=100;n++){
  const st={precificacao:{fabricacao_distribuida_centavos:n+300},faturas:[{status:'emitido',categoria:'fabricacao',valor_total:1}],precoPorEsquadria:new Map([['a',{area_m2:1,fabricacao_centavos:n+100}],['b',{area_m2:2,fabricacao_centavos:200}]]),billedAreas:{fabricacao:new Map([['a',.25]])}};
  const pp=plano(st,'fabricacao');assert.equal([...pp.porId.values()].reduce((a,x)=>a+x.alvo,0),pp.saldo);assert.ok([...pp.porId.values()].every(x=>x.alvo>=1));
 }
 assert.equal(manual(.345,350),12075);assert.equal(manual(.005,1),1);
}
console.log('OK: compensação por categoria, antecipação, estorno, saldo final e 100 cenários de rateio.');

// Estoque valorizado: total desconhecido não é zero, subtotal somente comprovado.
{
 const code=readFileSync(new URL('../assets/painel-gerencial.js',import.meta.url),'utf8');
 const i=code.indexOf('function integer('),j=code.indexOf('function calc(',i);
 const k=code.indexOf('function table('),l=code.indexOf('async function carregarEstoque(',k);
 const render=new Function('esc','brl',code.slice(i,j)+code.slice(k,l)+'return renderEstoque;')(String,c=>'R$ '+(c/100).toFixed(2));
 const completo={linhas_fisicas:2,linhas_conciliadas:2,pendencias:0,fragmentos_sem_evidencia:0,valor_comprovado_centavos:90000,total_centavos:90000,galpoes:[{tipo:'OBRA',galpao:'AFOGADOS',linhas_fisicas:1,linhas_conciliadas:1,pendencias:0,fragmentos_sem_evidencia:0,valor_comprovado_centavos:30000},{tipo:'EMPRESA',galpao:'IMBIRIBEIRA',linhas_fisicas:1,linhas_conciliadas:1,pendencias:0,fragmentos_sem_evidencia:0,valor_comprovado_centavos:60000}]};
 assert.ok(render(completo).includes('R$ 900.00'));
 const pendente=structuredClone(completo);Object.assign(pendente,{linhas_conciliadas:1,pendencias:1,valor_comprovado_centavos:60000,total_centavos:null});Object.assign(pendente.galpoes[0],{linhas_conciliadas:0,pendencias:1,valor_comprovado_centavos:0});
 const html=render(pendente);assert.ok(html.includes('A apurar'));assert.ok(html.includes('R$ 600.00'));assert.ok(!html.includes('R$ 900.00'));
 assert.throws(()=>render({...pendente,total_centavos:60000}),/Totais de estoque não conciliam/);
 assert.ok(code.includes("if(!temPermissao('estoque.consultar'))return '';")&&code.includes('ew_estoque_valorizado_resumo'));
}
console.log('OK: estoque valorizado mostra posição atual, pendências e subtotal comprovado.');

// Financeiro empresarial: parsing exato, validação de saldo, permissões e consulta sem duplicar caixa.
{
 const code=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');
 new Function(code); // sintaxe do módulo real
 const i=code.indexOf('function parseMoney('),j=code.indexOf('let seq=',i);
 const parse=new Function(code.slice(i,j)+'return parseMoney;')();
 assert.equal(parse('1,01'),101);assert.equal(parse('0.01'),1);assert.equal(parse('1200.10'),120010);
 for(const v of ['0','-1','1,001','1.000,00','Infinity','1e3'])assert.throws(()=>parse(v));
 assert.ok(code.includes("temPermissao('financeiro.consultar')&&temPermissao('relatorios.financeiros')"));
 assert.ok(code.includes("o!=='NOTA_ESTOQUE'||temPermissao('compras.consultar_valores')"));
 assert.ok(code.includes('n===seq&&live()&&currentCompany.id===id&&currentUser?.id===uid'));
 for(const rpc of ['ew_fin_empresa_consultar','ew_fin_empresa_criar_titulo','ew_fin_empresa_baixar','ew_fin_empresa_cancelar_titulo','ew_fin_empresa_estornar_baixa'])assert.ok(code.includes(rpc));
 assert.ok(code.includes('não saldo bancário nem lucro')&&code.includes('Documentos ainda não programados não entram'));
 assert.ok(source.includes('id="navFinanceiroEmpresa"')&&source.includes("window.ewFinanceiroEmpresa?.limpar()")&&source.includes("window.ewFinanceiroEmpresa?.abrir()"));
}
console.log('OK: financeiro empresarial — centavos, tela, permissões, sessão e identificação de caixa.');

// Indicadores gerenciais: nenhum lucro fabricado, receita atribuída conciliada.
{
 const code=readFileSync(new URL('../assets/painel-gerencial.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('function integer('),b=code.indexOf('function calc(',a),c=code.indexOf('function table('),d=code.indexOf('function renderEstoque(',c),e=code.indexOf('function renderResultados('),f=code.indexOf('async function carregarResultados(',e);
 const render=new Function('esc','brl',code.slice(a,b)+code.slice(c,d)+code.slice(e,f)+'return renderResultados;')(String,n=>'R$ '+(n/100).toFixed(2));
 const r={fabricacao_centavos:10000,instalacao_centavos:2000,material_centavos:3000,consumos:2,consumos_pendentes:1,material_sem_item_centavos:0,manuais_pagar_centavos:500,manuais_receber_centavos:0,itens_total:1,fabrica:[{fabrica:'AFOGADOS',faturamento_centavos:8000,area_expedida_m2:2,areas_pendentes:0,material_centavos:3000,consumos:2,consumos_pendentes:1},{fabrica:null,faturamento_centavos:2000,area_expedida_m2:0,areas_pendentes:0,material_centavos:0,consumos:0,consumos_pendentes:0}],obras:[{nome:'Obra A',codigo:'A',faturamento_centavos:12000,material_centavos:3000,consumos:2,consumos_pendentes:1}],itens:[{obra:'Obra A',codigo:'EA1',material_centavos:3000,n:2,pendencias:1}],manuais:[{tipo:'PAGAR',categoria:'Energia',centro_custo:'AFOGADOS',valor_centavos:500}]};
 const html=render(r);for(const x of ['A atribuir','R$ 120.00','R$ 30.00 · parcial','A apurar','DRE gerencial','Sem registro'])assert.ok(html.includes(x),x);
 assert.throws(()=>render({...r,fabricacao_centavos:9999}),/Totais gerenciais não conciliam/);
 assert.ok(code.includes('ew_resultados_gerenciais')&&code.includes('não deduzido automaticamente'));
}
console.log('OK: resultados gerenciais conciliados, pendências e DRE sem lucro fictício.');

// DRE: despesas por competência, reconhecimento sem compra duplicada, subtotal sinalizado.
{
 const code=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(code);
 const i=code.indexOf('const dreClasses='),j=code.indexOf('const signed=',i);
 const calc=new Function('cents',code.slice(i,j)+'return dreCalcular;')(n=>{const v=Number(n);if(!Number.isSafeInteger(v)||v<0)throw Error('centavos');return v;});
 const r={fabricacao_centavos:15000,instalacao_centavos:3000,material_reconhecido_centavos:1000,manuais_pendentes:0,manuais_total:2,reconhecimentos_pendentes:0,materiais_disponiveis_total:1,classes:{RECEITA_OPERACIONAL:1000,CUSTO_INDIRETO:5000,FORA_RESULTADO:9000},manuais:[],materiais:[],reconhecimentos:[{valido:true,valor_centavos:1000}]};
 const d=calc(r);assert.equal(d.receita,19000);assert.equal(d.custos,6000);assert.equal(d.parcial,13000);
 assert.equal(calc({...r,classes:{DESPESA_ADMIN:20000}}).parcial,-3000);
 assert.throws(()=>calc({...r,material_reconhecido_centavos:2000}),/Totais da DRE/);
 assert.ok(code.includes('Resultado dos lançamentos classificados (parcial)')&&code.includes('Não é lucro líquido definitivo')&&code.includes('Fora do resultado'));
 assert.ok(code.includes('ew_dre_classificar_titulo')&&code.includes('ew_dre_reconhecer_material')&&code.includes('ew_dre_estornar_material'));
}
console.log('OK: DRE parcial, receitas, custos reconhecidos, despesas e prejuízo sem duplicação.');

// Rateios: soma financeira de origem preservada, contribuição e custos por centro.
{
 const code=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(code);
 const i=code.indexOf('function rateioValidar('),j=code.indexOf('function renderRateio(',i);
 const val=new Function('cents',code.slice(i,j)+'return rateioValidar;')(n=>{const v=Number(n);if(!Number.isSafeInteger(v)||v<0)throw Error('centavos');return v;});
 const linha={receita_centavos:10000,material_centavos:2000,rateio_centavos:4000,area_faturada:2};
 const r={...linha,industrial_classificado_centavos:8000,rateado_centavos:4000,rateios_pendentes:0,titulos_total:0,itens_total:1,titulos:[],liberacoes:[],rateios:[{valido:true,valor_centavos:4000}],fabrica:[linha],obras:[linha],itens:[linha]};
 assert.equal(val(r).saldo,4000);assert.equal(val(r).contribuicao,4000);
 assert.equal(val({...r,itens_total:2,itens:[]}).saldo,4000);
 assert.throws(()=>val({...r,itens:[{...linha,material_centavos:1999}]}),/Totais por código/);
 assert.throws(()=>val({...r,itens_total:2,itens:[{...linha,material_centavos:2001}]}),/Totais por código/);
 assert.throws(()=>val({...r,itens:[{...linha,area_faturada:-1}]}),/Área faturada/);
 assert.throws(()=>val({...r,itens_total:0}),/Quantidade de registros/);
 assert.throws(()=>val({...r,titulos_total:0,titulos:[{}]}),/Quantidade de registros/);
 assert.equal(val({...r,receita_centavos:1000,fabrica:[{...linha,receita_centavos:1000}],obras:[{...linha,receita_centavos:1000}],itens:[{...linha,receita_centavos:1000}]}).contribuicao,-5000);assert.throws(()=>val({...r,rateado_centavos:9000}),/Rateios não conciliam/);
 assert.throws(()=>val({...r,fabrica:[{...linha,receita_centavos:10001}]}),/Totais de contribuição/);
 assert.ok(code.includes('Contribuição parcial de fabricação')&&code.includes('Rateio não cria despesa')&&code.includes('não custo completo de uma unidade física'));
 assert.ok(code.includes('ew_rateio_industrial_criar')&&code.includes('ew_rateio_industrial_estornar'));
}
console.log('OK: custos industriais e contribuição parcial sem duplicar valores da DRE.');

// Navegação por domínio e recolhimento sem perda da página.
assert.ok(['OBRAS E PRODUÇÃO','COMPRAS E ESTOQUE','FINANÇAS E RELATÓRIOS','CONFIGURAÇÕES'].every(x=>source.includes(x))&&!source.includes('ESPAÇO DE TRABALHO'));
assert.ok(source.includes('aria-controls="workspaceNav"')&&source.includes("wrap.classList.toggle('workspaceNavCollapsed')")&&source.includes(".wrap.workspaceOpen.workspaceNavCollapsed>main{margin-left:0}")&&source.includes("if(!autenticado)wrap.classList.remove('workspaceNavCollapsed')"));
console.log('OK: menu por domínio, controle de recolhimento e reset de sessão.');

// Filtros de compras: acentos, situação, intervalo inclusivo e registros sem data.
{
 const code=readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('const filtroNorm='),b=code.indexOf('function comprasData(',a);
 const match=new Function(code.slice(a,b)+'return comprasFiltroCombina;')();
 const row={busca:'Obra A · Alumínio',situacao:'ABERTA',data:'2026-11-25'};
 assert.ok(match(row,{busca:'aluminio',situacao:'ABERTA',de:'2026-11-25',ate:'2026-11-25'}));
 assert.ok(!match(row,{situacao:'CANCELADA'}));assert.ok(!match(row,{de:'2026-11-26'}));assert.ok(!match({...row,data:''},{ate:'2026-11-26'}));
 assert.ok(match(row,{}));assert.ok(!match(row,{busca:'vidro'}));
 assert.ok(code.includes("readAllRows('ew_compras_solicitacoes'")&&code.includes("readAllRows('ew_compras_cotacoes'"));
}
console.log('OK: filtros de compras e paginação integral de solicitações e cotações.');

// Preços, reaproveitamento e distribuição consultiva de custos industriais.
{
 const code=readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('function linhasPreco('),b=code.indexOf('function materialPreco(',a),c=code.indexOf('function saldosReaproveitaveis('),d=code.indexOf('async function consultarReaproveitamento(',c);
 const {linhasPreco,saldosReaproveitaveis}=new Function(code.slice(a,b)+code.slice(c,d)+'return {linhasPreco,saldosReaproveitaveis};')();
 const i={chave:'1',variacao_id:'v',unidade:'KG',quantidade:1.005,preco_unitario_centavos:100};
 assert.equal(linhasPreco({total_centavos:101,itens:[i]})[0].subtotal,101);
 assert.equal(linhasPreco({total_centavos:102,itens:[i]}).length,0);
 assert.equal(linhasPreco({total_centavos:202,itens:[i,i]}).length,0);
 assert.equal(linhasPreco({total_centavos:0,itens:[{...i,preco_unitario_centavos:null}]}).length,0);
 const l={local_empresa_id:'l',galpao:'A',variacao_id:'v',unidade:'BARRA',comprimento_mm:6000};
 const result=saldosReaproveitaveis([{...l,quantidade_delta:4},{...l,quantidade_delta:-1},{...l,comprimento_mm:5000,quantidade_delta:9},{...l,local_empresa_id:'outro',quantidade_delta:8}],[l],[{id:'l',ativo:true}]);
 assert.equal(result.length,1);assert.equal(result[0].quantidade,3);
 const fin=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(fin);
 const x=fin.indexOf('function distribuirRateioPorQuantidade('),y=fin.indexOf('function renderRateio(',x);
 const split=new Function('cents',fin.slice(x,y)+'return distribuirRateioPorQuantidade;')(Number);
 assert.deepEqual(split(100,[{id:'a',quantidade:1},{id:'b',quantidade:2}]),[{id:'a',centavos:33},{id:'b',centavos:67}]);
 assert.deepEqual(split(1,[{id:'b',quantidade:1},{id:'a',quantidade:1}]),[{id:'b',centavos:0},{id:'a',centavos:1}]);
 for(let total=1;total<=100;total++){const r=split(total,[{id:'a',quantidade:7},{id:'b',quantidade:11},{id:'c',quantidade:19}]);assert.equal(r.reduce((s,l)=>s+l.centavos,0),total);}
 assert.throws(()=>split(100,[{id:'a',quantidade:0}]));assert.throws(()=>split(100,[{id:'a',quantidade:1},{id:'a',quantidade:2}]));
 assert.ok(source.includes('id="comprasTabHistorico"')&&code.includes("etapa==='historico'&&!permission('compras.consultar_valores')"));
}
console.log('OK: preços conciliados, estoque compatível e simulação exata em 100 distribuições.');

assert.ok(readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8').includes("p_confirmar:true,p_previa:p.linhas"));
assert.ok(source.includes('financeiro-empresarial.js?v=20261128m'));

{
 const code=readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8');
 const a=code.indexOf('function chavePreco('),b=code.indexOf('function materialPreco(',a),c=code.indexOf('function abatimentoRascunho('),d=code.indexOf('async function consultarReaproveitamento(',c);
 const abater=new Function(code.slice(a,b)+code.slice(c,d)+'return abatimentoRascunho;')();
 const x={variacao_id:'v',unidade:'BARRA',comprimento_mm:6000};
 const rows=[{...x,quantidade:2},{...x,quantidade:3},{...x,comprimento_mm:5000,quantidade:4}];
 assert.deepEqual(abater(rows,x,4).map(y=>y.quantidade),[0,1]);
 assert.throws(()=>abater(rows,x,6));
 assert.equal(abater([{...x,unidade:'KG',quantidade:1.005}],{...x,unidade:'KG'},0.005)[0].quantidade,1);
 assert.ok(code.includes("await rpc('ew_compras_transferir_locais',{...payload")&&code.includes("confirmado=true;pendingOps.delete('reuso_rascunho')"));
}
console.log('OK: abatimento do rascunho somente por material compatível e transferência confirmada.');

{
 const code=readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('function linhasPreco('),b=code.indexOf('function materialPreco(',a),c=code.indexOf('function previsaoEntregaPedido('),d=code.indexOf('function painelPrevisaoCompras(',c);
 const {previsaoEntregaPedido,saldoEntregaPedido}=new Function(code.slice(a,b)+code.slice(c,d)+'return {previsaoEntregaPedido,saldoEntregaPedido};')();
 assert.equal(previsaoEntregaPedido('2026-11-28',15),'2026-12-13');
 assert.equal(previsaoEntregaPedido('2026-11-28',null),null);assert.equal(previsaoEntregaPedido('2026-02-30',1),null);
 const p={total_centavos:50000,itens:[{chave:'1',variacao_id:'v',unidade:'BARRA',quantidade:4,preco_unitario_centavos:12500}]};
 assert.equal(saldoEntregaPedido(p,new Map([['1',1]])),37500);assert.equal(saldoEntregaPedido(p,new Map([['1',5]])),null);
 const fin=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(fin);
 const x=fin.indexOf('function indicadorFabrica('),y=fin.indexOf('function renderIndicadores(',x);
 const calc=new Function('cents',fin.slice(x,y)+'return indicadorFabrica;')(Number);
 assert.deepEqual(calc({receita_centavos:10000,material_centavos:2000,rateio_centavos:3000,area_m2:2}),{receita:10000,custo:5000,contribuicao:5000,area:2,custoM2:2500,margem:50});
 assert.equal(calc({receita_centavos:10000,material_centavos:2000,rateio_centavos:3000,area_m2:null}).custoM2,null);
}
console.log('OK: previsão de entrega, saldo contratual, margem parcial e área conciliada.');

{
 const code=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('function previsaoTitulos('),b=code.indexOf('function renderPrevisaoTitulos(',a);
 const calc=new Function('cents',code.slice(a,b)+'return previsaoTitulos;')(Number);
 const r={a_pagar_centavos:100,a_receber_centavos:250,titulos_total:4,titulos:[
 {tipo:'PAGAR',origem_valida:true,vencimento:'2026-12-01',saldo_centavos:100},
 {tipo:'RECEBER',origem_valida:true,vencimento:'2026-12-02',saldo_centavos:250},
 {tipo:'PAGAR',origem_valida:false,vencimento:'2026-12-01',saldo_centavos:999},
 {tipo:'PAGAR',origem_valida:true,cancelado_em:'2026-11-28',saldo_centavos:999}]};
 assert.deepEqual(calc(r),{linhas:[{mes:'2026-12',pagar:100,receber:250}],pagar:100,receber:250,completa:true});
 assert.equal(calc({...r,titulos_total:5}).completa,false);
 assert.throws(()=>calc({...r,a_pagar_centavos:99}));
 assert.throws(()=>calc({...r,a_pagar_centavos:101}));
 assert.ok(code.includes('value="PESO_CONSUMO"'));
}
console.log('OK: previsão conciliada por vencimento, exclusão de origens inválidas e sinalização de lista parcial.');

{
 const code=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('function renderComprasFinanceiro('),b=code.indexOf('function bindFrete(',a);
 const render=new Function('cents','money','can','esc','table','cells','option',code.slice(a,b)+'return renderComprasFinanceiro;')(Number,String,()=>false,String,()=>'<table></table>',()=>'',()=>{});
 const x={total:1,saldo_programado_centavos:100,sem_programacao_centavos:0,pendencias:0,linhas:[{origem_tipo:'DESPESA_OBRA',origem_id:'a',pedidos:[1,2],situacao:'PROGRAMADO',saldo_centavos:100}],pedidos:[],fretes_disponiveis:[]};
 assert.ok(render(x).includes('Saldo programado: 100'));
 assert.ok(render({...x,linhas:[x.linhas[0],x.linhas[0]]}).includes('Documento duplicado'));
 assert.ok(render({...x,saldo_programado_centavos:50}).includes('Previsão não conciliada'));
 assert.ok(code.includes('ew_fin_vincular_frete')&&code.includes('ew_industrial_produtividade'));
}
console.log('OK: previsão vinculada às compras e proteção contra documentos duplicados.');

{
 const code=readFileSync(new URL('../assets/financeiro-empresarial.js',import.meta.url),'utf8');new Function(code);
 const a=code.indexOf('function simularCustoIntegral('),b=code.indexOf('function renderSimCusto(',a);
 const calc=new Function('cents',code.slice(a,b)+'return simularCustoIntegral;')(n=>{if(!Number.isSafeInteger(n)||n<0)throw Error('valor');return n;});
 const d={materiais:100000,folha:200000,encargos:50000,beneficios:10000,energia:20000,manutencao:10000,frete:5000,outros:0,ativo:120000,residual:0,vida:12,area:100,horas:200};
 assert.deepEqual(calc(d),{depreciacao:10000,pessoal:260000,total:405000,porM2:4050,porHora:2025});
 assert.equal(calc({...d,horas:0}).porHora,null);
 assert.throws(()=>calc({...d,residual:120001}));assert.throws(()=>calc({...d,area:0}));assert.throws(()=>calc({...d,vida:0}));
 assert.ok(code.includes('ew_fin_estornar_vinculo_frete')&&code.includes('ew_fin_frete_previa')&&code.includes('ew_industrial_registrar_horas'));
}
console.log('OK: cálculo simulado de custo integral e integração de frete/horas.');
