import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const read=path=>readFileSync(fileURLToPath(new URL(path,import.meta.url)),'utf8');
const html=read('../app.html');
const js=read('../assets/relatorios-obras.js');
const css=read('../assets/relatorios-obras.css');
const sql=read('../database/proposals/20261122_materiais_diretos_romaneio_v4617.sql');
const protect=read('../database/proposals/20261122_material_direto_bloquear_estorno_v4617.sql');
assert.doesNotThrow(()=>new Function(js));
for(const token of ['value="liberacoes"','value="expedicao"','value="aluminio"',
 'id="reportFullPeriod"','id="reportWorkScope"','id="reportWorkChecks"',
 'data-report-stock="recebimento"','data-report-stock="producao"',
 'data-report-stock="galpoes"','data-report-stock="obras"',
 'data-report-stock="direto"','data-report-stock="outros"',
 'relatorios-obras.js?v=20261125a','relatorios-obras.css?v=20261122b']){
 assert.ok(html.includes(token),'Falta componente no relatório: '+token);
}
assert.ok(js.includes("async function liberacoes(ctx)")&&
 js.includes("async function expedicao(ctx)")&&js.includes("async function aluminio(ctx)"));
assert.ok(js.includes("if(el('reportFullPeriod').checked)return true"),
 'Todo o período deve ignorar qualquer filtro de data');
assert.ok(js.includes("ctx.obraIds.has(f.obra_id)"),
 'Consolidação de faturamento por múltiplas obras');
assert.ok(js.includes("classificacao(m)"),'Flags do estoque precisam filtrar dados');
assert.ok(js.includes("m.origem==='SAIDA_OBRA'"),
 'Saída direta precisa aparecer no relatório de estoque');
assert.match(js,/PLANO_CORTE.*PLANO_CORTE_LOTE.*SAIDA_OBRA/s,
 'Perfil entregue à produção e entregue direto para obra entram no peso');
assert.ok(js.includes("areaLinha(x.i,partes)"),'Área expedida deve considerar marco e folhas, inclusive histórico');
assert.ok(css.includes('.reportsChoices'),'Filtros de seleção de obras precisam da grade');
assert.match(html,/function carregarMateriaisDisponiveisRomaneio\(\)/,
 'Romaneio precisa carregar saldos reais');
assert.ok(html.includes('variacao_id:mat.varId')&&html.includes('local_estoque:mat.local'),
 'Linha de material precisa indicar saldo da obra e do galpão');
assert.ok(sql.includes("'SAIDA_OBRA'")&&
 sql.includes('ew_romaneios_materiais_saidas')&&
 sql.includes("origem,operacao_id,observacao,usuario_id,local_estoque")&&
 sql.includes("v_available<v_qty"),
 'Emissão tem de baixar saldo e impedir negativo');
assert.ok(sql.includes("Somente ADM ou almoxarife")&&
 sql.includes("v_material_tipo='perfil'"),
 'Segurança por usuário e variante de material');
assert.ok(sql.includes("estorno_movimento_id")&&
 sql.includes("Devolução física confirmada"),
 'Cancelamento deve registrar devolução');
assert.ok(protect.includes("Cancele o romaneio e confirme a devolução física"));
const readOnlyReports=js.replace(/request\('\/rest\/v1\/rpc\/ew_historico_numeracao_romaneios',\{method:'POST',token:session\.access_token,body:\{[\s\S]*?\}\}\)/g,'READ_ONLY_RPC');
assert.doesNotMatch(readOnlyReports,/\/rest\/v1\/rpc\/|method\s*:\s*'POST'/,
 'Relatórios continuam somente leitura');
console.log('OK v46.20: período total, filtros combináveis, relatórios e saídas diretas com vínculo auditável.');
