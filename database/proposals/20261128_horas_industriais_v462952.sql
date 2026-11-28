BEGIN;
CREATE TABLE ew_financeiro_interna.horas_industriais (
 empresa_id uuid NOT NULL,operacao_id uuid NOT NULL,galpao_id uuid NOT NULL,data_trabalho date NOT NULL,
 minutos bigint NOT NULL CHECK(minutos BETWEEN 0 AND 10000000),motivo text NOT NULL,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 estornado_em timestamptz,estornado_por uuid,estorno_operacao_id uuid,estorno_motivo text,
 PRIMARY KEY(empresa_id,operacao_id)
);
CREATE UNIQUE INDEX ew_horas_dia_ativo ON ew_financeiro_interna.horas_industriais(empresa_id,galpao_id,data_trabalho) WHERE estornado_em IS NULL;
CREATE UNIQUE INDEX ew_horas_estorno_op ON ew_financeiro_interna.horas_industriais(empresa_id,estorno_operacao_id) WHERE estorno_operacao_id IS NOT NULL;
ALTER TABLE ew_financeiro_interna.horas_industriais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.horas_industriais FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_industrial_registrar_horas(p_empresa_id uuid,p_operacao_id uuid,p_galpao_id uuid,p_data date,p_minutos bigint,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE h ew_financeiro_interna.horas_industriais%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_data IS NULL OR p_data>(now() AT TIME ZONE 'America/Recife')::date OR p_minutos IS NULL OR p_minutos NOT BETWEEN 0 AND 10000000 OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Dados de horas inválidos.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|HORAS|'||p_operacao_id::text,0));
 SELECT * INTO h FROM ew_financeiro_interna.horas_industriais WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF h.galpao_id IS DISTINCT FROM p_galpao_id OR h.data_trabalho IS DISTINCT FROM p_data OR h.minutos IS DISTINCT FROM p_minutos OR h.motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Identificador já utilizado.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 PERFORM 1 FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=p_galpao_id AND ativo FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Local ativo indisponível.';END IF;
 INSERT INTO ew_financeiro_interna.horas_industriais(empresa_id,operacao_id,galpao_id,data_trabalho,minutos,motivo,criado_por) VALUES(p_empresa_id,p_operacao_id,p_galpao_id,p_data,p_minutos,btrim(p_motivo),auth.uid());
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE FUNCTION public.ew_industrial_estornar_horas(p_empresa_id uuid,p_operacao_id uuid,p_registro_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE h ew_financeiro_interna.horas_industriais%ROWTYPE;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,true);
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Informe justificativa válida.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|HORAS_ESTORNO|'||p_operacao_id::text,0));
 SELECT * INTO h FROM ew_financeiro_interna.horas_industriais WHERE empresa_id=p_empresa_id AND estorno_operacao_id=p_operacao_id;
 IF FOUND THEN
  IF h.operacao_id IS DISTINCT FROM p_registro_id OR h.estorno_motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Identificador já utilizado.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 UPDATE ew_financeiro_interna.horas_industriais SET estornado_em=now(),estornado_por=auth.uid(),estorno_operacao_id=p_operacao_id,estorno_motivo=btrim(p_motivo) WHERE empresa_id=p_empresa_id AND operacao_id=p_registro_id AND estornado_em IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registro ativo indisponível.';END IF;
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE FUNCTION public.ew_industrial_horas_consultar(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF auth.uid() IS NULL OR p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Período inválido.';END IF;
 WITH h AS MATERIALIZED(SELECT h.*,g.nome FROM ew_financeiro_interna.horas_industriais h LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=h.empresa_id AND g.id=h.galpao_id WHERE h.empresa_id=p_empresa_id AND h.data_trabalho BETWEEN p_inicio AND p_fim),
 totais AS(SELECT galpao_id,nome,sum(minutos) minutos,count(*) dias_informados FROM h WHERE estornado_em IS NULL GROUP BY galpao_id,nome)
 SELECT jsonb_build_object('total',(SELECT count(*) FROM h),'registros',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.data_trabalho DESC,x.operacao_id) FROM (SELECT operacao_id,galpao_id,nome,data_trabalho,minutos,motivo,estornado_em,estorno_motivo FROM h ORDER BY (estornado_em IS NOT NULL),data_trabalho DESC,operacao_id LIMIT 500)x),'[]'::jsonb),
 'totais',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY nome,galpao_id) FROM totais t),'[]'::jsonb)) INTO r;
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_industrial_registrar_horas(uuid,uuid,uuid,date,bigint,text),public.ew_industrial_estornar_horas(uuid,uuid,uuid,text),public.ew_industrial_horas_consultar(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_industrial_registrar_horas(uuid,uuid,uuid,date,bigint,text),public.ew_industrial_estornar_horas(uuid,uuid,uuid,text),public.ew_industrial_horas_consultar(uuid,date,date) TO authenticated;
COMMIT;
