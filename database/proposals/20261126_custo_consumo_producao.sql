-- Consumo do lote na produção: não gera outro lançamento financeiro.
CREATE TABLE ew_compras_interna.custo_consumos_integrados (
 empresa_id uuid NOT NULL,movimento_id uuid NOT NULL,operacao_custo uuid NOT NULL DEFAULT gen_random_uuid(),
 quantidade numeric NOT NULL CHECK(quantidade>0),criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT clock_timestamp(),
 estornado_em timestamptz,estorno_operacao uuid,
 PRIMARY KEY(empresa_id,movimento_id),UNIQUE(empresa_id,operacao_custo),
 CHECK((estornado_em IS NULL)=(estorno_operacao IS NULL))
);
ALTER TABLE ew_compras_interna.custo_consumos_integrados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.custo_consumos_integrados FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE VIEW ew_compras_interna.custo_movimentos_reconhecidos WITH(security_invoker=true) AS
 SELECT l.empresa_id,l.movimento_id id,l.cancelado_em IS NOT NULL estornado FROM ew_compras_interna.custo_lotes l
 UNION
 SELECT t.empresa_id,t.origem_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL)
 UNION
 SELECT t.empresa_id,t.destino_movimento_id,v.estornado_em IS NOT NULL
 FROM ew_compras_interna.custo_transferencias_integradas v JOIN ew_compras_interna.transferencias_fisicas_custo t USING(empresa_id,fluxo,transferencia_id)
 WHERE (t.estado='ATIVA' AND v.estornado_em IS NULL) OR (t.estado='ESTORNADA' AND v.estornado_em IS NOT NULL)
 UNION
 SELECT c.empresa_id,c.movimento_id,c.estornado_em IS NOT NULL FROM ew_compras_interna.custo_consumos_integrados c;
CREATE FUNCTION ew_compras_interna.custo_integrar_consumo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE al jsonb; a record; op uuid; n int:=0; u uuid:=auth.uid();
BEGIN
 IF NEW.origem NOT IN ('PLANO_CORTE','PLANO_CORTE_LOTE') OR NEW.quantidade_delta>=0 THEN RETURN NEW; END IF;
 IF u IS NULL OR NOT public.ew_pode(NEW.empresa_id,'estoque.baixar') OR NOT public.ew_pode(NEW.empresa_id,'estoque.consultar') THEN RAISE EXCEPTION 'Sem autorização para consumo'; END IF;
 al:=ew_compras_interna.custo_alocar_saldo_comprovado(NEW.empresa_id,NEW.id);
 IF al IS NULL THEN RETURN NEW; END IF;
 INSERT INTO ew_compras_interna.custo_consumos_integrados(empresa_id,movimento_id,quantidade,criado_por)
 VALUES(NEW.empresa_id,NEW.id,-NEW.quantidade_delta,u) RETURNING operacao_custo INTO op;
 FOR a IN SELECT x.* FROM jsonb_to_recordset(al) x(lote_id uuid,fragmento_id uuid,quantidade numeric) ORDER BY x.lote_id,x.fragmento_id LOOP
  n:=n+1;
  PERFORM ew_compras_interna.custo_mover_fragmento(NEW.empresa_id,a.lote_id,a.fragmento_id,op,n,a.quantidade,'PRODUCAO',NEW.obra_id,NEW.local_estoque,u);
 END LOOP;
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_custo_consumo AFTER INSERT ON public.ew_estoque_obras_movimentos
 FOR EACH ROW WHEN (NEW.origem IN ('PLANO_CORTE','PLANO_CORTE_LOTE') AND NEW.quantidade_delta<0)
 EXECUTE FUNCTION ew_compras_interna.custo_integrar_consumo();
CREATE FUNCTION ew_compras_interna.custo_estornar_consumo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE c record; orig record; e record; qtd numeric; u uuid:=auth.uid();
BEGIN
 IF NEW.origem<>'ESTORNO' OR NEW.estorno_de_id IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO c FROM ew_compras_interna.custo_consumos_integrados WHERE empresa_id=NEW.empresa_id AND movimento_id=NEW.estorno_de_id FOR UPDATE;
 IF NOT FOUND OR c.estornado_em IS NOT NULL THEN RETURN NEW; END IF;
 SELECT * INTO STRICT orig FROM public.ew_estoque_obras_movimentos WHERE empresa_id=NEW.empresa_id AND id=c.movimento_id;
 IF u IS NULL OR NOT public.ew_pode(NEW.empresa_id,'estoque.estornar') THEN RAISE EXCEPTION 'Sem autorização para estorno de consumo'; END IF;
 SELECT coalesce(sum(m.quantidade_delta),0) INTO qtd FROM public.ew_estoque_obras_movimentos m
 WHERE m.empresa_id=NEW.empresa_id AND m.obra_id=orig.obra_id AND m.variacao_id=orig.variacao_id AND m.comprimento_mm IS NOT DISTINCT FROM orig.comprimento_mm AND m.unidade=orig.unidade AND m.local_estoque=orig.local_estoque
 AND m.origem='ESTORNO' AND (m.estorno_de_id=orig.id OR EXISTS(SELECT 1 FROM public.ew_estornos_parcelas ep WHERE ep.empresa_id=NEW.empresa_id AND ep.movimento_original_id=orig.id AND ep.movimento_estorno_id=m.id AND ep.quantidade=abs(m.quantidade_delta)));
 IF qtd<>c.quantidade THEN RAISE EXCEPTION 'Estorno do consumo deve devolver a quantidade integral ao galpão original'; END IF;
 FOR e IN SELECT lote_id,evento_id FROM ew_compras_interna.custo_eventos WHERE empresa_id=NEW.empresa_id AND operacao_id=c.operacao_custo ORDER BY lote_id,parte DESC LOOP
  PERFORM ew_compras_interna.custo_estornar_evento(NEW.empresa_id,e.lote_id,e.evento_id,NEW.operacao_id,u);
 END LOOP;
 UPDATE ew_compras_interna.custo_consumos_integrados SET estornado_em=clock_timestamp(),estorno_operacao=NEW.operacao_id WHERE empresa_id=NEW.empresa_id AND movimento_id=orig.id;
 RETURN NEW;
END;$f$;
CREATE CONSTRAINT TRIGGER ew_custo_consumo_estorno AFTER INSERT ON public.ew_estoque_obras_movimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 WHEN (NEW.origem='ESTORNO' AND NEW.estorno_de_id IS NOT NULL) EXECUTE FUNCTION ew_compras_interna.custo_estornar_consumo();
REVOKE ALL ON FUNCTION ew_compras_interna.custo_integrar_consumo(),ew_compras_interna.custo_estornar_consumo() FROM PUBLIC,anon,authenticated;
