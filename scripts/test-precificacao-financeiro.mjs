import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const app=readFileSync(fileURLToPath(new URL('../app.html',import.meta.url)),'utf8');
const start=app.indexOf('function finPrecoSugerido(linha,tipo,unidades,qtdLancamento,qtdFaturada,valorFaturadoCentavos){');
const end=app.indexOf('function finRenderFaturaveis(){',start);
assert.ok(start>=0&&end>start,'Função de sugestão financeira está presente');
const sugerir=new Function(app.slice(start,end)+'\nreturn finPrecoSugerido;')();
const ea2={fabricacao_centavos:154560,instalacao_centavos:66240};
assert.equal(sugerir(ea2,'fabricacao',1,0.75,0,0),1545.6,
 'EA2 fabricação: valor integral 1.545,60, expedição 75% sugere 1.159,20');
assert.equal(Math.round(0.75*sugerir(ea2,'fabricacao',1,0.75,0,0)*100)/100,1159.20);
assert.equal(sugerir(ea2,'instalacao',1,0.75,0,0),662.4,
 'EA2 instalação: valor integral 662,40, expedição 75% sugere 496,80');
assert.equal(Math.round(0.75*sugerir(ea2,'instalacao',1,0.75,0,0)*100)/100,496.80);
assert.equal(sugerir({fabricacao_centavos:10000},'fabricacao',3,1,2,6666),33.34,
 'Última das 3 unidades deve sugerir R$ 33,34 para fechar R$ 100,00');
assert.equal(sugerir({fabricacao_centavos:10000},'fabricacao',3,1,0,0),33.3333,
 'Primeira unidade de 3 divide em quatro decimais sem arredondar o item total');
assert.equal(sugerir(null,'fabricacao',1,0.75,0,0),null,
 'Obra antiga não pode inventar preço individual');
assert.equal(sugerir({fabricacao_centavos:0},'fabricacao',1,1,0,0),null,
 'Categoria sem orçamento para fabricação não sugere cobrança');
assert.ok(app.includes("apiGet('ew_precificacao_revisoes',{select:'id,versao,aprovado_em")&&
 app.includes("apiGet('ew_precificacao_revisoes_itens',{")&&
 app.includes("estado:'eq.aprovada'")&&
 app.includes("revisao_id:'eq.'+precificacoes[0].id"),
 'Somente a revisão aprovada mais recente da obra serve de referência');
assert.ok(app.includes("apiGet('ew_precificacao_revisoes_categorias',{")&&
 app.includes("precificacaoCategorias:precoCategorias||[]")&&
 app.includes("Precificação aprovada · revisão ")&&
 app.includes("moedaM2(fab)")&&app.includes("moedaM2(inst)"),
 'Financeiro deve mostrar histórico por categoria, m² e revisão aprovada');
assert.ok(app.includes("billedValues={fabricacao:new Map(),instalacao:new Map()}")&&
 app.includes("Math.round(Number(x.valor_total||0)*100)")&&
 app.includes("row.dataset.autoPrice='0'")&&
 app.includes("finPrecoM2Sugerido(precificacao,tipo,e.quantidade,areaUnit,areaMax,ja"),
 'Descontar histórico faturado e aceitar edição manual do preço sugerido');
assert.ok(app.includes("const teto=finState.precificacao?")&&
 app.includes("Number(finState.precificacao[tipo+'_distribuida_centavos'])/100"),
 'Frontend valida novo teto de faturamento, preservando orçamento legado');
const sql=readFileSync(fileURLToPath(new URL(
 '../database/proposals/20261122_precificacao_tetos_faturamento_v469.sql',import.meta.url)),'utf8');
for(const required of [
 'public.ew_precificacao_revisoes',
 "estado='aprovada'",
 'ORDER BY versao DESC LIMIT 1',
 "IF NOT FOUND THEN",
 "public.ew_obra_orcamento",
 "v_total_invoiced+v_quantidade>v_shipped",
 "ue.perfil='administrador'",
 "p_categoria='instalacao' AND p_instalacao_confirmada",
 "v_faturado+v_total>v_budget"
])assert.ok(sql.includes(required),'Validação de faturamento removida: '+required);
assert.ok(!sql.includes("SECURITY DEFINER"),
 'Preservar modo de autorização da RPC atual (invoker)');
console.log('OK: integração financeira v46.9 — preços aprovados, 75% do EA2, 3 unidades com centavos, tetos e edição.');
