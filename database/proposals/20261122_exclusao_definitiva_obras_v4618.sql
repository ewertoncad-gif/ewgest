-- EWGEST v46.18 — Encerramento definitivo de obra, sem reativação.
-- Não apaga cadastros históricos, romaneios, material ou auditoria.
BEGIN;

CREATE OR REPLACE FUNCTION public.ew_restaurar_estoque_local(p_empresa_id uuid,p_obra_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 RAISE EXCEPTION 'RESTAURACAO_DESATIVADA: a exclusão de obra/estoque é definitiva. Reimporte a obra e refaça os processos.';
END;
$fn$;
REVOKE ALL ON FUNCTION public.ew_restaurar_estoque_local(uuid,uuid) FROM PUBLIC,anon,authenticated;

-- O estoque não pode mais ser arquivado à parte: o encerramento passa
-- pela conferência e confirmação definitiva em Gerenciar obras.
CREATE OR REPLACE FUNCTION public.ew_excluir_estoque_local(p_empresa_id uuid,p_obra_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 RAISE EXCEPTION 'ARQUIVAMENTO_ISOLADO_DESATIVADO: encerre a obra definitivamente em Gerenciar obras, depois de cancelar as operações e estornar o estoque.';
END;
$fn$;
REVOKE ALL ON FUNCTION public.ew_excluir_estoque_local(uuid,uuid) FROM PUBLIC,anon,authenticated;

-- Proibição estrutural de alterar um estoque encerrado de volta para ativo,
-- inclusive por futuras rotinas privilegiadas que esqueçam a regra.
CREATE OR REPLACE FUNCTION public.ew_bloquear_reabertura_estoque()
 RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF OLD.excluido_em IS NOT NULL AND NEW.excluido_em IS NULL THEN
  RAISE EXCEPTION 'ESTOQUE_ENCERRADO_DEFINITIVO: estoque arquivado não pode ser restaurado. Importe nova obra.';
 END IF;
 RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS ew_bloquear_reabertura_estoque ON public.ew_estoques_locais;
CREATE TRIGGER ew_bloquear_reabertura_estoque BEFORE UPDATE OF excluido_em
 ON public.ew_estoques_locais FOR EACH ROW
 EXECUTE FUNCTION public.ew_bloquear_reabertura_estoque();

-- A obra arquivada tem ID histórico imutável. Nova importação cria novo ID.
CREATE OR REPLACE FUNCTION public.ew_bloquear_reabertura_obra()
 RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF OLD.arquivada_em IS NOT NULL AND NEW.arquivada_em IS NULL THEN
  RAISE EXCEPTION 'OBRA_ENCERRADA_DEFINITIVA: não é possível reabrir esta obra. Faça uma nova importação.';
 END IF;
 RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS ew_bloquear_reabertura_obra ON public.obras;
CREATE TRIGGER ew_bloquear_reabertura_obra BEFORE UPDATE OF arquivada_em
 ON public.obras FOR EACH ROW
 EXECUTE FUNCTION public.ew_bloquear_reabertura_obra();
REVOKE ALL ON FUNCTION public.ew_bloquear_reabertura_obra() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ew_bloquear_reabertura_estoque() FROM PUBLIC,anon,authenticated;
COMMIT;
