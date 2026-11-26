-- Fundação do rateio de custo de transferência. Não executa apropriações,
-- não cria despesas, não altera estoque, flags, orçamento ou notas.
-- Somente chamar com lote fiscal comprovado e saldo reservado na mesma transação.
-- Custo zero é permitido somente quando comprovado; NULL nunca representa zero.
-- Estorno deve usar o valor efetivamente persistido na apropriação original.
CREATE OR REPLACE FUNCTION ew_compras_interna.custo_parcela_centavos(
 p_total_centavos bigint,p_quantidade_lote numeric,p_quantidade_anterior numeric,p_quantidade_transferida numeric
) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $fn$
BEGIN
 IF p_total_centavos IS NULL OR p_total_centavos<0
 OR p_quantidade_lote IS NULL OR p_quantidade_anterior IS NULL OR p_quantidade_transferida IS NULL
 OR p_quantidade_lote::text IN ('NaN','Infinity','-Infinity')
 OR p_quantidade_anterior::text IN ('NaN','Infinity','-Infinity')
 OR p_quantidade_transferida::text IN ('NaN','Infinity','-Infinity')
 OR p_quantidade_lote<=0 OR p_quantidade_anterior<0 OR p_quantidade_transferida<=0
 OR p_quantidade_anterior+p_quantidade_transferida>p_quantidade_lote THEN
  RAISE EXCEPTION 'Lote de custo ausente ou quantidade inválida' USING ERRCODE='22023';
 END IF;
 RETURN (round(p_total_centavos::numeric*(p_quantidade_anterior+p_quantidade_transferida)/p_quantidade_lote)
       - round(p_total_centavos::numeric*p_quantidade_anterior/p_quantidade_lote))::bigint;
END;
$fn$;
REVOKE ALL ON FUNCTION ew_compras_interna.custo_parcela_centavos(bigint,numeric,numeric,numeric) FROM PUBLIC,anon,authenticated;

-- Regressões: falham a transação se uma invariável for violada.
DO $test$
DECLARE a bigint; b bigint; c bigint; x bigint;
BEGIN
 a:=ew_compras_interna.custo_parcela_centavos(10000,3,0,1);
 b:=ew_compras_interna.custo_parcela_centavos(10000,3,1,1);
 c:=ew_compras_interna.custo_parcela_centavos(10000,3,2,1);
 IF a<>3333 OR b<>3334 OR c<>3333 OR a+b+c<>10000 THEN RAISE EXCEPTION 'Falha no fechamento de centavos'; END IF;
 IF ew_compras_interna.custo_parcela_centavos(100,2.5,0,0.5)<>20 THEN RAISE EXCEPTION 'Falha em unidade fracionária'; END IF;
 IF ew_compras_interna.custo_parcela_centavos(0,3,0,1)<>0 THEN RAISE EXCEPTION 'Falha no custo zero comprovado'; END IF;
 IF ew_compras_interna.custo_parcela_centavos(9223372036854775807,1,0,1)<>9223372036854775807 THEN RAISE EXCEPTION 'Falha no limite bigint'; END IF;
 BEGIN
  x:=ew_compras_interna.custo_parcela_centavos(NULL,3,0,1); RAISE EXCEPTION 'Aceitou custo desconhecido';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  x:=ew_compras_interna.custo_parcela_centavos(100,3,2,2); RAISE EXCEPTION 'Aceitou quantidade superior ao lote';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  x:=ew_compras_interna.custo_parcela_centavos(100,'NaN'::numeric,0,1); RAISE EXCEPTION 'Aceitou NaN';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  x:=ew_compras_interna.custo_parcela_centavos(-1,3,0,1); RAISE EXCEPTION 'Aceitou custo negativo';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END;
$test$;
-- Integração pendente: rastrear saldo por lote e posições de rateio não sobrepostas,
-- vincular a transferência física, persistir valor imutável e estorno compensatório,
-- validar permissões existentes e integrar o financeiro sem duplicar notas.
