-- Traz para o novo relatório os cancelamentos anteriores já comprovados pelo banco.
-- Não inventa horários, operadores ou motivos: usa apenas campos existentes.
create unique index if not exists ew_auditoria_cancelamento_romaneio_unico
 on public.ew_auditoria_operacoes(referencia_id) where acao='CANCELAR_ROMANEIO';
insert into public.ew_auditoria_operacoes
 (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,referencia_id,motivo,detalhes,criado_em)
select r.empresa_id,r.obra_id,o.nome,o.codigo,r.cancelado_por,'CANCELAR_ROMANEIO',r.id,
 r.motivo_cancelamento,
 jsonb_build_object('numero',r.numero,'status_novo','cancelado',
  'criado_por',r.criado_por,'criado_em',r.criado_em,'cancelado_em',r.cancelado_em,
  'origem','cancelamento_anterior_a_v43_1'),r.cancelado_em
from public.romaneios r join public.obras o on o.id=r.obra_id
where r.status='cancelado' and r.cancelado_por is not null
 and r.cancelado_em is not null and nullif(r.motivo_cancelamento,'') is not null
 and not exists (select 1 from public.ew_auditoria_operacoes a
  where a.acao='CANCELAR_ROMANEIO' and a.referencia_id=r.id);
