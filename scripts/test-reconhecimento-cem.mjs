import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const app=readFileSync(new URL('../app.html',import.meta.url),'utf8');
const sql=readFileSync(new URL('../database/proposals/20261126_reconhecimento_cem_descricao_exata.sql',import.meta.url),'utf8');
const extract=(a,b)=>app.slice(app.indexOf(a),app.indexOf(b,app.indexOf(a)));
assert.ok(app.includes('id="recognitionScopeWork" checked'));
assert.ok(app.includes('id="recognitionScopeFuture"'));
assert.ok(app.includes("node('recognitionScopeFuture').checked=false"));
assert.ok(app.includes("p_reconhecer_futuras:node('recognitionScopeFuture').checked"));
assert.ok(app.includes('ew_desativar_regra_cem'));
const make=new Function(extract('function validarReconhecimento(){','function fecharConferenciaTipologia(){')+
extract('async function confirmarReconhecimentoTipologia(){','function renderModulacoesCadastradas(){')+
"\n const nodes=new Map();\n const node=id=>{if(!nodes.has(id))nodes.set(id,{value:'',checked:false,disabled:false,textContent:''});return nodes.get(id);};\n let recognitionPendingItem={id:'e'},typologyCatalog=[{id:'t',codigo:'T'}],modulationCatalog=[{id:'m'}],divergence=true,calls=[];\n const diferencaNoReconhecimento=()=>divergence,ensureSession=async()=>{},session={access_token:'fake'};\n const request=async(url,opts)=>{calls.push([url,opts.body]);return {numero_variacao:2,codigo_interno:'MOD2',esquadrias_classificadas:1,regra_autorizada:opts.body.p_reconhecer_futuras};};\n const fecharConferenciaTipologia=()=>{},loadPanel=async()=>{},renderTypologiesAdmin=()=>{},setView=()=>{};\n return {node,validarReconhecimento,confirmarReconhecimentoTipologia,calls,div:v=>divergence=v};\n")();
make.node('recognitionTarget').value='t';
make.node('recognitionModulation').value='__CRIAR__';
make.node('recognitionModDescription').value='Descrição exata';
make.validarReconhecimento();
assert.equal(make.node('recognitionConfirm').disabled,true);
make.node('recognitionApproval').checked=true;
make.validarReconhecimento();
assert.equal(make.node('recognitionConfirm').disabled,true,'exige aceitar divergência');
make.node('recognitionDivergence').checked=true;
make.validarReconhecimento();
assert.equal(make.node('recognitionConfirm').disabled,false,'quantidade de módulos é opcional');
await make.confirmarReconhecimentoTipologia();
assert.equal(make.calls[0][1].p_reconhecer_futuras,false);
make.node('recognitionScopeFuture').checked=true;
await make.confirmarReconhecimentoTipologia();
assert.equal(make.calls[1][1].p_reconhecer_futuras,true);
assert.equal(make.calls[1][1].p_confirmar_divergencia,true);
make.node('recognitionModCount').value='1.5';
make.validarReconhecimento();assert.equal(make.node('recognitionConfirm').disabled,true);
make.node('recognitionModulation').value='m';
make.validarReconhecimento();assert.equal(make.node('recognitionConfirm').disabled,false);
for(const token of ["CREATE UNIQUE INDEX regras_cem_uma_ativa","r.empresa_id=p_empresa_id","COLLATE \"C\"","a.modulacao_id<>r.modulacao_id","e.modulacao_id<>r.modulacao_id","AND r.ativo","ew_pode(v_item.empresa_id,'cadastros.editar')","ew_pode(p_empresa_id,'obras.importar')","NEW.reconhecimento_regra_cem_id IS DISTINCT FROM OLD.reconhecimento_regra_cem_id","INSERT INTO ew_tipologias_interna.aplicacoes_cem","REVOKE ALL ON SCHEMA ew_tipologias_interna","ENABLE ROW LEVEL SECURITY","ew_buscar_regra_cem(p_empresa_id,v_descricao,v_modulos)"]){
 assert.ok(sql.includes(token),'Contrato SQL ausente: '+token);
}
console.log('Reconhecimento CEM: autorização, divergência, escopo e contratos SQL aprovados.');
