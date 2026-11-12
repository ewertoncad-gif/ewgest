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
 'interface renovada v42.6',
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
assert.ok(contentForm.includes('class="romaneioSubmissionNote"'),
 'A emissão informa claramente que o botão executa a baixa das esquadrias');
assert.ok(!contentForm.includes('id="romaneioConfirm"'),
 'Não exigir checkbox redundante antes da emissão');
assert.ok(!source.includes("node('romaneioConfirm').checked"),
 'Validação do botão não deve exigir checkbox removido');
assert.ok(source.includes('id="workspaceNav"') && source.includes('id="navHome"')
 && source.includes('id="navRomaneios"'),
 'Nova navegação acessível permanece disponível');
assert.ok(source.includes('id="romaneiosBack" type="button" class="btn secondary">← Tela inicial'),
 'Retorno de romaneios renomeado para Tela inicial');
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
assert.ok(source.includes('Quantidade na obra')&&source.includes('Comprimento da barra')&&
 source.includes('Ajustar quantidade')&&source.includes('Não cadastrada'),
 'Estoque simplificado mostra barras, comprimento e ajuste de saldo');
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
assert.ok(source.includes("node('cemFlagEsquadrias').checked=false"),
  'Desmarca esquadrias automaticamente para obra já existente');
assert.ok(source.includes('async function cemImportarSelecionados()')&&
 source.includes("'/rest/v1/rpc/ew_importar_cem_conciliado'"),
 'Botão importa somente materiais via transação no servidor');
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

console.log('OK: '+cases.length+' classificações; cadastros, estoques, histórico de acessos e regressões.');


