// EWGEST v46.21 — verificações estáticas de integração da UI (sem banco).
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const html=readFileSync(new URL('../app.html',import.meta.url),'utf8');
const js=readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8');
const sql=readFileSync(new URL('../database/proposals/20261123_compras_locais_estoque_v4621.sql',import.meta.url),'utf8');
const css=readFileSync(new URL('../assets/compras-estoque.css',import.meta.url),'utf8');
assert.doesNotThrow(()=>new Function(js),'Novo JavaScript contém erro de sintaxe');
for(const id of ['navCompras','compras','comprasConteudo','comprasTabSolicitacao','comprasTabCotacao',
'comprasTabPedido','ewComprasRecebimento','ewEstoqueEmpresaPainel','stockCreateCompanyLocal']){
 assert.match(html,new RegExp('id="'+id+'"'),'ID da interface ausente: '+id);
}
for(const script of ['compras-estoque.js','compras-estoque.css'])assert.ok(html.includes(script));
for(const call of ['ew_compras_criar_solicitacao','ew_compras_criar_cotacao','ew_compras_criar_pedido',
'ew_compras_receber_pedido','ew_compras_criar_local_empresa']) {
 assert.ok(js.includes(call)&&sql.includes(call),'RPC não vinculada à UI: '+call);
}
for(const guard of ['ew_exigir_sessao_atual','ew_pode','for update','on conflict','quantidade','operacao_id'])
 assert.ok(sql.toLowerCase().includes(guard.toLowerCase()),'Guarda esperada: '+guard);
assert.match(sql,/row level security/);
assert.match(sql,/grant select/);
assert.match(sql,/estoque.gerenciar_locais/);
assert.match(sql,/ew_compras_solic_destino/);
assert.match(sql,/ew_compras_pedido_destino/);
assert.match(sql,/origem,operacao_id,observacao,usuario_id,local_estoque/);
assert.match(css,/ewComprasTable/);
// Cenário matemático ilustrativo; NÃO é teste real de RPC/transação.
const pedidas=[10,6],jaRecebidas=[4,0],agora=[3,2];
const saldos=pedidas.map((total,i)=>total-jaRecebidas[i]);
assert.deepEqual(saldos,[6,6]);
assert.deepEqual(saldos.map((s,i)=>s-agora[i]),[3,4]);
assert.ok(saldos.every((s,i)=>agora[i]<=s));
assert.equal(saldos[0]<7,true);

const nfUi=readFileSync(new URL('../assets/compras-conciliacao-nfe.js',import.meta.url),'utf8');
const empUi=readFileSync(new URL('../assets/compras-nota-empresa.js',import.meta.url),'utf8');
const nfSql=readFileSync(new URL('../database/proposals/20261124_compras_conciliacao_nfe_v4621.sql',import.meta.url),'utf8');
const empSql=readFileSync(new URL('../database/proposals/20261124_compras_nota_empresa_v4621.sql',import.meta.url),'utf8');
const estornoSql=readFileSync(new URL('../database/proposals/20261124_compras_estorno_recebimento_v4621.sql',import.meta.url),'utf8');
const transSql=readFileSync(new URL('../database/proposals/20261124_compras_transferencias_locais_v4621.sql',import.meta.url),'utf8');
assert.doesNotThrow(()=>new Function(nfUi),'Conciliação fiscal possui JS inválido');
const nfTestWindow={};
const {runInNewContext:runFiscal}=await import('node:vm');
runFiscal(nfUi,{window:nfTestWindow,Intl});
const nfFunctions=nfTestWindow.ewComprasNfe;
assert.equal(nfFunctions.quantityAsInvoice({unidade:'BARRA',comprimento_mm:6000},2,'MT'),12,
 'Duas barras de 6m equivalem a 12 metros fiscais.');
assert.equal(nfFunctions.quantityAsInvoice({unidade:'BARRA',comprimento_mm:6500},1,'M'),6.5,
 'Comprimento deve considerar a dimensão real da barra, não o comprimento padrão.');
assert.equal(nfFunctions.quantityAsInvoice({unidade:'BARRA',comprimento_mm:6000},1,'BARRA'),1);
assert.equal(nfFunctions.quantityAsInvoice({unidade:'BARRA',comprimento_mm:6000},1,'KG'),null);
assert.equal(nfFunctions.quantityAsInvoice({unidade:'KG'},0.725,'KG'),0.725);
assert.equal(nfFunctions.quantityAsInvoice({unidade:'PC'},3,'UN'),3);
assert.equal(nfFunctions.quantityAsInvoice({unidade:'BARRA',comprimento_mm:0},1,'MT'),null);
assert.equal(nfFunctions.compatible({variacao_id:'v'},{perfil_id:'pf'},
  [{id:'v',tipo:'perfil',perfil_id:'pf'}],'aluminio'),true);
assert.equal(nfFunctions.compatible({variacao_id:'v'},{perfil_id:'pf'},
  [{id:'v',tipo:'perfil',perfil_id:'pf'}],'acessorios'),false);
assert.ok(nfUi.includes('const selectedByItem=new Map()')&&nfUi.includes('qty+(fiscalUsed.get(itemId)||0)'),
 'A UI deve somar linhas recebidas por item da nota, incluindo o saldo já conciliado.');
assert.ok(nfUi.includes("despesa_item_id:'in.('")&&nfUi.includes("recebimento_id:'in.('"),
 'A consulta de vínculos deve ser limitada aos documentos envolvidos, não a toda empresa.');

assert.doesNotThrow(()=>new Function(empUi),'Nota empresarial possui JS inválido');
for(const path of ['compras-conciliacao-nfe.js','compras-nota-empresa.js'])assert.ok(html.includes(path),'Script fiscal não carregado: '+path);
for(const [fn,file,ui] of [
 ['ew_compras_vincular_nfe_pedido',nfSql,nfUi],
 ['ew_compras_desvincular_nfe',nfSql,nfUi],
 ['ew_compras_registrar_nota_empresa',empSql,empUi],
 ['ew_compras_cancelar_nota_empresa',empSql,empUi]
]) assert.ok(file.includes(fn)&&ui.includes(fn),'Rotina fiscal não conectada: '+fn);
for(const guard of ['ew_compras_proteger_recebimento_nfe','ew_compras_proteger_cancelamento_nfe','ew_compras_proteger_estorno_recebimento_conciliado'])
 assert.ok(nfSql.includes(guard),'Guarda fiscal ausente: '+guard);
assert.ok(empSql.includes('ew_compras_proteger_estorno_rec_empresa'));
assert.ok(nfSql.toLowerCase().includes('row level security')&&empSql.toLowerCase().includes('row level security'));
assert.ok(!/INSERT\s+INTO\s+public\.(?:ew_estoque_obras_movimentos|ew_compras_estoque_empresa)\b/i.test(nfSql),
 'Conciliação de NF não pode criar estoque físico');
assert.ok(!/INSERT\s+INTO\s+public\.(?:ew_estoque_obras_movimentos|ew_compras_estoque_empresa)\b/i.test(empSql),
 'Nota empresarial não pode criar estoque físico');
for(const file of ['10_fluxo_pedidos_transferencias_rollback.sql','20_conciliacao_nfe_rollback.sql','30_nota_estoque_empresa_rollback.sql','40_migracao_estoque_legado_rollback.sql','50_idempotencia_operacoes_rollback.sql','60_cancelamentos_comerciais_rollback.sql','70_permissoes_cancelamento_rollback.sql','80_estorno_ordenado_nfe_rollback.sql','90_estorno_transferencias_sucessivas_rollback.sql','100_quantidades_mt_kg_fracionadas_rollback.sql']){
 const txt=readFileSync(new URL('../tests/compras_v4621/'+file,import.meta.url),'utf8');
 assert.ok(txt.includes('RAISE NOTICE')||txt.includes('raise notice'),'Cenário de SQL incompleto: '+file);
}

const proof=readFileSync(new URL('../assets/compras-comprovante-transferencia.js',import.meta.url),'utf8');
assert.doesNotThrow(()=>new Function(proof));
assert.ok(html.includes('compras-comprovante-transferencia.js'));
assert.ok(js.includes('data-ew-transfer-print')&&js.includes('window.ewTransferReceipt.imprimir'));
assert.ok(!/request\s*\(|apiGet\s*\(|\/rest\/v1\/rpc\//.test(proof),
 'A impressão de comprovante é apenas consulta, sem API ou movimentação.');
const {runInNewContext}=await import('node:vm');
const printed={};
runInNewContext(proof,{window:printed,Intl});
const movement={
 id:'11111111-2222-4333-8444-555555555555',empresa_id:'empresa',
 origem_tipo:'EMPRESA',origem_id:'origem',destino_tipo:'OBRA',destino_id:'destino',
 origem_galpao:'IMBIRIBEIRA',destino_galpao:'AFOGADOS',
 variacao_id:'produto',quantidade:4,unidade:'MT',
 motivo:'Transferência <script>alert(1)</script>',
 criado_em:'2026-11-24T10:30:00Z',estornado_em:null
};
const doc=printed.ewTransferReceipt.documentHtml(movement,{
 empresa:'GVG & Estoque',
 locais:[{value:'EMPRESA:origem',label:'Empresa · ESTOQUE GVG'},
  {value:'OBRA:destino',label:'Obra · CASA BOA VIAGEM'}],
 materiais:[{id:'produto',label:'FIT2130PTO · fita vedadora'}]});
assert.match(doc,/VIA ORIGEM/);
assert.match(doc,/VIA DESTINO/);
assert.match(doc,/4 MT/);
assert.match(doc,/SEM nova movimentação/i); // Ajustar se o texto da renderização mudar
assert.ok(!doc.includes('<script>alert(1)</script>'));
assert.match(doc,/&lt;script&gt;/);
assert.match(doc,/Não gera romaneio|não gera romaneio/);
console.log('PASS: comprovante em duas vias, sem mutação e com conteúdo escapado.');

const cancelSql=readFileSync(new URL('../database/proposals/20261124_compras_cancelamentos_comerciais_v4621.sql',import.meta.url),'utf8');
for(const fn of ['ew_compras_cancelar_solicitacao','ew_compras_cancelar_cotacao','ew_compras_cancelar_pedido']){
 assert.ok(cancelSql.includes(fn)&&js.includes(fn),'Cancelamento sem vínculo entre banco e UI: '+fn);
}
assert.ok(js.includes('bindCancelButtons()'),'Botões de cancelamento precisam funcionar.');
assert.ok(js.includes("q.status!=='CANCELADA'"),'Cotação cancelada não deve surgir como disponível.');
assert.ok(js.includes("p.status==='ABERTO'&&!receipts.some"),'Pedido com histórico não deve oferecer cancelamento direto.');
assert.ok(cancelSql.includes('compras_recebimentos r where r.pedido_id=v_p.id'),'Cancelamento de pedido deve conferir histórico físico.');
assert.ok(cancelSql.includes('ew_compras_exigir_cotacao_ativa'),'Pedido precisa bloquear cotação cancelada no servidor.');
const cancelCase=readFileSync(new URL('../tests/compras_v4621/60_cancelamentos_comerciais_rollback.sql',import.meta.url),'utf8');
assert.ok(cancelCase.includes('PASS: cancelamentos'),'Cenário funcional de cancelamento não incluído.');
const rolesCase=readFileSync(new URL('../tests/compras_v4621/70_permissoes_cancelamento_rollback.sql',import.meta.url),'utf8');
assert.ok(rolesCase.includes('PASS: níveis 03,04,05,06,07,08'), 'Teste de permissões por nível de acesso está ausente.');
assert.ok(cancelSql.includes('first')||cancelSql.includes('select * into v_s from public.ew_compras_solicitacoes'),
 'O cancelamento precisa validar solicitação e cotação.');
assert.ok(!/delete\s+from\s+public\.ew_compras_/.test(cancelSql.toLowerCase()),
 'Cancelamento de compras não pode apagar registros de auditoria.');
console.log('PASS: cancelamentos comerciais, permissões e proteção de histórico rastreados.');


const guardSource=js.slice(js.indexOf('const validQty='),js.indexOf('const parseMoney='));
assert.ok(guardSource.startsWith('const validQty='));
const checkQuantity=new Function(guardSource+'\nreturn validQty;')();
assert.equal(checkQuantity(0.725,'KG'),true,'KG permite até três decimais');
assert.equal(checkQuantity(0.0005,'KG'),false,'KG rejeita quarta casa decimal');
assert.equal(checkQuantity(1.25,'KG'),true);
assert.equal(checkQuantity(0.5,'MT'),false,'MT inteiro é invariante da produção');
assert.equal(checkQuantity(1,'MT'),true);
assert.equal(checkQuantity(1.25,'BARRA'),false,'BARRA permanece unidade inteira');
assert.ok(js.includes("qty.step=v.unidade==='KG'?'0.001':'1';"));
assert.ok(js.includes("qty.min=v.unidade==='KG'?'0.001':'1';"));
assert.ok(js.includes("$('ewTransQty').step=['BARRA','PC','PR','CJ','UN','MT'].includes(p.unidade)?'1':'0.001';"));
assert.ok(estornoSql.includes("m.origem<>'ESTORNO'"),'Estorno de obra não pode bloquear outro estorno');
assert.ok(estornoSql.includes("m.origem not in ('ESTORNO_PEDIDO','ESTORNO_TRANSFERENCIA')"),
 'Estorno de local empresarial não pode bloquear outro estorno');
assert.ok(transSql.includes("m.origem<>'ESTORNO'"),'Transferência estornada não bloqueia outra');
assert.ok(estornoSql.indexOf("where id=v_rec.pedido_id for update") < estornoSql.indexOf("where r.id=p_recebimento_id for update"),
 'Estorno deve travar pedido antes de recebimento');
console.log('PASS: guardas para MT inteiro, KG fracionado, ordem de locks e estornos sucessivos.');

console.log('PASS: Compras, conciliação de NF-e e nota empresarial — sintaxe, referências, RLS, contratos e ausência de entradas físicas na conciliação.');


const paginationSource=js.slice(js.indexOf('async function readAllRows('),js.indexOf('const pendingOps=new Map();'));
assert.ok(paginationSource.startsWith('async function readAllRows('));
const fixtures=Array.from({length:1251},(_,i)=>({id:String(i).padStart(6,'0')}));
let pageCalls=[];
const paged=new Function('apiGet',paginationSource+'\nreturn readAllRows;')(async(table,params)=>{
 pageCalls.push(params);return fixtures.slice(Number(params.offset),Number(params.offset)+Number(params.limit));
});
assert.deepEqual(await paged('receipts',{empresa_id:'eq.test'}),fixtures);
assert.equal(pageCalls.length,3);
assert.ok(pageCalls.every(p=>p.order==='id.asc'&&p.empresa_id==='eq.test'));
const duplicated=new Function('apiGet',paginationSource+'\nreturn readAllRows;')(async(table,params)=>
 Number(params.offset)===0?fixtures.slice(0,500):[fixtures[0]]);
await assert.rejects(()=>duplicated('receipts',{}),/Consulta mudou/);
console.log('PASS: paginação de histórico com 1251 registros e rejeição de IDs duplicados.');

const filterStart=js.indexOf('function purchaseOptions(');
const filterEnd=js.indexOf('function requestOptions(',filterStart);
const filterPurchases=new Function('productLabel',js.slice(filterStart,filterEnd)+'\nreturn purchaseOptions;')(v=>v.nome);
const plannedCatalog=[{id:'p',nome:'PERFIL P',tipo:'perfil',comprimento_mm:6000,unidade:'BARRA'},{id:'a',nome:'ACESSÓRIO A',tipo:'acessorio',comprimento_mm:null,unidade:'PC'},{id:'e',nome:'EXTRA',tipo:'perfil',comprimento_mm:6000,unidade:'BARRA'}];
const plannedNeeds=[{variacao_id:'p',comprimento_mm:6000,unidade:'BARRA',faltante:0},{variacao_id:'p',comprimento_mm:4000,unidade:'BARRA',faltante:2},{variacao_id:'a',comprimento_mm:null,unidade:'PC',faltante:1}];
const filteredKeys=(kind,extra,category='',search='',needs=plannedNeeds)=>filterPurchases(plannedCatalog,needs,kind,extra,category,search).map(v=>v.key).sort();
assert.deepEqual(filteredKeys('obra',false),['a|','p|4000']);
assert.deepEqual(filteredKeys('obra',false,'perfil'),['p|4000']);
assert.deepEqual(filteredKeys('obra',false,'acessorio'),['a|']);
assert.deepEqual(filteredKeys('obra',false,'','acessorio'),['a|']);
assert.deepEqual(filteredKeys('obra',true),['a|','e|6000','p|4000','p|6000']);
assert.deepEqual(filteredKeys('empresa',false,'','',[]),['a|','e|6000','p|6000']);
console.log('OK: compras filtram previsão, atendimento, categoria, busca e estoque independente.');
