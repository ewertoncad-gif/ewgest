-- EWGEST #38 — estorno físico de NF-e aprovada, preservando a nota e o histórico.
-- Estoques são fungíveis no nível (obra, variação, comprimento, unidade, galpão).
-- Impede estorno se houver consumo de produção após o recebimento. Transferências
-- entre galpões da MESMA obra são permitidas, com conferência do saldo atual.
alter table public.ew_nfe_recebimentos
 add column if not exists estornado_em timestamptz,
 add column if not exists estornado_por uuid references auth.users(id),
 add column if not exists estorno_motivo text,
 add column if not exists estorno_operacao_id uuid,
 add column if not exists estorno_detalhes jsonb;
-- Permite receber novamente uma NF-e cujo recebimento anterior foi estornado,
-- sem apagar a linha original nem seu vínculo com o movimento de estoque.
alter table public.ew_nfe_recebimentos
 drop constraint if exists ew_nfe_recebimentos_despesa_item_id_key;
create unique index if not exists ew_nfe_recebimento_item_ativo_unico
 on public.ew_nfe_recebimentos(despesa_item_id) where estornado_em is null;
create unique index if not exists ew_nfe_recebimento_estorno_operacao_unica
 on public.ew_nfe_recebimentos(estorno_operacao_id)
 where estorno_operacao_id is not null;

CREATE OR REPLACE FUNCTION public.ew_receber_item_nfe(p_empresa_id uuid, p_despesa_item_id uuid, p_variacao_id uuid, p_quantidade numeric, p_unidade text, p_comprimento_mm integer, p_local_estoque text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();v_despesa public.ew_obra_despesas%ROWTYPE;
 v_item public.ew_obra_despesas_itens%ROWTYPE;
 v_variacao public.ew_materiais_variacoes%ROWTYPE;
 v_recebido uuid;v_mov jsonb;v_id uuid;v_unidade text:=upper(btrim(coalesce(p_unidade,'')));
 v_local text:=upper(btrim(coalesce(p_local_estoque,'')));
 v_unidade_cadastro text;v_unidade_embalagem text;v_fator_embalagem numeric;
 v_unidade_nf text;v_limite_fisico numeric;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_empresa_id IS NULL OR p_operacao_id IS NULL OR
   NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
     ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM confirma entradas físicas provenientes de NF-e.';END IF;
 IF p_despesa_item_id IS NULL OR p_variacao_id IS NULL OR
   p_quantidade IS NULL OR p_quantidade<=0 OR p_quantidade>1000000 OR
   p_quantidade<>round(p_quantidade,3)
 THEN RAISE EXCEPTION 'Item ou quantidade de recebimento inválidos.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(p_despesa_item_id::text,912423));
 SELECT id INTO v_recebido FROM public.ew_nfe_recebimentos WHERE despesa_item_id=p_despesa_item_id AND estornado_em IS NULL;
 IF v_recebido IS NOT NULL THEN RETURN jsonb_build_object('id',v_recebido,'ja_recebido',true);END IF;
 SELECT * INTO v_item FROM public.ew_obra_despesas_itens
 WHERE id=p_despesa_item_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Item de nota não encontrado nesta empresa.';END IF;
 SELECT * INTO v_despesa FROM public.ew_obra_despesas
 WHERE id=v_item.despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_despesa.status<>'aprovada' OR v_despesa.categoria NOT IN ('aluminio','acessorios') OR
   v_despesa.origem<>'nfe_xml' OR v_despesa.chave_nfe IS NULL
 THEN RAISE EXCEPTION 'A NF-e deve estar aprovada e classificada como alumínio ou acessórios.';END IF;
 SELECT * INTO v_variacao FROM public.ew_materiais_variacoes
 WHERE id=p_variacao_id AND empresa_id=p_empresa_id;
 IF NOT FOUND OR
   (v_despesa.categoria='aluminio' AND
     (v_variacao.tipo<>'perfil' OR v_item.perfil_id IS DISTINCT FROM v_variacao.perfil_id)) OR
   (v_despesa.categoria='acessorios' AND
     (v_variacao.tipo<>'acessorio' OR v_item.acessorio_id IS DISTINCT FROM v_variacao.acessorio_id))
 THEN RAISE EXCEPTION 'Variação incompatível com o item da NF-e. Vincule o material correto antes de receber.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais WHERE
   empresa_id=p_empresa_id AND obra_id=v_despesa.obra_id AND excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Estoque da obra inexistente ou arquivado.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_locais_fisicos WHERE
   empresa_id=p_empresa_id AND nome=v_local AND ativo)
 THEN RAISE EXCEPTION 'Selecione um galpão válido.';END IF;
 v_unidade_nf:=upper(btrim(coalesce(v_item.unidade,'')));
 IF v_variacao.tipo='perfil' THEN
   IF v_unidade<>'BARRA' OR p_comprimento_mm NOT BETWEEN 100 AND 20000 OR
      p_quantidade<>trunc(p_quantidade)
   THEN RAISE EXCEPTION 'Perfis exigem quantidade inteira em BARRA e comprimento comercial em mm.';END IF;
   IF v_unidade_nf IN ('BARRA','BR') AND p_quantidade>v_item.quantidade
   THEN RAISE EXCEPTION 'Quantidade recebida maior que o número de barras da NF-e.';END IF;
   IF v_unidade_nf IN ('MT','M') AND p_quantidade*p_comprimento_mm/1000>v_item.quantidade+0.0001
   THEN RAISE EXCEPTION 'Metros em barras ultrapassam os metros registrados na NF-e.';END IF;
 ELSE
   SELECT upper(btrim(unidade_item)),upper(btrim(unidade_embalagem)),quantidade_por_embalagem
   INTO v_unidade_cadastro,v_unidade_embalagem,v_fator_embalagem
   FROM public.ew_acessorios
   WHERE id=v_variacao.acessorio_id AND empresa_id=p_empresa_id;
   IF v_unidade_cadastro IN ('PEÇA','PECA','PÇ','PÇS') THEN v_unidade_cadastro:='PC';END IF;
   IF v_unidade_cadastro IN ('PAR','PARES') THEN v_unidade_cadastro:='PR';END IF;
   IF v_unidade_cadastro IN ('METRO','M') THEN v_unidade_cadastro:='MT';END IF;
   IF v_unidade_cadastro='UNIDADE' THEN v_unidade_cadastro:='UN';END IF;
   IF p_comprimento_mm IS NOT NULL OR v_unidade<>v_unidade_cadastro
   THEN RAISE EXCEPTION 'Unidade do recebimento deve ser a unidade do item (%). Converta embalagens antes.',v_unidade_cadastro;END IF;
   IF v_unidade_nf=v_unidade_cadastro THEN v_limite_fisico:=v_item.quantidade;
   ELSIF v_unidade_nf=v_unidade_embalagem AND coalesce(v_fator_embalagem,0)>0
   THEN v_limite_fisico:=v_item.quantidade*v_fator_embalagem;
   ELSIF v_unidade_nf='UN' AND v_unidade_cadastro='PC'
   THEN v_limite_fisico:=v_item.quantidade;
   ELSE RAISE EXCEPTION 'Unidade da NF-e (%) não é compatível com a unidade do item (%) nem tem conversão cadastrada.',
     v_unidade_nf,v_unidade_cadastro;
   END IF;
   IF p_quantidade>v_limite_fisico+0.001
   THEN RAISE EXCEPTION 'Recebimento excede a quantidade da NF-e convertida: % %.',v_limite_fisico,v_unidade_cadastro;END IF;
 END IF;
 -- A movimentação e o vínculo à NF-e são atômicos: erro reverte as duas inserções.
 v_mov:=public.ew_movimentar_estoque_obra_local(
   p_empresa_id,v_despesa.obra_id,p_variacao_id,p_comprimento_mm,v_unidade,
   p_quantidade,'COMPRA','Recebimento confirmado da NF-e '||left(v_despesa.numero_documento,75),
   p_operacao_id,v_local);
 IF coalesce((v_mov->>'repetida')::boolean,false) OR (v_mov->>'id') IS NULL
 THEN RAISE EXCEPTION 'Operação de estoque já utilizada; confira o histórico antes de repetir.';END IF;
 INSERT INTO public.ew_nfe_recebimentos(
   empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,
   unidade,quantidade,local_estoque,movimento_id,usuario_id)
 VALUES(p_empresa_id,v_despesa.obra_id,p_despesa_item_id,p_variacao_id,p_comprimento_mm,
   v_unidade,p_quantidade,v_local,(v_mov->>'id')::uuid,v_uid) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'obra_id',v_despesa.obra_id,'movimento_id',v_mov->>'id',
   'quantidade',p_quantidade,'unidade',v_unidade,'ja_recebido',false);
END;
$function$
;

create or replace function public.ew_estornar_recebimento_nfe(
 p_empresa_id uuid,p_recebimento_id uuid,p_motivo text,p_operacao_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
 v_user uuid:=auth.uid();
 v_rec public.ew_nfe_recebimentos%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_obra public.obras%rowtype;
 v_local record;
 v_motivo text:=btrim(coalesce(p_motivo,''));
 v_disponivel numeric:=0;
 v_restante numeric;
 v_baixas integer;
 v_abatido numeric;
 v_mov uuid;
 v_locais jsonb:='[]'::jsonb;
 v_primeiro boolean:=true;
begin
 perform public.ew_exigir_sessao_atual();
 if v_user is null or p_empresa_id is null or p_recebimento_id is null or p_operacao_id is null
  or not exists(select 1 from public.usuarios_empresas ue
    join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
    where ue.usuario_id=v_user and ue.empresa_id=p_empresa_id
      and ue.perfil='administrador' and ul.perfil='administrador'
      and ul.ativo and ul.excluido_em is null)
 then raise exception 'Somente o ADM pode estornar recebimentos de NF-e.';end if;
 if char_length(v_motivo) not between 5 and 400 then raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_recebimento_id::text,912425));
 select * into v_rec from public.ew_nfe_recebimentos n
  where n.id=p_recebimento_id and n.empresa_id=p_empresa_id for update;
 if not found then raise exception 'Recebimento não encontrado na empresa.';end if;
 if v_rec.estornado_em is not null then
   if v_rec.estorno_operacao_id=p_operacao_id then
     return jsonb_build_object('ja_estornado',true,'recebimento_id',v_rec.id,
       'locais',coalesce(v_rec.estorno_detalhes,'[]'::jsonb));
   end if;
   raise exception 'Recebimento já estornado anteriormente. Consulte o histórico.';
 end if;
 if exists(select 1 from public.ew_nfe_recebimentos n
  where n.estorno_operacao_id=p_operacao_id and n.id<>p_recebimento_id)
 then raise exception 'Identificador usado em outro estorno.';end if;
 select * into v_obra from public.obras o where o.id=v_rec.obra_id
  and o.empresa_id=p_empresa_id and o.arquivada_em is null for update;
 if not found then raise exception 'Obra não encontrada ou arquivada.';end if;
 select * into v_original from public.ew_estoque_obras_movimentos m
  where m.id=v_rec.movimento_id and m.empresa_id=p_empresa_id
   and m.obra_id=v_rec.obra_id for update;
 if not found or v_original.quantidade_delta<>v_rec.quantidade
    or v_original.variacao_id<>v_rec.variacao_id
    or v_original.comprimento_mm is distinct from v_rec.comprimento_mm
    or v_original.unidade<>v_rec.unidade
    or v_original.origem<>'COMPRA'
 then raise exception 'O recebimento original não confere com a movimentação de compra.';end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.estorno_de_id=v_original.id)
 then raise exception 'Movimento original já possui estorno associado. Revisão manual necessária.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   v_rec.obra_id::text||'|'||v_rec.variacao_id::text||'|'||
   coalesce(v_rec.comprimento_mm::text,'-')||'|'||v_rec.unidade,34777));
 -- Sem identificação de lote por NF, qualquer baixa de consumo posterior da MESMA
 -- variação/medida/unidade impede declarar o lote recebido como ainda não utilizado.
 -- Transferência de galpão não é consumo.
 select count(*) into v_baixas from public.ew_estoque_obras_movimentos m
 where m.empresa_id=p_empresa_id and m.obra_id=v_rec.obra_id
   and m.variacao_id=v_rec.variacao_id
   and m.comprimento_mm is not distinct from v_rec.comprimento_mm
   and m.unidade=v_rec.unidade and m.quantidade_delta<0
   and m.criado_em>=v_rec.criado_em
   and m.origem in ('PLANO_CORTE','PLANO_CORTE_LOTE','SAIDA_MANUAL','AJUSTE');
 if v_baixas>0 then raise exception
  'Estorno bloqueado: há baixa de produção/consumo após esta NF. O estoque não rastreia lote por nota; confira a entrega e faça reconciliação autorizada.';end if;
 select coalesce(sum(q.saldo),0) into v_disponivel from (
   select sum(m.quantidade_delta) saldo from public.ew_estoque_obras_movimentos m
   where m.empresa_id=p_empresa_id and m.obra_id=v_rec.obra_id
    and m.variacao_id=v_rec.variacao_id
    and m.comprimento_mm is not distinct from v_rec.comprimento_mm
    and m.unidade=v_rec.unidade
   group by m.local_estoque having sum(m.quantidade_delta)>0
 ) q;
 if v_disponivel<v_rec.quantidade then
  raise exception 'Saldo disponível na obra insuficiente (% %). Se transferido para outra obra, devolva antes do estorno.',
   v_disponivel,v_rec.unidade;end if;
 v_restante:=v_rec.quantidade;
 for v_local in
  select m.local_estoque,sum(m.quantidade_delta) as saldo
  from public.ew_estoque_obras_movimentos m
  where m.empresa_id=p_empresa_id and m.obra_id=v_rec.obra_id
   and m.variacao_id=v_rec.variacao_id
   and m.comprimento_mm is not distinct from v_rec.comprimento_mm
   and m.unidade=v_rec.unidade
  group by m.local_estoque having sum(m.quantidade_delta)>0
  order by (m.local_estoque=v_rec.local_estoque) desc,m.local_estoque
 loop
  exit when v_restante<=0;
  v_abatido:=least(v_local.saldo,v_restante);
  insert into public.ew_estoque_obras_movimentos
   (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
    origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
  values(p_empresa_id,v_rec.obra_id,v_rec.variacao_id,v_rec.comprimento_mm,
    v_rec.unidade,-v_abatido,'ESTORNO',gen_random_uuid(),
    left('Estorno do recebimento NF (sem cancelar a despesa): '||v_motivo,500),
    v_user,v_local.local_estoque,case when v_primeiro then v_original.id else null end)
  returning id into v_mov;
  v_primeiro:=false;
  v_locais:=v_locais||jsonb_build_array(jsonb_build_object(
    'galpao',v_local.local_estoque,'quantidade',v_abatido,'movimento_id',v_mov));
  v_restante:=v_restante-v_abatido;
 end loop;
 if v_restante<>0 then raise exception 'Não foi possível completar o estorno físico.';end if;
 update public.ew_nfe_recebimentos
 set estornado_em=now(),estornado_por=v_user,estorno_motivo=v_motivo,
  estorno_operacao_id=p_operacao_id,estorno_detalhes=v_locais
 where id=v_rec.id and empresa_id=p_empresa_id and estornado_em is null;
 return jsonb_build_object('ja_estornado',false,'recebimento_id',v_rec.id,
  'quantidade_estornada',v_rec.quantidade,'unidade',v_rec.unidade,
  'locais',v_locais,'despesa_preservada',true);
end
$f$;
revoke all on function public.ew_estornar_recebimento_nfe(uuid,uuid,text,uuid) from public;
revoke execute on function public.ew_estornar_recebimento_nfe(uuid,uuid,text,uuid) from anon;
grant execute on function public.ew_estornar_recebimento_nfe(uuid,uuid,text,uuid) to authenticated;

-- Mantém indicadores de Recebimento corretos após estorno (não contar entradas anuladas).
CREATE OR REPLACE FUNCTION public.ew_quantidades_recebidas_obra(p_empresa_id uuid, p_obra_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or not exists (
  select 1 from public.usuarios_empresas u where u.usuario_id=v_uid
    and u.empresa_id=p_empresa_id and u.perfil in ('almoxarife','administrador')
 ) or not exists (
  select 1 from public.obras o where o.id=p_obra_id and o.empresa_id=p_empresa_id
 ) then
  raise exception 'Acesso não autorizado ao recebimento.';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'variacao_id',r.variacao_id,'comprimento_mm',r.comprimento_mm,
   'unidade',r.unidade,'quantidade',r.quantidade
 )), '[]'::jsonb)
 into v_result from (
  select n.variacao_id,n.comprimento_mm,n.unidade,sum(n.quantidade) quantidade
  from public.ew_nfe_recebimentos n
  join public.ew_obra_despesas_itens i on i.id=n.despesa_item_id and i.empresa_id=n.empresa_id
  join public.ew_obra_despesas d on d.id=i.despesa_id and d.empresa_id=n.empresa_id
  where n.empresa_id=p_empresa_id and n.obra_id=p_obra_id and d.status='aprovada' and n.estornado_em is null
  group by n.variacao_id,n.comprimento_mm,n.unidade
 ) r;
 return coalesce(v_result,'[]'::jsonb);
end
$function$
;
-- Bloquear rotinas genéricas que poderiam burlar o estorno auditado da NF-e.
CREATE OR REPLACE FUNCTION public.ew_estornar_movimento_obra(p_obra_id uuid, p_movimento_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid := auth.uid();
 v_obra public.obras%rowtype;
 v_original public.ew_estoque_obras_movimentos%rowtype;
 v_audit public.ew_auditoria_operacoes%rowtype;
 v_ver jsonb;
 v_mov public.ew_estoque_obras_movimentos%rowtype;
 v_motivo text := btrim(coalesce(p_motivo,''));
 v_saldo numeric;
 v_n integer := 0;
 v_par integer;
 v_soma numeric;
 v_materials integer;
 v_locais integer;
 v_originais jsonb := '[]'::jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null or p_obra_id is null or p_movimento_id is null or p_operacao_id is null then
  raise exception 'Obra, movimento, operação e usuário são obrigatórios.';
 end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo com 5 a 400 caracteres.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_obra from public.obras where id=p_obra_id for update;
 if not found or v_obra.arquivada_em is not null then
  raise exception 'Obra não encontrada ou já arquivada.';
 end if;
 if not exists (
  select 1 from public.usuarios_empresas ue
  join public.usuarios_login ul
   on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
  where ue.usuario_id=v_uid and ue.empresa_id=v_obra.empresa_id
   and ue.perfil in ('administrador','gerenciador')
   and ul.perfil=ue.perfil and ul.ativo and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem realizar estornos.'; end if;
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao <> 'ESTORNAR_ESTOQUE'
   or v_audit.obra_id is distinct from p_obra_id or v_audit.usuario_id <> v_uid
   or v_audit.referencia_id is distinct from p_movimento_id then
   raise exception 'Identificador de operação já usado em outro estorno.';
  end if;
  return jsonb_build_object('repetida',true,
   'estornados',v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 select * into v_original from public.ew_estoque_obras_movimentos
 where id=p_movimento_id and obra_id=p_obra_id for update;
 if not found then raise exception 'Movimentação não encontrada nesta obra.'; end if;
 if v_original.origem='ESTORNO' and v_original.observacao like 'Estorno do recebimento NF%' then
  raise exception 'Estorno de recebimento NF-e não pode ser revertido pela função genérica.';
 end if;
 if exists(select 1 from public.ew_nfe_recebimentos n where n.movimento_id=v_original.id) then
  raise exception 'Movimento vinculado à NF-e: use Estornar recebimento na tela Recebimento.';
 end if;
 if v_original.estorno_de_id is not null then
  raise exception 'Uma contrapartida de estorno não pode ser cancelada novamente.';
 end if;
 if exists(select 1 from public.ew_estoque_obras_movimentos e
  where e.estorno_de_id=p_movimento_id) then
  raise exception 'Esta movimentação já foi estornada.';
 end if;
 v_ver := public.ew_inspecionar_reversao_obra(p_obra_id);
 if exists (
  select 1 from pg_catalog.jsonb_array_elements_text(v_ver->'motivos') as x(motivo)
  where x.motivo not like 'Estorne as movimentações do estoque%'
 ) then
  raise exception 'Cancele romaneios, saídas e liberações e resolva outras pendências antes do estorno individual.';
 end if;
 -- Transferência entre galpões é uma operação única de duas pernas.
 if v_original.transferencia_id is not null then
  if v_original.origem<>'TRANSFERENCIA' then
   raise exception 'Movimento de transferência possui origem inconsistente.';
  end if;
  select count(*),coalesce(sum(m.quantidade_delta),0),
   count(distinct (m.variacao_id::text||'|'||coalesce(m.comprimento_mm::text,'')||'|'||m.unidade)),
   count(distinct m.local_estoque)
  into v_par,v_soma,v_materials,v_locais
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.transferencia_id=v_original.transferencia_id;
  if v_par<>2 or v_soma<>0 or v_materials<>1 or v_locais<>2 then
   raise exception 'Transferência incompleta ou inconsistente. Não é seguro estornar uma perna isoladamente.';
  end if;
 end if;
 -- Toda a obra é serializada pelo mesmo bloqueio da reversão total.
 perform 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
  and (m.id=p_movimento_id or
   (v_original.transferencia_id is not null
    and m.transferencia_id=v_original.transferencia_id))
 order by m.id for update;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  if v_mov.estorno_de_id is not null or exists(
   select 1 from public.ew_estoque_obras_movimentos s where s.estorno_de_id=v_mov.id
  ) then raise exception 'Uma das movimentações já foi estornada. Recarregue o histórico.'; end if;
  select coalesce(sum(m.quantidade_delta),0) into v_saldo
  from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id and m.variacao_id=v_mov.variacao_id
   and m.comprimento_mm is not distinct from v_mov.comprimento_mm
   and m.unidade=v_mov.unidade and m.local_estoque=v_mov.local_estoque;
  if v_saldo-v_mov.quantidade_delta<0 then
   raise exception 'Estorno individual deixaria saldo negativo em % (% %). Desfaça antes as movimentações posteriores dependentes.',
    v_mov.local_estoque,v_saldo,v_mov.unidade;
  end if;
 end loop;
 for v_mov in
  select * from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id
   and (m.id=p_movimento_id or
    (v_original.transferencia_id is not null
     and m.transferencia_id=v_original.transferencia_id))
  order by m.id
 loop
  insert into public.ew_estoque_obras_movimentos (
   empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
   origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id
  ) values (
   v_mov.empresa_id,v_mov.obra_id,v_mov.variacao_id,v_mov.comprimento_mm,
   v_mov.unidade,-v_mov.quantidade_delta,'ESTORNO',pg_catalog.gen_random_uuid(),
   left('Estorno individual: '||v_motivo,500),v_uid,v_mov.local_estoque,v_mov.id
  );
  v_n:=v_n+1;
  v_originais:=v_originais||jsonb_build_array(jsonb_build_object(
   'movimento_id',v_mov.id,'origem',v_mov.origem,'quantidade',v_mov.quantidade_delta,
   'variacao_id',v_mov.variacao_id,'comprimento_mm',v_mov.comprimento_mm,
   'unidade',v_mov.unidade,'galpao',v_mov.local_estoque,
   'usuario_original',v_mov.usuario_id,'registrado_em',v_mov.criado_em,
   'transferencia_id',v_mov.transferencia_id
  ));
 end loop;
 insert into public.ew_auditoria_operacoes (
  empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,
  referencia_id,operacao_id,motivo,detalhes
 ) values (
  v_obra.empresa_id,p_obra_id,v_obra.nome,v_obra.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_movimento_id,p_operacao_id,v_motivo,
  jsonb_build_object('modo','individual','movimentos_estornados',v_n,
   'movimentos_originais',v_originais)
 );
 return jsonb_build_object('repetida',false,'estornados',v_n,
  'historico_preservado',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.ew_estornar_estoque_obra(p_obra_id uuid, p_motivo text, p_operacao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;
 v_motivo text:=btrim(coalesce(p_motivo,''));v_n int;v_audit public.ew_auditoria_operacoes%rowtype;
 v_originais jsonb;v_status jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if p_operacao_id is null then raise exception 'Identificador de operação obrigatório.';end if;
 if length(v_motivo) not between 5 and 400 then
  raise exception 'Informe motivo de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 v_status:=public.ew_inspecionar_reversao_obra(p_obra_id);
 select * into v_audit from public.ew_auditoria_operacoes where operacao_id=p_operacao_id;
 if found then
  if v_audit.acao<>'ESTORNAR_ESTOQUE' or v_audit.obra_id<>p_obra_id or v_audit.usuario_id<>v_uid
   then raise exception 'Identificador de operação já utilizado.';end if;
  return jsonb_build_object('repetida',true,'estornados',
    v_audit.detalhes->'movimentos_estornados','historico_preservado',true);
 end if;
 if (v_status->'resumo'->>'romaneios')::int>0
   or (v_status->'resumo'->>'saidas_producao')::int>0
   or (v_status->'resumo'->>'liberacoes')::int>0
   or (v_status->'resumo'->>'lotes_cem')::int>0
   or (v_status->'resumo'->>'planos_liberados')::int>0
   or (v_status->'resumo'->>'unidades_liberadas')::int>0
   or (v_status->'resumo'->>'fabricadas')::int>0
 then raise exception 'Cancele romaneios, saídas e liberações antes de estornar o estoque.';end if;
 -- Reverter estoque inteiro com NF vinculada pode desfazer uma devolução
 -- física sem atualizar o histórico da nota. Exigir fluxo específico.
 if exists(select 1 from public.ew_nfe_recebimentos n where n.obra_id=p_obra_id) then
  raise exception 'A obra contém recebimentos de NF-e. Use o estorno por recebimento; não zere o estoque inteiro.';
 end if;
 -- Uma transferência ENTRE OBRAS não pode ser revertida em apenas uma
 -- das obras. Ela deve ser estornada atomicamente nas duas pontas.
 IF EXISTS (
  SELECT 1 FROM public.ew_estoque_obras_movimentos m
  WHERE m.obra_id=p_obra_id AND m.origem='TRANSFERENCIA'
    AND m.transferencia_id IS NOT NULL
    AND EXISTS (
     SELECT 1 FROM public.ew_estoque_obras_movimentos outra
     WHERE outra.transferencia_id=m.transferencia_id
       AND outra.origem='TRANSFERENCIA' AND outra.obra_id<>m.obra_id
    )
    AND NOT EXISTS (
     SELECT 1 FROM public.ew_estoque_obras_movimentos est
     WHERE est.estorno_de_id=m.id
    )
 ) THEN
  RAISE EXCEPTION 'Há transferência ativa entre obras. Estorne as duas pontas pelo histórico de movimentações antes de estornar o estoque inteiro.';
 END IF;
 perform 1 from public.ew_estoque_obras_movimentos m
  where m.obra_id=p_obra_id order by m.id for update;
 if exists(select 1 from public.ew_estoque_obras_movimentos m where m.obra_id=p_obra_id
   group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
   having sum(m.quantidade_delta)<0) then
  raise exception 'Saldo negativo em galpão. Concilie o estoque antes do estorno.';end if;
 -- Registra em detalhes cada movimento que será revertido.
 select count(*),
  coalesce(jsonb_agg(jsonb_build_object('id',m.id,'origem',m.origem,
   'quantidade',m.quantidade_delta,'local',m.local_estoque,
   'unidade',m.unidade,'comprimento_mm',m.comprimento_mm,
   'variacao_id',m.variacao_id,'criado_em',m.criado_em,'usuario_original',m.usuario_id)),
   '[]'::jsonb)
 into v_n,v_originais from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if v_n=0 then
  if (v_status->'resumo'->>'saldos_nao_zerados')::int>0 then
   raise exception 'Não existem movimentos pendentes, mas há saldos diferentes de zero.';end if;
  return jsonb_build_object('repetida',false,'estornados',0,'historico_preservado',true);
 end if;
 insert into public.ew_estoque_obras_movimentos (
  empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,
  origem,operacao_id,observacao,usuario_id,local_estoque,estorno_de_id)
 select m.empresa_id,m.obra_id,m.variacao_id,m.comprimento_mm,m.unidade,
  -m.quantidade_delta,'ESTORNO',gen_random_uuid(),left('Estorno para reimportação: '||v_motivo,500),
  v_uid,m.local_estoque,m.id
 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id and m.estorno_de_id is null
   and not exists (select 1 from public.ew_estoque_obras_movimentos x where x.estorno_de_id=m.id);
 if exists(select 1 from public.ew_estoque_obras_movimentos m
 where m.obra_id=p_obra_id
 group by m.variacao_id,m.comprimento_mm,m.unidade,m.local_estoque
 having sum(m.quantidade_delta)<>0) then
  raise exception 'A operação não zerou todos os saldos. Nenhum estorno foi confirmado.';end if;
 insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,operacao_id,motivo,detalhes)
 values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'ESTORNAR_ESTOQUE',
  p_operacao_id,v_motivo,jsonb_build_object('movimentos_estornados',v_n,
   'movimentos_originais',v_originais));
 return jsonb_build_object('repetida',false,'estornados',v_n,'historico_preservado',true);
end;$function$
;

-- Após todas as entradas físicas da NF-e serem estornadas, permitir eventual
-- cancelamento financeiro administrativo, sem apagar nenhuma linha de histórico.
CREATE OR REPLACE FUNCTION public.ew_cancelar_despesa_financeira(p_empresa_id uuid, p_despesa_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();v_status text;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE
   ue.usuario_id=v_uid AND ue.empresa_id=p_empresa_id AND ue.perfil='administrador')
 THEN RAISE EXCEPTION 'Somente ADM pode cancelar despesas aprovadas.';END IF;
 IF length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Informe o motivo do cancelamento entre 5 e 400 caracteres.';END IF;
 SELECT status INTO v_status FROM public.ew_obra_despesas
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND OR v_status<>'aprovada'
 THEN RAISE EXCEPTION 'Somente despesas aprovadas podem ser canceladas.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos r
    JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id
    WHERE i.despesa_id=p_despesa_id AND r.empresa_id=p_empresa_id AND r.estornado_em is null)
 THEN RAISE EXCEPTION 'Esta nota possui materiais recebidos. Estorne as entradas de estoque antes de cancelar a despesa.';END IF;
 IF EXISTS(
    select 1 from public.ew_insumos_movimentos m
    join public.ew_obra_despesas_itens i on i.id=m.despesa_item_id
    where i.despesa_id=p_despesa_id and m.empresa_id=p_empresa_id
     and m.origem='RECEBIMENTO'
 ) THEN RAISE EXCEPTION 'Nota com vidros/outros no estoque: use o cancelamento com estorno físico.';END IF;
 UPDATE public.ew_obra_despesas
 SET status='cancelada',cancelado_por=v_uid,cancelado_em=now(),
 observacoes=observacoes||' | Cancelada: '||btrim(p_motivo)
 WHERE id=p_despesa_id AND empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',p_despesa_id,'status','cancelada');
END;$function$
;
