-- EWGEST v46.4 — liberações técnicas por partes (marco = 50%; conjunto das folhas = 50%).
-- NÃO baixa estoque. A retirada física de materiais continua exclusiva do almoxarife.
-- "quantidade" dos registros 'folhas' representa CONJUNTOS de folhas por esquadria,
-- nunca o número de folhas físicas. A expedição continua contando folhas físicas.
alter table public.liberacoes_corte
 add column if not exists tipo_componente text not null default 'completo';
alter table public.liberacoes_corte
 drop constraint if exists ew_liberacoes_tipo_componente_check;
alter table public.liberacoes_corte
 add constraint ew_liberacoes_tipo_componente_check
 check (tipo_componente in ('completo','marco','folhas'));
comment on column public.liberacoes_corte.tipo_componente is
 'completo=100% da esquadria; marco=50%; folhas=conjunto de folhas=50%. Não gera baixa de estoque.';

-- Escrita centralizada: serializa por esquadria, controla limites de ambas as partes.
create or replace function public.ew_registrar_liberacao_componente(
 p_esquadria_id uuid,p_quantidade integer,p_data_liberacao date,
 p_fabrica text,p_componente text
) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_uid uuid:=auth.uid();v_e public.esquadrias%rowtype;
 v_tipo text:=lower(btrim(coalesce(p_componente,'')));
 v_fabrica text:=upper(btrim(coalesce(p_fabrica,'')));
 v_c integer;v_m integer;v_f integer;v_frame integer;v_folhas integer;
 v_id uuid;
begin
 perform public.ew_exigir_sessao_atual();
 if v_uid is null then raise exception 'Entre no sistema para registrar uma liberação.';end if;
 if p_quantidade is null or p_quantidade<1 or p_quantidade>100000
 then raise exception 'Informe quantidade inteira e positiva.';end if;
 if p_data_liberacao is null or p_data_liberacao>current_date or p_data_liberacao<date '2000-01-01'
 then raise exception 'Data de liberação inválida.';end if;
 if v_tipo not in ('completo','marco','folhas')
 then raise exception 'Selecione completo, somente marco ou conjunto das folhas.';end if;
 if v_fabrica<>'' and v_fabrica not in ('AFOGADOS','IMBIRIBEIRA')
 then raise exception 'Fábrica inválida.';end if;
 select * into v_e from public.esquadrias where id=p_esquadria_id for update;
 if not found then raise exception 'Esquadria não encontrada.';end if;
 if not exists(select 1 from public.usuarios_empresas ue where ue.usuario_id=v_uid
   and ue.empresa_id=v_e.empresa_id and ue.perfil in ('administrador','gerenciador','supervisor'))
 then raise exception 'Usuário não autorizado para liberar esta esquadria.';end if;
 if v_tipo<>'completo' and
    (v_e.descricao !~* '[0-9]{1,2}[[:space:]-]*FOLHA' or
     v_e.descricao ~* 'MAXIM[[:space:]-]*AR')
 then raise exception 'Esta esquadria deve ser liberada como conjunto completo.';end if;
 select coalesce(sum(quantidade) filter(where tipo_componente='completo'),0)::integer,
        coalesce(sum(quantidade) filter(where tipo_componente='marco'),0)::integer,
        coalesce(sum(quantidade) filter(where tipo_componente='folhas'),0)::integer
   into v_c,v_m,v_f from public.liberacoes_corte
  where esquadria_id=p_esquadria_id and cancelado_em is null;
 v_frame:=v_c+v_m+(case when v_tipo in ('completo','marco') then p_quantidade else 0 end);
 v_folhas:=v_c+v_f+(case when v_tipo in ('completo','folhas') then p_quantidade else 0 end);
 if v_frame>v_e.quantidade or v_folhas>v_e.quantidade then
   raise exception 'Quantidade excede o saldo desta parte. Marcos disponíveis: %, conjuntos de folhas disponíveis: %.',
   v_e.quantidade-v_c-v_m,v_e.quantidade-v_c-v_f;
 end if;
 insert into public.liberacoes_corte
  (esquadria_id,quantidade,data_liberacao,usuario_id,fabrica,tipo_componente)
 values(p_esquadria_id,p_quantidade,p_data_liberacao,v_uid,
        nullif(v_fabrica,''),v_tipo)
 returning id into v_id;
 -- qtd_liberada permanece inteira: conta unidades com pelo menos uma parte liberada.
 -- Para a AREA liberada usa-se 100% completo, 50% marco e 50% folhas.
 update public.esquadrias set qtd_liberada=greatest(v_frame,v_folhas)
 where id=p_esquadria_id;
 return jsonb_build_object('registro_id',v_id,'quantidade_liberada',p_quantidade,
  'tipo_componente',v_tipo,'fabrica',nullif(v_fabrica,''),
  'marcos_liberados',v_frame,'conjuntos_folhas_liberados',v_folhas,
  'saldo_marcos',v_e.quantidade-v_frame,'saldo_folhas',v_e.quantidade-v_folhas);
end;
$fn$;
-- Mantém as APIs antigas, classificadas como liberação COMPLETA.
create or replace function public.registrar_liberacao_corte(
 p_esquadria_id uuid,p_quantidade integer,p_data_liberacao date
) returns jsonb language sql security definer set search_path='' as $sql$
 select public.ew_registrar_liberacao_componente(
 p_esquadria_id,p_quantidade,p_data_liberacao,null,'completo');
$sql$;
create or replace function public.registrar_liberacao_corte_fabrica(
 p_esquadria_id uuid,p_quantidade integer,p_data_liberacao date,p_fabrica text
) returns jsonb language sql security definer set search_path='' as $sql$
 select public.ew_registrar_liberacao_componente(
 p_esquadria_id,p_quantidade,p_data_liberacao,p_fabrica,'completo');
$sql$;

-- Novo plano com componente explícito (mantém a validação dos materiais e operação idempotente).
CREATE OR REPLACE FUNCTION public.ew_liberar_plano_corte_componente(p_esquadria_id uuid, p_quantidade integer, p_data_liberacao date, p_fabrica text, p_materiais jsonb, p_fonte text, p_arquivo_nome text, p_operacao_id uuid, p_componente text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_usuario uuid:=auth.uid();v_item public.esquadrias%ROWTYPE;v_op uuid;
 v_result jsonb;v_liberacao uuid;v_entrada jsonb;v_variacao uuid;v_tipo text;
 v_length integer;v_unidade text;v_quantidade numeric;v_saldo numeric;v_local text;
 v_materiais_count integer;v_seen text[]:=ARRAY[]::text[];v_key text;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
 IF v_usuario IS NULL OR p_operacao_id IS NULL THEN RAISE EXCEPTION 'Sessão ou operação inválida.';END IF;
 SELECT id INTO v_op FROM public.ew_planos_liberados WHERE operacao_id=p_operacao_id;
 IF FOUND THEN RETURN jsonb_build_object('plano_id',v_op,'repetida',true);END IF;
 SELECT * INTO v_item FROM public.esquadrias WHERE id=p_esquadria_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esquadria não encontrada.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_usuario
     AND ue.empresa_id=v_item.empresa_id AND ue.perfil IN ('administrador','gerenciador','supervisor'))
 THEN RAISE EXCEPTION 'Usuário não autorizado para esta liberação.';END IF;
 IF jsonb_typeof(p_materiais) IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'Lista de materiais inválida.';END IF;
 v_materiais_count:=jsonb_array_length(p_materiais);
 IF v_materiais_count>150 THEN RAISE EXCEPTION 'Limite de 150 linhas de materiais por liberação.'; END IF;
 IF p_fonte NOT IN ('MANUAL','CEM_CONFERIDO','SEM_BAIXA') THEN RAISE EXCEPTION 'Origem inválida.';END IF;
 IF v_materiais_count=0 AND p_fonte<>'SEM_BAIXA' THEN RAISE EXCEPTION 'Confirme sem baixa ou informe os materiais.';END IF;
 IF v_materiais_count>0 AND p_fonte='SEM_BAIXA' THEN RAISE EXCEPTION 'Informe a origem dos materiais.';END IF;
 IF v_materiais_count>0 AND NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais l
   WHERE l.empresa_id=v_item.empresa_id AND l.obra_id=v_item.obra_id AND l.excluido_em IS NULL)
 THEN RAISE EXCEPTION 'Estoque da obra não existe ou está arquivado. Nenhuma baixa foi feita.'; END IF;
 IF length(coalesce(p_arquivo_nome,''))>240 THEN RAISE EXCEPTION 'Nome de arquivo inválido.';END IF;
 -- Valida todos os materiais antes de criar a liberação.
 FOR v_entrada IN SELECT value FROM jsonb_array_elements(p_materiais) LOOP
   IF jsonb_typeof(v_entrada)<>'object' THEN RAISE EXCEPTION 'Linha de material inválida.';END IF;
   v_variacao:=(v_entrada->>'variacao_id')::uuid;
   v_length:=nullif(v_entrada->>'comprimento_mm','')::integer;
   v_unidade:=v_entrada->>'unidade';
   v_local:=upper(btrim(coalesce(nullif(v_entrada->>'local_estoque',''),'IMBIRIBEIRA')));
   if not exists(select 1 from public.ew_locais_fisicos l where l.empresa_id=v_item.empresa_id and l.nome=v_local and l.ativo) then raise exception 'Local físico inválido para material.';end if;
   v_quantidade:=(v_entrada->>'quantidade')::numeric;
   SELECT tipo INTO v_tipo FROM public.ew_materiais_variacoes
     WHERE id=v_variacao AND empresa_id=v_item.empresa_id AND ativo=true;
   IF v_tipo IS NULL THEN RAISE EXCEPTION 'Material não encontrado nesta empresa.';END IF;
   IF v_quantidade IS NULL OR v_quantidade<=0 OR v_quantidade>1000000
     OR (v_tipo='perfil' AND (v_unidade<>'BARRA' OR v_length NOT BETWEEN 100 AND 20000
         OR v_quantidade<>trunc(v_quantidade)))
     OR (v_tipo='acessorio' AND (v_length IS NOT NULL OR v_unidade NOT IN ('PC','PR','CJ','MT','KG','UN')))
   THEN RAISE EXCEPTION 'Quantidade, unidade ou comprimento de material inválido.';END IF;
   v_key:=v_variacao::text||'|'||coalesce(v_length::text,'-')||'|'||v_unidade||'|'||v_local;
   IF v_key=ANY(v_seen) THEN RAISE EXCEPTION 'O mesmo material/comprimento foi repetido no espelho.';END IF;
   v_seen:=array_append(v_seen,v_key);
 END LOOP;
 -- O próprio registro original respeita saldo pendente e fábrica.
 v_result:=public.ew_registrar_liberacao_componente(p_esquadria_id,p_quantidade,p_data_liberacao,p_fabrica,p_componente);
 v_liberacao:=(v_result->>'registro_id')::uuid;
 INSERT INTO public.ew_planos_liberados
 (operacao_id,empresa_id,obra_id,esquadria_id,liberacao_id,fonte,arquivo_nome,
  materiais_confirmados,data_liberacao,usuario_id)
 VALUES(p_operacao_id,v_item.empresa_id,v_item.obra_id,v_item.id,v_liberacao,p_fonte,
  nullif(btrim(coalesce(p_arquivo_nome,'')),''),p_materiais,p_data_liberacao,v_usuario)
 RETURNING id INTO v_op;
 -- A liberação registra o plano impresso. Só o almoxarife entrega/baixa depois.
 RETURN v_result||jsonb_build_object('plano_id',v_op,'tipo_componente',p_componente,'linhas_baixadas',0,'linhas_pendentes_entrega',v_materiais_count,'repetida',false);
END;$function$;

-- A saída física exige liberação da parte correspondente.
CREATE OR REPLACE FUNCTION public.registrar_saida_producao(p_registro_id uuid, p_esquadria_id uuid, p_tipo text, p_quantidade integer, p_data_saida date, p_folhas_por_unidade integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_item public.esquadrias%ROWTYPE;
  v_folhas integer;
  v_marcos_liberados bigint;
  v_folhas_liberadas bigint;
  v_completas_enviadas bigint;
  v_marcos_enviados bigint;
  v_folhas_enviadas bigint;
  v_marcos_novos bigint;
  v_folhas_novas bigint;
  v_existente public.saidas_producao%ROWTYPE;
  v_primeira_liberacao date;
BEGIN
  PERFORM public.ew_exigir_sessao_atual();
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Entre na EWGEST para registrar uma saída.';
  END IF;
  IF p_registro_id IS NULL OR p_esquadria_id IS NULL THEN
    RAISE EXCEPTION 'Identificador do registro ou da esquadria ausente.';
  END IF;
  IF p_tipo IS NULL OR p_tipo NOT IN ('completo','marco','folha') THEN
    RAISE EXCEPTION 'Escolha completo, marco ou folha.';
  END IF;
  IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
    RAISE EXCEPTION 'Informe quantidade inteira e positiva.';
  END IF;
  IF p_data_saida IS NULL OR p_data_saida < DATE '2000-01-01' OR p_data_saida > current_date THEN
    RAISE EXCEPTION 'Informe uma data de saída válida e não futura.';
  END IF;
  -- Conjunto completo não precisa informar a composição física das folhas.
  -- Ela será confirmada quando houver saída desmembrada, se ainda não existir no cadastro.
  IF p_folhas_por_unidade IS NOT NULL AND p_folhas_por_unidade NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION 'Quantidade de folhas por esquadria inválida (1 a 12).';
  END IF;
  IF p_tipo IN ('marco','folha') AND p_folhas_por_unidade IS NULL THEN
    RAISE EXCEPTION 'Informe a composição de folhas para expedição desmembrada.';
  END IF;

  -- Serializa lançamentos do mesmo item e garante que não superem o liberado.
  SELECT * INTO v_item FROM public.esquadrias
  WHERE id=p_esquadria_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esquadria não encontrada.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.usuarios_empresas ue
    WHERE ue.empresa_id=v_item.empresa_id
      AND ue.usuario_id=v_usuario
      AND (
        ue.perfil IN ('administrador','gerenciador','supervisor')
        OR (
          ue.perfil='almoxarife'
          AND EXISTS(
            SELECT 1 FROM public.usuarios_login ul
            WHERE ul.usuario_id=v_usuario AND ul.empresa_id=ue.empresa_id
              AND ul.perfil='almoxarife' AND ul.ativo
          )
          AND EXISTS(
            SELECT 1 FROM public.romaneios r
            WHERE r.id::text=pg_catalog.current_setting('ewgest.romaneio_emissao_id',true)
              AND r.criado_por=v_usuario AND r.empresa_id=v_item.empresa_id
              AND r.obra_id=v_item.obra_id AND r.status='emitido'
              AND r.criado_em=pg_catalog.transaction_timestamp()
          )
        )
      )
  ) THEN
    RAISE EXCEPTION 'Sem permissão para registrar saídas desta empresa.';
  END IF;
  -- MAXIM-AR sai sempre como conjunto completo, sem opção de marco ou folha separados.
  IF v_item.descricao ~* 'MAXIM[[:space:]-]*AR' AND p_tipo<>'completo' THEN
    RAISE EXCEPTION 'MAXIM-AR só pode ser expedido como esquadria completa.';
  END IF;
  IF COALESCE(v_item.qtd_liberada,0) <= 0 THEN
    RAISE EXCEPTION 'Este código ainda não possui unidades liberadas para corte.';
  END IF;

  SELECT * INTO v_existente FROM public.saidas_producao WHERE id=p_registro_id;
  IF FOUND THEN
    IF v_existente.cancelado_em IS NOT NULL THEN
      RAISE EXCEPTION 'Saída já cancelada; não é possível reativar este identificador.';
    END IF;
    IF v_existente.esquadria_id<>p_esquadria_id
      OR v_existente.tipo<>p_tipo
      OR v_existente.quantidade<>p_quantidade
      OR v_existente.data_saida<>p_data_saida THEN
      RAISE EXCEPTION 'Identificador de operação já utilizado para outro lançamento.';
    END IF;
    RETURN jsonb_build_object('registro_id',v_existente.id,'repetido',true);
  END IF;

  SELECT folhas_por_unidade INTO v_folhas
    FROM public.esquadrias_saida_config
    WHERE esquadria_id=p_esquadria_id;
  IF v_folhas IS NULL AND p_folhas_por_unidade IS NOT NULL THEN
    INSERT INTO public.esquadrias_saida_config
      (esquadria_id,folhas_por_unidade,configurado_por)
    VALUES (p_esquadria_id,p_folhas_por_unidade,v_usuario);
    v_folhas:=p_folhas_por_unidade;
  ELSIF v_folhas IS NOT NULL AND p_folhas_por_unidade IS NOT NULL
    AND v_folhas<>p_folhas_por_unidade THEN
    RAISE EXCEPTION 'Composição já cadastrada: % folha(s) por esquadria. Não foi alterada.', v_folhas;
  END IF;
  IF v_folhas IS NULL AND p_tipo<>'completo' THEN
    RAISE EXCEPTION 'Antes de desmembrar, confirme a quantidade de folhas por esquadria.';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN tipo IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo='completo' THEN quantidade*v_folhas
                           WHEN tipo='folha' THEN quantidade ELSE 0 END),0)
    INTO v_marcos_enviados,v_folhas_enviadas
    FROM public.saidas_producao
    WHERE esquadria_id=p_esquadria_id AND cancelado_em IS NULL;

  v_marcos_novos:=CASE WHEN p_tipo IN ('completo','marco') THEN p_quantidade ELSE 0 END;
  v_folhas_novas:=CASE WHEN p_tipo='completo' THEN p_quantidade*v_folhas
                       WHEN p_tipo='folha' THEN p_quantidade ELSE 0 END;

  -- A autorização de saída exige que a PARTE também tenha sido liberada.
  SELECT COALESCE(SUM(CASE WHEN tipo_componente IN ('completo','marco') THEN quantidade ELSE 0 END),0),
         COALESCE(SUM(CASE WHEN tipo_componente IN ('completo','folhas') THEN quantidade ELSE 0 END),0)
    INTO v_marcos_liberados,v_folhas_liberadas
    FROM public.liberacoes_corte
   WHERE esquadria_id=p_esquadria_id AND cancelado_em IS NULL;
  IF v_marcos_enviados+v_marcos_novos>v_marcos_liberados THEN
    RAISE EXCEPTION 'Marcos sem liberação suficiente. Disponíveis: %.',v_marcos_liberados-v_marcos_enviados;
  END IF;
  IF v_folhas IS NOT NULL AND v_folhas_enviadas+v_folhas_novas>v_folhas_liberadas*v_folhas THEN
    RAISE EXCEPTION 'Folhas sem liberação suficiente. Conjuntos liberados: %.',v_folhas_liberadas;
  END IF;
  IF p_tipo='completo' AND v_folhas IS NULL THEN
    SELECT COALESCE(SUM(quantidade),0) INTO v_completas_enviadas
    FROM public.saidas_producao WHERE esquadria_id=p_esquadria_id
      AND tipo='completo' AND cancelado_em IS NULL;
    IF v_completas_enviadas+p_quantidade>v_folhas_liberadas THEN
      RAISE EXCEPTION 'Não há conjuntos de folhas liberados para essa saída completa.';
    END IF;
  END IF;

  -- Bloqueia datas de saída anteriores à primeira liberação registrada do item.
  SELECT MIN(data_liberacao) INTO v_primeira_liberacao
  FROM public.liberacoes_corte WHERE esquadria_id=p_esquadria_id;
  IF v_primeira_liberacao IS NOT NULL AND p_data_saida<v_primeira_liberacao THEN
    RAISE EXCEPTION 'A saída não pode anteceder a primeira liberação (%).',
      v_primeira_liberacao;
  END IF;

  INSERT INTO public.saidas_producao
    (id,esquadria_id,tipo,quantidade,data_saida,usuario_id)
  VALUES (p_registro_id,p_esquadria_id,p_tipo,p_quantidade,p_data_saida,v_usuario);

  RETURN jsonb_build_object(
    'registro_id',p_registro_id,
    'repetido',false,
    'marcos_enviados',v_marcos_enviados+v_marcos_novos,
    'folhas_enviadas',CASE WHEN v_folhas IS NULL THEN NULL ELSE v_folhas_enviadas+v_folhas_novas END,
    'marcos_possiveis',v_marcos_liberados,
    'folhas_possiveis',CASE WHEN v_folhas IS NULL THEN NULL ELSE v_folhas_liberadas*v_folhas END
  );
END;
$function$;

-- Cancelamento preserva o histórico e confere os saldos por partes.
CREATE OR REPLACE FUNCTION public.ew_cancelar_liberacoes_obra(p_obra_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_ob public.obras%rowtype;v_e record;
 v_qtd integer;v_ativas integer;v_lotes integer;v_motivo text:=btrim(coalesce(p_motivo,''));v_liberacoes jsonb;
begin
 perform public.ew_exigir_sessao_atual();
 if length(v_motivo) not between 5 and 400 then raise exception 'Informe o motivo, de 5 a 400 caracteres.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obra_id::text,977124));
 select * into v_ob from public.obras where id=p_obra_id for update;
 if not found or v_ob.arquivada_em is not null then raise exception 'Obra inexistente ou arquivada.';end if;
 if v_uid is null or not exists(
  select 1 from public.usuarios_empresas u join public.usuarios_login ul
   on ul.usuario_id=u.usuario_id and ul.empresa_id=u.empresa_id
  where u.usuario_id=v_uid and u.empresa_id=v_ob.empresa_id
   and u.perfil in ('administrador','gerenciador') and ul.perfil=u.perfil and ul.ativo
   and ul.excluido_em is null
 ) then raise exception 'Somente ADM e Gerenciador podem cancelar liberações.';end if;
 perform 1 from public.esquadrias where obra_id=p_obra_id order by id for update;
 if exists (select 1 from public.romaneios where obra_id=p_obra_id and status<>'cancelado')
  then raise exception 'Cancele os romaneios emitidos antes das liberações.';end if;
 if exists(select 1 from public.saidas_producao s join public.esquadrias e
    on e.id=s.esquadria_id where e.obra_id=p_obra_id and s.cancelado_em is null)
  then raise exception 'Existem saídas de produção ativas. Estorne-as primeiro.';end if;
 if exists(select 1 from public.esquadrias where obra_id=p_obra_id and qtd_fabricada<>0)
  then raise exception 'Existem quantidades fabricadas que precisam ser conciliadas.';end if;
 -- Confere consistência acumulada ANTES de qualquer alteração.
 for v_e in
  select e.id,e.codigo,e.qtd_liberada,greatest(
      coalesce(sum(CASE WHEN l.tipo_componente IN ('completo','marco')
          AND l.cancelado_em IS NULL THEN l.quantidade ELSE 0 END),0),
      coalesce(sum(CASE WHEN l.tipo_componente IN ('completo','folhas')
          AND l.cancelado_em IS NULL THEN l.quantidade ELSE 0 END),0)
    )::integer as ativos
  from public.esquadrias e left join public.liberacoes_corte l on l.esquadria_id=e.id
  where e.obra_id=p_obra_id group by e.id,e.codigo,e.qtd_liberada
 loop
  if v_e.qtd_liberada<>v_e.ativos then
   raise exception 'Saldo de liberação inconsistente para %. Solicite conferência técnica.',v_e.codigo;
  end if;
 end loop;
 select count(*) into v_ativas
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 select coalesce(sum(e.qtd_liberada),0) into v_qtd
 from public.esquadrias e where e.obra_id=p_obra_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'esquadria',e.codigo,
  'quantidade',l.quantidade,'liberado_em',l.registrada_em,'liberado_por',l.usuario_id)),
  '[]'::jsonb) into v_liberacoes
 from public.liberacoes_corte l join public.esquadrias e on e.id=l.esquadria_id
 where e.obra_id=p_obra_id and l.cancelado_em is null;
 update public.liberacoes_corte l set cancelado_em=now(),cancelado_por=v_uid,motivo_cancelamento=v_motivo
 from public.esquadrias e where l.esquadria_id=e.id and e.obra_id=p_obra_id
 and l.cancelado_em is null;
 update public.esquadrias set qtd_liberada=0 where obra_id=p_obra_id;
 select count(*) into v_lotes from public.ew_liberacoes_lotes
  where obra_id=p_obra_id and cancelado_em is null;
 update public.ew_liberacoes_lotes set cancelado_em=now(),cancelado_por=v_uid,
  motivo_cancelamento=v_motivo where obra_id=p_obra_id and cancelado_em is null;
 if v_ativas>0 or v_lotes>0 then
  insert into public.ew_auditoria_operacoes
  (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,detalhes)
  values(v_ob.empresa_id,v_ob.id,v_ob.nome,v_ob.codigo,v_uid,'CANCELAR_LIBERACOES',v_motivo,
   jsonb_build_object('registros',v_ativas,'quantidade',v_qtd,'lotes',v_lotes,
    'liberacoes_originais',v_liberacoes,
    'estoque','Baixas de materiais ainda precisam de estorno separado'));
 end if;
 return jsonb_build_object('canceladas',v_ativas,'unidades',v_qtd,'lotes',v_lotes,
  'estoque_pendente',true,'historico_preservado',true);
end;$function$;

revoke all on function public.ew_registrar_liberacao_componente(uuid,integer,date,text,text) from public,anon;
revoke all on function public.ew_liberar_plano_corte_componente(uuid,integer,date,text,jsonb,text,text,uuid,text) from public,anon;
grant execute on function public.ew_registrar_liberacao_componente(uuid,integer,date,text,text) to authenticated;
grant execute on function public.ew_liberar_plano_corte_componente(uuid,integer,date,text,jsonb,text,text,uuid,text) to authenticated;

-- Registra a retificação com uma ação de auditoria específica.
alter table public.ew_auditoria_operacoes
 drop constraint if exists ew_auditoria_operacoes_acao_check;
alter table public.ew_auditoria_operacoes
 add constraint ew_auditoria_operacoes_acao_check check (acao in (
 'CANCELAR_ROMANEIO','CANCELAR_SAIDAS_AVULSAS','CANCELAR_LIBERACOES',
 'ESTORNAR_ESTOQUE','ARQUIVAR_OBRA','CORRIGIR_ESCOPO_LIBERACAO'
));

-- Correção pontual de QA, explicitamente identificada: EA2 do TESTE-TREINAMENTO.
-- Usuário declarou ter liberado SOMENTE o marco e já houve 1 marco expedido.
-- Não muda quantidade liberada nem movimentações. Não é aplicada a outras obras.
with alvo as (
 update public.liberacoes_corte l set tipo_componente='marco'
 from public.esquadrias e join public.obras o on o.id=e.obra_id
 where l.id='f42b1792-31be-4594-8a48-48e64172c1e3'::uuid
   and l.esquadria_id=e.id
   and e.id='cb07edaf-d286-4f04-b5f2-a28841ae3e91'::uuid
   and e.codigo='EA2' and o.codigo='TESTE-TREINAMENTO'
   and l.tipo_componente='completo' and l.quantidade=1 and l.cancelado_em is null
   and (select coalesce(sum(s.quantidade),0) from public.saidas_producao s
       where s.esquadria_id=e.id and s.tipo='marco' and s.cancelado_em is null)=1
   and not exists(select 1 from public.saidas_producao s
       where s.esquadria_id=e.id and s.tipo in ('completo','folha') and s.cancelado_em is null)
 returning l.id,l.usuario_id,e.empresa_id,o.id as obra_id,o.nome as obra_nome,o.codigo as obra_codigo
)
insert into public.ew_auditoria_operacoes
 (empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,acao,motivo,referencia_id,detalhes)
select empresa_id,obra_id,obra_nome,obra_codigo,usuario_id,
 'CORRIGIR_ESCOPO_LIBERACAO',
 'Adequação da liberação de teste EA2 para somente marco conforme solicitação, sem alteração de estoque',
 id,jsonb_build_object('antes','completo','depois','marco','quantidade',1,
 'regra_area','marco 50% + conjunto de folhas 50%') from alvo;
