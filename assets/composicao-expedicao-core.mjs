// Núcleo independente; peso em pontos-base inteiros (100% = 10000).
export function validarComposicao(partes){
 if(!Array.isArray(partes)||partes.length<1||partes.length>30)throw new Error('Informe de 1 a 30 componentes.');
 const ids=new Set(),nomes=new Set();
 const resultado=partes.map(p=>{
  const id=String(p.id||'').trim(),nome=String(p.nome||'').trim();
  const quantidade=Number(p.quantidade),peso=Number(p.peso);
  const chave=normalizar(nome);
  if(!id||ids.has(id)||!chave||nome.length>100||nomes.has(chave))throw new Error('Identificador ou nome de componente repetido/inválido.');
  if(!Number.isSafeInteger(quantidade)||quantidade<1||quantidade>100)throw new Error('Quantidade física por esquadria inválida.');
  if(!Number.isSafeInteger(peso)||peso<1||peso>10000)throw new Error('Percentual inválido.');
  ids.add(id);nomes.add(chave);return {id,nome,quantidade,peso};
 });
 if(resultado.reduce((s,p)=>s+p.peso,0)!==10000)throw new Error('Os percentuais devem somar 100%.');
 return resultado;
}
export function calcularSaldo(partes,liberadas,saidas=[]){
 const p=validarComposicao(partes);
 if(!Number.isSafeInteger(liberadas)||liberadas<0)throw new Error('Quantidade liberada inválida.');
 const mapa=new Map(p.map(x=>[x.id,{...x,total:liberadas*x.quantidade,enviado:0}]));
 for(const x of saidas){
  if(x.cancelada===true)continue;
  const linha=mapa.get(x.id);
  if(!linha||!Number.isSafeInteger(x.quantidade)||x.quantidade<1)throw new Error('Histórico de expedição inválido.');
  linha.enviado+=x.quantidade;
 }
 const linhas=[...mapa.values()].map(x=>{
  if(!Number.isSafeInteger(x.total)||x.enviado>x.total)throw new Error('Expedição acima da quantidade liberada.');
  return {...x,saldo:x.total-x.enviado};
 });
 return {linhas,completas:Math.min(...linhas.map(x=>Math.floor(x.saldo/x.quantidade)))};
}
export function expandirCompleta(partes,quantidade){
 if(!Number.isSafeInteger(quantidade)||quantidade<1)throw new Error('Quantidade inválida.');
 return validarComposicao(partes).map(p=>({id:p.id,quantidade:p.quantidade*quantidade}));
}
// Não arredondar antes de somar; servidor deve usar NUMERIC e revisão imutável.
export function areaExpedida(partes,liberadas,saidas,larguraMm,alturaMm){
 const area=Number(larguraMm)*Number(alturaMm)/1000000;
 if(!Number.isFinite(area)||!(Number(larguraMm)>0)||!(Number(alturaMm)>0))throw new Error('Dimensão inválida.');
 return calcularSaldo(partes,liberadas,saidas).linhas.reduce((s,x)=>s+area*x.enviado*x.peso/(10000*x.quantidade),0);
}
const normalizar=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]+/g,' ').trim().replace(/\s+/g,' ');
// Sugestão conservadora: descartar sufixo comercial explícito, não elementos técnicos.
// Seleção sempre manual; o operador precisa conferir a descrição integral.
export function assinaturaEstrutural(t){
 const tecnica=String(t.descricao||'').split(/\bLINHA\b/i)[0];
 const fabricante=normalizar(t.fabricante);
 let base=normalizar(tecnica);
 if(fabricante&&base.endsWith(' '+fabricante))base=base.slice(0,-fabricante.length-1);
 return base.replace(/\bMAXIM AR\b/g,'MAXIMAR').replace(/\bFOLHAS\b/g,'FOLHA').replace(/\bCOM\b/g,'').replace(/\s+/g,' ').trim();
}
export function sugerirSimilares(origem,catalogo){
 const assinatura=assinaturaEstrutural(origem);
 if(!assinatura||!origem.empresa_id)return [];
 return catalogo.filter(t=>t.id!==origem.id&&t.empresa_id===origem.empresa_id&&
  assinaturaEstrutural(t)===assinatura&&Number(t.quantidade_modulos||1)===Number(origem.quantidade_modulos||1))
 .sort((a,b)=>String(a.codigo).localeCompare(String(b.codigo),'pt-BR',{numeric:true}));
}
