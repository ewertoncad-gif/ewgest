// Modelo XLSX específico para cotações EWGEST. Sem scripts externos.
export const HEADER=['Item','Material','Quantidade','Unidade','Comprimento (mm)','Preço unitário (R$)'];
export function modelo(solicitacao,fornecedor,linhas){
 if(!solicitacao||!fornecedor||!linhas.length||linhas.length>200)throw Error('Selecione solicitação e fornecedor.');
 return [['EWGEST-COTACAO-V1',String(solicitacao),String(fornecedor)],HEADER.slice(),...linhas.map(x=>[String(x.chave),String(x.material),Number(x.quantidade),String(x.unidade),x.comprimento_mm==null?'':Number(x.comprimento_mm),''])];
}
export function parsePreco(value){
 let s=String(value??'').trim().replace(/^R\$\s*/,'');
 if(/^\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?$/.test(s))s=s.replace(/\./g,'');
 if(!/^\d+(?:[.,]\d{1,2})?$/.test(s))return null;
 const c=Math.round(Number(s.replace(',','.'))*100);
 return Number.isSafeInteger(c)&&c>=0&&c<=100000000000?c:null;
}
export function validarRetorno(expected,actual){
 const get=(r,i)=>String(r?.[i]??'').trim();
 if(!Array.isArray(actual)||actual.length!==expected.length||expected[0].some((v,i)=>get(actual[0],i)!==String(v))||HEADER.some((v,i)=>get(actual[1],i)!==v))throw Error('Planilha de outra solicitação/fornecedor ou modelo alterado.');
 const byKey=new Map(expected.slice(2).map(r=>[String(r[0]),r])),seen=new Set(),prices=[];
 for(const row of actual.slice(2)){
  const k=get(row,0),original=byKey.get(k);
  if(!original||seen.has(k))throw Error('Item ausente ou repetido: '+k);seen.add(k);
  if(get(row,1)!==String(original[1]).trim()||get(row,2)===''||Number(get(row,2).replace(',','.'))!==original[2]||get(row,3)!==original[3]||get(row,4)!==String(original[4]))throw Error('Material, unidade ou quantidade alterada no item '+k);
  const cents=parsePreco(get(row,5));
  if(cents===null)throw Error('Preço inválido ou ausente no item '+k);
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
// O modelo lógico V1 é preservado para importar arquivos antigos e validar os itens.
// O layout comercial V2 guarda os identificadores em uma aba oculta.
export function exportarXlsx(rows,info={}){
 const first=7,last=first+rows.length-3,total=last+1;
 const cell=(col,r,x,style=0,formula=null)=>{
  const ref=col+r,base='<c r="'+ref+'" s="'+style+'"';
  if(formula)return base+'><f>'+xml(formula)+'</f></c>';
  if(x==='')return base+'/>';
  return typeof x==='number'?base+'><v>'+x+'</v></c>':base+' t="inlineStr"><is><t xml:space="preserve">'+xml(x)+'</t></is></c>';
 };
 const row=(n,c,h=24)=>'<row r="'+n+'" ht="'+h+'" customHeight="1">'+c.join('')+'</row>';
 const split=m=>{const i=m.indexOf(' · ');return i<0?['',m]:[m.slice(0,i),m.slice(i+3)];};
 const visible=[
 row(1,[cell('A',1,'COTAÇÃO DE MATERIAIS',1)],36),
 row(2,[cell('A',2,'EWGEST | '+(info.empresa||'Gestão de compras'),2)],24),
 row(3,[cell('A',3,'Obra / local: '+(info.obra||'Não informado'),3),cell('E',3,'Fornecedor: '+(info.fornecedor||'Não informado'),3)],28),
 row(4,[cell('A',4,'Grupo: '+(info.grupo||'Materiais'),3),cell('E',4,'Data: '+(info.data||new Date().toLocaleDateString('pt-BR')),3)],24),
 row(5,[cell('A',5,'Preencha apenas as células amarelas de preço unitário. Salve e devolva o arquivo original.',4)],30),
 row(6,['Item','Código','Descrição / acabamento','Quantidade','Unidade','Comp. (mm)','Preço unitário (R$)','Total (R$)'].map((v,i)=>cell(String.fromCharCode(65+i),6,v,5)),30),
 ...rows.slice(2).map((r,i)=>{const n=first+i,[code,desc]=split(String(r[1]));return row(n,[cell('A',n,String(r[0]),6),cell('B',n,code,6),cell('C',n,desc,7),cell('D',n,r[2],6),cell('E',n,r[3],6),cell('F',n,r[4],6),cell('G',n,r[5],8),cell('H',n,'',9,'IF(G'+n+'="","",ROUND(D'+n+'*G'+n+',2))')],Math.max(32,Math.min(100,16*Math.ceil(desc.length/48)+14)));}),
 row(total,[cell('A',total,'TOTAL GERAL',10),cell('H',total,'',11,'SUM(H'+first+':H'+last+')')],32)
 ].join('');
 const control=row(1,rows[0].map((v,i)=>cell(String.fromCharCode(65+i),1,v)))+row(2,[cell('A',2,'LAYOUT-V2')]);
 const styles='<styleSheet xmlns="'+NS+'"><numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;R$&quot; #,##0.00"/></numFmts>'+
 '<fonts count="4"><font><sz val="11"/><name val="Calibri"/><color rgb="FF23364D"/></font><font><b/><sz val="20"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font><font><b/><sz val="11"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font><font><b/><sz val="11"/><name val="Calibri"/><color rgb="FF183B57"/></font></fonts>'+
 '<fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF16354C"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF217A82"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEFF5F8"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/></patternFill></fill></fills>'+
 '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFD6E0E8"/></left><right style="thin"><color rgb="FFD6E0E8"/></right><top style="thin"><color rgb="FFD6E0E8"/></top><bottom style="thin"><color rgb="FFD6E0E8"/></bottom><diagonal/></border></borders>'+
 '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="12">'+
 [
 [0,0,0,0,''],[0,1,2,0,'horizontal="left"'],[0,2,3,0,'horizontal="left"'],[0,3,4,0,'wrapText="1"'],[0,0,4,0,'wrapText="1"'],[0,2,2,1,'horizontal="center" wrapText="1"'],[0,0,0,1,'horizontal="center"'],[0,0,0,1,'wrapText="1"'],[164,3,5,1,'horizontal="right"'],[164,0,4,1,'horizontal="right"'],[0,2,2,1,'horizontal="left"'],[164,2,2,1,'horizontal="right"']
 ].map(([num,font,fill,border,align],i)=>'<xf numFmtId="'+num+'" fontId="'+font+'" fillId="'+fill+'" borderId="'+border+'" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyNumberFormat="1" applyAlignment="1"'+(i===8?' applyProtection="1"':'')+'><alignment vertical="center" '+align+'/>'+(i===8?'<protection locked="0"/>':'')+'</xf>').join('')+'</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
 const ct='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+[1,2].map(n=>'<Override PartName="/xl/worksheets/sheet'+n+'.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join('')+'</Types>';
 return zip({
 '[Content_Types].xml':ct,
 '_rels/.rels':'<Relationships xmlns="'+PKG+'"><Relationship Id="rId1" Type="'+REL+'/officeDocument" Target="xl/workbook.xml"/></Relationships>',
 'xl/workbook.xml':'<workbook xmlns="'+NS+'" xmlns:r="'+REL+'"><sheets><sheet name="COTACAO" sheetId="1" r:id="rId1"/><sheet name="CONTROLE" sheetId="2" state="veryHidden" r:id="rId2"/></sheets><calcPr calcMode="auto" fullCalcOnLoad="1"/></workbook>',
 'xl/_rels/workbook.xml.rels':'<Relationships xmlns="'+PKG+'"><Relationship Id="rId1" Type="'+REL+'/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="'+REL+'/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="'+REL+'/styles" Target="styles.xml"/></Relationships>',
 'xl/styles.xml':styles,
 'xl/worksheets/sheet1.xml':'<worksheet xmlns="'+NS+'"><sheetViews><sheetView showGridLines="0" workbookViewId="0"><pane ySplit="6" topLeftCell="A7" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>'+[10,16,58,14,13,15,23,23].map((w,i)=>'<col min="'+(i+1)+'" max="'+(i+1)+'" width="'+w+'" customWidth="1"/>').join('')+'</cols><sheetData>'+visible+'</sheetData><sheetProtection sheet="1" objects="1" scenarios="1" autoFilter="0" selectLockedCells="0" selectUnlockedCells="0"/><autoFilter ref="A6:H'+last+'"/><mergeCells count="8">'+['A1:H1','A2:H2','A3:D3','E3:H3','A4:D4','E4:H4','A5:H5','A'+total+':G'+total].map(ref=>'<mergeCell ref="'+ref+'"/>').join('')+'</mergeCells><pageMargins left="0.25" right="0.25" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/></worksheet>',
 'xl/worksheets/sheet2.xml':'<worksheet xmlns="'+NS+'"><sheetData>'+control+'</sheetData></worksheet>'
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
 const sheets=tags(wb,'sheet'),v2=sheets.length===2&&sheets.some(x=>x.getAttribute('name')==='CONTROLE');
 if(!(sheets.length===1||v2)||!sheets.some(x=>x.getAttribute('name')==='COTACAO'))throw Error('Use a aba COTACAO do modelo original.');
 const strings=p.has('xl/sharedStrings.xml')?tags(parseXml(p.get('xl/sharedStrings.xml')),'si').map(x=>tags(x,'t').map(t=>t.textContent).join('')):[];
 function read(name,max,cols,allowFormula){
  const sheet=sheets.find(x=>x.getAttribute('name')===name),rid=sheet.getAttributeNS(REL,'id');
  const target=tags(rels,'Relationship').find(x=>x.getAttribute('Id')===rid)?.getAttribute('Target');
  const path=target?.startsWith('/')?target.slice(1):'xl/'+target;
  if(!/^xl\/worksheets\/sheet[0-9]+\.xml$/.test(path))throw Error('Aba de cotação inválida.');
  const d=parseXml(p.get(path)),rows=[],seen=new Set();
  for(const r of tags(d,'row')){
   const rn=Number(r.getAttribute('r'));if(!Number.isSafeInteger(rn)||rn<1||rn>max||seen.has(rn))throw Error('Linhas alteradas ou excedentes.');seen.add(rn);
   const row=rows[rn-1]=[],cells=new Set();
   for(const c of tags(r,'c')){
    const m=/^([A-Z])([0-9]+)$/.exec(c.getAttribute('r')||''),t=c.getAttribute('t'),val=tags(c,'v')[0]?.textContent||'',formula=tags(c,'f')[0];
    if(formula&&!allowFormula?.(m?.[1],rn,formula.textContent))throw Error('Fórmula não permitida no modelo de cotação.');
    let x=t==='inlineStr'?tags(c,'t').map(x=>x.textContent).join(''):t==='s'?strings[Number(val)]:val;
    if(x===undefined||(!formula&&(t==='e'||t==='b')))throw Error('Célula inválida.');
    if(!m||Number(m[2])!==rn||m[1].charCodeAt(0)-65>=cols){if(x!=='')throw Error('Colunas adicionais não são aceitas.');continue;}
    const j=m[1].charCodeAt(0)-65;if(cells.has(j))throw Error('Célula duplicada.');cells.add(j);row[j]=formula?'':x;
   }
  }
  return rows;
 }
 if(!v2)return read('COTACAO',202,6);
 const control=read('CONTROLE',2,3);
 if(control[1]?.[0]!=='LAYOUT-V2')throw Error('Controle da cotação inválido.');
 const rows=read('COTACAO',207,8,(col,r,f)=>col==='H'&&r>=7&&(
 f===('IF(G'+r+'="","",ROUND(D'+r+'*G'+r+',2))')||f===('SUM(H7:H'+(r-1)+')')));
 const header=['Item','Código','Descrição / acabamento','Quantidade','Unidade','Comp. (mm)','Preço unitário (R$)','Total (R$)'];
 if(header.some((v,i)=>rows[5]?.[i]!==v)||rows.at(-1)?.[0]!=='TOTAL GERAL')throw Error('Cabeçalho ou total do modelo alterado.');
 const items=rows.slice(6,-1).map(r=>{if(!r)throw Error('Linha de item ausente.');return [r[0],r[1]?r[1]+' · '+(r[2]||''):(r[2]||''),r[3],r[4],r[5]||'',r[6]||''];});
 return [control[0],HEADER.slice(),...items];
}
