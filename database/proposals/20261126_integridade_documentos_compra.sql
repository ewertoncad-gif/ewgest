-- Proteção de identidade fiscal entre estoque próprio e obra, sem alterar dados históricos.
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_identidade_fiscal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE k text:=nullif(btrim(coalesce(NEW.chave_nfe,'')),''); doc text; forn text;
BEGIN
 IF TG_TABLE_NAME='ew_obra_despesas' THEN
  IF NEW.status='cancelada' THEN RETURN NEW;END IF;
  IF TG_OP='UPDATE' THEN
   IF (NEW.empresa_id,NEW.obra_id,NEW.id) IS DISTINCT FROM (OLD.empresa_id,OLD.obra_id,OLD.id) THEN RAISE EXCEPTION 'Identidade da despesa é imutável.';END IF;
   IF OLD.status='aprovada' AND (NEW.valor,NEW.categoria,NEW.fornecedor,NEW.numero_documento,NEW.chave_nfe,NEW.data_documento) IS DISTINCT FROM (OLD.valor,OLD.categoria,OLD.fornecedor,OLD.numero_documento,OLD.chave_nfe,OLD.data_documento)
   THEN RAISE EXCEPTION 'Despesa aprovada: cancele pela rotina oficial antes de corrigir dados financeiros.';END IF;
  END IF;
  doc:=nullif(upper(btrim(coalesce(NEW.numero_documento,''))),'');
  forn:=nullif(lower(btrim(coalesce(NEW.fornecedor,''))),'');
 ELSE
  IF NEW.status='CANCELADA' THEN RETURN NEW;END IF;
  doc:=nullif(upper(btrim(coalesce(NEW.numero_documento,''))),'');
  SELECT lower(btrim(nome)) INTO forn FROM public.ew_fornecedores WHERE id=NEW.fornecedor_id AND empresa_id=NEW.empresa_id;
 END IF;
 IF k IS NOT NULL THEN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nf-global|'||NEW.empresa_id::text||'|'||k,68742));
  IF (TG_TABLE_NAME='ew_obra_despesas' AND EXISTS(SELECT 1 FROM public.ew_compras_notas_empresa n WHERE n.empresa_id=NEW.empresa_id AND n.chave_nfe=k AND n.status='ATIVA'))
  OR (TG_TABLE_NAME='ew_compras_notas_empresa' AND EXISTS(SELECT 1 FROM public.ew_obra_despesas d WHERE d.empresa_id=NEW.empresa_id AND d.chave_nfe=k AND d.status<>'cancelada'))
  THEN RAISE EXCEPTION 'Chave NF-e já registrada em outro fluxo de estoque da empresa.';END IF;
 END IF;
 IF TG_TABLE_NAME='ew_obra_despesas' THEN
 IF doc IS NOT NULL AND forn IS NOT NULL THEN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nf-obra-doc|'||NEW.empresa_id::text||'|'||NEW.obra_id::text||'|'||forn||'|'||doc,68742));
  IF EXISTS(SELECT 1 FROM public.ew_obra_despesas d WHERE d.empresa_id=NEW.empresa_id AND d.obra_id=NEW.obra_id AND d.id<>NEW.id AND d.status<>'cancelada' AND lower(btrim(d.fornecedor))=forn AND upper(btrim(d.numero_documento))=doc AND (k IS NULL OR d.chave_nfe IS NULL))
  THEN RAISE EXCEPTION 'Documento já registrado para este fornecedor na obra. Confira a nota anterior antes de lançar novamente.';END IF;
 END IF;
 END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_identidade_fiscal() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_identidade_fiscal_guard BEFORE INSERT OR UPDATE ON public.ew_obra_despesas FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_identidade_fiscal();
CREATE TRIGGER ew_identidade_fiscal_guard BEFORE INSERT OR UPDATE ON public.ew_compras_notas_empresa FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_identidade_fiscal();
-- Itens de nota com vínculo físico ou fiscal não podem ser modificados por PATCH.
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_itens_fiscais_vinculados() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid; e uuid;
BEGIN
 IF TG_OP='UPDATE' THEN
  IF (NEW.id,NEW.despesa_id,NEW.empresa_id) IS DISTINCT FROM (OLD.id,OLD.despesa_id,OLD.empresa_id) THEN RAISE EXCEPTION 'Identidade do item fiscal é imutável.';END IF;
 END IF;
 d:=NEW.despesa_id;e:=NEW.empresa_id;
 IF EXISTS(SELECT 1 FROM public.ew_compras_nfe_conciliacoes c WHERE c.despesa_id=d AND c.empresa_id=e AND c.desvinculado_em IS NULL)
 OR EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos r JOIN public.ew_obra_despesas_itens i ON i.id=r.despesa_item_id AND i.empresa_id=r.empresa_id WHERE i.despesa_id=d AND i.empresa_id=e AND r.estornado_em IS NULL)
 OR EXISTS(SELECT 1 FROM public.ew_insumos_movimentos m JOIN public.ew_obra_despesas_itens i ON i.id=m.despesa_item_id AND i.empresa_id=m.empresa_id WHERE i.despesa_id=d AND i.empresa_id=e AND m.origem='RECEBIMENTO' AND TG_OP='UPDATE')
 THEN RAISE EXCEPTION 'Nota com vínculo físico ou fiscal ativo: regularize os vínculos antes de alterar itens.';END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_itens_fiscais_vinculados() FROM PUBLIC,anon,authenticated;
-- INSERT permanece disponível para rotinas que criam itens e entradas intercaladamente.
CREATE TRIGGER ew_itens_fiscais_guard BEFORE UPDATE ON public.ew_obra_despesas_itens FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_itens_fiscais_vinculados();
