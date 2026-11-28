-- EWGEST 46.29.39 — Contas a pagar/receber e baixas financeiras.
-- Proposta: aplicar somente após CI real. Não cria lançamentos a partir de dados históricos.
BEGIN;
CREATE SCHEMA IF NOT EXISTS ew_financeiro_interna;
REVOKE ALL ON SCHEMA ew_financeiro_interna FROM PUBLIC,anon,authenticated;
CREATE TABLE ew_financeiro_interna.titulos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 operacao_id uuid NOT NULL, dados_operacao jsonb NOT NULL,
 tipo text NOT NULL CHECK(tipo IN ('PAGAR','RECEBER')),
 origem_tipo text NOT NULL CHECK(origem_tipo IN ('MANUAL','FATURAMENTO_OBRA','DESPESA_OBRA','NOTA_ESTOQUE')),
 origem_id uuid,
 descricao text NOT NULL CHECK(length(btrim(descricao)) BETWEEN 3 AND 200),
 contraparte text NOT NULL CHECK(length(btrim(contraparte)) BETWEEN 1 AND 200),
 numero_documento text NOT NULL CHECK(length(numero_documento)<=120),
 categoria text NOT NULL CHECK(length(btrim(categoria)) BETWEEN 1 AND 80),
 centro_custo text NOT NULL CHECK(length(btrim(centro_custo)) BETWEEN 1 AND 180),
 galpao_id uuid,
 competencia date NOT NULL, vencimento date NOT NULL,
 valor_centavos bigint NOT NULL CHECK(valor_centavos BETWEEN 1 AND 100000000000000),
 criado_por uuid NOT NULL, criado_em timestamptz NOT NULL DEFAULT now(),
 cancelado_em timestamptz, cancelado_por uuid, cancelamento_motivo text, cancelamento_operacao_id uuid,
 UNIQUE(empresa_id,id), UNIQUE(empresa_id,operacao_id), UNIQUE(empresa_id,cancelamento_operacao_id),
 CHECK((origem_tipo='MANUAL')=(origem_id IS NULL)),
 CHECK((cancelado_em IS NULL AND cancelado_por IS NULL AND cancelamento_motivo IS NULL AND cancelamento_operacao_id IS NULL) OR
 (cancelado_em IS NOT NULL AND cancelado_por IS NOT NULL AND length(btrim(cancelamento_motivo)) BETWEEN 5 AND 400 AND cancelamento_operacao_id IS NOT NULL))
);
CREATE UNIQUE INDEX ew_fin_titulo_origem_ativa ON ew_financeiro_interna.titulos(empresa_id,origem_tipo,origem_id) WHERE origem_id IS NOT NULL AND cancelado_em IS NULL;
CREATE INDEX ew_fin_titulos_vencimento ON ew_financeiro_interna.titulos(empresa_id,vencimento,id);
CREATE TABLE ew_financeiro_interna.baixas(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, titulo_id uuid NOT NULL,
 operacao_id uuid NOT NULL, valor_centavos bigint NOT NULL CHECK(valor_centavos BETWEEN 1 AND 100000000000000),
 data_baixa date NOT NULL, meio text NOT NULL CHECK(length(meio)<=80), observacoes text NOT NULL CHECK(length(observacoes)<=400),
 criado_por uuid NOT NULL, criado_em timestamptz NOT NULL DEFAULT now(),
 estornado_em timestamptz, estornado_por uuid, estorno_motivo text, estorno_operacao_id uuid,
 FOREIGN KEY(empresa_id,titulo_id) REFERENCES ew_financeiro_interna.titulos(empresa_id,id),
 UNIQUE(empresa_id,operacao_id), UNIQUE(empresa_id,estorno_operacao_id),
 CHECK((estornado_em IS NULL AND estornado_por IS NULL AND estorno_motivo IS NULL AND estorno_operacao_id IS NULL) OR
 (estornado_em IS NOT NULL AND estornado_por IS NOT NULL AND length(btrim(estorno_motivo)) BETWEEN 5 AND 400 AND estorno_operacao_id IS NOT NULL))
);
CREATE INDEX ew_fin_baixas_titulo ON ew_financeiro_interna.baixas(empresa_id,titulo_id,estornado_em);
CREATE INDEX ew_fin_baixas_data ON ew_financeiro_interna.baixas(empresa_id,data_baixa);
ALTER TABLE ew_financeiro_interna.titulos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_financeiro_interna.baixas ENABLE ROW LEVEL SECURITY;
CREATE VIEW ew_financeiro_interna.documentos_origem AS
 SELECT f.empresa_id,'FATURAMENTO_OBRA'::text origem_tipo,f.id origem_id,'RECEBER'::text tipo,
  ('Faturamento '||f.categoria||' · '||coalesce(o.nome,'Obra'))::text descricao,coalesce(nullif(o.cliente,''),o.nome,'Cliente') contraparte,
  coalesce(f.numero_documento,'') numero_documento,f.categoria categoria,f.data_faturamento competencia,
  round(f.valor_total*100)::bigint valor_centavos,(f.status='emitido' AND f.cancelado_em IS NULL) valido
 FROM public.ew_obra_faturamentos f JOIN public.obras o ON o.empresa_id=f.empresa_id AND o.id=f.obra_id
 UNION ALL
 SELECT d.empresa_id,'DESPESA_OBRA',d.id,'PAGAR','Despesa '||d.categoria||' · '||coalesce(o.nome,'Obra'),
  coalesce(nullif(d.fornecedor,''),'Fornecedor'),coalesce(d.numero_documento,''),d.categoria,d.data_documento,
  round(d.valor*100)::bigint,(d.status='aprovada' AND d.cancelado_em IS NULL)
 FROM public.ew_obra_despesas d JOIN public.obras o ON o.empresa_id=d.empresa_id AND o.id=d.obra_id
 UNION ALL
 SELECT n.empresa_id,'NOTA_ESTOQUE',n.id,'PAGAR','Compra de estoque próprio',coalesce(f.nome,'Fornecedor'),
  coalesce(n.numero_documento,''),'estoque próprio',n.data_documento,n.valor_centavos,
  (n.status='ATIVA' AND n.cancelado_em IS NULL)
 FROM public.ew_compras_notas_empresa n LEFT JOIN public.ew_fornecedores f ON f.empresa_id=n.empresa_id AND f.id=n.fornecedor_id;

CREATE FUNCTION ew_financeiro_interna.exigir(p_empresa uuid,p_tipo text DEFAULT NULL,p_cancelar boolean DEFAULT false,p_origem text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa,'financeiro.consultar') OR NOT public.ew_pode(p_empresa,'relatorios.financeiros') THEN RAISE EXCEPTION 'Sem acesso ao financeiro empresarial.';END IF;
 IF p_origem='NOTA_ESTOQUE' AND NOT public.ew_pode(p_empresa,'compras.consultar_valores') THEN RAISE EXCEPTION 'Sem acesso aos valores de compras.';END IF;
 IF p_tipo IS NOT NULL AND (p_tipo NOT IN ('PAGAR','RECEBER') OR NOT public.ew_pode(p_empresa,
  CASE WHEN p_tipo='PAGAR' AND p_cancelar THEN 'financeiro.cancelar_despesas'
   WHEN p_tipo='RECEBER' AND p_cancelar THEN 'financeiro.cancelar_faturamento'
   WHEN p_tipo='PAGAR' THEN 'financeiro.despesas' ELSE 'financeiro.faturar' END)) THEN RAISE EXCEPTION 'Sem permissão para esta operação financeira.';END IF;
END $$;
-- A origem é bloqueada antes da conferência para não aceitar baixa de documento já cancelado.
CREATE FUNCTION ew_financeiro_interna.origem_conferir(p_empresa uuid,p_tipo text,p_id uuid)
RETURNS ew_financeiro_interna.documentos_origem LANGUAGE plpgsql SET search_path TO '' AS $$
DECLARE v_doc ew_financeiro_interna.documentos_origem%ROWTYPE;
BEGIN
 IF p_tipo='FATURAMENTO_OBRA' THEN PERFORM 1 FROM public.ew_obra_faturamentos WHERE empresa_id=p_empresa AND id=p_id FOR SHARE;
 ELSIF p_tipo='DESPESA_OBRA' THEN PERFORM 1 FROM public.ew_obra_despesas WHERE empresa_id=p_empresa AND id=p_id FOR SHARE;
 ELSIF p_tipo='NOTA_ESTOQUE' THEN PERFORM 1 FROM public.ew_compras_notas_empresa WHERE empresa_id=p_empresa AND id=p_id FOR SHARE;
 ELSE RAISE EXCEPTION 'Tipo de documento inválido.';END IF;
 SELECT * INTO v_doc FROM ew_financeiro_interna.documentos_origem WHERE empresa_id=p_empresa AND origem_tipo=p_tipo AND origem_id=p_id AND valido;
 IF NOT FOUND OR v_doc.valor_centavos IS NULL OR v_doc.valor_centavos<=0 THEN RAISE EXCEPTION 'Documento de origem indisponível ou cancelado.';END IF;
 RETURN v_doc;
END $$;
CREATE FUNCTION public.ew_fin_empresa_criar_titulo(p_empresa_id uuid,p_operacao_id uuid,p_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_tipo text:=p_dados->>'tipo';v_origem text:=coalesce(p_dados->>'origem_tipo','MANUAL');v_origem_id uuid;
 v_doc ew_financeiro_interna.documentos_origem%ROWTYPE;v_old ew_financeiro_interna.titulos%ROWTYPE;
 v_id uuid;v_valor bigint;v_desc text;v_contra text;v_num text;v_cat text;v_centro text;v_galpao uuid;v_comp date;v_venc date;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id,v_tipo,false,v_origem);
 IF p_operacao_id IS NULL OR jsonb_typeof(p_dados) IS DISTINCT FROM 'object' OR v_tipo IS NULL OR v_origem NOT IN ('MANUAL','FATURAMENTO_OBRA','DESPESA_OBRA','NOTA_ESTOQUE') THEN RAISE EXCEPTION 'Dados do título inválidos.';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_empresa_id::text||'|fin-titulo|'||p_operacao_id::text,0));
 SELECT * INTO v_old FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF v_old.dados_operacao<>p_dados OR v_old.cancelado_em IS NOT NULL THEN RAISE EXCEPTION 'Operação já utilizada ou cancelada.';END IF;
  RETURN jsonb_build_object('id',v_old.id,'valor_centavos',v_old.valor_centavos,'repetido',true);
 END IF;
 IF jsonb_typeof(p_dados->'valor_centavos') IS DISTINCT FROM 'number' OR (p_dados->>'valor_centavos')::numeric<>round((p_dados->>'valor_centavos')::numeric) THEN RAISE EXCEPTION 'Informe valor em centavos inteiros.';END IF;
 v_valor:=(p_dados->>'valor_centavos')::bigint;v_venc:=(p_dados->>'vencimento')::date;
 IF v_valor NOT BETWEEN 1 AND 100000000000000 OR v_venc IS NULL OR v_venc<'1900-01-01'::date OR v_venc>'2200-01-01'::date THEN RAISE EXCEPTION 'Valor ou vencimento inválido.';END IF;
 IF v_origem='MANUAL' THEN
  IF nullif(p_dados->>'origem_id','') IS NOT NULL THEN RAISE EXCEPTION 'Título manual não pode vincular documento.';END IF;
  v_desc:=btrim(coalesce(p_dados->>'descricao',''));v_contra:=btrim(coalesce(p_dados->>'contraparte',''));
  v_num:=btrim(coalesce(p_dados->>'numero_documento',''));v_cat:=btrim(coalesce(p_dados->>'categoria',''));
  v_comp:=(p_dados->>'competencia')::date;
  v_centro:=coalesce(nullif(p_dados->>'centro',''),'GERAL');
  IF v_centro NOT IN ('GERAL','ADMINISTRATIVO') THEN
   v_galpao:=v_centro::uuid;
   SELECT nome INTO v_centro FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=v_galpao AND ativo;
   IF NOT FOUND THEN RAISE EXCEPTION 'Centro de custo não pertence à empresa.';END IF;
  END IF;
 ELSE
  v_origem_id:=(p_dados->>'origem_id')::uuid;
  v_doc:=ew_financeiro_interna.origem_conferir(p_empresa_id,v_origem,v_origem_id);
  IF v_doc.tipo<>v_tipo OR v_doc.valor_centavos<>v_valor THEN RAISE EXCEPTION 'Documento ou valor mudou. Atualize a consulta.';END IF;
  IF EXISTS(SELECT 1 FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND origem_tipo=v_origem AND origem_id=v_origem_id AND cancelado_em IS NULL) THEN RAISE EXCEPTION 'Documento já programado no financeiro.';END IF;
  v_desc:=left(v_doc.descricao,200);v_contra:=left(v_doc.contraparte,200);v_num:=left(v_doc.numero_documento,120);v_cat:=left(v_doc.categoria,80);v_comp:=v_doc.competencia;v_centro:='GERAL';
 END IF;
 IF v_comp IS NULL OR v_comp<'1900-01-01'::date OR v_comp>'2200-01-01'::date OR length(v_desc) NOT BETWEEN 3 AND 200 OR length(v_contra) NOT BETWEEN 1 AND 200 OR length(v_num)>120 OR length(v_cat) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Informe descrição, contraparte, categoria e competência válidas.';END IF;
 INSERT INTO ew_financeiro_interna.titulos(empresa_id,operacao_id,dados_operacao,tipo,origem_tipo,origem_id,descricao,contraparte,numero_documento,categoria,centro_custo,galpao_id,competencia,vencimento,valor_centavos,criado_por)
 VALUES(p_empresa_id,p_operacao_id,p_dados,v_tipo,v_origem,v_origem_id,v_desc,v_contra,v_num,v_cat,v_centro,v_galpao,v_comp,v_venc,v_valor,auth.uid()) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'valor_centavos',v_valor,'repetido',false);
END $$;
CREATE FUNCTION public.ew_fin_empresa_baixar(p_empresa_id uuid,p_titulo_id uuid,p_operacao_id uuid,p_valor_centavos bigint,p_data date,p_meio text,p_observacoes text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE;b ew_financeiro_interna.baixas%ROWTYPE;d ew_financeiro_interna.documentos_origem%ROWTYPE;v_pago bigint;v_id uuid;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id);
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=p_titulo_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Título indisponível.';END IF;
 PERFORM ew_financeiro_interna.exigir(p_empresa_id,t.tipo,false,t.origem_tipo);
 IF p_operacao_id IS NULL OR p_valor_centavos IS NULL OR p_valor_centavos<=0 OR p_data IS NULL OR p_data<'1900-01-01'::date OR p_data>current_date OR length(coalesce(p_meio,''))>80 OR length(coalesce(p_observacoes,''))>400 THEN RAISE EXCEPTION 'Valor, data ou informações da baixa inválidos.';END IF;
 SELECT * INTO b FROM ew_financeiro_interna.baixas WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF b.titulo_id<>p_titulo_id OR b.valor_centavos<>p_valor_centavos OR b.data_baixa<>p_data OR b.meio<>coalesce(p_meio,'') OR b.observacoes<>coalesce(p_observacoes,'') OR b.estornado_em IS NOT NULL THEN RAISE EXCEPTION 'Operação de baixa já utilizada ou estornada.';END IF;
  RETURN jsonb_build_object('id',b.id,'repetido',true);
 END IF;
 IF t.cancelado_em IS NOT NULL THEN RAISE EXCEPTION 'Título cancelado.';END IF;
 IF t.origem_tipo<>'MANUAL' THEN
  d:=ew_financeiro_interna.origem_conferir(p_empresa_id,t.origem_tipo,t.origem_id);
  IF d.valor_centavos<>t.valor_centavos THEN RAISE EXCEPTION 'Valor do documento de origem mudou. Concilie antes de baixar.';END IF;
 END IF;
 SELECT coalesce(sum(valor_centavos),0)::bigint INTO v_pago FROM ew_financeiro_interna.baixas WHERE empresa_id=p_empresa_id AND titulo_id=p_titulo_id AND estornado_em IS NULL;
 IF p_valor_centavos>t.valor_centavos-v_pago THEN RAISE EXCEPTION 'Baixa supera o saldo do título.';END IF;
 INSERT INTO ew_financeiro_interna.baixas(empresa_id,titulo_id,operacao_id,valor_centavos,data_baixa,meio,observacoes,criado_por)
 VALUES(p_empresa_id,p_titulo_id,p_operacao_id,p_valor_centavos,p_data,coalesce(p_meio,''),coalesce(p_observacoes,''),auth.uid()) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'saldo_centavos',t.valor_centavos-v_pago-p_valor_centavos,'repetido',false);
END $$;
CREATE FUNCTION public.ew_fin_empresa_estornar_baixa(p_empresa_id uuid,p_baixa_id uuid,p_operacao_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE;b ew_financeiro_interna.baixas%ROWTYPE;v_titulo uuid;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id);
 SELECT titulo_id INTO v_titulo FROM ew_financeiro_interna.baixas WHERE empresa_id=p_empresa_id AND id=p_baixa_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Baixa indisponível.';END IF;
 SELECT * INTO STRICT t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=v_titulo FOR UPDATE;
 PERFORM ew_financeiro_interna.exigir(p_empresa_id,t.tipo,true,t.origem_tipo);
 SELECT * INTO STRICT b FROM ew_financeiro_interna.baixas WHERE empresa_id=p_empresa_id AND id=p_baixa_id FOR UPDATE;
 IF p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Informe motivo do estorno.';END IF;
 IF b.estornado_em IS NOT NULL THEN
  IF b.estorno_operacao_id=p_operacao_id AND b.estorno_motivo=btrim(p_motivo) THEN RETURN jsonb_build_object('id',b.id,'repetido',true);END IF;
  RAISE EXCEPTION 'Baixa já estornada.';
 END IF;
 UPDATE ew_financeiro_interna.baixas SET estornado_em=now(),estornado_por=auth.uid(),estorno_motivo=btrim(p_motivo),estorno_operacao_id=p_operacao_id WHERE empresa_id=p_empresa_id AND id=p_baixa_id;
 RETURN jsonb_build_object('id',b.id,'repetido',false);
END $$;
CREATE FUNCTION public.ew_fin_empresa_cancelar_titulo(p_empresa_id uuid,p_titulo_id uuid,p_operacao_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE t ew_financeiro_interna.titulos%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id);
 SELECT * INTO t FROM ew_financeiro_interna.titulos WHERE empresa_id=p_empresa_id AND id=p_titulo_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Título indisponível.';END IF;
 PERFORM ew_financeiro_interna.exigir(p_empresa_id,t.tipo,true,t.origem_tipo);
 IF p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 400 THEN RAISE EXCEPTION 'Informe motivo do cancelamento.';END IF;
 IF t.cancelado_em IS NOT NULL THEN
  IF t.cancelamento_operacao_id=p_operacao_id AND t.cancelamento_motivo=btrim(p_motivo) THEN RETURN jsonb_build_object('id',t.id,'repetido',true);END IF;
  RAISE EXCEPTION 'Título já cancelado.';
 END IF;
 IF EXISTS(SELECT 1 FROM ew_financeiro_interna.baixas WHERE empresa_id=p_empresa_id AND titulo_id=p_titulo_id AND estornado_em IS NULL) THEN RAISE EXCEPTION 'Estorne as baixas incorretas antes de cancelar o título. Movimentos reais não devem ser apagados.';END IF;
 UPDATE ew_financeiro_interna.titulos SET cancelado_em=now(),cancelado_por=auth.uid(),cancelamento_motivo=btrim(p_motivo),cancelamento_operacao_id=p_operacao_id WHERE empresa_id=p_empresa_id AND id=p_titulo_id;
 RETURN jsonb_build_object('id',t.id,'repetido',false);
END $$;
CREATE FUNCTION public.ew_fin_empresa_consultar(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_ver_estoque boolean;v_result jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir(p_empresa_id);
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Selecione período de até 367 dias.';END IF;
 v_ver_estoque:=public.ew_pode(p_empresa_id,'compras.consultar_valores');
 WITH tit AS MATERIALIZED (
  SELECT t.*,t.origem_tipo='MANUAL' OR coalesce(d.valido AND d.valor_centavos=t.valor_centavos,false) origem_valida,
   coalesce(b.pago,0)::bigint baixado_centavos,
   t.valor_centavos-coalesce(b.pago,0)::bigint saldo_centavos
  FROM ew_financeiro_interna.titulos t LEFT JOIN ew_financeiro_interna.documentos_origem d ON d.empresa_id=t.empresa_id AND d.origem_tipo=t.origem_tipo AND d.origem_id=t.origem_id
  LEFT JOIN LATERAL (SELECT sum(valor_centavos) pago FROM ew_financeiro_interna.baixas b WHERE b.empresa_id=t.empresa_id AND b.titulo_id=t.id AND b.estornado_em IS NULL) b ON true
  WHERE t.empresa_id=p_empresa_id AND (v_ver_estoque OR t.origem_tipo<>'NOTA_ESTOQUE')
 ), docs AS MATERIALIZED (
  SELECT d.* FROM ew_financeiro_interna.documentos_origem d WHERE d.empresa_id=p_empresa_id AND d.valido AND d.valor_centavos>0 AND (v_ver_estoque OR d.origem_tipo<>'NOTA_ESTOQUE')
   AND NOT EXISTS(SELECT 1 FROM tit t WHERE t.origem_tipo=d.origem_tipo AND t.origem_id=d.origem_id AND t.cancelado_em IS NULL)
 ), caixa AS MATERIALIZED (
  SELECT t.tipo,t.centro_custo,b.valor_centavos,b.data_baixa
  FROM tit t JOIN ew_financeiro_interna.baixas b ON b.empresa_id=t.empresa_id AND b.titulo_id=t.id
  WHERE b.estornado_em IS NULL AND b.data_baixa BETWEEN p_inicio AND p_fim
 ), centros AS (
  SELECT centro_custo,coalesce(sum(valor_centavos) FILTER(WHERE tipo='PAGAR'),0) saidas_centavos,coalesce(sum(valor_centavos) FILTER(WHERE tipo='RECEBER'),0) entradas_centavos FROM caixa GROUP BY centro_custo
 ), listados AS (
  SELECT id,tipo,origem_tipo,origem_id,descricao,contraparte,numero_documento,categoria,centro_custo,competencia,vencimento,valor_centavos,baixado_centavos,saldo_centavos,origem_valida,cancelado_em,cancelamento_motivo,
   CASE WHEN cancelado_em IS NOT NULL THEN 'CANCELADO' WHEN NOT origem_valida THEN 'ORIGEM PENDENTE' WHEN saldo_centavos=0 THEN 'LIQUIDADO' WHEN baixado_centavos>0 THEN 'PARCIAL' ELSE 'ABERTO' END situacao,
   (SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'valor_centavos',b.valor_centavos,'data_baixa',b.data_baixa,'meio',b.meio,'observacoes',b.observacoes,'estornado_em',b.estornado_em,'estorno_motivo',b.estorno_motivo) ORDER BY b.data_baixa DESC,b.id),'[]'::jsonb)
    FROM ew_financeiro_interna.baixas b WHERE b.empresa_id=t.empresa_id AND b.titulo_id=t.id) baixas
  FROM tit t
  ORDER BY (cancelado_em IS NOT NULL), (saldo_centavos=0),vencimento,id LIMIT 500
 )
 SELECT jsonb_build_object(
  'escopo_completo',v_ver_estoque,
  'a_pagar_centavos',coalesce((SELECT sum(saldo_centavos) FROM tit WHERE cancelado_em IS NULL AND origem_valida AND tipo='PAGAR'),0),
  'a_receber_centavos',coalesce((SELECT sum(saldo_centavos) FROM tit WHERE cancelado_em IS NULL AND origem_valida AND tipo='RECEBER'),0),
  'vencido_pagar_centavos',coalesce((SELECT sum(saldo_centavos) FROM tit WHERE cancelado_em IS NULL AND origem_valida AND tipo='PAGAR' AND vencimento<current_date),0),
  'vencido_receber_centavos',coalesce((SELECT sum(saldo_centavos) FROM tit WHERE cancelado_em IS NULL AND origem_valida AND tipo='RECEBER' AND vencimento<current_date),0),
  'entradas_centavos',coalesce((SELECT sum(valor_centavos) FROM caixa WHERE tipo='RECEBER'),0),
  'saidas_centavos',coalesce((SELECT sum(valor_centavos) FROM caixa WHERE tipo='PAGAR'),0),
  'origens_pendentes',(SELECT count(*) FROM tit WHERE cancelado_em IS NULL AND NOT origem_valida),
  'documentos_sem_programacao',(SELECT count(*) FROM docs),
  'titulos_total',(SELECT count(*) FROM tit),
  'titulos',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY (l.cancelado_em IS NOT NULL),(l.saldo_centavos=0),l.vencimento,l.id) FROM listados l),'[]'::jsonb),
  'documentos',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.competencia DESC,d.origem_id) FROM (SELECT origem_tipo,origem_id,tipo,descricao,contraparte,numero_documento,categoria,competencia,valor_centavos FROM docs ORDER BY competencia DESC,origem_id LIMIT 500)d),'[]'::jsonb),
  'centros',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'nome',nome) ORDER BY nome,id) FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND ativo),'[]'::jsonb),
  'caixa_centros',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY centro_custo) FROM centros c),'[]'::jsonb)) INTO v_result;
 RETURN v_result;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA ew_financeiro_interna FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ew_financeiro_interna FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.ew_fin_empresa_criar_titulo(uuid,uuid,jsonb),public.ew_fin_empresa_baixar(uuid,uuid,uuid,bigint,date,text,text),public.ew_fin_empresa_estornar_baixa(uuid,uuid,uuid,text),public.ew_fin_empresa_cancelar_titulo(uuid,uuid,uuid,text),public.ew_fin_empresa_consultar(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_fin_empresa_criar_titulo(uuid,uuid,jsonb),public.ew_fin_empresa_baixar(uuid,uuid,uuid,bigint,date,text,text),public.ew_fin_empresa_estornar_baixa(uuid,uuid,uuid,text),public.ew_fin_empresa_cancelar_titulo(uuid,uuid,uuid,text),public.ew_fin_empresa_consultar(uuid,date,date) TO authenticated;
COMMIT;
