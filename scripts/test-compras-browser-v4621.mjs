// Smoke test EWGEST v46.21 — interface de conciliação fiscal no Chromium.
// Todos os dados e respostas RPC são sintéticos. Não acessa Supabase nem produção.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {chromium} from 'playwright';

const browser=await chromium.launch({headless:true});
try{
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await page.setContent('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"></head>'+
  '<body><div id="comprasMensagem"></div><main style="width:100%;max-width:100%">'+
  '<section id="fiscal"></section></main></body></html>');
 await page.addStyleTag({content:readFileSync(new URL('../assets/compras-estoque.css',import.meta.url),'utf8')});
 await page.addStyleTag({content:'html,body{box-sizing:border-box;margin:0;width:100%;max-width:100%;overflow-x:hidden}*{box-sizing:border-box}main{padding:12px}#fiscal{width:100%;max-width:100%}.ewComprasTableWrap{max-width:100%;overflow-x:auto}'});
 await page.evaluate(()=>{
  window.escapeHTML=value=>String(value??'').replace(/[&<>"']/g,x=>
   ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
  window.session={access_token:'MOCK_ONLY'};
  window._mock={noteQty:1,corporateNotes:[],rpcCalls:[],reloadCount:0,allow:true};
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
 await page.evaluate(()=>window.ewComprasNfe.render(document.querySelector('#fiscal'),window._ctx));
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
 await page.waitForFunction(()=>window._mock.rpcCalls.length===1);
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
 await page.waitForFunction(()=>window._mock.rpcCalls.length===2);
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
 await page.waitForFunction(()=>window._mock.rpcCalls.length===3);
 const third=await page.evaluate(()=>window._mock.rpcCalls[2]);
 assert.match(third.path,/ew_compras_registrar_nota_empresa$/);
 assert.equal(third.body.p_valor_centavos,12050);
 assert.equal(third.body.p_itens[0].valor_total_centavos,12050);

 const bounds=await page.evaluate(()=>({
  viewport:window.innerWidth,overflow:document.documentElement.scrollWidth,
  fiscalWidth:document.querySelector('#fiscal').getBoundingClientRect().width}));
 assert.ok(bounds.overflow<=bounds.viewport+2,'Interface mobile transbordou horizontalmente');
 await page.setViewportSize({width:1360,height:900});
 assert.ok(await page.locator('#ewNfeEmpOrder').isVisible());
 assert.ok(await page.locator('#ewCompNFOrder').isVisible());
 console.log('PASS Chromium: nota de obra, quantidade excedida bloqueada, 2 parciais válidos, nota empresa em centavos, mobile e desktop.');
}finally{await browser.close()}
