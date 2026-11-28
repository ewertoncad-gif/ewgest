-- Histórico de movimentações sem alterar a lotação original nem a base do ativo.
BEGIN;
CREATE TABLE ew_financeiro_interna.movimentacoes_industriais(
 empresa_id uuid NOT NULL,operacao_id uuid NOT NULL,tipo text NOT NULL CHECK(tipo IN ('FUNCIONARIO','ATIVO')),
 entidade_id uuid NOT NULL,evento text NOT NULL CHECK(evento IN ('TRANSFERENCIA','DESLIGAMENTO')),
 data_evento date NOT NULL,origem_id uuid NOT NULL,destino_id uuid,motivo text NOT NULL,
 criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,operacao_id),UNIQUE(empresa_id,tipo,entidade_id,data_evento),
 CHECK((evento='TRANSFERENCIA' AND destino_id IS NOT NULL AND destino_id<>origem_id) OR (evento='DESLIGAMENTO' AND tipo='FUNCIONARIO' AND destino_id IS NULL))
);
ALTER TABLE ew_financeiro_interna.movimentacoes_industriais ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_financeiro_interna.movimentacoes_industriais FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_industrial_movimentar(p_empresa_id uuid,p_operacao_id uuid,p_tipo text,p_entidade_id uuid,p_evento text,p_data date,p_destino_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE m ew_financeiro_interna.movimentacoes_industriais%ROWTYPE;g uuid;inicio date;
BEGIN
 IF p_tipo='FUNCIONARIO' THEN PERFORM ew_financeiro_interna.exigir_pessoal(p_empresa_id,true);
 ELSE PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,true,false);END IF;
 IF auth.uid() IS NULL OR p_operacao_id IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('FUNCIONARIO','ATIVO') OR p_evento IS NULL OR p_evento NOT IN ('TRANSFERENCIA','DESLIGAMENTO') OR p_data IS NULL OR p_data>(now() AT TIME ZONE 'America/Recife')::date OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 300 THEN RAISE EXCEPTION 'Movimentação inválida.';END IF;
 IF p_tipo='ATIVO' AND (p_evento<>'TRANSFERENCIA' OR extract(day from p_data)<>1) THEN RAISE EXCEPTION 'Transferência patrimonial somente no primeiro dia da competência.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_empresa_id::text||'|MOV_INDUSTRIAL|'||p_operacao_id::text,0));
 SELECT * INTO m FROM ew_financeiro_interna.movimentacoes_industriais WHERE empresa_id=p_empresa_id AND operacao_id=p_operacao_id;
 IF FOUND THEN
  IF m.tipo IS DISTINCT FROM p_tipo OR m.entidade_id IS DISTINCT FROM p_entidade_id OR m.evento IS DISTINCT FROM p_evento OR m.data_evento IS DISTINCT FROM p_data OR m.destino_id IS DISTINCT FROM p_destino_id OR m.motivo IS DISTINCT FROM btrim(p_motivo) THEN RAISE EXCEPTION 'Operação já utilizada.';END IF;
  RETURN jsonb_build_object('repetido',true);
 END IF;
 IF p_tipo='FUNCIONARIO' THEN
  SELECT galpao_id,admissao INTO g,inicio FROM ew_financeiro_interna.funcionarios_industriais WHERE empresa_id=p_empresa_id AND id=p_entidade_id FOR UPDATE;
 ELSE
  SELECT a.galpao_id,a.inicio INTO g,inicio FROM ew_financeiro_interna.ativos_industriais a WHERE a.empresa_id=p_empresa_id AND a.id=p_entidade_id FOR UPDATE;
 END IF;
 IF NOT FOUND OR p_data<inicio THEN RAISE EXCEPTION 'Cadastro ou data indisponível.';END IF;
 SELECT * INTO m FROM ew_financeiro_interna.movimentacoes_industriais WHERE empresa_id=p_empresa_id AND tipo=p_tipo AND entidade_id=p_entidade_id ORDER BY data_evento DESC LIMIT 1;
 IF FOUND THEN
  IF m.evento='DESLIGAMENTO' OR p_data<=m.data_evento THEN RAISE EXCEPTION 'Histórico encerrado ou data fora de sequência.';END IF;
  g:=m.destino_id;
 END IF;
 IF p_tipo='ATIVO' AND EXISTS(SELECT 1 FROM ew_financeiro_interna.depreciacoes_industriais WHERE empresa_id=p_empresa_id AND ativo_id=p_entidade_id AND competencia>=p_data) THEN RAISE EXCEPTION 'Competência já depreciada; não é permitido alterar seu local histórico.';END IF;
 IF p_evento='TRANSFERENCIA' THEN
  IF p_destino_id IS NULL OR p_destino_id=g THEN RAISE EXCEPTION 'Escolha outro local.';END IF;
  PERFORM 1 FROM public.ew_locais_fisicos WHERE empresa_id=p_empresa_id AND id=p_destino_id AND ativo FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Destino indisponível.';END IF;
 ELSIF p_destino_id IS NOT NULL THEN RAISE EXCEPTION 'Desligamento não possui destino.';END IF;
 INSERT INTO ew_financeiro_interna.movimentacoes_industriais(empresa_id,operacao_id,tipo,entidade_id,evento,data_evento,origem_id,destino_id,motivo,criado_por) VALUES(p_empresa_id,p_operacao_id,p_tipo,p_entidade_id,p_evento,p_data,g,p_destino_id,btrim(p_motivo),auth.uid());
 RETURN jsonb_build_object('repetido',false);
END $$;
CREATE FUNCTION public.ew_industrial_movimentos_consultar(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;rh boolean;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão inválida.';END IF;
 rh:=public.ew_pode(p_empresa_id,'usuarios.gerenciar');
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',m.operacao_id,'tipo',m.tipo,'entidade_id',m.entidade_id,'evento',m.evento,'data',m.data_evento,'origem',o.nome,'destino',d.nome,'motivo',m.motivo) ORDER BY m.data_evento DESC,m.operacao_id),'[]') INTO r
 FROM ew_financeiro_interna.movimentacoes_industriais m
 LEFT JOIN public.ew_locais_fisicos o ON o.empresa_id=m.empresa_id AND o.id=m.origem_id
 LEFT JOIN public.ew_locais_fisicos d ON d.empresa_id=m.empresa_id AND d.id=m.destino_id
 WHERE m.empresa_id=p_empresa_id AND (m.tipo='ATIVO' OR rh);
 RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.ew_industrial_movimentar(uuid,uuid,text,uuid,text,date,uuid,text),public.ew_industrial_movimentos_consultar(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_industrial_movimentar(uuid,uuid,text,uuid,text,date,uuid,text),public.ew_industrial_movimentos_consultar(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.ew_industrial_cadastros_consultar(p_empresa_id uuid,p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r jsonb;rh boolean;
BEGIN
 PERFORM ew_financeiro_interna.exigir_resultado(p_empresa_id,false,false);
 IF auth.uid() IS NULL OR p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'Período inválido.';END IF;
 rh:=public.ew_pode(p_empresa_id,'usuarios.gerenciar');
 SELECT jsonb_build_object('pessoal_permitido',rh,
 'funcionarios',CASE WHEN rh THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'matricula',f.matricula,'nome',f.nome,'funcao',f.funcao,'local',g.nome,'admissao',f.admissao,'desligado_em',CASE WHEN m.evento='DESLIGAMENTO' THEN m.data_evento END) ORDER BY f.nome,f.id),'[]') FROM ew_financeiro_interna.funcionarios_industriais f LEFT JOIN LATERAL(SELECT evento,origem_id,destino_id,data_evento FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=f.empresa_id AND m.tipo='FUNCIONARIO' AND m.entidade_id=f.id ORDER BY data_evento DESC LIMIT 1)m ON true LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=coalesce(m.destino_id,m.origem_id,f.galpao_id) WHERE f.empresa_id=p_empresa_id) ELSE '[]'::jsonb END,
 'folhas',CASE WHEN rh THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'local',g.nome,'competencia',f.competencia,'salarios',f.salarios,'encargos',f.encargos,'beneficios',f.beneficios,'referencia',f.referencia,'estornado_em',f.estornado_em,'estorno_motivo',f.estorno_motivo) ORDER BY f.competencia DESC,f.id),'[]') FROM ew_financeiro_interna.folhas_industriais f LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=f.empresa_id AND g.id=f.galpao_id WHERE f.empresa_id=p_empresa_id AND f.competencia BETWEEN date_trunc('month',p_inicio::timestamp)::date AND p_fim) ELSE '[]'::jsonb END,
 'ativos',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'codigo',a.codigo,'descricao',a.descricao,'local',g.nome,'inicio',a.inicio,'valor_centavos',a.valor_centavos,'residual_centavos',a.residual_centavos,'vida_meses',a.vida_meses,'depreciado_centavos',coalesce(d.total,0),'meses',coalesce(d.meses,0)) ORDER BY a.codigo),'[]') FROM ew_financeiro_interna.ativos_industriais a LEFT JOIN LATERAL(SELECT destino_id FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=a.empresa_id AND m.tipo='ATIVO' AND m.entidade_id=a.id ORDER BY data_evento DESC LIMIT 1)m ON true LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=a.empresa_id AND g.id=coalesce(m.destino_id,a.galpao_id) LEFT JOIN LATERAL(SELECT sum(valor_centavos) total,count(*) meses FROM ew_financeiro_interna.depreciacoes_industriais d WHERE d.empresa_id=a.empresa_id AND d.ativo_id=a.id)d ON true WHERE a.empresa_id=p_empresa_id),
 'depreciacoes',(SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',a.codigo,'local',g.nome,'competencia',d.competencia,'valor_centavos',d.valor_centavos) ORDER BY d.competencia DESC,a.codigo),'[]') FROM ew_financeiro_interna.depreciacoes_industriais d JOIN ew_financeiro_interna.ativos_industriais a ON a.empresa_id=d.empresa_id AND a.id=d.ativo_id LEFT JOIN LATERAL(SELECT destino_id FROM ew_financeiro_interna.movimentacoes_industriais m WHERE m.empresa_id=a.empresa_id AND m.tipo='ATIVO' AND m.entidade_id=a.id AND m.data_evento<=d.competencia ORDER BY data_evento DESC LIMIT 1)m ON true LEFT JOIN public.ew_locais_fisicos g ON g.empresa_id=a.empresa_id AND g.id=coalesce(m.destino_id,a.galpao_id) WHERE d.empresa_id=p_empresa_id AND d.competencia BETWEEN date_trunc('month',p_inicio::timestamp)::date AND p_fim)) INTO r;
 RETURN r;
END $$;

COMMIT;
