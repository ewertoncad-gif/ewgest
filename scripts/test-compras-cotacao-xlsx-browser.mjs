import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {chromium} from 'playwright';
const core=readFileSync(new URL('../assets/compras-cotacao-xlsx.mjs',import.meta.url),'utf8');
const browser=await chromium.launch({headless:true});
try{
 const page=await browser.newPage();
 await page.route('http://localhost/**',r=>r.fulfill({contentType:r.request().url().endsWith('.mjs')?'application/javascript':'text/html',body:r.request().url().endsWith('.mjs')?core:'<!doctype html><html></html>'}));
 await page.goto('http://localhost/');
 const result=await page.evaluate(async()=>{
  const m=await import('/core.mjs');
  const exp=m.modelo('sol','fornecedor',[{chave:'1',material:'Perfil A & B',quantidade:4,unidade:'BARRA',comprimento_mm:6000}]);
  const filled=structuredClone(exp);filled[2][5]=125.5;
  const blob=m.exportarXlsx(filled);
  const rows=await m.lerXlsx(blob);
  return m.validarRetorno(exp,rows);
 });
 assert.deepEqual(result,[{chave:'1',preco_unitario_centavos:12550}]);
 console.log('PASS Chromium: exportar XLSX, ler e validar conteúdo retornado.');
}finally{await browser.close();}
