import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
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
 // Repack a valid OOXML template with deflate and shared strings, as office
 // applications commonly do when saving. Do not require a separate library.
 const exported=await page.evaluate(async()=>{
  const m=await import('/core.mjs');
  const rows=m.modelo('sol','fornecedor',[{chave:'1',material:'Perfil A & B',quantidade:4,unidade:'BARRA',comprimento_mm:6000}]);
  rows[2][5]=125.5;return Array.from(new Uint8Array(await m.exportarXlsx(rows).arrayBuffer()));
 });
 const py=String.raw`import sys,io,zipfile,xml.etree.ElementTree as E
ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
n=lambda name:'{'+ns+'}'+name
src=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))
dst=io.BytesIO()
sheet=E.fromstring(src.read('xl/worksheets/sheet1.xml'))
sst=E.Element(n('sst'))
for c in sheet.iter(n('c')):
 if c.get('t')=='inlineStr':
  text=''.join(x.text or '' for x in c.iter(n('t')))
  index=len(sst);si=E.SubElement(sst,n('si'));E.SubElement(si,n('t')).text=text
  for child in list(c):c.remove(child)
  c.set('t','s');E.SubElement(c,n('v')).text=str(index)
rel=E.fromstring(src.read('xl/_rels/workbook.xml.rels'))
rp='http://schemas.openxmlformats.org/package/2006/relationships'
E.SubElement(rel,'{'+rp+'}Relationship',{'Id':'rId4','Type':'http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings','Target':'sharedStrings.xml'})
types=E.fromstring(src.read('[Content_Types].xml'))
E.SubElement(types,'{http://schemas.openxmlformats.org/package/2006/content-types}Override',{'PartName':'/xl/sharedStrings.xml','ContentType':'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml'})
with zipfile.ZipFile(dst,'w',zipfile.ZIP_DEFLATED) as z:
 for name in src.namelist():
  if name=='xl/worksheets/sheet1.xml':data=E.tostring(sheet,encoding='utf-8')
  elif name=='xl/_rels/workbook.xml.rels':data=E.tostring(rel,encoding='utf-8')
  elif name=='[Content_Types].xml':data=E.tostring(types,encoding='utf-8')
  else:data=src.read(name)
  z.writestr(name,data)
 z.writestr('xl/sharedStrings.xml',E.tostring(sst,encoding='utf-8'))
sys.stdout.buffer.write(dst.getvalue())`;
 const inspect=String.raw`import sys,io,zipfile,xml.etree.ElementTree as E
z=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))
ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
wb=E.fromstring(z.read('xl/workbook.xml'))
assert wb.find('.//s:sheet[@name="CONTROLE"]',ns).get('state')=='veryHidden'
sheet=E.fromstring(z.read('xl/worksheets/sheet1.xml'))
styles=E.fromstring(z.read('xl/styles.xml'))
assert sheet.find('.//s:pane',ns).get('ySplit')=='6'
assert sheet.find('s:sheetProtection',ns).get('sheet')=='1'
assert sheet.find('.//s:c[@r="G7"]',ns).get('s')=='8'
assert sheet.find('.//s:c[@r="H7"]/s:f',ns) is not None
assert styles.find('.//s:protection',ns).get('locked')=='0'
assert not any('EWGEST-COTACAO-V1' in (t.text or '') for t in sheet.findall('.//s:t',ns))
assert len({r.get('Id') for r in E.fromstring(z.read('xl/_rels/workbook.xml.rels'))})==3
print('PASS layout comercial e controle oculto')`;
 const inspected=spawnSync('python3',['-c',inspect],{input:Buffer.from(exported)});
 assert.equal(inspected.status,0,inspected.stderr.toString());
 console.log(inspected.stdout.toString().trim());
 const repacked=spawnSync('python3',['-c',py],{input:Buffer.from(exported)});
 assert.equal(repacked.status,0,repacked.stderr.toString());
 const prices=await page.evaluate(async bytes=>{
  const m=await import('/core.mjs');
  const expected=m.modelo('sol','fornecedor',[{chave:'1',material:'Perfil A & B',quantidade:4,unidade:'BARRA',comprimento_mm:6000}]);
  return m.validarRetorno(expected,await m.lerXlsx(new Blob([new Uint8Array(bytes)])));
 },Array.from(repacked.stdout));
 assert.deepEqual(prices,[{chave:'1',preco_unitario_centavos:12550}]);
 console.log('PASS XLSX compactado (deflate) com shared strings.');
 console.log('PASS Chromium: exportar XLSX, ler e validar conteúdo retornado.');
}finally{await browser.close();}
