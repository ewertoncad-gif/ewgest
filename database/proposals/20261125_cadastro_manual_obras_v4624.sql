BEGIN;
ALTER TABLE public.obras ADD COLUMN IF NOT EXISTS cadastro_manual boolean NOT NULL DEFAULT false;
ALTER TABLE public.obras ADD COLUMN IF NOT EXISTS cadastrada_por uuid REFERENCES auth.users(id);
CREATE OR REPLACE FUNCTION public.ew_cadastrar_obra_manual(p_empresa_id uuid,p_nome text,p_codigo text,p_cliente text,p_prazo date,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE u uuid:=auth.uid(); n text:=btrim(coalesce(p_nome,'')); c text:=upper(btrim(coalesce(p_codigo,''))); cli text:=btrim(coalesce(p_cliente,'')); o public.obras%rowtype;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF u IS NULL OR p_operacao_id IS NULL OR NOT public.ew_pode(p_empresa_id,'obras.importar') OR NOT public.ew_pode(p_empresa_id,'cadastros.consultar') THEN RAISE EXCEPTION 'Sem permissão para cadastrar obra.'; END IF;
 IF length(n) NOT BETWEEN 3 AND 180 OR length(c)>80 OR length(cli)>180 OR c LIKE 'MAN-%' THEN RAISE EXCEPTION 'Nome, código ou cliente inválido. Prefixo MAN- reservado para estoques legados.'; END IF;
 IF p_prazo IS NOT NULL AND p_prazo<date '2000-01-01' THEN RAISE EXCEPTION 'Prazo inválido.'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_empresa_id::text,462400));
 IF c='' THEN c:='OBR-'||upper(left(replace(p_operacao_id::text,'-',''),10)); END IF;
 SELECT * INTO o FROM public.obras WHERE id=p_operacao_id;
 IF FOUND THEN
  IF o.empresa_id=p_empresa_id AND o.cadastro_manual AND o.cadastrada_por=u AND o.arquivada_em IS NULL AND o.nome=n AND o.codigo=c AND o.cliente IS NOT DISTINCT FROM nullif(cli,'') AND o.prazo_previsto IS NOT DISTINCT FROM p_prazo THEN RETURN jsonb_build_object('id',o.id,'codigo',o.codigo,'nome',o.nome,'repetida',true); END IF;
  RAISE EXCEPTION 'Identificador de operação já utilizado.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.obras WHERE empresa_id=p_empresa_id AND arquivada_em IS NULL AND (upper(btrim(codigo))=c OR upper(btrim(nome))=upper(n))) THEN RAISE EXCEPTION 'Já existe obra ativa com este nome ou código.'; END IF;
 INSERT INTO public.obras(id,empresa_id,nome,codigo,cliente,prazo_previsto,situacao,cadastro_manual,cadastrada_por)
 VALUES(p_operacao_id,p_empresa_id,n,c,nullif(cli,''),p_prazo,'Em andamento',true,u) RETURNING * INTO o;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por) VALUES(p_empresa_id,o.id,u);
 RETURN jsonb_build_object('id',o.id,'codigo',o.codigo,'nome',o.nome,'repetida',false);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_cadastrar_obra_manual(uuid,text,text,text,date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ew_cadastrar_obra_manual(uuid,text,text,text,date,uuid) TO authenticated;
COMMIT;
