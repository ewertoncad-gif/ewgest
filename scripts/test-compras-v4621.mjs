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
assert.ok(nfSql.includes('row level security')&&empSql.includes('ROW LEVEL SECURITY'));
assert.ok(!/INSERT\s+INTO\s+public\.(?:ew_estoque_obras_movimentos|ew_compras_estoque_empresa)\b/i.test(nfSql),
 'Conciliação de NF não pode criar estoque físico');
assert.ok(!/INSERT\s+INTO\s+public\.(?:ew_estoque_obras_movimentos|ew_compras_estoque_empresa)\b/i.test(empSql),
 'Nota empresarial não pode criar estoque físico');
for(const file of ['10_fluxo_pedidos_transferencias_rollback.sql','20_conciliacao_nfe_rollback.sql','30_nota_estoque_empresa_rollback.sql']){
 const txt=readFileSync(new URL('../tests/compras_v4621/'+file,import.meta.url),'utf8');
 assert.ok(txt.includes('RAISE NOTICE')||txt.includes('raise notice'),'Cenário de SQL incompleto: '+file);
}
console.log('PASS: Compras, conciliação de NF-e e nota empresarial — sintaxe, referências, RLS, contratos e ausência de entradas físicas na conciliação.');

