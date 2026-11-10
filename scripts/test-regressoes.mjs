import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const source=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
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
 'abreviações e almoxarifado v40.0',
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
 '/rest/v1/rpc/registrar_liberacao_corte_fabrica',
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
const evaluateRole=role=>new Function('membership',
 source.slice(funcInicio,funcFinal)+'\nreturn {isAlmoxarife,podeEmitirRomaneio};'
)({perfil:role});
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
assert.ok(contentForm.indexOf('id="romaneioNotes"')<contentForm.indexOf('id="romaneioConfirm"'),
 'Observações antes de confirmar a expedição');
const observ=montarRomaneio({...cabecalho,observacoes:'ENTREGA PARCIAL\nCONFERIDO PELO ALMOXARIFE'},[linha(1)]);
assert.ok(observ.includes('ENTREGA PARCIAL\nCONFERIDO PELO ALMOXARIFE'),
 'Observações com quebra de linha preservadas no comprovante');
assert.ok(observ.includes('.notes{')&&observ.includes('white-space:pre-line'),
 'Observações aceitam linhas múltiplas na impressão');
console.log('OK: '+cases.length+' classificações; cadastro de abreviações, observações finais, almoxarife e regressões.');


