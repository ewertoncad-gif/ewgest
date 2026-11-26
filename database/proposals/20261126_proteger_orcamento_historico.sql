-- Evita que um PATCH altere o contrato usado por uma precificação ou histórico financeiro.
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_orcamento_historico() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF (NEW.empresa_id,NEW.obra_id) IS DISTINCT FROM (OLD.empresa_id,OLD.obra_id) THEN RAISE EXCEPTION 'Identidade do orçamento é imutável.';END IF;
 IF (NEW.valor_total,NEW.aluminio,NEW.acessorios,NEW.vidros,NEW.outros,NEW.fabricacao,NEW.instalacao) IS DISTINCT FROM (OLD.valor_total,OLD.aluminio,OLD.acessorios,OLD.vidros,OLD.outros,OLD.fabricacao,OLD.instalacao) AND (
 EXISTS(SELECT 1 FROM public.ew_precificacao_revisoes r WHERE r.empresa_id=OLD.empresa_id AND r.obra_id=OLD.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_obra_orcamento_niveis n WHERE n.empresa_id=OLD.empresa_id AND n.obra_id=OLD.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_obra_faturamentos f WHERE f.empresa_id=OLD.empresa_id AND f.obra_id=OLD.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_obra_despesas d WHERE d.empresa_id=OLD.empresa_id AND d.obra_id=OLD.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_compras_pedidos p WHERE p.empresa_id=OLD.empresa_id AND p.obra_id=OLD.obra_id)
 ) THEN RAISE EXCEPTION 'Orçamento com histórico ou níveis cadastrados: alteração exige revisão contratual controlada.';END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_orcamento_historico() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_orcamento_historico_guard BEFORE UPDATE ON public.ew_obra_orcamento FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_orcamento_historico();
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_nivel_orcamento() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE limite numeric; soma numeric;
BEGIN
 SELECT CASE NEW.categoria_base WHEN 'aluminio' THEN aluminio WHEN 'acessorios' THEN acessorios WHEN 'vidros' THEN vidros WHEN 'outros' THEN outros WHEN 'fabricacao' THEN fabricacao WHEN 'instalacao' THEN instalacao END INTO limite
 FROM public.ew_obra_orcamento WHERE empresa_id=NEW.empresa_id AND obra_id=NEW.obra_id FOR UPDATE;
 IF NOT FOUND OR limite IS NULL THEN RAISE EXCEPTION 'Nível sem orçamento válido.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_precificacao_revisoes r WHERE r.empresa_id=NEW.empresa_id AND r.obra_id=NEW.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_obra_faturamentos f WHERE f.empresa_id=NEW.empresa_id AND f.obra_id=NEW.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_obra_despesas d WHERE d.empresa_id=NEW.empresa_id AND d.obra_id=NEW.obra_id)
 OR EXISTS(SELECT 1 FROM public.ew_compras_pedidos p WHERE p.empresa_id=NEW.empresa_id AND p.obra_id=NEW.obra_id)
 THEN RAISE EXCEPTION 'Níveis com histórico: alteração exige revisão contratual controlada.';END IF;
 SELECT coalesce(sum(valor),0) INTO soma FROM public.ew_obra_orcamento_niveis WHERE empresa_id=NEW.empresa_id AND obra_id=NEW.obra_id AND categoria_base=NEW.categoria_base;
 IF soma+NEW.valor>limite THEN RAISE EXCEPTION 'Níveis excedem o orçamento original do grupo financeiro.';END IF;
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION ew_compras_interna.proteger_nivel_orcamento() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER ew_nivel_orcamento_guard BEFORE INSERT ON public.ew_obra_orcamento_niveis FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_nivel_orcamento();
