// Smoke test EWGEST v46.21 — interface de conciliação fiscal no Chromium.
// Todos os dados e respostas RPC são sintéticos. Não acessa Supabase nem produção.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {chromium} from 'playwright';

const browser=await chromium.launch({headless:true});
try{
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
}finally{await browser.close()}
