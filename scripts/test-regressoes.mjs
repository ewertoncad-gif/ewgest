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
 'comparação de tipologias v35.2',
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
 '\nreturn {codigoVariacaoTecnica,modulacaoCadastroLegado,proximoSufixoVisual,typologyCode};'
)(catalogoRaiz,mods);
assert.equal(formatos.typologyCode({tipologia_id:principalId,modulacao_id:'m1'}),'INV-VNZN00-01');
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
 differenceConfig:{value:'m1'},differenceComparison:{
   children:[],replaceChildren(){this.children=[];},
   append(...children){this.children.push(...children);}
 },
 differenceSecondStep:{classList:{toggle(){}}},differenceCreateFields:{classList:{toggle(){}}},
 differenceCorrectFields:{classList:{toggle(){}}},differenceCorrectDescription:{textContent:''},
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
 [{id:'fam',codigo:'WINFAC-JCR203'}],[modReferencia],fakeDocument,
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
state.form.differenceNewDescription.value=modReferencia.descricao;
functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,true,'Impedir cadastrar descrição duplicada');
state.form.differenceNewDescription.value='MODULO JANELA DE CORRER - SERIE 105';
state.next='corrigir';functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'Permitir corrigir descrição original');
state.next='adiar';functions.atualizarTelaDiferenca();
assert.equal(state.form.differenceSave.disabled,false,'Permitir adiar e seguir obra');

console.log('OK: '+cases.length+' classificacoes; EA por obra; sufixos; Sim/Nao e nova/corrigir/adiar.');

