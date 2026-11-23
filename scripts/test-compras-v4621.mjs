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
console.log('PASS: sintaxe JS, contratos da interface/RPC, guardas estáticas e cálculo de saldos (mock).');
