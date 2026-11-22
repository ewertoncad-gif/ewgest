// EWGEST v46.9 — testa a API HTTP do PostgreSQL/PostgREST de CI.
// JWTs assinados com SEGREDO FICTÍCIO local, usuários/empresas fictícios.
// Nunca enviar senhas, chaves ou tokens de Supabase de produção ao runner.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHmac} from 'node:crypto';
const jwtSecret='ewgest-homologacao-somente-dados-ficticios-20261122';
const base='http://127.0.0.1:3000';
const admin='11111111-1111-4111-8111-111111111111';
const almox='22222222-2222-4222-8222-222222222222';
const adminB='44444444-4444-4444-8444-444444444444';
const fixture=readFileSync('tests/homologacao_pg17/10_cenarios.sql','utf8');
const match=fixture.match(/INSERT INTO public\._homolog_payload VALUES \('(\{[^\n]*\})'::jsonb\)/);
assert.ok(match,'Fixture sintética de precificação não encontrada');
const original=JSON.parse(match[1]);
function jwt(sub){
 const b64=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
 const header=b64({alg:'HS256',typ:'JWT'});
 const claims=b64({role:'authenticated',sub,exp:Math.floor(Date.now()/1000)+3600,
   iat:Math.floor(Date.now()/1000),aud:'authenticated'});
 const data=header+'.'+claims;
 return data+'.'+createHmac('sha256',jwtSecret).update(data).digest('base64url');
}
const authHeader=sub=>sub?{Authorization:'Bearer '+jwt(sub)}:{};
async function api(path,body,sub=null,method='POST'){
 const response=await fetch(base+path,{
  method,headers:{...authHeader(sub), ...(method==='POST'?{'Content-Type':'application/json'}:{})},
  ...(method==='POST'?{body:JSON.stringify(body)}:{})
 });
 const txt=await response.text();
 let data;
 try{data=JSON.parse(txt)}catch{data=txt}
 return {status:response.status,data};
}
const input={
 p_empresa_id:original.empresa_id,
 p_codigo_obra:'HOMOLOG-REST-01',
 p_nome_obra:'OBRA FICTICIA COM REST API',
 p_cliente:original.cliente,
 p_esquadrias:original.esquadrias,
 p_perfis:[],
 p_acessorios:[],
 p_operacao_id:'dddddddd-1111-4111-8111-111111111111',
 p_decisoes:[],
 p_orcamento:original.orcamento,
 p_precificacao:original.precificacao
};
const endpoint='/rpc/ew_importar_obra_cem_precificacao';
const anon=await api(endpoint,input);
assert.ok([401,403].includes(anon.status),
 'Sem JWT não pode chamar RPC de importação privilegiada: '+JSON.stringify(anon));
const almoxarife=await api(endpoint,input,almox);
assert.ok(almoxarife.status>=400,
 'Almoxarife nunca pode importar com preços: '+JSON.stringify(almoxarife));
assert.match(JSON.stringify(almoxarife.data),/Somente ADM/);
const correto=await api(endpoint,input,admin);
assert.equal(correto.status,200,'Administrador deve conseguir importar: '+JSON.stringify(correto));
assert.equal(correto.data.precificacao_gravada,true);
assert.equal(correto.data.orcamento_gravado,true);
assert.equal(correto.data.esquadrias_novas,2);
assert.equal(correto.data.estoque_fisico_alterado,false);
assert.ok(correto.data.obra_id,'ID da obra esperado');
const retry=await api(endpoint,input,admin);
assert.equal(retry.status,200,'Reenvio idempotente deve retornar HTTP 200');
assert.equal(retry.data.ja_importado,true);
assert.equal(retry.data.obra_id,correto.data.obra_id);
const adulterado=structuredClone(input);
adulterado.p_precificacao.percentual_fabricacao_bp=5000;
const rejeitado=await api(endpoint,adulterado,admin);
assert.ok(rejeitado.status>=400,'Payload alterado não deve usar operação anterior');
assert.match(JSON.stringify(rejeitado.data),/outros dados/);
const lista='/ew_precificacao_revisoes?select=obra_id,versao,empresa_id,aprovado_por';
const anonLeitura=await api(lista,null,null,'GET');
assert.ok([401,403].includes(anonLeitura.status)||(
 anonLeitura.status===200&&Array.isArray(anonLeitura.data)&&anonLeitura.data.length===0),
 'Anon nunca pode obter histórico financeiro');
const semPermissao=await api(lista,null,almox,'GET');
assert.equal(semPermissao.status,200,'Usuário autenticado recebe filtro RLS (lista vazia)');
assert.deepEqual(semPermissao.data,[]);
const admLeitura=await api(lista,null,admin,'GET');
assert.equal(admLeitura.status,200,'ADM precisa ler a revisão aprovada');
assert.ok(Array.isArray(admLeitura.data)&&
 admLeitura.data.some(x=>x.obra_id===correto.data.obra_id&&x.versao===1));
console.log('OK: PostgREST local sem sessão/almoxarife bloqueados; ADM via JWT grava obra, retry idempotente, payload divergente rejeitado e RLS na leitura.');


// CONCORRENCIA E ISOLAMENTO MULTIEMPRESA (somente JWT/obras fictícias).
const importacaoNova=structuredClone(input);
importacaoNova.p_codigo_obra='HOMOLOG-REST-CORRIDA';
importacaoNova.p_nome_obra='OBRA FICTICIA COM REQUISICOES SIMULTANEAS';
importacaoNova.p_operacao_id='eeeeeeee-1111-4111-8111-111111111111';
const emParalelo=await Promise.all([
 api(endpoint,importacaoNova,admin),
 api(endpoint,importacaoNova,admin)
]);
assert.deepEqual(emParalelo.map(x=>x.status),[200,200],
 'Mesmo ID submetido simultaneamente precisa dar duas respostas confirmadas');
assert.deepEqual(emParalelo.map(x=>x.data.obra_id),
 [emParalelo[0].data.obra_id,emParalelo[0].data.obra_id],
 'Duas requisições simultâneas não podem criar obras distintas');
assert.equal(emParalelo.filter(x=>x.data.ja_importado===true).length,1,
 'Apenas uma das duas requisições repetidas deve reconhecer o resultado anterior');
assert.equal(emParalelo.filter(x=>x.data.ja_importado!==true).length,1,
 'Somente uma gravação deve ter sido executada');

const tentativaB=structuredClone(input);
tentativaB.p_codigo_obra='HOMOLOG-REST-ATAQUE-B';
tentativaB.p_nome_obra='OBRA FICTICIA BLOQUEADA';
tentativaB.p_operacao_id='ffffffff-1111-4111-8111-111111111111';
const gravacaoB=await api(endpoint,tentativaB,adminB);
assert.ok(gravacaoB.status>=400,'ADM de empresa B não importa na A');
assert.match(JSON.stringify(gravacaoB.data),/Somente ADM/);
for(const tabela of ['ew_precificacao_revisoes','ew_precificacao_revisoes_itens',
 'ew_precificacao_revisoes_categorias','ew_precificacao_categorias',
 'ew_precificacao_tipologias_padrao']){
 const res=await api('/'+tabela+'?select=*',null,adminB,'GET');
 assert.equal(res.status,200,'Tabelas de precificação devem responder com RLS: '+tabela);
 assert.deepEqual(res.data,[],
  'RLS não pode revelar históricos, preços ou padrões da empresa A à B: '+tabela);
}
const acessoDireto=await api('/ew_precificacao_revisoes', {
 empresa_id:input.p_empresa_id,obra_id:correto.data.obra_id,versao:999
},admin);
assert.ok([401,403].includes(acessoDireto.status),
 'Mesmo ADM deve registrar revisões apenas pela RPC autorizada');
const expirada=jwt(admin).split('.');
const claims={role:'authenticated',sub:admin,aud:'authenticated',
 exp:Math.floor(Date.now()/1000)-3600,iat:Math.floor(Date.now()/1000)-7200};
const header=expirada[0],payload=Buffer.from(JSON.stringify(claims)).toString('base64url');
const jwtExpirado=header+'.'+payload+'.'+createHmac('sha256',jwtSecret)
 .update(header+'.'+payload).digest('base64url');
const expiredResponse=await fetch(base+endpoint,{
 method:'POST',headers:{Authorization:'Bearer '+jwtExpirado,'Content-Type':'application/json'},
 body:JSON.stringify(tentativaB)
});
assert.ok([401,403].includes(expiredResponse.status),
 'JWT expirado nunca pode autorizar RPC');
// O bloqueio de outra empresa e de acesso direto não deve alterar a contagem.
const revisoesFinais=await api('/ew_precificacao_revisoes?select=id',null,admin,'GET');
assert.equal(revisoesFinais.status,200);
assert.equal(revisoesFinais.data.length,3,
 'Uma revisão SQL + uma HTTP original + uma concorrente; sem duplicidade ou invasão');
console.log('OK: HTTP com concorrência de operações iguais, isolamento de ADM de outra empresa, proteção de escrita direta e JWT expirado.');
