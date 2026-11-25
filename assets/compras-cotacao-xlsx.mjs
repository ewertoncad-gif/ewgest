// Modelo XLSX específico para cotações EWGEST. Sem scripts externos.
export const HEADER=['Item','Material','Quantidade','Unidade','Comprimento (mm)','Preço unitário (R$)'];
export function modelo(solicitacao,fornecedor,linhas){
 if(!solicitacao||!fornecedor||!linhas.length||linhas.length>200)throw Error('Selecione solicitação e fornecedor.');
 return [['EWGEST-COTACAO-V1',String(solicitacao),String(fornecedor)],HEADER.slice(),...linhas.map(x=>[String(x.chave),String(x.material),Number(x.quantidade),String(x.unidade),x.comprimento_mm==null?'':Number(x.comprimento_mm),''])];
}
export function validarRetorno(expected,actual){
 const get=(r,i)=>String(r?.[i]??'').trim();
 if(!Array.isArray(actual)||actual.length!==expected.length||expected[0].some((v,i)=>get(actual[0],i)!==String(v))||HEADER.some((v,i)=>get(actual[1],i)!==v))throw Error('Planilha de outra solicitação/fornecedor ou modelo alterado.');
 const byKey=new Map(expected.slice(2).map(r=>[String(r[0]),r])),seen=new Set(),prices=[];
 for(const row of actual.slice(2)){
  const k=get(row,0),original=byKey.get(k);
  if(!original||seen.has(k))throw Error('Item ausente ou repetido: '+k);seen.add(k);
  if(get(row,1)!==String(original[1]).trim()||get(row,2)===''||Number(get(row,2).replace(',','.'))!==original[2]||get(row,3)!==original[3]||get(row,4)!==String(original[4]))throw Error('Material, unidade ou quantidade alterada no item '+k);
  const price=get(row,5).replace(/^R\$\s*/,'');
  if(!/^\d+(?:[.,]\d{1,2})?$/.test(price))throw Error('Preço inválido ou ausente no item '+k);
  const cents=Math.round(Number(price.replace(',','.'))*100);
  if(!Number.isSafeInteger(cents)||cents<0||cents>100000000000)throw Error('Preço fora dos limites.');
  prices.push({chave:k,preco_unitario_centavos:cents});
 }
 return prices;
}
const MAX=12*1024*1024,NS='http://schemas.openxmlformats.org/spreadsheetml/2006/main',REL='http://schemas.openxmlformats.org/officeDocument/2006/relationships',PKG='http://schemas.openxmlformats.org/package/2006/relationships';
const xml=s=>String(s??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const crc32=b=>{let c=0xffffffff;for(const v of b){c^=v;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;};
function zip(files){
 const enc=new TextEncoder(),chunks=[],central=[];let offset=0,size=0;
 for(const [name,value] of Object.entries(files)){
  const n=enc.encode(name),b=enc.encode(value),crc=crc32(b);
  const l=new Uint8Array(30+n.length),v=new DataView(l.buffer);
  v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint32(14,crc,true);v.setUint32(18,b.length,true);v.setUint32(22,b.length,true);v.setUint16(26,n.length,true);l.set(n,30);
  const h=new Uint8Array(46+n.length),d=new DataView(h.buffer);
  d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint32(16,crc,true);d.setUint32(20,b.length,true);d.setUint32(24,b.length,true);d.setUint16(28,n.length,true);d.setUint32(42,offset,true);h.set(n,46);
  chunks.push(l,b);central.push(h);offset+=l.length+b.length;size+=h.length;
 }
 const e=new Uint8Array(22),d=new DataView(e.buffer);
 d.setUint32(0,0x06054b50,true);d.setUint16(8,central.length,true);d.setUint16(10,central.length,true);d.setUint32(12,size,true);d.setUint32(16,offset,true);
 return new Blob([...chunks,...central,e],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
}
export function exportarXlsx(rows){
 const sheet=rows.map((r,i)=>'<row r="'+(i+1)+'">'+r.map((x,j)=>{
  const ref=String.fromCharCode(65+j)+(i+1);
  return typeof x==='number'?'<c r="'+ref+'"><v>'+x+'</v></c>':'<c r="'+ref+'" t="inlineStr"><is><t xml:space="preserve">'+xml(x)+'</t></is></c>';
 }).join('')+'</row>').join('');
 return zip({
 '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
 '_rels/.rels':'<Relationships xmlns="'+PKG+'"><Relationship Id="rId1" Type="'+REL+'/officeDocument" Target="xl/workbook.xml"/></Relationships>',
 'xl/workbook.xml':'<workbook xmlns="'+NS+'" xmlns:r="'+REL+'"><sheets><sheet name="COTACAO" sheetId="1" r:id="rId1"/></sheets></workbook>',
 'xl/_rels/workbook.xml.rels':'<Relationships xmlns="'+PKG+'"><Relationship Id="rId1" Type="'+REL+'/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
 'xl/worksheets/sheet1.xml':'<worksheet xmlns="'+NS+'"><cols><col min="1" max="1" width="12" customWidth="1"/><col min="2" max="2" width="65" customWidth="1"/><col min="3" max="6" width="23" customWidth="1"/></cols><sheetData>'+sheet+'</sheetData></worksheet>'
 });
}
async function unzipSelected(file){
 if(!file||file.size>MAX)throw Error('Arquivo XLSX excede 12 MB.');
 const dec=new TextDecoder('utf-8',{fatal:true}),b=new Uint8Array(await file.arrayBuffer()),v=new DataView(b.buffer);let e=-1;
 for(let i=b.length-22;i>=Math.max(0,b.length-65557);i--)if(v.getUint32(i,true)===0x06054b50&&i+22+v.getUint16(i+20,true)===b.length){e=i;break;}
 if(e<0||v.getUint16(e+4,true)||v.getUint16(e+6,true))throw Error('Arquivo XLSX inválido.');
 const count=v.getUint16(e+10,true),size=v.getUint32(e+12,true),start=v.getUint32(e+16,true);
 if(count<1||count>300||start+size>e)throw Error('Estrutura XLSX inválida.');
 const parts=new Map();let pos=start,total=0;
 for(let i=0;i<count;i++){
  if(pos+46>e||v.getUint32(pos,true)!==0x02014b50)throw Error('Diretório XLSX inválido.');
  const flag=v.getUint16(pos+8,true),method=v.getUint16(pos+10,true),crc=v.getUint32(pos+16,true),packed=v.getUint32(pos+20,true),unpacked=v.getUint32(pos+24,true),nl=v.getUint16(pos+28,true),xl=v.getUint16(pos+30,true),cl=v.getUint16(pos+32,true),off=v.getUint32(pos+42,true);
  const end=pos+46+nl+xl+cl;if(end>e)throw Error('Diretório incompleto.');
  const name=dec.decode(b.slice(pos+46,pos+46+nl));pos=end;
  if(/vbaProject|externalLinks/i.test(name))throw Error('Macros ou links externos não são aceitos.');
  if(!/^(xl\/workbook\.xml|xl\/_rels\/workbook\.xml\.rels|xl\/sharedStrings\.xml|xl\/worksheets\/sheet[0-9]+\.xml)$/.test(name))continue;
  if(parts.has(name)||(flag&1)||![0,8].includes(method)||unpacked>MAX||(total+=unpacked)>MAX||off+30>start||v.getUint32(off,true)!==0x04034b50)throw Error('Componente XLSX inválido.');
  const dataOff=off+30+v.getUint16(off+26,true)+v.getUint16(off+28,true);
  if(dataOff+packed>start)throw Error('Componente XLSX incompleto.');
  let data=b.slice(dataOff,dataOff+packed);
  if(method===8){
   const reader=new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw')).getReader();
   let used=0;const chunks=[];
   try{for(;;){const {done,value}=await reader.read();if(done)break;used+=value.length;if(used>unpacked||used>MAX)throw Error('Planilha compactada excede limite.');chunks.push(value);}}
   catch(e){await reader.cancel().catch(()=>{});throw e;}
   data=new Uint8Array(used);let at=0;for(const c of chunks){data.set(c,at);at+=c.length;}
  }
  if(data.length!==unpacked||crc32(data)!==crc)throw Error('Planilha corrompida.');
  parts.set(name,dec.decode(data));
 }
 return parts;
}
function parseXml(s){
 if(!s||/<!DOCTYPE|<!ENTITY/i.test(s))throw Error('XML inválido.');
 const d=new DOMParser().parseFromString(s,'application/xml');
 if(d.getElementsByTagName('parsererror').length)throw Error('XML inválido.');
 return d;
}
const tags=(d,name)=>[...d.getElementsByTagNameNS('*',name)];
export async function lerXlsx(file){
 const p=await unzipSelected(file),wb=parseXml(p.get('xl/workbook.xml')),rels=parseXml(p.get('xl/_rels/workbook.xml.rels'));
 const sheet=tags(wb,'sheet');if(sheet.length!==1||sheet[0].getAttribute('name')!=='COTACAO')throw Error('Use a aba COTACAO do modelo original.');
 const rid=sheet[0].getAttributeNS(REL,'id');
 const target=tags(rels,'Relationship').find(x=>x.getAttribute('Id')===rid)?.getAttribute('Target');
 const path=target?.startsWith('/')?target.slice(1):'xl/'+target;
 if(!/^xl\/worksheets\/sheet[0-9]+\.xml$/.test(path))throw Error('Aba de cotação inválida.');
 const d=parseXml(p.get(path));if(tags(d,'f').length)throw Error('Substitua fórmulas por valores numéricos antes de enviar.');
 const strings=p.has('xl/sharedStrings.xml')?tags(parseXml(p.get('xl/sharedStrings.xml')),'si').map(x=>tags(x,'t').map(t=>t.textContent).join('')):[];
 const rows=[],seen=new Set();
 for(const r of tags(d,'row')){
  const rn=Number(r.getAttribute('r'));if(!Number.isSafeInteger(rn)||rn<1||rn>202||seen.has(rn))throw Error('Linhas alteradas ou excedentes.');seen.add(rn);
  const row=rows[rn-1]=[],cells=new Set();
  for(const c of tags(r,'c')){
   const m=/^([A-F])([0-9]+)$/.exec(c.getAttribute('r')||'');
   const t=c.getAttribute('t'),val=tags(c,'v')[0]?.textContent||'';
   let x=t==='inlineStr'?tags(c,'t').map(x=>x.textContent).join(''):t==='s'?strings[Number(val)]:val;
   if(x===undefined||t==='e'||t==='b')throw Error('Célula inválida.');
   if(!m||Number(m[2])!==rn){if(x!=='')throw Error('Colunas adicionais não são aceitas.');continue;}
   const j=m[1].charCodeAt(0)-65;if(cells.has(j))throw Error('Célula duplicada.');cells.add(j);row[j]=x;
  }
 }
 return rows;
}
