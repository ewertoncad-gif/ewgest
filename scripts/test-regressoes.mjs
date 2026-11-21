import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const source=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const receiptCacheHeaders=readFileSync(fileURLToPath(new URL('../_headers',import.meta.url)),'utf8');
assert.ok(source.includes('/assets/recebimento-manual.js?v=20261121f')&&
 source.includes('/assets/recebimento-manual.css?v=20261121f'),
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
 'interface renovada v43.1',
 'id="pendingReviewPanel"',
 'id="recognitionOverlay"',
 'id="recognitionApproval"',
 'id="recognitionDivergence"',
 'resolver_modulacao_pendente_admin',
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
 '/rest/v1/rpc/ew_liberar_plano_corte_revisado',
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
 'Somente o marco',
 'Somente as folhas',
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
state.next='corrigir';state.form.differenceConfig.value='m1';
functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'Permitir corrigir descrição original somente após escolher configuração');
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
const montarRomaneio=new Function('works','escapeHTML',
 source.slice(iniciar,terminar)+'\nreturn construirHTMLRomaneio;'
)([{id:'obra',nome:'MIRAGE',cliente:'MOURA DUBEUX'}],esc);
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
 leaves:Number(x.folhas_enviadas||0),per:x.per||null}),
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
const evaluateRole=role=>new Function('membership','document',
 source.slice(funcInicio,funcFinal)+'\nreturn {isAlmoxarife,podeEmitirRomaneio};'
)({perfil:role},{querySelectorAll:()=>[]});
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
 'campoDescricao.value=descricaoPadraoRomaneio(item,modo)'
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
 source.includes('Comprimento da barra')&&source.includes('Ajustar quantidade')&&
 source.includes('Quantidade ainda não cadastrada'),
 'Estoque atual mostra necessidade, saldo físico, barras e ajuste de quantidade');
assert.ok(source.includes('async function abrirEstoque()')&&source.includes('async function registrarMovimentoEstoque(e)'),
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
 source.includes("nova?'ew_importar_obra_cem_financeiro':'ew_importar_cem_conciliado'"),
 'Importação usa RPC transacional diferente para nova obra e obra existente');
assert.ok(!source.includes('rows.slice(0,6)'), 'Exibe a lista completa de materiais do CEM');


assert.ok(source.includes('id="stockManualForm"')&&source.includes('id="stockManualWork"')&&
 source.includes('id="stockNewMaterialCode"'), 'Cadastro manual de obra e material deve existir');
assert.ok(source.includes('id="releaseMirrorRows"')&&source.includes('name="releaseMethod"')&&
 !source.includes('name="releaseMethod" type="radio" value="cem"'),
 'Liberação individual tem espelho manual, sem importação de lote CEM');
assert.ok(source.includes('id="releaseBatchOpen"')&&source.includes('id="releaseBatchPreview"')&&
 source.includes("'/rest/v1/rpc/ew_liberar_lote_cem'")&&source.includes('function releaseBatchCollect()'),
 'Liberação em lote CEM deve ter espelho editável, validação e confirmação única');
assert.ok(source.includes('id="stockFactoryFilter"')&&source.includes('id="stockManualFactory"')&&
 source.includes('data-stock-transfer=')&&source.includes("'/rest/v1/rpc/ew_transferir_estoque_obra'"),
 'Estoque controlado, transferível e filtrável por local físico');
assert.ok(source.includes('const obrasParaRomaneio=works.filter'),
 'Romaneios escondem obra de estoque arquivado sem esquadrias e sem histórico');
assert.ok(source.includes("'/rest/v1/rpc/ew_liberar_plano_corte_revisado'"),
 'Liberação confirma materiais em operação atômica');
assert.ok(source.includes("'/rest/v1/rpc/ew_movimentar_estoque_obra_local'")&&
 source.includes("'/rest/v1/rpc/ew_cadastrar_material_manual_estoque_local'"),
 'Cadastro existente e novos materiais exigem local físico do estoque');
assert.ok(source.includes('function cemEncontrarConciliacoes(r,perfis,acessorios)'),
 'Comparação de códigos importados com cadastro manual');
assert.ok(source.includes('ew_importar_cem_conciliado'),
 'Importação deve solicitar decisões do ADM em casos de equivalência');
assert.ok(!source.includes("rows.slice(0,6)"), 'Lista de materiais importados deve ser completa');

assert.ok(source.includes('id="stockCreateAnother"')&&
 source.includes("node('stockCreateAnother').addEventListener"),
 'Criar estoque de outra obra acessível diretamente no topo');
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
assert.ok(source.includes("'/rest/v1/rpc/ew_importar_saldo_obra_cem'")&&
 source.includes("'/rest/v1/rpc/ew_excluir_estoque_local'")&&
 source.includes("'/rest/v1/rpc/ew_restaurar_estoque_local'"),
 'Integração com importação e recuperação do Supabase');
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



assert.ok(source.includes('const obrasComEsquadrias=works.filter(w=>elements.some(e=>e.obra_id===w.id));')&&
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
assert.ok(source.indexOf('id="stockNewManual"')>source.indexOf('id="stockRecords"'),
 'Adicionar material foi movido para baixo da tabela');
assert.ok(source.includes('function stockCemReadMirror(){')&&
 source.includes('function stockCemMirrorRow(tipo,row={},index=-1){')&&
 source.includes('p_perfis:mirror.perfis,p_acessorios:mirror.acessorios'),
 'Importação utiliza o espelho editado, não os dados originais do arquivo');
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
 edgeSource.includes("!isFullAdmin(caller) && perfil === 'administrador'")&&
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
const checkRoles=new Function('membership',source.slice(startRole,endRole)+
 'return {manager:canAdministrate(),admin:isFullAdminUser()};');
assert.deepEqual(checkRoles({perfil:'gerenciador'}),{manager:true,admin:false});
assert.deepEqual(checkRoles({perfil:'administrador'}),{manager:true,admin:true});
assert.deepEqual(checkRoles({perfil:'tecnico'}),{manager:false,admin:false});

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
for(const id of ['manageWorks','navManageWorks','manageWorksList',
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
 source.includes('root.innerHTML=stockLocais.map(loc=>')&&
 source.includes('stockReverseSelectedWorkId'),
 'Estoques arquivados não entram nas movimentações comuns e permanecem consultáveis');
// Obra com estoque arquivado permanece selecionável exclusivamente para consulta.
for(const id of ['stockWorkHistory','stockArchivedHint','stockReverseHistoryList','stockReverseHistoryFilter']){
 assert.ok(source.includes('id="'+id+'"'),'Histórico de estoque por obra precisa de '+id);
}
assert.ok(source.includes("locaisPorObra.get(w.id)?.excluido_em")&&
 source.includes("ESTOQUE ARQUIVADO")&&
 source.includes('Somente consulta')&&
 source.includes("node('stockNewManual').disabled=arquivado"),
 'Estoque arquivado deve aparecer no seletor sem permitir movimentação operacional');
assert.ok(source.includes('function stockReverseHistoryRender(id)')&&
 source.includes('async function stockReverseIndividual(movimentoId)')&&
 source.includes("request('/rest/v1/rpc/ew_estornar_movimento_obra'")&&
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
 source.indexOf('async function stockManageDelete(id)'));
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
// A exclusão da obra requer motivo e uma confirmação: não pede código digitado nem pressupõe nova importação.
const formExcluir=source.slice(source.indexOf('<div id="manageWorksDeleteForm"'),
 source.indexOf('<section id="romaneiosPage"'));
const fluxoExcluir=source.slice(source.indexOf("node('manageWorksDelete').addEventListener"),
 source.indexOf("window.addEventListener('error'"));
assert.ok(formExcluir.includes('>Excluir obra</button>')&&
 !formExcluir.includes('manageWorksConfirmation')&&
 !formExcluir.toLowerCase().includes('reimportar'),
 'Excluir obra deve ter botão simples, sem código ou reimportação');
assert.ok(fluxoExcluir.includes('Tem certeza que deseja excluir esta obra?')&&
 fluxoExcluir.includes('window.confirm(aviso)')&&
 fluxoExcluir.includes("confirmacao=String(workDeleteInspection.codigo||workDeleteInspection.nome||'').trim()")&&
 fluxoExcluir.includes("p_confirmacao:confirmacao")&&
 !fluxoExcluir.includes("node('manageWorksConfirmation')"),
 'Confirmar exclusão uma única vez e validar código automaticamente para compatibilidade com RPC');
assert.ok(source.includes('info?.permitido&&motivo.length>=5&&motivo.length<=300')&&
 !source.includes('Digite exatamente o código da obra para confirmar'),
 'Motivo obrigatório e sem frase digitada');
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
assert.ok(source.includes("estornados.has(m.id)?'Estornado':'Não estornado'")&&
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
 source.includes("node('navWorks').addEventListener('click',abrirObrasPelaBarra)")&&
 source.includes("node('navWorks').classList.toggle('hidden',somenteRomaneios)")&&
 source.includes("['navWorks','worksPage']"),
 'A navegação Obras precisa respeitar permissões e destacar o menu ativo');
assert.ok(source.includes('function abrirObrasPelaBarra()')&&
 source.includes('if(lista.length===1)')&&
 source.includes('function mostrarListaDeObras()')&&
 source.includes('detailBackTarget=\'worksPage\'')&&
 source.includes("if(detailBackTarget==='worksPage')mostrarListaDeObras()"),
 'Uma única obra deve abrir diretamente; múltiplas obras exigem lista e volta correta');
assert.ok(source.includes('function obrasComEsquadriasAtivas()')&&
 source.includes('return works.filter(w=>ids.has(w.id))'),
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
 source.includes('await inspecionarExclusaoObra(obraId)')&&
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
 source.includes('id="navManageWorks"')&&
 source.includes("node('navManageWorks').addEventListener('click',abrirGerenciamentoObras)"),
 'Gerenciar obras fica apenas na barra lateral, preservando o acesso');
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
assert.ok(/EWGEST <strong>· v\d+\.\d+<\/strong>/.test(source)&&
 source.includes('@media(prefers-reduced-motion:reduce){.startupSpinner'),
 'Indicador de carregamento acessível e versão presente no rodapé');
// v44.7: os sete atalhos marcados no cabeçalho devem desaparecer, sem eventos órfãos.
const obsoleteHeaderButtons=[
 'manageWorksBack','romaneiosBack','usersBack','materialsBack','stockBack',
 'cemBack','backTypologies','openManufacturersFromCatalog'
];
for(const id of obsoleteHeaderButtons){
 assert.ok(!source.includes('id="'+id+'"')&&!source.includes("node('"+id+"')"),
  'Atalho de navegação redundante ou evento órfão: '+id);
}
for(const id of ['navHome','navRomaneios','navTypologies','navManufacturers',
 'navMaterials','navStock','navCem','navUsers','navManageWorks']){
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
assert.ok(source.includes('<script src="/assets/orcamento-niveis.js?v=20261120c"></script>')&&
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
assert.ok(source.includes('Entrada manual de materiais e notas')&&
 source.includes('id="finManualRows"')&&source.includes('id="finManualLocal"')&&
 source.includes('id="finManualAdd"')&&source.includes('id="finManualSum"')&&
 source.includes('id="finCostTotal" type="text" inputmode="decimal"'),
 'Formulário de nota manual deve ter galpão, materiais, quantidades e total monetário');
assert.ok(source.includes('id="finCostXML" class="hidden" disabled')&&
 !source.includes('<label>XML da nota fiscal (NF-e)')&&
 source.includes('id="finCostCategory" required'),
 'Entrada financeira não pode oferecer envio de XML; almoxarifado mantém fluxo próprio');
assert.ok(source.includes('recebimento-manual.js?v=20261121f')&&
 source.includes('recebimento-manual.css?v=20261121f')&&receiveCSS.includes('.finManualTable'),
 'HTML deve carregar arquivos de recebimento manual');
assert.ok(receiveScript.includes('ew_registrar_recebimento_manual_financeiro')&&
 receiveScript.includes('p_itens:items')&&receiveScript.includes('finCostOpId ||= crypto.randomUUID()')&&
 receiveScript.includes('ew_registrar_despesa_financeira')&&
 receiveScript.includes('const sum=items.reduce')&&
 receiveScript.includes('if(sum!==note)'),
 'Entrada física exige itens com subtotal correto; despesas sem catálogo permanecem separadas');
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
 "const initForm=()=>{};",
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
 orcamentoNiveis:niveisExemplo,
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
 acessorios:[{id:'a1',codigo:'PARAFUSO',descricao:'Parafuso'},
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
 'let finState=state,category=selectedCategory; const cents=()=>10000;\n'+
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
 quantidade:'2.5',valor:'R$ 100,00'},0).quantidade,2.5,
 'Não alterar acessório medido em unidade fracionável');

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
assert.ok(receiveScript.includes("byId('finCostTotal').readOnly=hasStock;")&&
 receiveScript.includes("totalField.value=soma>0?finMoney(soma/100):''")&&
 !receiveScript.includes('rows.length===1&&note!==null'),
 'Valor da NF de materiais deve vir da soma dos itens sem substituir um valor de linha');

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

console.log('OK: '+cases.length+' classificações; cadastros, estoque, histórico e sessão única.');
