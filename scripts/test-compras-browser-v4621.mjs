// Smoke test EWGEST v46.21 — interface de conciliação fiscal no Chromium.
// Todos os dados e respostas RPC são sintéticos. Não acessa Supabase nem produção.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {chromium} from 'playwright';

const browser=await chromium.launch({headless:true});
try{
 {
 const receiving=await browser.newPage();
 const appSource=readFileSync(new URL('../app.html',import.meta.url),'utf8');
 const nav=appSource.slice(appSource.indexOf('<button id="navRecebimento"'),appSource.indexOf('<button id="navEnviarNotas"'));
 const section=appSource.slice(appSource.indexOf('<section id="recebimento"'),appSource.indexOf('<section id="financeiro"'));
 await receiving.setContent('<html><body>'+nav+section+'</body></html>');
 const css=appSource.slice(appSource.indexOf('    #recebimento[data-modo]'),appSource.indexOf('    .workspaceSubnav{'));
 await receiving.addStyleTag({content:'.hidden{display:none!important}'+css});
 await receiving.evaluate(()=>{
  window.node=id=>document.getElementById(id);
  window.temPermissao=()=>true;
  window.escapeHTML=v=>String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  window.finMoney=v=>Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
  window.finEstornarRecebimentoFisico=id=>{window._undo=id;};
  window.finState={obraId:'obra',despesas:[{id:'nf',numero_documento:'555',fornecedor:'Fornecedor teste',valor:100,status:'aprovada'}],historicalReceiptItems:[{id:'i1',despesa_id:'nf',codigo_fornecedor:'GN096',descricao:'Perfil'},{id:'i2',despesa_id:'nf',codigo_fornecedor:'CT007',descricao:'Perfil'}],stockReceipts:[{id:'r1',despesa_item_id:'i1',quantidade:1,unidade:'BARRA',local_estoque:'IMBIRIBEIRA'},{id:'r2',despesa_item_id:'i2',quantidade:2,unidade:'BARRA',local_estoque:'IMBIRIBEIRA',estornado_em:'2026-11-25'}]};
  node('recebimento').classList.remove('hidden');node('navRecebimentoSubmenu').classList.remove('hidden');
  node('recebimentoWork').append(new Option('Obra teste','obra'));node('recebimentoWork').value='obra';
 });
 const fn=(a,b)=>appSource.slice(appSource.indexOf(a),appSource.indexOf(b,appSource.indexOf(a)));
 await receiving.addScriptTag({content:fn('function recebimentoSelecionarModo(modo){','async function abrirRecebimento(')+fn('function recebimentoRenderHistoricoNotas(){','function finRenderRecebimentos(){')});
 await receiving.evaluate(()=>{document.querySelectorAll('[data-recebimento-modo]').forEach(b=>b.onclick=()=>recebimentoSelecionarModo(b.dataset.recebimentoModo));recebimentoRenderHistoricoNotas();});
 await receiving.locator('[data-recebimento-modo="historico"]').click();
 assert.equal(await receiving.locator('#recebimentoPaginaTitulo').innerText(),'Histórico e estornos');
 assert.equal(await receiving.locator('#recebimentoWork').inputValue(),'obra');
 assert.ok(await receiving.locator('#finExpensePanel').isHidden());
 assert.equal(await receiving.locator('.recebimentoNotaCard').count(),1);
 assert.equal(await receiving.locator('.recebimentoNotaCard tbody tr').count(),2);
 assert.equal(await receiving.locator('#recebimentoHistoricoNotas .finReceiveUndo').count(),1);
 await receiving.locator('#recebimentoHistoricoBusca').fill('sem correspondência');
 assert.ok(await receiving.locator('.recebimentoNotaCard').isHidden());
 await receiving.locator('#recebimentoHistoricoBusca').fill('GN096');
 await receiving.locator('#recebimentoHistoricoNotas .finReceiveUndo').click();
 assert.equal(await receiving.evaluate(()=>window._undo),'r1');
 await receiving.locator('[data-recebimento-modo="manual"]').click();
 assert.ok(await receiving.locator('#recebimentoHistoricoNotas').isHidden());
 assert.ok(await receiving.locator('#finExpensePanel').isVisible());
 assert.equal(await receiving.locator('#recebimentoWork').inputValue(),'obra');
 assert.equal(await receiving.locator('[data-recebimento-modo="producao"]').count(),0);
 await receiving.close();
 console.log('PASS submenu de recebimento, histórico por NF, busca e estorno único');
 const stockNav=appSource.slice(appSource.indexOf('<button id="navStock"'),appSource.indexOf('<button id="navFinanceiro"'));
 const stockSection=appSource.slice(appSource.indexOf('<section id="stock"'),appSource.indexOf('<section id="cemImport"'));
 const stockPage=await browser.newPage();
 await stockPage.setContent('<html><body>'+stockNav+stockSection+'</body></html>');
 await stockPage.addStyleTag({content:'.hidden{display:none!important}'+css});
 await stockPage.evaluate(()=>{
  window.node=id=>document.getElementById(id);window.ewLimparEntregasProducao=()=>{};
  node('stock').classList.remove('hidden');node('navStockSubmenu').classList.remove('hidden');
 });
 await stockPage.addScriptTag({content:fn('function stockSelecionarModo(modo){','function stockProducaoSelecionar(){')});
 await stockPage.evaluate(()=>document.querySelectorAll('[data-stock-modo]').forEach(b=>b.onclick=()=>stockSelecionarModo(b.dataset.stockModo)));
 await stockPage.locator('[data-stock-modo="producao"]').click();
 assert.equal(await stockPage.locator('#stockPaginaTitulo').innerText(),'Entrega à produção');
 assert.ok(await stockPage.locator('#stockProducaoWork').isVisible());
 assert.ok(await stockPage.locator('#stockMateriaisPanel').isHidden());
 await stockPage.locator('[data-stock-modo="transferencias"]').click();
 assert.ok(await stockPage.locator('#stockTransferPickLocal').isVisible());
 assert.ok(await stockPage.locator('#stockProducaoArea').isHidden());
 await stockPage.locator('[data-stock-modo="historico"]').click();
 assert.ok(await stockPage.locator('#stockHistoricoAbrir').isVisible());
 assert.ok(await stockPage.locator('#stockTransferPickLocal').isHidden());
 await stockPage.locator('[data-stock-modo="consulta"]').click();
 assert.ok(await stockPage.locator('#stockMateriaisPanel').isVisible());
 assert.ok(await stockPage.locator('#stockHistoricoAtalho').isHidden());
 await stockPage.close();
 console.log('PASS Estoque: consulta, transferências, entrega à produção e histórico separados');
 }
 const page=await browser.newPage({viewport:{width:390,height:844}});
 page.on('pageerror',e=>console.error('Browser pageerror:',e.message));
 await page.setContent('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"></head>'+
  '<body><div id="comprasMensagem"></div><main style="width:100%;max-width:100%">'+
  '<section id="ewComprasConciliacao"></section></main></body></html>');
 await page.addStyleTag({content:readFileSync(new URL('../assets/compras-estoque.css',import.meta.url),'utf8')});
 await page.addStyleTag({content:'html,body{box-sizing:border-box;margin:0;width:100%;max-width:100%}*{box-sizing:border-box}main{padding:12px}#ewComprasConciliacao{width:100%;max-width:100%}.ewComprasTableWrap{max-width:100%;overflow-x:auto}'});
 await page.evaluate(()=>{
  window.escapeHTML=value=>String(value??'').replace(/[&<>"']/g,x=>
   ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
  window.session={access_token:'MOCK_ONLY'};
  window._mock={noteQty:1,corporateNotes:[],rpcCalls:[],reloadCount:0,allow:true,idSequence:0};
  // about:blank do Playwright é origem opaca; randomUUID exige contexto seguro.
  // A função é nativa no site real (HTTPS); o teste usa ID sintético.
  if(typeof window.crypto?.randomUUID!=='function')
   Object.defineProperty(window.crypto,'randomUUID',{configurable:true,
    value:()=> '00000000-0000-4000-8000-'+String(++window._mock.idSequence).padStart(12,'0')});
  window.temPermissao=()=>window._mock.allow;
  window.ensureSession=async()=>window.session;
  window.request=async(path,opts)=>{
   window._mock.rpcCalls.push({path,body:opts?.body});
   return {id:'fake-success',repetida:false};
  };
  window.apiGet=async(table,filters)=>{
   const m=window._mock;
   switch(table){
    case 'ew_obra_despesas':
     return [{id:'note',numero_documento:'NF 001',fornecedor:'FORNECEDOR TESTE',
      categoria:'aluminio',valor:500,status:'aprovada',criado_em:'2026-11-24'}];
    case 'ew_compras_nfe_conciliacoes':return [];
    case 'ew_obra_despesas_itens':
     if(m.pauseFiscal)await new Promise(resolve=>{m.releaseFiscal=resolve});
     if(m.truncateFiscal)return Array.from({length:500},(_,i)=>({id:'truncated-'+i}));
     return [{id:'fi1',despesa_id:'note',perfil_id:'pf',acessorio_id:null,
      unidade:'BARRA',quantidade:m.noteQty,descricao:'Perfil 6000 mm'}];
    case 'ew_compras_nfe_vinculos':return [];
    case 'ew_compras_notas_empresa':return m.corporateNotes;
    case 'ew_compras_notas_empresa_itens':return [];
    default:throw Error('Acesso externo inesperado: '+table+' '+JSON.stringify(filters));
   }
  };
  window.ewCompras={abrir:async()=>{window._mock.reloadCount++}};
  window._ctx={
   empresa_id:'company',
   orders:[
    {id:'p',numero:10,obra_id:'work',local_empresa_id:null,fornecedor_id:'sup',
     status:'PARCIAL',itens:[{chave:'A',variacao_id:'v',unidade:'BARRA',
       comprimento_mm:6000,quantidade:3}]},
    {id:'pe',numero:11,obra_id:null,local_empresa_id:'loc',fornecedor_id:'sup',
     status:'PARCIAL',itens:[{chave:'E',variacao_id:'v',unidade:'BARRA',
       comprimento_mm:6000,quantidade:1}]}
   ],
   suppliers:[{id:'sup',nome:'FORNECEDOR TESTE'}],
   workNames:[{id:'work',nome:'CASA TESTE'}],
   localNames:[{id:'loc',nome:'ESTOQUE DA EMPRESA'}],
   variations:[{id:'v',tipo:'perfil',perfil_id:'pf',nome:'PERFIL P01'}],
   receipts:[
    {id:'r1',pedido_id:'p',criado_em:'2026-11-21',itens:[{chave:'A',quantidade:1}]},
    {id:'r2',pedido_id:'p',criado_em:'2026-11-22',itens:[{chave:'A',quantidade:1}]},
    {id:'re',pedido_id:'pe',criado_em:'2026-11-23',itens:[{chave:'E',quantidade:1}]}
   ]
  };
 });
 await page.addScriptTag({content:readFileSync(new URL('../assets/compras-nota-empresa.js',import.meta.url),'utf8')});
 await page.addScriptTag({content:readFileSync(new URL('../assets/compras-conciliacao-nfe.js',import.meta.url),'utf8')});
 await page.evaluate(()=>window.ewComprasNfe.render(document.querySelector('#ewComprasConciliacao'),window._ctx));
 await page.locator('#ewCompNFOrder').selectOption('p');
 await page.locator('#ewCompNFDoc').waitFor();
 await page.locator('#ewCompNFDoc').selectOption('note');
 await page.locator('[data-nf-receipt]').first().waitFor();
 assert.equal(await page.locator('[data-nf-receipt]').count(),2,'Esperadas duas entregas para mesma nota');
 assert.match(await page.locator('#ewCompNFItems').innerText(),/disponível 1 BARRA/i);
 for(const row of await page.locator('[data-nf-receipt]').all()){
  await row.locator('[data-nf-mark]').check();
  await row.locator('[data-nf-fiscal]').selectOption('fi1');
 }
 await page.locator('#ewCompNFForm button[type="submit"]').click();
 assert.match(await page.locator('#ewCompNFStatus').innerText(),/excede o saldo da nota/i);
 assert.equal((await page.evaluate(()=>window._mock.rpcCalls)).length,0,
  'UI não deve chamar RPC quando dois recebimentos superam NF de uma barra');
 await page.locator('[data-nf-receipt]').nth(1).locator('[data-nf-mark]').uncheck();
 await page.locator('#ewCompNFForm button[type="submit"]').click();
 await page.waitForFunction(()=>window._mock.rpcCalls.length===1,null,{timeout:7000});
 const first=await page.evaluate(()=>window._mock.rpcCalls[0]);
 assert.match(first.path,/ew_compras_vincular_nfe_pedido$/);
 assert.equal(first.body.p_vinculos.length,1);
 assert.equal(first.body.p_despesa_id,'note');
 assert.match(await page.locator('#comprasMensagem').innerText(),/estoque físico preservado/i);

 // Em uma segunda consulta a nota comporta duas entregas.
 await page.evaluate(()=>window._mock.noteQty=2);
 await page.locator('#ewCompNFDoc').selectOption('');
 await page.locator('#ewCompNFDoc').selectOption('note');
 await page.locator('[data-nf-receipt]').first().waitFor();
 for(const row of await page.locator('[data-nf-receipt]').all()){
  await row.locator('[data-nf-mark]').check();
  await row.locator('[data-nf-fiscal]').selectOption('fi1');
 }
 await page.locator('#ewCompNFForm button[type="submit"]').click();
 await page.waitForFunction(()=>window._mock.rpcCalls.length===2,null,{timeout:7000});
 const second=await page.evaluate(()=>window._mock.rpcCalls[1]);
 assert.equal(second.body.p_vinculos.length,2,'Duas entregas devem ser permitidas quando NF comporta duas barras');

 // A nota empresarial não pode alterar estoque e deve exigir igualdade de subtotais.
 await page.locator('#ewNfeEmpOrder').selectOption('pe');
 await page.locator('#ewNfeEmpForm').waitFor();
 await page.locator('#ewNfeEmpNumber').fill('NF EMP 123');
 await page.locator('#ewNfeEmpTotal').fill('120,50');
 await page.locator('[data-ew-emp-pick]').check();
 await page.locator('[data-ew-emp-amount]').fill('120,00');
 await page.locator('#ewNfeEmpForm button[type="submit"]').click();
 assert.match(await page.locator('#ewNfeEmpStatus').innerText(),/soma deve ser igual/i);
 assert.equal((await page.evaluate(()=>window._mock.rpcCalls)).length,2,'Valor errado não pode ser gravado');
 await page.locator('[data-ew-emp-amount]').fill('120,50');
 await page.locator('#ewNfeEmpForm button[type="submit"]').click();
 await page.waitForFunction(()=>window._mock.rpcCalls.length===3,null,{timeout:7000});
 const third=await page.evaluate(()=>window._mock.rpcCalls[2]);
 assert.match(third.path,/ew_compras_registrar_nota_empresa$/);
 assert.equal(third.body.p_valor_centavos,12050);
 assert.equal(third.body.p_itens[0].valor_total_centavos,12050);

 // Uma resposta atrasada não pode restaurar o formulário após limpar a nota.
 await page.locator('#ewCompNFDoc').selectOption('');
 await page.evaluate(()=>window._mock.pauseFiscal=true);
 await page.locator('#ewCompNFDoc').selectOption('note');
 await page.waitForFunction(()=>typeof window._mock.releaseFiscal==='function');
 await page.locator('#ewCompNFDoc').selectOption('');
 await page.evaluate(()=>{window._mock.pauseFiscal=false;window._mock.releaseFiscal()});
 await page.evaluate(()=>new Promise(resolve=>setTimeout(resolve,50)));
 assert.equal(await page.locator('#ewCompNFForm').count(),0,'Resposta obsoleta não pode reabrir a nota');
 // Uma resposta fiscal potencialmente truncada deve falhar antes de criar um formulário.
 await page.evaluate(()=>window._mock.truncateFiscal=true);
 await page.locator('#ewCompNFDoc').selectOption('note');
 await page.waitForFunction(()=>document.querySelector('#ewCompNFStatus').textContent.includes('limite de itens'));
 assert.equal(await page.locator('#ewCompNFForm').count(),0);
 assert.equal((await page.evaluate(()=>window._mock.rpcCalls)).length,3);
 await page.evaluate(()=>window._mock.truncateFiscal=false);

 const bounds=await page.evaluate(()=>({
  viewport:window.innerWidth,overflow:document.documentElement.scrollWidth,
  fiscalWidth:document.querySelector('#ewComprasConciliacao').getBoundingClientRect().width,
  offenders:[...document.querySelectorAll('body *')].filter(el=>
   el.getBoundingClientRect().right>window.innerWidth+2).slice(0,12)
   .map(el=>({tag:el.tagName,id:el.id,width:Math.round(el.getBoundingClientRect().width),
    right:Math.round(el.getBoundingClientRect().right)}))}));
 assert.ok(bounds.overflow<=bounds.viewport+2,'Interface mobile transbordou horizontalmente: '+JSON.stringify(bounds));
 await page.setViewportSize({width:1360,height:900});
 assert.ok(await page.locator('#ewNfeEmpOrder').isVisible());
 assert.ok(await page.locator('#ewCompNFOrder').isVisible());
 console.log('PASS Chromium: nota de obra, quantidade excedida bloqueada, 2 parciais válidos, nota empresa em centavos, mobile e desktop.');

 // Teste do módulo de recebimento real, com respostas sintéticas e saldo atualizado.
 const receiving=await browser.newPage({viewport:{width:390,height:844}});
 await receiving.setContent('<!doctype html><html><head><meta charset="utf-8"></head><body>'+
 '<button id="comprasTabSolicitacao"></button><button id="comprasTabCotacao"></button><button id="comprasTabPedido"></button>'+
 '<select id="recebimentoWork"><option value="obra1">Obra 1</option><option value="empresa:loc1">Empresa</option></select>'+
 '<main id="ewComprasRecebimento"></main></body></html>');
 await receiving.addStyleTag({content:readFileSync(new URL('../assets/compras-estoque.css',import.meta.url),'utf8')});
 await receiving.addStyleTag({content:'*{box-sizing:border-box}body{margin:0;padding:12px}.hidden{display:none!important}main{max-width:100%}.ewComprasTableWrap{max-width:100%;overflow-x:auto}'});
 await receiving.evaluate(()=>{
  window.escapeHTML=v=>String(v??'').replace(/[&<>"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));
  window.temPermissao=()=>true;window.ensureSession=async()=>{};
  window.currentCompany={id:'company'};window.session={access_token:'MOCK'};
  window._mockReceiving={receipts:[{id:'first',pedido_id:'p1',itens:[{chave:'A',quantidade:1}],galpao:'AFOGADOS'}],calls:[]};
  if(typeof crypto.randomUUID!=='function')Object.defineProperty(crypto,'randomUUID',{value:()=> '00000000-0000-4000-8000-000000000123'});
  window.apiGet=async(table)=>{
   if(table==='ew_compras_recebimentos')return window._mockReceiving.receipts;
   if(table==='ew_locais_fisicos')return [{nome:'AFOGADOS',ativo:true}];
   if(table==='ew_materiais_variacoes')return [{id:'v',tipo:'perfil',perfil_id:'pf',cor:'NATURAL'}];
   if(table==='ew_perfis')return [{id:'pf',codigo:'P01',descricao:'Perfil teste',comprimento_comercial_mm:6000}];
   return [];
  };
  window.request=async(path,opts)=>{
   if(path.endsWith('ew_compras_pedidos_resumo'))return [
    {id:'p1',numero:1,obra_id:'obra1',itens:[{chave:'A',variacao_id:'v',unidade:'BARRA',quantidade:3}]},
    {id:'p2',numero:2,local_empresa_id:'loc1',itens:[{chave:'A',variacao_id:'v',unidade:'BARRA',quantidade:5}]}
   ];
   if(!path.endsWith('ew_compras_receber_pedido'))throw Error('RPC inesperada');
   window._mockReceiving.calls.push(opts.body);
   window._mockReceiving.receipts.push({id:'second',pedido_id:opts.body.p_pedido_id,itens:opts.body.p_itens,galpao:opts.body.p_galpao});
   return {id:'second'};
  };
 });
 await receiving.addScriptTag({content:readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8')});
 await receiving.evaluate(()=>window.ewCompras.atualizarRecebimento('obra1'));
 await receiving.locator('#ewReceberPedido').selectOption('p1');
 const row=receiving.locator('[data-receive-key="A"]');
 assert.equal(await row.locator('td').nth(3).innerText(),'1');
 assert.equal(await row.locator('td').nth(4).innerText(),'2');
 await row.locator('[type=checkbox]').check();
 await row.locator('[type=number]').fill('1');
 await receiving.locator('#ewReceberGalpao').selectOption('AFOGADOS');
 await receiving.locator('#ewReceberForm [type=submit]').click();
 await receiving.waitForFunction(()=>document.querySelector('#ewReceberMessage')?.textContent==='Recebimento confirmado.');
 assert.equal(await receiving.locator('#ewReceberPedido').inputValue(),'p1');
 assert.equal(await row.locator('td').nth(3).innerText(),'2');
 assert.equal(await row.locator('td').nth(4).innerText(),'1');
 assert.equal(await receiving.evaluate(()=>window._mockReceiving.calls.length),1);
 assert.ok(await receiving.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2),'Recebimento excede largura mobile');
 await receiving.locator('#recebimentoWork').selectOption('empresa:loc1');
 await receiving.evaluate(()=>window.ewCompras.atualizarRecebimento('empresa:loc1'));
 assert.equal(await receiving.locator('#ewReceberPedido option[value="p1"]').count(),0);
 await receiving.locator('#ewReceberPedido').selectOption('p2');
 assert.equal(await row.locator('td').nth(4).innerText(),'5');
 console.log('PASS Chromium: recebimento parcial, seleção preservada, saldo atualizado, local empresarial separado e mobile.');
 await receiving.close();

 // Editor de níveis: usa o HTML e o módulo reais, somente RPCs sintéticas.
 const levels=await browser.newPage({viewport:{width:1280,height:800}});
 const app=readFileSync(new URL('../app.html',import.meta.url),'utf8');
 const section=app.match(/<section id="accessLevels"[\s\S]*?<\/section>/)?.[0];
 assert.ok(section,'Tela exclusiva de níveis ausente');
 await levels.setContent('<!doctype html><html><body><select id="createUserLevel"><option value="3">3</option></select><select id="userEditLevel"><option value="3">3</option></select><select id="createUserRole"><option value="tecnico">tecnico</option></select><select id="userEditRole"><option value="tecnico">tecnico</option></select>'+section.replace('class="hidden"','')+'</body></html>');
 await levels.addStyleTag({content:readFileSync(new URL('../assets/niveis-acesso.css',import.meta.url),'utf8')});
 await levels.addStyleTag({content:'*{box-sizing:border-box}body{margin:0;padding:12px}.hidden{display:none!important}main,section{max-width:100%}input{max-width:100%}'});
 await levels.evaluate(()=>{
  window.currentAccessLevel=1;window.currentCompany={id:'empresa-sintetica'};
  window.session={access_token:'MOCK'};window.isFullAdminUser=()=>window.currentAccessLevel===1;
  window.temPermissao=()=>window.currentAccessLevel===1;window.ensureSession=async()=>{};
  window.confirm=()=>true;
  window._levels={saved:[],data:{niveis:Array.from({length:8},(_,i)=>({nivel:i+1,nome:'Perfil '+(i+1),flags:{'estoque.consultar':i===0||i===1,'financeiro.consultar':i===0}})),catalogo:[{chave:'estoque.consultar',grupo:'Estoque',descricao:'Consultar estoque',ordem:1},{chave:'financeiro.consultar',grupo:'Financeiro',descricao:'Consultar financeiro',ordem:2}]}};
  window.request=async(path,opts)=>{
   if(path.endsWith('ew_listar_niveis'))return structuredClone(window._levels.data);
   if(!path.endsWith('ew_salvar_nivel'))throw Error('RPC inesperada');
   window._levels.saved.push(opts.body);
   const flags=Object.fromEntries(window._levels.data.catalogo.map(x=>[x.chave,opts.body.p_flags.includes(x.chave)]));
   window._levels.data.niveis.find(x=>x.nivel===opts.body.p_nivel).flags=flags;
   return {flags};
  };
 });
 await levels.addScriptTag({content:readFileSync(new URL('../assets/niveis-acesso.js',import.meta.url),'utf8')});
 await levels.evaluate(()=>window.nivelAcessoPreparar());
 assert.equal(await levels.locator('[data-level]').count(),8);
 await levels.locator('[data-level="1"]').click();
 assert.ok(await levels.locator('[data-flag="estoque.consultar"]').isDisabled());
 assert.ok(await levels.locator('[data-flag="financeiro.consultar"]').isChecked());
 assert.ok(await levels.locator('#userLevelsSave').isDisabled());
 await levels.locator('[data-level="2"]').click();
 assert.ok(await levels.locator('[data-flag="estoque.consultar"]').isChecked());
 await levels.locator('#userLevelsSearch').fill('financeiro');
 assert.ok(!(await levels.locator('[data-flag="estoque.consultar"]').isVisible()));
 await levels.locator('[data-flag="financeiro.consultar"]').check();
 await levels.locator('#userLevelsSave').click();
 await levels.waitForFunction(()=>document.querySelector('#userLevelsStatus').textContent.includes('atualizado'));
 const saved=await levels.evaluate(()=>window._levels.saved);
 assert.equal(saved[0].p_nivel,2);
 assert.equal(saved[0].p_empresa_id,'empresa-sintetica');
 assert.deepEqual(saved[0].p_flags.sort(),['estoque.consultar','financeiro.consultar']);
 await levels.locator('#userLevelsSearch').fill('');
 await levels.locator('#userLevelsNone').click();
 assert.equal(await levels.locator('[data-flag]:checked').count(),0);
 await levels.locator('#userLevelsAll').click();
 assert.equal(await levels.locator('[data-flag]:checked').count(),2);
 await levels.setViewportSize({width:390,height:844});
 assert.ok(await levels.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2),'Editor de níveis transbordou mobile');
 await levels.evaluate(()=>{window.currentAccessLevel=2;return window.nivelAcessoPreparar()});
 assert.ok(!(await levels.locator('#userLevelsPanel').isVisible()));
 console.log('PASS Chromium: oito níveis, proteção ADM, filtro, flags, salvar, ações em massa e acesso restrito.');
 await levels.close();

 // v46.28: tela real de cotação — agrupamento, fornecedores e preços independentes.
 const quoting=await browser.newPage({viewport:{width:1280,height:800}});
 await quoting.setContent('<!doctype html><html><body><button id="cadastroJumpFornecedores" hidden></button><aside><button id="navCompras" aria-expanded="false"></button><div id="navComprasSubmenu"><button id="comprasTabSolicitacao">Solicitação</button><button id="comprasTabCotacao">Cotação</button><button id="comprasTabAprovacao">Aprovação de cotações</button><button id="comprasTabPedido">Pedidos de compra</button><button id="comprasTabHistorico">Histórico de preços</button></div></aside><h1 id="comprasPaginaTitulo"></h1><p id="comprasPaginaDescricao"></p><div id="comprasMensagem"></div><main id="comprasConteudo"></main></body></html>');
 await quoting.evaluate(()=>{
  window.escapeHTML=v=>String(v??'').replace(/[&<>"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));
  window.currentCompany={id:'empresa-teste'};window.session={access_token:'MOCK'};window.ensureSession=async()=>{};
  window.temPermissao=()=>true;window.setView=()=>{};window.confirm=()=>true;
  window._cadastroOpened=false;document.getElementById('cadastroJumpFornecedores').onclick=()=>{window._cadastroOpened=true;};
  window.works=[{id:'a',nome:'Obra A'},{id:'b',nome:'Obra B'}];
  if(typeof crypto.randomUUID!=='function')Object.defineProperty(crypto,'randomUUID',{value:()=> '00000000-0000-4000-8000-000000000987'});
  const item={chave:'1',variacao_id:'v',unidade:'BARRA',quantidade:2,comprimento_mm:6000};
  const acc={chave:'2',variacao_id:'va',unidade:'PC',quantidade:1,comprimento_mm:null};
  window._q={calls:[],invites:[],links:[],moved:false,noSuppliers:false,sols:['s1','s2','s3'].map((id,i)=>({id,obra_id:i===2?'b':'a',status:'ABERTA',itens:i===1?[item,acc]:[item],criado_em:'2026-11-25',observacoes:id})),quotes:[]};
  window.apiGet=async table=>{
   if(table==='ew_compras_solicitacoes')return structuredClone(window._q.sols);
   if(table==='ew_compras_cotacoes')return structuredClone(window._q.quotes);
   if(table==='ew_fornecedores')return [{id:'f1',nome:'Fornecedor 1',ativo:true},{id:'f2',nome:'Fornecedor 2',ativo:true},{id:'f3',nome:'Fornecedor de acessórios',ativo:true}];
   if(table==='ew_materiais_variacoes')return [{id:'v',tipo:'perfil',perfil_id:'pf',cor:'NATURAL',ativo:true},{id:'va',tipo:'acessorio',acessorio_id:'ac',cor:'PRETO',ativo:true}];
   if(table==='ew_acessorios')return [{id:'ac',codigo:'A01',descricao:'Acessório teste',unidade_item:'PC'}];
   if(table==='ew_perfis')return [{id:'pf',codigo:'P01',descricao:'Perfil teste',comprimento_comercial_mm:6000}];
   return [];
  };
  const assertClassificar=b=>{if(b.p_empresa_id!=='empresa-teste'||b.p_variacao_id!=='va'||!['gp','ga'].includes(b.p_grupo_id))throw Error('Classificação inválida');};
  window.request=async(path,opts)=>{
   const fn=path.split('/').pop(),body=opts.body,m=window._q;
   if(fn==='ew_compras_pedidos_resumo')return [];
   if(fn==='ew_compras_grupos_catalogo')return {grupos:[{id:'gp',nome:'Perfis',ativo:true},{id:'ga',nome:'Acessórios',ativo:true}],fornecedores:[{id:'f1',grupos:['gp']},{id:'f2',grupos:['gp']},{id:'f3',grupos:m.noSuppliers?[]:['ga']}],legados:[]};
   if(fn==='ew_compras_grupos_desdobrados')return structuredClone(m.links);
   if(fn==='ew_compras_previa_grupos')return [{grupo_id:'gp',nome:'Perfis',ativo:true,itens:[{...item,quantidade:4},...(m.moved?[acc]:[])],fornecedores:[{id:'f1',nome:'Fornecedor 1'},{id:'f2',nome:'Fornecedor 2'}]},...(!m.moved?[{grupo_id:'ga',nome:'Acessórios',ativo:true,itens:[acc],fornecedores:[{id:'f3',nome:'Fornecedor de acessórios'}]}]:[])];
   if(fn==='ew_compras_classificar_material'){assertClassificar(body);m.moved=body.p_grupo_id==='gp';return null;}

   if(fn==='ew_compras_convites_cotacao')return structuredClone(m.invites);
   m.calls.push({fn,body});
   if(fn==='ew_compras_agrupar_solicitacoes'){
    m.sols=m.sols.map(s=>body.p_solicitacoes.includes(s.id)?{...s,status:'AGRUPADA'}:s);
    m.sols.push({id:'grupo',obra_id:'a',status:'ABERTA',itens:[{...item,quantidade:4},acc],criado_em:'2026-11-25'});
    return {id:'grupo'};
   }
   if(fn==='ew_compras_desdobrar_grupos'){
    m.sols=m.sols.map(s=>s.id==='grupo'?{...s,status:'DESDOBRADA'}:s);
    m.sols.push({id:'grupo-perfis',obra_id:'a',status:'ABERTA',itens:[{...item,quantidade:4}],criado_em:'2026-11-25'});
    m.sols.push({id:'grupo-acessorios',obra_id:'a',status:'ABERTA',itens:[acc],criado_em:'2026-11-25'});
    m.links=[{solicitacao_id:'grupo',filha_id:'grupo-perfis',grupo_id:'gp',nome:'Perfis',status:'ABERTA'},{solicitacao_id:'grupo',filha_id:'grupo-acessorios',grupo_id:'ga',nome:'Acessórios',status:'ABERTA'}];
    return {id:'desdobramento'};
   }
   if(fn==='ew_compras_replicar_cotacao'){
    m.invites=body.p_fornecedores.map(id=>({fornecedor_id:id,fornecedor:id==='f1'?'Fornecedor 1':'Fornecedor 2',status:'AGUARDANDO',ativo:true}));
    return {ok:true};
   }
   if(fn==='ew_compras_criar_cotacao'){
    m.quotes.push({id:'q1',solicitacao_id:body.p_solicitacao_id,fornecedor_id:body.p_fornecedor_id,status:'ABERTA',criado_em:'2026-11-25',itens:m.sols.find(s=>s.id===body.p_solicitacao_id).itens.map(i=>({...i,preco_unitario_centavos:body.p_precos.find(p=>p.chave===i.chave).preco_unitario_centavos})),total_centavos:50000});
    return {id:'q1'};
   }
   throw Error('RPC inesperada: '+fn);
  };
 });
 await quoting.addScriptTag({content:readFileSync(new URL('../assets/compras-estoque.js',import.meta.url),'utf8')});
 await quoting.locator('#comprasTabCotacao').click();
 await quoting.locator('#comprasCotacaoSolic').waitFor();
 assert.equal(await quoting.locator('#comprasPaginaTitulo').innerText(),'Cotação');
 assert.equal(await quoting.locator('#comprasTabCotacao').getAttribute('aria-current'),'page');
 assert.equal(await quoting.locator('#navCompras').getAttribute('aria-expanded'),'true');
 assert.equal(await quoting.locator('#comprasConteudo [id^="comprasTab"]').count(),0);
 assert.ok(await quoting.locator('#comprasAgruparPainel').isHidden());
 await quoting.locator('#comprasAgruparAbrir').click();
 assert.ok(await quoting.locator('#comprasAgruparPainel').isVisible());
 await quoting.locator('#comprasAgruparObra').selectOption('a');
 assert.equal(await quoting.locator('#comprasAgruparLista input').count(),2);
 await quoting.locator('#comprasAgruparLista input[value="s1"]').check();
 assert.ok(await quoting.locator('#comprasAgruparConfirmar').isDisabled());
 await quoting.locator('#comprasAgruparLista input[value="s2"]').check();
 await quoting.locator('#comprasAgruparConfirmar').click();
 await quoting.waitForFunction(()=>document.querySelector('#comprasCotacaoSolic')?.value==='grupo');
 assert.equal(await quoting.locator('#comprasCotacaoSolic option[value="s1"]').count(),0);
 assert.equal(await quoting.locator('#comprasCotacaoSolic option[value="s3"]').count(),1);
 const changeGroup=quoting.locator('[data-alterar-grupo="va"]');
 await changeGroup.click();
 await quoting.locator('.ewComprasGrupoEdicao select').selectOption('gp');
 await quoting.locator('[data-salvar-grupo]').click();
 await quoting.waitForFunction(()=>document.querySelector('[data-alterar-grupo="va"]')?.dataset.grupoAtual==='gp');
 await changeGroup.click();
 await quoting.locator('.ewComprasGrupoEdicao select').selectOption('ga');
 await quoting.locator('[data-salvar-grupo]').click();
 await quoting.waitForFunction(()=>document.querySelector('[data-alterar-grupo="va"]')?.dataset.grupoAtual==='ga');
 await quoting.locator('#comprasPrepararGrupos').click();
 await quoting.locator('#comprasCotacaoSolic option[value="grupo-acessorios"]').waitFor({state:'attached'});
 assert.equal(await quoting.locator('#comprasCotacaoSolic option[value="grupo"]').count(),0,'Solicitação original não pode reaparecer após desdobramento');
 assert.equal(await quoting.locator('#comprasCotacaoSolic option[value="grupo-perfis"]').count(),1);
 assert.equal(await quoting.locator('#comprasCotacaoSolic option[value="grupo-acessorios"]').count(),1);
 assert.equal(await quoting.evaluate(()=>window._q.sols.find(s=>s.id==='grupo').status),'DESDOBRADA','Histórico original preservado');
 await quoting.locator('#comprasCotacaoSolic').selectOption('grupo-acessorios');
 assert.equal(await quoting.locator('#comprasCotacaoFornecedor option[value="f3"]').count(),1);
 await quoting.evaluate(()=>{window._q.noSuppliers=true;});
 await quoting.locator('#comprasTabCotacao').click();
 await quoting.locator('#comprasCotacaoSolic').selectOption('grupo-acessorios');
 await quoting.locator('#comprasAbrirCadastroFornecedor').click();
 assert.equal(await quoting.evaluate(()=>window._cadastroOpened),true);
 assert.ok((await quoting.locator('#comprasGruposPrevia').innerText()).includes('Fornecedores → Grupos atendidos por fornecedor'));
 await quoting.evaluate(()=>{window._q.noSuppliers=false;});
 await quoting.locator('#comprasTabCotacao').click();
 await quoting.locator('#comprasCotacaoSolic').selectOption('grupo-acessorios');
 assert.equal(await quoting.locator('#comprasCotacaoFornecedor option[value="f3"]').count(),1);
 assert.equal(await quoting.locator('#comprasCotacaoFornecedor option[value="f1"]').count(),0);
 assert.equal(await quoting.locator('[data-quote-key="1"]').count(),0);
 assert.equal(await quoting.locator('#comprasCotacaoSolic option[value="grupo"]').count(),0,'Original permanece oculta após recarregar a cotação');
 await quoting.locator('#comprasCotacaoSolic').selectOption('grupo-perfis');
 assert.equal(await quoting.locator('#comprasCotacaoFornecedor option[value="f3"]').count(),0);
 assert.equal(await quoting.locator('[data-quote-key="2"]').count(),0);
 await quoting.waitForFunction(()=>document.querySelector('#comprasCotacaoSolic')?.value==='grupo-perfis');
 await quoting.locator('#comprasConvites details summary').click();
 await quoting.locator('[data-fornecedor="f1"]').check();
 await quoting.locator('[data-fornecedor="f2"]').check();
 await quoting.locator('#comprasReplicarLote').click();
 await quoting.locator('[data-convite="f1"]').waitFor();
 assert.equal(await quoting.locator('[data-convite]').count(),2);
 await quoting.locator('[data-convite="f1"]').click();
 const price=quoting.locator('[data-quote-key="1"] input');
 await price.fill('55');
 await price.press('Tab');
 assert.equal((await price.inputValue()).replace(/\s/g,' '),'R$ 55,00');
 await price.fill('1250,5');
 await price.press('Tab');
 assert.equal((await price.inputValue()).replace(/\s/g,' '),'R$ 1.250,50');
 await price.fill('R$ 151,00');
 await price.press('Tab');
 assert.equal((await price.inputValue()).replace(/\s/g,' '),'R$ 151,00');
 assert.equal(await price.getAttribute('placeholder'),'R$ 0,00');
 await price.fill('125,00');
 await quoting.locator('[data-convite="f2"]').click();
 assert.equal(await quoting.locator('[data-quote-key="1"] input').inputValue(),'','Não copiar preço entre fornecedores');
 await quoting.locator('[data-quote-key="1"] input').fill('125,001');
 await quoting.locator('#comprasCotarForm button[type="submit"]').click();
 assert.equal(await quoting.locator('#comprasMensagem').innerText(),'Valores inválidos.');
 assert.equal(await quoting.evaluate(()=>window._q.calls.length),3);
 await quoting.locator('[data-quote-key="1"] input').fill('125,00');
 await quoting.locator('#comprasCotarForm button[type="submit"]').click();
 await quoting.waitForFunction(()=>document.querySelector('#comprasMensagem').textContent==='Cotação registrada.');
 const qcalls=await quoting.evaluate(()=>window._q.calls);
 assert.deepEqual(qcalls[0].body.p_solicitacoes,['s1','s2']);
 assert.equal(qcalls[1].fn,'ew_compras_desdobrar_grupos');
 assert.deepEqual(qcalls[2].body.p_fornecedores,['f1','f2']);
 assert.equal(qcalls[3].body.p_fornecedor_id,'f2');
 assert.deepEqual(qcalls[3].body.p_precos,[{chave:'1',preco_unitario_centavos:12500}]);
 await quoting.locator('[data-cotacao-replicar]').click();
 assert.equal(await quoting.locator('#comprasCotacaoSolic').inputValue(),'grupo-perfis');
 assert.equal(await quoting.locator('[data-quote-key="1"] input').inputValue(),'');
 console.log('PASS Chromium v46.28: agrupamento por obra, fornecedores em lote, preços independentes e registro da cotação.');
 await quoting.locator('#comprasTabAprovacao').click();
 await quoting.locator('#comprasPedidoForm').waitFor();
 assert.equal(await quoting.locator('#comprasPaginaTitulo').innerText(),'Aprovação de cotações');
 assert.equal(await quoting.locator('#comprasTabAprovacao').getAttribute('aria-current'),'page');
 await quoting.locator('#comprasFiltroBusca').fill('fornecedor inexistente');
 assert.equal(await quoting.locator('[data-aprovar-cotacao="q1"]').isVisible(),false);
 await quoting.locator('#comprasFiltroLimpar').click();
 assert.equal(await quoting.locator('[data-aprovar-cotacao="q1"]').isVisible(),true);
 await quoting.locator('[data-aprovar-cotacao="q1"]').click();
 assert.equal(await quoting.locator('#comprasPedidoCotacao').inputValue(),'q1');
 await quoting.locator('#comprasTabPedido').click();
 await quoting.waitForFunction(()=>document.querySelector('#comprasTabPedido')?.getAttribute('aria-current')==='page');
 assert.equal(await quoting.locator('#comprasPaginaTitulo').innerText(),'Pedidos de compra');
 assert.equal(await quoting.locator('#comprasPedidoForm').count(),0);
 assert.equal(await quoting.locator('#comprasCotacaoSolic').count(),0);
 await quoting.locator('#comprasTabHistorico').click();
 await quoting.waitForFunction(()=>document.querySelector('#comprasTabHistorico')?.getAttribute('aria-current')==='page');
 assert.equal(await quoting.locator('#comprasPaginaTitulo').innerText(),'Histórico de preços');
 assert.equal(await quoting.locator('[data-compra-lista]').count(),1);
 assert.ok((await quoting.locator('[data-compra-lista]').innerText()).includes('Fornecedor 2'));
 await quoting.locator('#comprasFiltroBusca').fill('fornecedor inexistente');
 assert.equal(await quoting.locator('[data-compra-lista]').isVisible(),false);
 await quoting.locator('#comprasTabSolicitacao').click();
 await quoting.waitForFunction(()=>document.querySelector('#comprasTabSolicitacao')?.getAttribute('aria-current')==='page');
 assert.equal(await quoting.locator('#comprasPaginaTitulo').innerText(),'Solicitação de compra');
 assert.equal(await quoting.locator('#comprasPedidoForm').count(),0);
 await quoting.close();
}finally{await browser.close()}
