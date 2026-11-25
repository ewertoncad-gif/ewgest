BEGIN;
-- v46.27: sequência compartilhada por obra, sem renumerar documentos.
CREATE SCHEMA ew_romnum_interna;
REVOKE ALL ON SCHEMA ew_romnum_interna FROM PUBLIC,anon,authenticated;
CREATE TABLE ew_romnum_interna.pisos(
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid PRIMARY KEY REFERENCES public.obras(id) ON DELETE CASCADE,
 piso bigint NOT NULL CHECK(piso BETWEEN 1 AND 999999999)
);
CREATE TABLE ew_romnum_interna.eventos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL,
 obra_id uuid NOT NULL,usuario_id uuid,evento text NOT NULL,documento_id uuid,numero text,detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,criado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ew_romnum_interna.pisos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_romnum_interna.eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA ew_romnum_interna FROM PUBLIC,anon,authenticated;
CREATE INDEX ew_romnum_eventos_obra_idx ON ew_romnum_interna.eventos(empresa_id,obra_id,criado_em,id);
DO $check$
BEGIN
 IF EXISTS(SELECT 1 FROM (SELECT empresa_id,obra_id,numero FROM public.romaneios UNION ALL SELECT empresa_id,obra_id,numero FROM public.ew_romaneios_transferencia WHERE status<>'AGRUPADO') d GROUP BY empresa_id,obra_id,numero HAVING count(*)>1)
 OR EXISTS(SELECT 1 FROM (SELECT numero FROM public.romaneios UNION ALL SELECT numero FROM public.ew_romaneios_transferencia) d WHERE numero !~ '^RM[0-9]{3,9}$')
 THEN RAISE EXCEPTION 'Numeração legada incompatível: revisar documentos antes da migração.';END IF;
END;$check$;
ALTER TABLE public.romaneios ALTER COLUMN numero DROP DEFAULT;
ALTER TABLE public.romaneios DROP CONSTRAINT IF EXISTS romaneios_empresa_id_numero_key;
ALTER TABLE public.romaneios ADD CONSTRAINT romaneios_obra_numero_key UNIQUE(empresa_id,obra_id,numero);
ALTER TABLE public.ew_romaneios_transferencia DROP CONSTRAINT ew_romaneios_transferencia_numero_key;
CREATE UNIQUE INDEX ew_romtrans_obra_numero_reservado ON public.ew_romaneios_transferencia(empresa_id,obra_id,numero) WHERE status<>'AGRUPADO';

CREATE FUNCTION ew_romnum_interna.codigo(n bigint) RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path='' AS $f$
 SELECT 'RM'||lpad(n::text,greatest(3,length(n::text)),'0')
$f$;
CREATE FUNCTION ew_romnum_interna.travar(e uuid,o uuid) RETURNS void LANGUAGE plpgsql SET search_path='' AS $f$
BEGIN
 -- Falha rápida, em vez de esperar mantendo locks de estoque e criar deadlock.
 IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('EW_ROMNUM|'||e::text||'|'||o::text,4627)) THEN
 RAISE EXCEPTION 'Numeração desta obra em uso. Tente novamente.' USING ERRCODE='55P03';END IF;
END;$f$;
CREATE FUNCTION ew_romnum_interna.proximo(e uuid,o uuid) RETURNS bigint LANGUAGE sql VOLATILE SET search_path='' AS $f$
 SELECT greatest(coalesce((SELECT piso FROM ew_romnum_interna.pisos WHERE empresa_id=e AND obra_id=o),1),1+coalesce(max(n),0))
 FROM (
 SELECT substring(numero from 3)::bigint n FROM public.romaneios WHERE empresa_id=e AND obra_id=o
 UNION ALL SELECT substring(numero from 3)::bigint FROM public.ew_romaneios_transferencia WHERE empresa_id=e AND obra_id=o AND status<>'AGRUPADO'
 ) d
$f$;
CREATE FUNCTION ew_romnum_interna.atribuir() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE n bigint; reutilizado boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=NEW.obra_id AND empresa_id=NEW.empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Obra indisponível para numeração.';END IF;
 PERFORM ew_romnum_interna.travar(NEW.empresa_id,NEW.obra_id);
 n:=ew_romnum_interna.proximo(NEW.empresa_id,NEW.obra_id);
 IF n>999999999 THEN RAISE EXCEPTION 'Limite de numeração atingido.';END IF;
 NEW.numero:=ew_romnum_interna.codigo(n);
 SELECT EXISTS(SELECT 1 FROM public.ew_romaneios_transferencia WHERE empresa_id=NEW.empresa_id AND obra_id=NEW.obra_id AND numero=NEW.numero AND status='AGRUPADO') INTO reutilizado;
 INSERT INTO ew_romnum_interna.eventos(empresa_id,obra_id,usuario_id,evento,documento_id,numero,detalhes)
 VALUES(NEW.empresa_id,NEW.obra_id,NEW.criado_por,CASE WHEN reutilizado THEN 'NUMERO_REUTILIZADO' ELSE 'NUMERO_ATRIBUIDO' END,NEW.id,NEW.numero,jsonb_build_object('tipo',TG_TABLE_NAME));
 RETURN NEW;
END;$f$;
CREATE FUNCTION ew_romnum_interna.proteger() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $f$
BEGIN
 IF NEW.numero IS DISTINCT FROM OLD.numero OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id OR NEW.obra_id IS DISTINCT FROM OLD.obra_id THEN RAISE EXCEPTION 'Identificação histórica do romaneio não pode ser alterada.';END IF;
 IF TG_TABLE_NAME='ew_romaneios_transferencia' THEN
  IF OLD.status='AGRUPADO' AND NEW.status<>'AGRUPADO' THEN RAISE EXCEPTION 'Rascunho agrupado não pode ser reativado.';END IF;
  IF NEW.status='AGRUPADO' AND OLD.status<>'AGRUPADO' THEN
   IF OLD.status<>'RASCUNHO' THEN RAISE EXCEPTION 'Somente rascunhos podem liberar número.';END IF;
   PERFORM ew_romnum_interna.travar(NEW.empresa_id,NEW.obra_id);
  END IF;
 END IF;
 RETURN NEW;
END;$f$;
CREATE TRIGGER ew_romnum_atribuir BEFORE INSERT ON public.romaneios FOR EACH ROW EXECUTE FUNCTION ew_romnum_interna.atribuir();
CREATE TRIGGER ew_romnum_atribuir BEFORE INSERT ON public.ew_romaneios_transferencia FOR EACH ROW EXECUTE FUNCTION ew_romnum_interna.atribuir();
CREATE TRIGGER ew_romnum_proteger BEFORE UPDATE ON public.romaneios FOR EACH ROW EXECUTE FUNCTION ew_romnum_interna.proteger();
CREATE TRIGGER ew_romnum_proteger BEFORE UPDATE ON public.ew_romaneios_transferencia FOR EACH ROW EXECUTE FUNCTION ew_romnum_interna.proteger();

INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES
 ('romaneios.juntar','Romaneios','Juntar rascunhos de transferência da mesma obra',38),
 ('romaneios.adiantar_numeracao','Romaneios','Adiantar numeração de romaneios por obra',39),
 ('romaneios.historico_numeracao','Relatórios','Consultar histórico de numeração e agrupamentos de romaneios',40)
ON CONFLICT(chave) DO NOTHING;
INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
SELECT n.empresa_id,n.nivel,c.chave,CASE WHEN n.nivel=1 THEN true WHEN n.nivel=8 THEN false
 WHEN c.chave='romaneios.juntar' THEN coalesce(t.permitido,false)
 WHEN c.chave='romaneios.adiantar_numeracao' THEN n.nivel=2 AND coalesce(t.permitido,false)
 ELSE coalesce(r.permitido,false) END
FROM public.ew_niveis_acesso n CROSS JOIN (VALUES ('romaneios.juntar'),('romaneios.adiantar_numeracao'),('romaneios.historico_numeracao')) c(chave)
LEFT JOIN public.ew_niveis_permissoes t ON t.empresa_id=n.empresa_id AND t.nivel=n.nivel AND t.chave='romaneios.transferir'
LEFT JOIN public.ew_niveis_permissoes r ON r.empresa_id=n.empresa_id AND r.nivel=n.nivel AND r.chave='relatorios.operacionais'
ON CONFLICT DO NOTHING;
CREATE FUNCTION public.consultar_proximo_romaneio(p_empresa_id uuid,p_obra_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE n bigint;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT (public.ew_pode(p_empresa_id,'romaneios.consultar') OR public.ew_pode(p_empresa_id,'romaneios.emitir') OR public.ew_pode(p_empresa_id,'romaneios.transferir')) OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Sem acesso à numeração da obra.';END IF;
 n:=ew_romnum_interna.proximo(p_empresa_id,p_obra_id);
 RETURN jsonb_build_object('proximo_numero',n,'codigo',ew_romnum_interna.codigo(n));
END;$f$;
CREATE FUNCTION public.adiantar_numero_romaneio(p_empresa_id uuid,p_obra_id uuid,p_proximo_numero integer,p_justificativa text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE n bigint;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'romaneios.adiantar_numeracao') OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=p_obra_id AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Sem permissão para adiantar a numeração.';END IF;
 IF p_proximo_numero IS NULL OR p_proximo_numero NOT BETWEEN 1 AND 999999999 OR length(btrim(coalesce(p_justificativa,''))) NOT BETWEEN 8 AND 300 THEN RAISE EXCEPTION 'Informe número e justificativa válidos.';END IF;
 PERFORM ew_romnum_interna.travar(p_empresa_id,p_obra_id);
 n:=ew_romnum_interna.proximo(p_empresa_id,p_obra_id);
 IF p_proximo_numero<=n THEN RAISE EXCEPTION 'Somente é permitido adiantar a numeração.';END IF;
 INSERT INTO ew_romnum_interna.pisos(empresa_id,obra_id,piso) VALUES(p_empresa_id,p_obra_id,p_proximo_numero) ON CONFLICT(obra_id) DO UPDATE SET piso=excluded.piso;
 INSERT INTO ew_romnum_interna.eventos(empresa_id,obra_id,usuario_id,evento,numero,detalhes) VALUES(p_empresa_id,p_obra_id,auth.uid(),'ADIANTAMENTO',ew_romnum_interna.codigo(p_proximo_numero),jsonb_build_object('proximo_antes',n,'proximo_depois',p_proximo_numero,'justificativa',btrim(p_justificativa)));
 RETURN jsonb_build_object('codigo',ew_romnum_interna.codigo(p_proximo_numero),'numero_anterior',n);
END;$f$;
-- Não permitir que clientes antigos alterem ou consultem a antiga sequência global.
REVOKE ALL ON FUNCTION public.consultar_proximo_romaneio(),public.adiantar_numero_romaneio(integer,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.consultar_proximo_romaneio(uuid,uuid),public.adiantar_numero_romaneio(uuid,uuid,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consultar_proximo_romaneio(uuid,uuid),public.adiantar_numero_romaneio(uuid,uuid,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.emitir_romaneio_com_saidas(p_chave_operacao uuid, p_obra_id uuid, p_data_saida date, p_motorista text, p_placa text, p_observacoes text, p_itens jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid(); v_work public.obras%rowtype; v_rom public.romaneios%rowtype;
 v_item public.esquadrias%rowtype; v_line jsonb; v_num integer:=0;
 v_id uuid; v_ship uuid; v_qty integer; v_per integer; v_kind text;
 v_previous integer; v_factory text; v_mean numeric(8,2); v_tipo_saida text;
 v_total integer:=0; v_area numeric(14,3); v_desc text; v_code text;
 v_location text; v_measure text; v_unit text; v_desc_definida boolean;
 v_var uuid;v_length integer;v_local text;v_available numeric;v_material_tipo text;
 v_cor text;v_perfil_peso numeric;v_ri_id uuid;v_movimento_id uuid;v_peso_total numeric;
 v_rev uuid;v_comp text;v_comp_nome text;v_equiv numeric;v_comp_result jsonb;
BEGIN
 PERFORM public.ew_exigir_permissao('romaneios.emitir');
  PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_chave_operacao IS NULL OR p_obra_id IS NULL THEN
  RAISE EXCEPTION 'Faça login e informe a obra e a operação.';
 END IF;
 SELECT * INTO v_work FROM public.obras WHERE id=p_obra_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Obra inexistente.'; END IF;
 IF v_work.arquivada_em IS NOT NULL THEN RAISE EXCEPTION 'Obra arquivada não pode emitir romaneio.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue WHERE ue.usuario_id=v_uid
    AND ue.empresa_id=v_work.empresa_id AND public.ew_pode(v_work.empresa_id,'romaneios.emitir')
    AND EXISTS(SELECT 1 FROM public.usuarios_login ul
      WHERE ul.usuario_id=v_uid AND ul.empresa_id=ue.empresa_id
      AND ul.ativo AND ul.perfil=ue.perfil)) THEN
   RAISE EXCEPTION 'Sem permissão para emitir romaneios desta obra.';
 END IF;
 IF p_data_saida IS NULL OR p_data_saida<'2000-01-01'::date OR p_data_saida>current_date THEN
   RAISE EXCEPTION 'Data do romaneio inválida ou futura.';
 END IF;
 IF length(btrim(coalesce(p_motorista,''))) NOT BETWEEN 2 AND 140
    OR length(btrim(coalesce(p_placa,''))) NOT BETWEEN 5 AND 12 THEN
   RAISE EXCEPTION 'Informe motorista e placa válidos.';
 END IF;
 IF length(coalesce(p_observacoes,''))>1000 THEN RAISE EXCEPTION 'Observações muito extensas.'; END IF;
 IF p_itens IS NULL OR jsonb_typeof(p_itens)<>'array' OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 60 THEN
   RAISE EXCEPTION 'Informe de 1 a 60 itens para o romaneio.';
 END IF;
 -- Idempotência da emissão inteira, incluindo todas as saídas.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_chave_operacao::text));
 SELECT * INTO v_rom FROM public.romaneios WHERE chave_operacao=p_chave_operacao;
 IF FOUND THEN
  IF v_rom.empresa_id<>v_work.empresa_id OR v_rom.obra_id<>p_obra_id THEN
    RAISE EXCEPTION 'Chave de emissão já usada em outra obra.';
  END IF;
  RETURN pg_catalog.jsonb_build_object('id',v_rom.id,'numero',v_rom.numero,'repetido',true);
 END IF;
 -- O trigger de numeração usa a trava transacional compartilhada por obra.
 INSERT INTO public.romaneios(empresa_id,obra_id,chave_operacao,data_saida,motorista,placa,observacoes,criado_por)
 VALUES(v_work.empresa_id,p_obra_id,p_chave_operacao,p_data_saida,btrim(p_motorista),upper(btrim(p_placa)),
   coalesce(p_observacoes,''),v_uid)
 RETURNING * INTO v_rom;
 -- Contexto transacional emitido apenas após validar empresa, papel e itens.
 PERFORM pg_catalog.set_config('ewgest.romaneio_emissao_id',v_rom.id::text,true);
 FOR v_line IN SELECT value FROM pg_catalog.jsonb_array_elements(p_itens) LOOP
   v_num:=v_num+1;
   IF pg_catalog.jsonb_typeof(v_line)<>'object' THEN RAISE EXCEPTION 'Item % inválido.',v_num; END IF;
   v_kind:=v_line->>'natureza';
   IF v_kind NOT IN ('esquadria','material') OR v_kind IS NULL THEN
    RAISE EXCEPTION 'Item % precisa ser esquadria ou material.',v_num;
   END IF;
   BEGIN v_qty:=(v_line->>'quantidade')::integer;
   EXCEPTION WHEN others THEN RAISE EXCEPTION 'Quantidade do item % inválida.',v_num; END;
   IF v_qty NOT BETWEEN 1 AND 100000 THEN RAISE EXCEPTION 'Quantidade inválida no item %.',v_num; END IF;
   v_desc:=btrim(coalesce(v_line->>'descricao',''));
   v_code:=btrim(coalesce(v_line->>'codigo',''));
   v_location:=btrim(coalesce(v_line->>'localizacao',''));
   v_measure:=btrim(coalesce(v_line->>'medida',''));
   v_unit:=upper(btrim(coalesce(v_line->>'unidade','UNID.')));
   IF length(v_unit) NOT BETWEEN 1 AND 12 OR length(v_desc)>350 OR length(v_code)>60
      OR length(v_location)>120 OR length(v_measure)>100 THEN
     RAISE EXCEPTION 'Dados extensos ou unidade inválida no item %.',v_num;
   END IF;
   v_factory:=NULL;v_mean:=NULL;v_id:=NULL;v_ship:=NULL;v_desc_definida:=false;
   v_rev:=NULL;v_comp:=NULL;v_comp_nome:=NULL;v_equiv:=NULL;
   IF v_kind='esquadria' THEN
     v_tipo_saida:=coalesce(nullif(v_line->>'tipo_saida',''),'completo');
     v_rev:=nullif(v_line->>'composicao_revisao_id','')::uuid;
     v_comp:=nullif(v_line->>'componente_id','');
     IF v_tipo_saida NOT IN ('completo','marco','folha','componente') OR
        (v_tipo_saida='componente' AND (v_rev IS NULL OR v_comp IS NULL)) OR
        (v_rev IS NOT NULL AND v_tipo_saida NOT IN ('completo','componente')) OR
        (v_tipo_saida<>'componente' AND v_comp IS NOT NULL) THEN
       RAISE EXCEPTION 'Tipo de saída inválido no item %.',v_num;
     END IF;
     IF NULLIF(v_line->>'esquadria_id','') IS NULL THEN
       RAISE EXCEPTION 'Selecione a esquadria no item %.',v_num;
     END IF;
     v_id:=(v_line->>'esquadria_id')::uuid;
     IF EXISTS(SELECT 1 FROM public.romaneios_itens
       WHERE romaneio_id=v_rom.id AND esquadria_id=v_id AND tipo_saida=v_tipo_saida AND componente_id IS NOT DISTINCT FROM v_comp) THEN
       RAISE EXCEPTION 'Componente da esquadria repetido neste romaneio (item %).',v_num;
     END IF;
     SELECT * INTO v_item FROM public.esquadrias WHERE id=v_id FOR UPDATE;
     IF NOT FOUND OR v_item.obra_id<>p_obra_id OR v_item.empresa_id<>v_work.empresa_id THEN
       RAISE EXCEPTION 'Esquadria do item % não pertence a esta obra.',v_num;
     END IF;
     BEGIN v_per:=(v_line->>'folhas_por_unidade')::integer;
     EXCEPTION WHEN others THEN RAISE EXCEPTION 'Confirme as folhas por unidade do item %.',v_num; END;
     -- Esquadria completa não precisa de folhas por unidade.
     -- O registrador resolve eventual composição já cadastrada.
     IF v_rev IS NULL AND ((v_per IS NOT NULL AND v_per NOT BETWEEN 1 AND 12)
       OR (v_tipo_saida<>'completo' AND v_per IS NULL)) THEN
       RAISE EXCEPTION 'Confirme folhas por unidade somente para saída de marco/folha (item %).',v_num;
     END IF;
     v_ship:=gen_random_uuid();
     IF v_rev IS NOT NULL THEN
       v_comp_result:=ew_expedicao_interna.registrar_saida(v_ship,v_id,v_tipo_saida,v_qty,p_data_saida,v_rev,v_comp);
       v_equiv:=(v_comp_result->>'equivalente')::numeric;v_comp_nome:=v_comp_result->>'nome';
     ELSE
       PERFORM public.registrar_saida_producao(v_ship,v_id,v_tipo_saida,v_qty,p_data_saida,v_per);
     END IF;
     v_code:=v_item.codigo;
     v_location:=coalesce(v_item.localizacao,'');
     v_desc:=case v_tipo_saida when 'marco' then 'MARCO — '
             when 'folha' then 'FOLHA — ' when 'componente' then v_comp_nome||' — ' else '' end ||
             coalesce(v_item.descricao,'Esquadria '||v_item.codigo);
     IF v_line ? 'descricao_romaneio' THEN
       IF jsonb_typeof(v_line->'descricao_romaneio')<>'string' THEN
         RAISE EXCEPTION 'Descrição do romaneio deve ser texto no item %.',v_num;
       END IF;
       v_desc:=btrim(v_line->>'descricao_romaneio');
       IF length(v_desc) NOT BETWEEN 2 AND 350 THEN
         RAISE EXCEPTION 'Descrição do romaneio precisa ter entre 2 e 350 caracteres (item %).',v_num;
       END IF;
       v_desc_definida:=true;
     END IF;
     v_measure:=to_char(v_item.largura_mm,'FM99999990D00')||' x '||
                  to_char(v_item.altura_mm,'FM99999990D00')||' mm';
     v_unit:='UNID.';
     SELECT CASE WHEN count(*)=count(fabrica) AND count(DISTINCT fabrica)=1
         THEN min(fabrica) ELSE NULL END INTO v_factory
       FROM public.liberacoes_corte WHERE esquadria_id=v_id;
     IF v_tipo_saida='completo' AND v_rev IS NULL AND v_factory IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM public.saidas_producao h
       WHERE h.esquadria_id=v_id AND h.tipo IN ('marco','folha')
     ) THEN
       SELECT coalesce(sum(s.quantidade),0)::integer INTO v_previous
       FROM public.saidas_producao s WHERE s.esquadria_id=v_id
         AND s.tipo='completo' AND s.cancelado_em IS NULL AND s.id<>v_ship;
       WITH lotes AS (
         SELECT data_liberacao,quantidade,
          (sum(quantidade) OVER(ORDER BY data_liberacao,id)-quantidade)::integer AS inicio,
          (sum(quantidade) OVER(ORDER BY data_liberacao,id))::integer AS fim
         FROM public.liberacoes_corte WHERE esquadria_id=v_id
       ), partes AS (
        SELECT greatest(0,least(fim,v_previous+v_qty)-greatest(inicio,v_previous)) as qtd,
        p_data_saida-data_liberacao as dias FROM lotes
       )
       SELECT CASE WHEN sum(qtd)=v_qty AND min(dias)>=0
         THEN round(sum(qtd*dias)::numeric/v_qty,2) ELSE NULL END
       INTO v_mean FROM partes WHERE qtd>0;
     END IF;
     v_area:=CASE WHEN v_rev IS NOT NULL THEN round(v_item.largura_mm::numeric*v_item.altura_mm::numeric*v_equiv/1000000,3)
       ELSE case v_tipo_saida
       when 'completo' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/1000000.0)::numeric,3)
       when 'marco' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/2000000.0)::numeric,3)
       when 'folha' then
         round((v_item.largura_mm*v_item.altura_mm*v_qty/(2000000.0*v_per))::numeric,3)
       else null end END;
   ELSE
     -- A baixa de material é atribuição do almoxarife ou ADM.
     IF NOT EXISTS(SELECT 1 FROM public.usuarios_empresas ue
       JOIN public.usuarios_login ul ON ul.empresa_id=ue.empresa_id AND ul.usuario_id=ue.usuario_id
       WHERE ue.usuario_id=v_uid AND ue.empresa_id=v_work.empresa_id
         AND public.ew_pode(v_work.empresa_id,'estoque.baixar')
         AND ul.perfil=ue.perfil AND ul.ativo AND ul.excluido_em IS NULL)
       THEN RAISE EXCEPTION 'Somente ADM ou almoxarife pode expedir materiais físicos do estoque.';END IF;
     -- Material avulso NÃO é texto livre: exige estoque real identificado.
     v_tipo_saida:=NULL;
     IF v_line->>'variacao_id' IS NULL OR v_line->>'local_estoque' IS NULL
       THEN RAISE EXCEPTION 'Material % deve ser escolhido do estoque da obra.',v_num; END IF;
     v_var:=(v_line->>'variacao_id')::uuid;
     v_length:=nullif(v_line->>'comprimento_mm','')::integer;
     v_local:=upper(btrim(v_line->>'local_estoque'));
     SELECT v.tipo,coalesce(p.codigo,a.codigo),coalesce(p.descricao,a.descricao),
       coalesce(nullif(v.cor,''),nullif(v.acabamento,''),''),p.peso_kg_m
       INTO v_material_tipo,v_code,v_desc,v_cor,v_perfil_peso
     FROM public.ew_materiais_variacoes v
      LEFT JOIN public.ew_perfis p ON p.id=v.perfil_id
      LEFT JOIN public.ew_acessorios a ON a.id=v.acessorio_id
     WHERE v.id=v_var AND v.empresa_id=v_work.empresa_id AND v.ativo;
     IF v_material_tipo IS NULL OR v_code IS NULL OR v_desc IS NULL THEN
       RAISE EXCEPTION 'Item % não está cadastrado como material ativo da empresa.',v_num;END IF;
     IF (v_material_tipo='perfil' AND (v_unit<>'BARRA' OR v_length NOT BETWEEN 100 AND 20000))
       OR (v_material_tipo='acessorio' AND (v_length IS NOT NULL OR v_unit NOT IN
        ('PC','PR','CJ','MT','KG','UN'))) OR v_material_tipo NOT IN ('perfil','acessorio')
       THEN RAISE EXCEPTION 'Unidade e comprimento incompatíveis com o material %.',v_num;END IF;
     IF NOT EXISTS(SELECT 1 FROM public.ew_estoques_locais l WHERE l.empresa_id=v_work.empresa_id
       AND l.obra_id=p_obra_id AND l.excluido_em IS NULL)
       THEN RAISE EXCEPTION 'Estoque da obra inativo. Não é possível expedir material.';END IF;
     IF NOT EXISTS(SELECT 1 FROM public.ew_locais_fisicos l WHERE l.empresa_id=v_work.empresa_id
       AND l.nome=v_local AND l.ativo)
       THEN RAISE EXCEPTION 'Galpão de origem do material % não está ativo.',v_num;END IF;
     PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
       p_obra_id::text||'|'||v_var::text||'|'||coalesce(v_length::text,'-')||'|'||v_unit,34777));
     SELECT coalesce(sum(m.quantidade_delta),0) INTO v_available
     FROM public.ew_estoque_obras_movimentos m
     WHERE m.empresa_id=v_work.empresa_id AND m.obra_id=p_obra_id
      AND m.variacao_id=v_var AND m.comprimento_mm IS NOT DISTINCT FROM v_length
      AND m.unidade=v_unit AND m.local_estoque=v_local;
     IF v_available<v_qty THEN
       RAISE EXCEPTION 'Item % sem saldo no galpão %. Disponível: % %, solicitado: % %.',
         v_num,v_local,v_available,v_unit,v_qty,v_unit;END IF;
     v_location:=v_local;
     v_measure:=CASE WHEN v_length IS NULL THEN '' ELSE v_length::text||' mm' END;
     v_desc:=v_desc||CASE WHEN v_cor<>'' THEN ' · '||v_cor ELSE '' END;
     v_area:=NULL;
   END IF;
   INSERT INTO public.romaneios_itens(romaneio_id,sequencia,natureza,esquadria_id,saida_producao_id,
    codigo,localizacao,descricao,medida,quantidade,unidade,area_m2,fabrica,prazo_liberacao_saida_dias,tipo_saida,descricao_impressao_definida,composicao_revisao_id,componente_id,componente_nome,equivalente_expedido)
   VALUES(v_rom.id,v_num,v_kind,v_id,v_ship,v_code,v_location,v_desc,v_measure,v_qty,v_unit,v_area,v_factory,v_mean,v_tipo_saida,v_desc_definida,v_rev,v_comp,v_comp_nome,v_equiv)
   RETURNING id INTO v_ri_id;
   IF v_kind='material' THEN
     INSERT INTO public.ew_estoque_obras_movimentos
      (empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,
       operacao_id,observacao,usuario_id,local_estoque)
     VALUES(v_work.empresa_id,p_obra_id,v_var,v_length,v_unit,-v_qty,'SAIDA_OBRA',
       gen_random_uuid(),'Saída direta para obra no romaneio '||v_rom.numero,v_uid,v_local)
     RETURNING id INTO v_movimento_id;
     v_peso_total:=CASE WHEN v_material_tipo='perfil' AND v_perfil_peso>0
      THEN round(v_qty*v_length/1000.0*v_perfil_peso,6) ELSE NULL END;
     INSERT INTO public.ew_romaneios_materiais_saidas
      (empresa_id,obra_id,romaneio_id,romaneio_item_id,movimento_id,variacao_id,
       comprimento_mm,unidade,quantidade,local_estoque,peso_kg,criado_por)
     VALUES(v_work.empresa_id,p_obra_id,v_rom.id,v_ri_id,v_movimento_id,v_var,
       v_length,v_unit,v_qty,v_local,v_peso_total,v_uid);
   END IF;
   v_total:=v_total+v_qty;
 END LOOP;
 RETURN pg_catalog.jsonb_build_object('id',v_rom.id,'numero',v_rom.numero,
    'repetido',false,'itens',v_num,'quantidade_total',v_total);
END;$function$;
CREATE OR REPLACE FUNCTION public.ew_gerar_romaneio_de_transferencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_entrada public.ew_estoque_obras_movimentos%rowtype;
 v_numero text;v_documento uuid;v_codigo text;v_descricao text;v_cor text;
begin
 if new.origem<>'TRANSFERENCIA' or new.quantidade_delta>=0
    or new.transferencia_id is null or new.estorno_de_id is not null then return new;end if;
 select * into v_entrada from public.ew_estoque_obras_movimentos m
 where m.transferencia_id=new.transferencia_id and m.empresa_id=new.empresa_id
   and m.quantidade_delta=-new.quantidade_delta and m.quantidade_delta>0
   and m.variacao_id=new.variacao_id and m.unidade=new.unidade
   and m.comprimento_mm is not distinct from new.comprimento_mm
   and m.origem='TRANSFERENCIA'
 limit 1;
 if v_entrada.id is null then
  raise exception 'Transferencia sem par de entrada: romaneio nao pode ser gerado.';
 end if;
 -- Remanejamento entre obras no mesmo galpao nao exige transporte entre predios.
 if v_entrada.local_estoque is not distinct from new.local_estoque then return new;end if;
 if exists(select 1 from public.ew_romaneios_transferencia_itens
  where transferencia_id=new.transferencia_id) then return new;end if;
 select coalesce(p.codigo,a.codigo,'SEM CODIGO'),
   coalesce(p.descricao,a.descricao,'Material sem descricao'),
   coalesce(nullif(to_jsonb(v)->>'cor',''),nullif(to_jsonb(v)->>'acabamento',''),'')
 into v_codigo,v_descricao,v_cor
 from public.ew_materiais_variacoes v
 left join public.ew_perfis p on p.id=v.perfil_id
 left join public.ew_acessorios a on a.id=v.acessorio_id
 where v.id=new.variacao_id and v.empresa_id=new.empresa_id;
 v_numero:=NULL; -- atribuído no BEFORE INSERT por obra
 insert into public.ew_romaneios_transferencia
  (empresa_id,numero,obra_id,origem_galpao,destino_galpao,criado_por)
 values(new.empresa_id,v_numero,new.obra_id,new.local_estoque,
  v_entrada.local_estoque,new.usuario_id) returning id into v_documento;
 insert into public.ew_romaneios_transferencia_itens
 (documento_id,tipo,transferencia_id,movimento_saida_id,movimento_entrada_id,
  obra_origem_id,obra_destino_id,variacao_id,codigo,descricao,
  quantidade,unidade,comprimento_mm,cor)
 values(v_documento,'TRANSFERENCIA',new.transferencia_id,new.id,v_entrada.id,
  new.obra_id,v_entrada.obra_id,new.variacao_id,coalesce(v_codigo,'SEM CODIGO'),
  coalesce(v_descricao,'Material'),-new.quantidade_delta,new.unidade,new.comprimento_mm,
  coalesce(v_cor,''));
 insert into public.ew_romaneios_transferencia_auditoria
  (documento_id,usuario_id,evento,detalhes)
 values(v_documento,new.usuario_id,'GERADO_POR_TRANSFERENCIA',
  jsonb_build_object('transferencia_id',new.transferencia_id,
  'origem',new.local_estoque,'destino',v_entrada.local_estoque));
 return new;
end;$function$;
CREATE OR REPLACE FUNCTION public.ew_romaneios_transferencia_juntar(p_empresa_id uuid, p_principal_id uuid, p_outros uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid();v_master public.ew_romaneios_transferencia%rowtype;
 v_doc public.ew_romaneios_transferencia%rowtype;v_id uuid;v_count integer:=0;v_ids uuid[];v_obra uuid;v_n int;v_antes bigint;v_depois bigint;v_principal uuid;v_itens jsonb;
begin
 PERFORM public.ew_exigir_permissao('romaneios.transferir');
 perform public.ew_exigir_sessao_atual();
 IF NOT public.ew_pode(p_empresa_id,'romaneios.juntar') OR NOT public.ew_pode(p_empresa_id,'romaneios.transferir') THEN RAISE EXCEPTION 'Sem permissão para juntar romaneios.';END IF;
 if not exists(select 1 from public.usuarios_empresas ue
 join public.usuarios_login ul on ul.usuario_id=ue.usuario_id and ul.empresa_id=ue.empresa_id
 where ue.usuario_id=v_uid and ue.empresa_id=p_empresa_id and ul.ativo and ul.excluido_em is null
 and ue.perfil in ('administrador','gerenciador','almoxarife')) then
 raise exception 'Sem permissao para juntar romaneios.';end if;
 if p_outros is null or cardinality(p_outros) not between 1 and 30
 then raise exception 'Selecione ao menos outro romaneio.';end if;
 -- Lock transacional por empresa: evita edicoes e agrupamentos simultaneos.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ROMTRANS|'||p_empresa_id::text,61741));
 select obra_id into v_obra from public.ew_romaneios_transferencia where id=p_principal_id and empresa_id=p_empresa_id;
 IF v_obra IS NULL OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=v_obra AND empresa_id=p_empresa_id AND arquivada_em IS NULL) THEN RAISE EXCEPTION 'Obra indisponível.';END IF;
 PERFORM ew_romnum_interna.travar(p_empresa_id,v_obra);
 v_antes:=ew_romnum_interna.proximo(p_empresa_id,v_obra);
 SELECT array_agg(DISTINCT x) INTO v_ids FROM unnest(array_append(p_outros,p_principal_id)) x WHERE x IS NOT NULL;
 IF cardinality(v_ids)<2 THEN RAISE EXCEPTION 'Selecione ao menos dois rascunhos.';END IF;
 PERFORM 1 FROM public.ew_romaneios_transferencia WHERE id=ANY(v_ids) AND empresa_id=p_empresa_id AND obra_id=v_obra AND status='RASCUNHO' ORDER BY id FOR UPDATE;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>cardinality(v_ids) THEN RAISE EXCEPTION 'Somente rascunhos da mesma obra podem ser agrupados.';END IF;
 SELECT id INTO v_principal FROM public.ew_romaneios_transferencia WHERE id=ANY(v_ids) ORDER BY substring(numero from 3)::bigint,id LIMIT 1;
 SELECT * INTO v_master FROM public.ew_romaneios_transferencia WHERE id=v_principal;
 if v_master.id is null or v_master.status<>'RASCUNHO' then
 raise exception 'O romaneio principal deve estar em rascunho.';end if;
 IF EXISTS(SELECT 1 FROM public.ew_romaneios_transferencia_itens i JOIN public.ew_estoque_obras_movimentos e ON e.estorno_de_id IN(i.movimento_saida_id,i.movimento_entrada_id) WHERE i.documento_id=ANY(v_ids) AND i.tipo='TRANSFERENCIA') THEN RAISE EXCEPTION 'Existe transferência estornada; não pode agrupar.';END IF;
 for v_id in select x from unnest(v_ids) as x order by x loop
  if v_id=v_principal then continue;end if;
  select * into v_doc from public.ew_romaneios_transferencia
   where id=v_id and empresa_id=p_empresa_id for update;
  if v_doc.id is null or v_doc.status<>'RASCUNHO' or
   v_doc.origem_galpao<>v_master.origem_galpao or
   v_doc.destino_galpao<>v_master.destino_galpao then
   raise exception 'Somente rascunhos da mesma rota (galpao de origem e destino) podem ser agrupados.';end if;
  if exists(select 1 from public.ew_romaneios_transferencia_itens i
   join public.ew_estoque_obras_movimentos e on e.estorno_de_id in
    (i.movimento_saida_id,i.movimento_entrada_id)
   where i.documento_id=v_id and i.tipo='TRANSFERENCIA') then
   raise exception 'Existe transferencia estornada; nao pode agrupar.';end if;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.id,'codigo',i.codigo,'descricao',i.descricao,'quantidade',i.quantidade,'unidade',i.unidade,'transferencia_id',i.transferencia_id) ORDER BY i.id),'[]'::jsonb) INTO v_itens FROM public.ew_romaneios_transferencia_itens i WHERE documento_id=v_id;
  update public.ew_romaneios_transferencia_itens set documento_id=v_principal
   where documento_id=v_id;
  update public.ew_romaneios_transferencia set status='AGRUPADO',agrupado_em=v_principal,
   atualizado_em=now() where id=v_id;
  insert into public.ew_romaneios_transferencia_auditoria(documento_id,usuario_id,evento,detalhes)
   values(v_principal,v_uid,'AGRUPADO',jsonb_build_object('documento_origem',v_id,'numero',v_doc.numero,'numero_principal',v_master.numero,'itens_originais',v_itens));
  v_count:=v_count+1;
 end loop;
 if v_count=0 then raise exception 'Nenhum documento selecionado para agrupamento.';end if;
 update public.ew_romaneios_transferencia set atualizado_em=now()
 where id=v_principal;
 v_depois:=ew_romnum_interna.proximo(p_empresa_id,v_obra);
 INSERT INTO ew_romnum_interna.eventos(empresa_id,obra_id,usuario_id,evento,documento_id,numero,detalhes)
 VALUES(p_empresa_id,v_obra,v_uid,'JUNCAO',v_principal,v_master.numero,jsonb_build_object('ids',v_ids,'proximo_antes',v_antes,'proximo_depois',v_depois));
 return jsonb_build_object('id',v_principal,'numero',v_master.numero,'agrupados',v_count,'proximo_codigo',ew_romnum_interna.codigo(v_depois));
end;$function$;
CREATE FUNCTION public.ew_historico_numeracao_romaneios(p_empresa_id uuid,p_obra_id uuid,p_inicio date,p_fim date,p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF auth.uid() IS NULL OR NOT public.ew_pode(p_empresa_id,'relatorios.operacionais') OR NOT public.ew_pode(p_empresa_id,'romaneios.historico_numeracao') THEN RAISE EXCEPTION 'Sem permissão para histórico de romaneios.';END IF;
 IF p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 OR (p_inicio IS NOT NULL AND p_fim IS NOT NULL AND p_inicio>p_fim) THEN RAISE EXCEPTION 'Filtros inválidos.';END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.data DESC,h.chave),'[]'::jsonb) FROM (
  SELECT e.*,coalesce(o.nome,'Obra histórica') AS obra,o.codigo AS obra_codigo FROM (
   SELECT 'E:'||r.id::text AS chave,r.obra_id,r.id AS documento_id,r.numero,'EXPEDICAO'::text AS tipo,'EMITIDO'::text AS evento,r.criado_por AS usuario_id,r.criado_em AS data,jsonb_build_object('status',r.status) AS detalhes FROM public.romaneios r WHERE r.empresa_id=p_empresa_id
   UNION ALL SELECT 'C:'||r.id::text,r.obra_id,r.id,r.numero,'EXPEDICAO','CANCELADO',r.cancelado_por,r.cancelado_em,jsonb_build_object('motivo',r.motivo_cancelamento) FROM public.romaneios r WHERE r.empresa_id=p_empresa_id AND r.cancelado_em IS NOT NULL
   UNION ALL SELECT 'T:'||a.id::text,d.obra_id,d.id,d.numero,'TRANSFERENCIA',a.evento,a.usuario_id,a.criado_em,a.detalhes FROM public.ew_romaneios_transferencia_auditoria a JOIN public.ew_romaneios_transferencia d ON d.id=a.documento_id WHERE d.empresa_id=p_empresa_id
   UNION ALL SELECT 'N:'||n.id::text,n.obra_id,n.documento_id,n.numero,'NUMERACAO',n.evento,n.usuario_id,n.criado_em,n.detalhes FROM ew_romnum_interna.eventos n WHERE n.empresa_id=p_empresa_id
  ) e LEFT JOIN public.obras o ON o.id=e.obra_id AND o.empresa_id=p_empresa_id
  WHERE (p_obra_id IS NULL OR e.obra_id=p_obra_id) AND (p_inicio IS NULL OR e.data::date>=p_inicio) AND (p_fim IS NULL OR e.data::date<=p_fim)
  ORDER BY e.data DESC,e.chave OFFSET p_offset LIMIT 500
 ) h);
END;$f$;
REVOKE ALL ON FUNCTION public.ew_historico_numeracao_romaneios(uuid,uuid,date,date,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ew_historico_numeracao_romaneios(uuid,uuid,date,date,integer) TO authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ew_romnum_interna FROM PUBLIC,anon,authenticated;
COMMIT;
