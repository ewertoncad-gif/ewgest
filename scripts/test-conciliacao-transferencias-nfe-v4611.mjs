import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const html=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const sql=readFileSync(fileURLToPath(new URL('../database/proposals/20261122_conciliacao_transferencias_nfe_v4611.sql',import.meta.url)),'utf8');
const begin=html.indexOf('async function stockReverseRevisar(id){');
const end=html.indexOf("node('stockArchivedReview').addEventListener('click',stockManageOpen)",begin);
assert.ok(begin>=0&&end>begin,'A revisão e o estorno em lote devem existir');
const functions=html.slice(begin,end);
assert.match(sql,/SECURITY INVOKER/);
assert.match(sql,/REVOKE ALL ON FUNCTION public\.ew_transferencias_nfe_conciliadas\(uuid\) FROM PUBLIC,anon,authenticated/);
assert.match(sql,/n\.estornado_em IS NULL/);
assert.match(sql,/sum\(m\.quantidade_delta\)<>0/);
assert.match(sql,/count\(DISTINCT m\.obra_id\)<>1/);
assert.match(sql,/count\(DISTINCT m\.local_estoque\)<>2/);
assert.match(sql,/sum\(m\.quantidade_delta\)<>0/);
assert.match(sql,/m\.origem IN \('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL'\)/);
assert.match(sql,/v_conciliadas:=public\.ew_transferencias_nfe_conciliadas\(p_obra_id\)/);
assert.match(sql,/'movimentos_pendentes',v_mov_abertos/);
assert.match(sql,/'transferencias_nfe_conciliadas',v_conciliadas/);
assert.match(sql,/'estornados',0/);
assert.match(sql,/'conciliados',v_conciliadas/);
assert.match(sql,/'saldo_zerado_sem_novos_lancamentos',true/);
assert.ok(sql.indexOf("IF v_conciliadas>0 THEN")<sql.indexOf("if exists(select 1 from public.ew_nfe_recebimentos n where n.obra_id=p_obra_id)"),
 'A reconciliação auditada deve preceder o bloqueio histórico de NF');
assert.match(html,/EWGEST <strong>· v46\.17<\/strong>/);

function context({serverCount=4,localCount=4,serverAfter=4}={}){
 const elements=new Map(),requests=[],confirms=[];
 const el=id=>{
  if(!elements.has(id))elements.set(id,{
   value:'',textContent:'',innerHTML:'',disabled:false,title:'',
   classList:{add(){},remove(){},toggle(){}},
   removeAttribute(){},setAttribute(){},scrollIntoView(){}
  });
  return elements.get(id);
 };
 const env={
  matIsAdmin:()=>true,
  stockLocais:[{obra_id:'obra-demo'}],
  works:[{id:'obra-demo',nome:'Obra fictícia',codigo:'CEM-TESTE'}],
  node:el,
  stockReversalBalances:()=>({movimentos:8,pendentes:localCount,saldos:[]}),
  stockReverseDescricaoMaterial:()=>({cabecalho:'Perfil fictício',detalhes:''}),
  stockReverseHistoryRender:()=>{},
  escapeHTML:x=>String(x),
  matFormat:x=>String(x),
  ensureSession:async()=>{},
  request:async(path,args)=>{
   requests.push({path,args});
   if(path.endsWith('/ew_inspecionar_reversao_obra'))return {
    motivos:[],resumo:{transferencias_nfe_conciliadas:requests.length===1?serverCount:serverAfter}};
   if(path.endsWith('/ew_estornar_estoque_obra'))return {estornados:0,conciliados:4};
   throw new Error('RPC inesperada '+path);
  },
  window:{confirm:msg=>(confirms.push(msg),true)},
  currentCompany:{id:'empresa-ficticia'},
  session:{access_token:'JWT-FICTICIO'},
  crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},
  abrirEstoque:async()=>{},
  stockReverseFechar:()=>{},
  stockManageRender:()=>{},
  stockReverseSelectedWorkId:null,
  stockReverseReady:false,
  stockReverseConciliadas:0,
  stockReverseHistoryLimit:60,
  stockReverseBalancesLimit:70,
 };
 vm.createContext(env);
 vm.runInContext(functions+';globalThis.verEstado=()=>({stockReverseConciliadas,stockReverseReady});',env);
 return {env,el,requests,confirms};
}
const v=context();
await v.env.stockReverseRevisar('obra-demo');
assert.equal(v.env.verEstado().stockReverseConciliadas,4);
assert.equal(v.env.verEstado().stockReverseReady,false,'Movimentos individuais não podem ser invertidos');
assert.equal(v.el('stockReverseApply').disabled,false);
assert.equal(v.el('stockReverseApply').textContent,'Registrar conciliação (saldo zero)');
assert.match(v.el('stockReverseMessage').textContent,/nenhum lançamento de estoque será criado/);
v.el('stockReverseReason').value='Estorno físico conferido e saldo zero';
await v.env.stockReverseExecutar();
assert.equal(v.requests.filter(x=>x.path.endsWith('ew_estornar_estoque_obra')).length,1);
assert.match(v.confirms[0],/Nenhum saldo será alterado/);
assert.match(v.el('stockManageStatus').textContent,/nenhum movimento novo foi criado/);

const alterado=context({serverCount:4,serverAfter:0});
await alterado.env.stockReverseRevisar('obra-demo');
alterado.el('stockReverseReason').value='Conferência técnica, ajuste divergente';
await alterado.env.stockReverseExecutar();
assert.equal(alterado.requests.filter(x=>x.path.endsWith('ew_estornar_estoque_obra')).length,0,
 'Se a reconciliação mudar entre leitura e envio, recusar a operação');
assert.match(alterado.el('stockReverseMessage').textContent,/A situação das transferências mudou/);

const normal=context({serverCount:0});
await normal.env.stockReverseRevisar('obra-demo');
assert.equal(normal.el('stockReverseApply').textContent,'Estornar todos os lançamentos sem estorno',
 'Conservar o fluxo usual quando a conciliação não se aplica');
assert.equal(normal.env.verEstado().stockReverseReady,true);
console.log('OK v46.11: conciliação saldo zero, dupla confirmação, impedimento de corrida e fluxo normal.');
