import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const read=path=>readFileSync(fileURLToPath(new URL(path,import.meta.url)),'utf8');
const app=read('../app.html'),rel=read('../assets/relatorios-obras.js'),
 transfer=read('../assets/romaneios-transferencia.js');
const sql=read('../database/proposals/20261122_exclusao_definitiva_obras_v4618.sql');
assert.doesNotThrow(()=>new Function(rel),'Relatórios devem compilar');
assert.doesNotThrow(()=>new Function(transfer),'Romaneios devem compilar');
assert.match(app,/EWGEST <strong>· v46\.23<\/strong>/);
assert.match(app,/Exclusão definitiva e sem restauração/);
assert.match(app,/Excluir obra definitivamente/);
assert.match(app,/ATENÇÃO: PROCESSO IRREVERSÍVEL\. TEM CERTEZA QUE DESEJA ESTORNAR\?/);
const fluxoExcluir=app.slice(app.indexOf("node('manageWorksDelete').addEventListener('click'"),
 app.indexOf("window.addEventListener('error'"));
assert.doesNotMatch(fluxoExcluir,/Digite exatamente o código da obra para confirmar|window\.prompt\(/);
assert.doesNotMatch(app,/data-stock-restore|romTransfIncludeArchived|stockManageRestore\(/);
assert.doesNotMatch(app,/\/rest\/v1\/rpc\/ew_restaurar_estoque_local/);
assert.doesNotMatch(app,/\/rest\/v1\/rpc\/ew_excluir_estoque_local/);
assert.doesNotMatch(transfer,/incluirArquivados|carregarNomesArquivados|romTransfIncludeArchived/);
assert.match(transfer,/docs\.filter\(d=>!obraArquivada\(d\.obra_id\)\)/);

assert.match(rel,/arquivada_em:'is\.null'/);
for(const v of ['ctx.ativas.has(f.obra_id)','ctx.ativas.has(m.obra_id)',
 'ctx.ativas.has(x.elemento.obra_id)','ctx.ativas.has(x.obra_id)',
 'ctx.ativas.has(x.doc.obra_id)','ctx.ativas.has(d.obra_id)']){
 assert.ok(rel.includes(v),'Uma modalidade ainda aceita obra encerrada: '+v);
}
assert.match(sql,/CREATE OR REPLACE FUNCTION public\.ew_restaurar_estoque_local/);
assert.match(sql,/RESTAURACAO_DESATIVADA/);
assert.match(sql,/ARQUIVAMENTO_ISOLADO_DESATIVADO/);
assert.match(sql,/CREATE TRIGGER ew_bloquear_reabertura_obra/);
assert.match(sql,/CREATE TRIGGER ew_bloquear_reabertura_estoque/);
assert.match(sql,/REVOKE ALL ON FUNCTION public\.ew_restaurar_estoque_local/);
assert.match(sql,/REVOKE ALL ON FUNCTION public\.ew_excluir_estoque_local/);
console.log('OK v46.20: fechamento definitivo, sem restauração, seletores operacionais só ativos.');
