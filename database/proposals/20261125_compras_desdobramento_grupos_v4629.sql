BEGIN;
-- v46.29: desdobramento imutável por grupo; reaproveita o fluxo auditado de pedido/recebimento.
-- Não aplicar isoladamente: depende da interface e da homologação comercial completa.
ALTER TABLE public.ew_compras_solicitacoes DROP CONSTRAINT ew_compras_solicitacoes_status_check;
ALTER TABLE public.ew_compras_solicitacoes ADD CONSTRAINT ew_compras_solicitacoes_status_check
 CHECK(status IN ('ABERTA','PEDIDO_GERADO','CANCELADA','AGRUPADA','DESDOBRADA'));
CREATE TABLE ew_compras_interna.desdobramentos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,
 solicitacao_id uuid NOT NULL UNIQUE REFERENCES public.ew_compras_solicitacoes(id),
 operacao_id uuid NOT NULL UNIQUE,criado_por uuid NOT NULL,criado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(empresa_id,id)
);
CREATE TABLE ew_compras_interna.desdobramentos_grupos (
 empresa_id uuid NOT NULL,desdobramento_id uuid NOT NULL,grupo_id uuid NOT NULL,
 solicitacao_filha_id uuid NOT NULL UNIQUE REFERENCES public.ew_compras_solicitacoes(id),
 nome_grupo text NOT NULL,itens jsonb NOT NULL,
 PRIMARY KEY(desdobramento_id,grupo_id),
 FOREIGN KEY(empresa_id,desdobramento_id) REFERENCES ew_compras_interna.desdobramentos(empresa_id,id),
 FOREIGN KEY(empresa_id,grupo_id) REFERENCES ew_compras_interna.grupos_compra(empresa_id,id)
);
ALTER TABLE ew_compras_interna.desdobramentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_compras_interna.desdobramentos_grupos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.desdobramentos,ew_compras_interna.desdobramentos_grupos FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.ew_compras_desdobrar_grupos(p_empresa_id uuid,p_solicitacao_id uuid,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE s public.ew_compras_solicitacoes%rowtype; d ew_compras_interna.desdobramentos%rowtype;
 previa jsonb; g jsonb; filho uuid;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT(public.ew_pode(p_empresa_id,'compras.cotar') AND public.ew_pode(p_empresa_id,'compras.consultar_valores')) THEN RAISE EXCEPTION 'Sem permissão para desdobrar.';END IF;
 IF p_operacao_id IS NULL THEN RAISE EXCEPTION 'Operação inválida.';END IF;
 SELECT * INTO s FROM public.ew_compras_solicitacoes WHERE id=p_solicitacao_id AND empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitação inexistente nesta empresa.';END IF;
 SELECT * INTO d FROM ew_compras_interna.desdobramentos WHERE solicitacao_id=s.id;
 IF FOUND THEN
  RETURN jsonb_build_object('id',d.id,'repetida',true);
 END IF;
 IF s.status<>'ABERTA' OR EXISTS(SELECT 1 FROM ew_compras_interna.desdobramentos_grupos WHERE solicitacao_filha_id=s.id) THEN RAISE EXCEPTION 'Solicitação indisponível para desdobramento.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_compras_cotacoes WHERE solicitacao_id=s.id) OR EXISTS(SELECT 1 FROM public.ew_compras_pedidos WHERE solicitacao_id=s.id) OR EXISTS(SELECT 1 FROM ew_compras_interna.convites WHERE solicitacao_id=s.id) THEN RAISE EXCEPTION 'Solicitação com histórico comercial; exige tratamento de legado.';END IF;
 previa:=public.ew_compras_previa_grupos(p_empresa_id,s.id);
 IF jsonb_array_length(previa)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(previa) x WHERE x->>'grupo_id' IS NULL OR NOT coalesce((x->>'ativo')::boolean,false)) THEN RAISE EXCEPTION 'Classifique os materiais em grupos ativos antes de desdobrar.';END IF;
 INSERT INTO ew_compras_interna.desdobramentos(empresa_id,solicitacao_id,operacao_id,criado_por)
 VALUES(p_empresa_id,s.id,p_operacao_id,auth.uid()) RETURNING * INTO d;
 FOR g IN SELECT value FROM jsonb_array_elements(previa) LOOP
  INSERT INTO public.ew_compras_solicitacoes(empresa_id,obra_id,local_empresa_id,operacao_id,itens,observacoes,criado_por)
  VALUES(p_empresa_id,s.obra_id,s.local_empresa_id,gen_random_uuid(),g->'itens',left('Grupo: '||(g->>'nome')||' · '||coalesce(s.observacoes,''),600),auth.uid()) RETURNING id INTO filho;
  INSERT INTO ew_compras_interna.desdobramentos_grupos(empresa_id,desdobramento_id,grupo_id,solicitacao_filha_id,nome_grupo,itens)
  VALUES(p_empresa_id,d.id,(g->>'grupo_id')::uuid,filho,g->>'nome',g->'itens');
 END LOOP;
 UPDATE public.ew_compras_solicitacoes SET status='DESDOBRADA' WHERE id=s.id;
 RETURN jsonb_build_object('id',d.id,'repetida',false,'grupos',jsonb_array_length(previa));
END;$f$;
CREATE FUNCTION public.ew_compras_grupos_desdobrados(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'compras.consultar') THEN RAISE EXCEPTION 'Sem permissão para consultar grupos.';END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('solicitacao_id',d.solicitacao_id,'filha_id',g.solicitacao_filha_id,'grupo_id',g.grupo_id,'nome',g.nome_grupo,'status',s.status) ORDER BY d.criado_em,g.nome_grupo),'[]'::jsonb)
 FROM ew_compras_interna.desdobramentos d JOIN ew_compras_interna.desdobramentos_grupos g ON g.desdobramento_id=d.id AND g.empresa_id=d.empresa_id
 JOIN public.ew_compras_solicitacoes s ON s.id=g.solicitacao_filha_id AND s.empresa_id=g.empresa_id WHERE d.empresa_id=p_empresa_id);
END;$f$;
-- Não permitir que o agrupamento legado recombine filhas e perca o vínculo.
CREATE FUNCTION ew_compras_interna.proteger_filha_grupo() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 IF NEW.status IN ('AGRUPADA','DESDOBRADA') AND EXISTS(SELECT 1 FROM ew_compras_interna.desdobramentos_grupos WHERE solicitacao_filha_id=NEW.id) THEN RAISE EXCEPTION 'Grupo desdobrado não pode ser agrupado novamente.';END IF;
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_compras_proteger_filha_grupo BEFORE UPDATE OF status ON public.ew_compras_solicitacoes FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_filha_grupo();
-- Mantém a checagem de solicitação ativa e bloqueia fornecedores incompatíveis nas filhas.
-- Legado sem desdobramento só segue se já tiver histórico comercial anterior à migração.
CREATE TABLE ew_compras_interna.legado_sem_grupo(solicitacao_id uuid PRIMARY KEY REFERENCES public.ew_compras_solicitacoes(id));
ALTER TABLE ew_compras_interna.legado_sem_grupo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.legado_sem_grupo FROM PUBLIC,anon,authenticated;
INSERT INTO ew_compras_interna.legado_sem_grupo SELECT DISTINCT solicitacao_id FROM public.ew_compras_cotacoes
 UNION SELECT DISTINCT solicitacao_id FROM public.ew_compras_pedidos
 UNION SELECT DISTINCT solicitacao_id FROM ew_compras_interna.convites;
CREATE FUNCTION ew_compras_interna.exigir_fornecedor_grupo(e uuid,s uuid,f uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE gid uuid;
BEGIN
 SELECT grupo_id INTO gid FROM ew_compras_interna.desdobramentos_grupos WHERE solicitacao_filha_id=s AND empresa_id=e;
 IF gid IS NULL THEN
  IF EXISTS(SELECT 1 FROM ew_compras_interna.legado_sem_grupo WHERE solicitacao_id=s) THEN RETURN;END IF;
  RAISE EXCEPTION 'Separe a solicitação em grupos antes de cotar.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ew_compras_interna.fornecedores_grupos fg JOIN ew_compras_interna.grupos_compra g ON g.id=fg.grupo_id AND g.empresa_id=fg.empresa_id AND g.ativo JOIN public.ew_fornecedores f0 ON f0.id=fg.fornecedor_id AND f0.empresa_id=fg.empresa_id AND f0.ativo WHERE fg.empresa_id=e AND fg.grupo_id=gid AND fg.fornecedor_id=f) THEN RAISE EXCEPTION 'Fornecedor não atende ao grupo de compra.';END IF;
END;$f$;
CREATE OR REPLACE FUNCTION ew_compras_interna.proteger_cotacao() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM 1 FROM public.ew_compras_solicitacoes s WHERE s.id=NEW.solicitacao_id AND s.empresa_id=NEW.empresa_id AND s.status='ABERTA' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitação indisponível para cotação.';END IF;
 PERFORM ew_compras_interna.exigir_fornecedor_grupo(NEW.empresa_id,NEW.solicitacao_id,NEW.fornecedor_id);
 RETURN NEW;
END;$f$;
CREATE FUNCTION ew_compras_interna.proteger_convite_grupo() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM ew_compras_interna.exigir_fornecedor_grupo(NEW.empresa_id,NEW.solicitacao_id,NEW.fornecedor_id);
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_compras_proteger_convite_grupo BEFORE INSERT ON ew_compras_interna.convites FOR EACH ROW EXECUTE FUNCTION ew_compras_interna.proteger_convite_grupo();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ew_compras_interna FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ew_compras_desdobrar_grupos(uuid,uuid,uuid),public.ew_compras_grupos_desdobrados(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_compras_desdobrar_grupos(uuid,uuid,uuid),public.ew_compras_grupos_desdobrados(uuid) TO authenticated;
COMMIT;
