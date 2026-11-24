import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const uiStart=html.indexOf('function atualizarEstadoExclusaoObra(){');
const uiEnd=html.indexOf('async function inspecionarExclusaoObra(',uiStart);
const clickStart=html.indexOf("node('manageWorksDelete').addEventListener('click',async()=>{",uiEnd);
const clickEnd=html.indexOf("\n\nwindow.addEventListener('error'",clickStart);
assert.ok(uiStart>0&&uiEnd>uiStart&&clickStart>uiEnd&&clickEnd>clickStart,
 'Funções reais de exclusão de obras precisam estar na página');
const updater=html.slice(uiStart,uiEnd);
const handler=html.slice(clickStart,clickEnd);
assert.match(html,/EWGEST <strong>· v46\.21<\/strong>/);
assert.match(updater,/!info\?\.permitido\|\|workDeleteSubmitting/);
assert.match(handler,/window\.alert\(mensagem\)/);
assert.match(handler,/motivoCampo\.focus\(\)/);

function setup({permitido=true,confirmar=true,erro=false}={}){
 const alerts=[],confirms=[],requests=[],hooks={},elements=new Map();
 const el=id=>{
  if(!elements.has(id))elements.set(id,{
   value:'',disabled:false,textContent:'',
   classList:{add(){},remove(){}},
   focus(){this.focused=true},
   addEventListener(event,callback){hooks[id+':'+event]=callback},
  });
  return elements.get(id);
 };
 const ctx={
  node:el,works:[{id:'obra-teste',codigo:'TESTE-123',nome:'OBRA DE TREINAMENTO'}],
  canAdministrate:()=>true,
  window:{
   alert(msg){alerts.push(msg)},
   confirm(msg){confirms.push(msg);return confirmar},
  },
  crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},
  ensureSession:async()=>{},
  request:async(path,options)=>{
   requests.push({path,options});
   if(erro)throw Error('Cancelamento negado pelo banco de dados');
   return {excluida:true,nome:'OBRA DE TREINAMENTO',repetida:false};
  },
  loadPanel:async()=>{},
  abrirGerenciamentoObras:()=>{},
  inspecionarExclusaoObra:async()=>{},
  selectedWork:null,selectedItem:null,hubObraId:'',
  session:{access_token:'TOKEN-FICTICIO'},
  workDeleteInspection:{permitido,obra_id:'obra-teste',codigo:'TESTE-123',nome:'OBRA DE TREINAMENTO'},
  workDeleteOperationId:'22222222-2222-4222-8222-222222222222',
  workDeleteSubmitting:false,
 };
 vm.createContext(ctx);
 vm.runInContext(updater+'\n'+handler,ctx);
 const update=()=>ctx.atualizarEstadoExclusaoObra();
 const click=()=>hooks['manageWorksDelete:click']();
 return {ctx,alerts,confirms,requests,el,update,click};
}
const vazio=setup();
vazio.update();
assert.equal(vazio.el('manageWorksDelete').disabled,false,
 'O botão precisa responder ao clique para avisar que falta motivo');
await vazio.click();
assert.equal(vazio.alerts.length,1);
assert.match(vazio.alerts[0],/Informe o motivo da exclusão antes de continuar/);
assert.equal(vazio.el('manageWorksReason').focused,true);
assert.equal(vazio.requests.length,0,'Sem motivo, nunca chamar RPC de exclusão');
assert.equal(vazio.confirms.length,0,'Sem motivo, nem abrir confirmação irreversível');
assert.match(vazio.el('manageWorksDeleteBlockedMessage').textContent,/mínimo de 5 caracteres/);

vazio.el('manageWorksReason').value='abc';
vazio.update();
await vazio.click();
assert.equal(vazio.alerts.length,2,'Motivo curto não libera exclusão');
assert.equal(vazio.requests.length,0);

vazio.el('manageWorksReason').value='Exclusão de obra de treinamento';
vazio.update();
assert.equal(vazio.el('manageWorksDeleteBlockedMessage').textContent,'');
await vazio.click();
assert.equal(vazio.alerts.length,2,'Motivo válido não precisa de alerta');
assert.equal(vazio.confirms.length,1,'Apenas uma confirmação para a exclusão');
assert.equal(vazio.confirms[0],'ATENÇÃO: PROCESSO IRREVERSÍVEL. TEM CERTEZA QUE DESEJA ESTORNAR?');
assert.equal(vazio.requests.length,1,'Executar após motivo e uma confirmação, sem digitação de código');
assert.equal(vazio.requests[0].path,'/rest/v1/rpc/ew_arquivar_obra_reconciliada');
assert.equal(vazio.requests[0].options.body.p_motivo,'Exclusão de obra de treinamento');
assert.equal(vazio.el('manageWorksDelete').disabled,true,'Após exclusão, bloquear botão sem inspeção ativa');

assert.ok(!handler.includes('window.prompt('),'Não pedir código digitado para concluir exclusão');

const negado=setup({permitido:false});
negado.update();
assert.equal(negado.el('manageWorksDelete').disabled,true,
 'Obra ainda bloqueada pelo servidor deve continuar realmente desabilitada');

const cancelado=setup({confirmar:false});
cancelado.el('manageWorksReason').value='Motivo justificado';
await cancelado.click();
assert.equal(cancelado.requests.length,0,'Cancelar confirmação não pode excluir obra');

const erro=setup({erro:true});
erro.el('manageWorksReason').value='Motivo para reverter obra';
await erro.click();
assert.equal(erro.requests.length,1);
assert.match(erro.el('manageWorksFeedback').textContent,/Cancelamento negado pelo banco de dados/);
assert.equal(erro.el('manageWorksDelete').disabled,false,'Erro deve permitir corrigir e tentar novamente');

console.log('OK v46.14: motivo vazio/curto mostra alerta e foca, motivo válido confirma, bloqueio de servidor preservado.');
