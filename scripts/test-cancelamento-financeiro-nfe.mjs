import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const begin=html.indexOf('async function finCancelarLancamento(tipo,id){');
const end=html.indexOf('// Faturamento parcial: quantidade equivalente de esquadria',begin);
assert.ok(begin>=0&&end>begin,'Função financeira não localizada na interface');
const body=html.slice(begin,end);
assert.match(html,/id="finHistoryMessage" class="feedback" role="status"/);
assert.match(html,/Estornar lançamento/);
assert.match(body,/ew_insumos_cancelar_nota/);
assert.doesNotMatch(body,/\?\s*'ew_cancelar_despesa_financeira'/);

async function scenario(kind,id,{admin=true,motivo='Corrigir lançamento incorreto',ok=true,serverError=null}={}){
 const calls=[],feedback=new Map(),events=[];
 const ctx={
  isFullAdminUser:()=>admin,
  temPermissao:chave=>admin&&['financeiro.cancelar_despesas','financeiro.cancelar_faturamento'].includes(chave),
  finState:{despesas:[
   {id:'nf-123',categoria:'aluminio'},
   {id:'nf-125',categoria:'acessorios'},
   {id:'nf-vidro',categoria:'vidros'},
  ]},
  window:{
   prompt:()=>motivo,
   confirm:(message)=>{events.push(['confirm',message]);return ok},
  },
  node:key=>{
   if(!feedback.has(key))feedback.set(key,{textContent:''});
   return feedback.get(key);
  },
  ensureSession:async()=>events.push(['session']),
  currentCompany:{id:'empresa-ficticia'},
  session:{access_token:'token-ficticio'},
  request:async(url,args)=>{
   calls.push({url,args});
   if(serverError)throw new Error(serverError);
   return {status:'cancelada'};
  },
  finLoad:async()=>events.push(['refresh']),
 };
 vm.runInNewContext(body+'\nglobalThis.invoke=finCancelarLancamento;',ctx);
 await ctx.invoke(kind,id);
 return {calls,feedback,events};
}
for(const [id,nome] of [['nf-123','aluminio'],['nf-125','acessorios'],['nf-vidro','vidros']]){
 const x=await scenario('despesa',id);
 assert.equal(x.calls.length,1,'Deve disparar uma única RPC para '+nome);
 assert.equal(x.calls[0].url,'/rest/v1/rpc/ew_insumos_cancelar_nota',
  'Despesas '+nome+' devem usar o cancelador seguro com fallback');
 assert.deepEqual(JSON.parse(JSON.stringify(x.calls[0].args.body)),{
  p_empresa_id:'empresa-ficticia',p_despesa_id:id,p_motivo:'Corrigir lançamento incorreto'});
 assert.match(x.feedback.get('finHistoryMessage').textContent,/Histórico preservado/);
 assert.equal(x.events.filter(e=>e[0]==='refresh').length,1);
}
const faturamento=await scenario('faturamento','fat-1');
assert.equal(faturamento.calls[0].url,'/rest/v1/rpc/ew_cancelar_faturamento_financeiro',
 'Não mudar a RPC de cancelamento de faturamentos');
assert.equal((await scenario('despesa','nf-123',{admin:false})).calls.length,0,
 'Sem flag de cancelamento não pode disparar RPC');
assert.equal((await scenario('despesa','nf-123',{ok:false})).calls.length,0,
 'Cancelar diálogo não pode executar RPC');
assert.equal((await scenario('despesa','nf-123',{motivo:'x'})).calls.length,0,
 'Motivo muito curto não pode executar RPC');
assert.equal((await scenario('despesa','nf-123',{motivo:'x'.repeat(401)})).calls.length,0,
 'Motivo excessivo não pode executar RPC');
const erro=await scenario('despesa','nf-123',{serverError:'Recebimento físico ainda ativo'});
assert.match(erro.feedback.get('finHistoryMessage').textContent,
 /Estorno não realizado: Recebimento físico ainda ativo/,
 'Erro da RPC deve ficar visível ao lado do histórico');
assert.equal(erro.events.some(e=>e[0]==='refresh'),false,
 'Estorno negado não pode atualizar o histórico como se tivesse sucesso');
console.log('OK: estorno de NF-e aluminio/acessorios/vidros, faturamento separado, motivo, ADM e mensagem local.');
