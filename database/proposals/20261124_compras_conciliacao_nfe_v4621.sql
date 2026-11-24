-- EWGEST v46.21 — conciliação fiscal de recebimentos por pedido, SEM entrada física duplicada.
-- Aplicar somente após compras/recebimentos/estornos/transferências v46.21.
-- NUNCA criar movimentos de estoque nesta rotina.
BEGIN;

CREATE TABLE IF NOT EXISTS public.ew_compras_nfe_conciliacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 pedido_id uuid NOT NULL REFERENCES public.ew_compras_pedidos(id),
 despesa_id uuid NOT NULL REFERENCES public.ew_obra_despesas(id),
 operacao_id uuid NOT NULL UNIQUE,
 criado_em timestamptz NOT NULL DEFAULT now(),
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 desvinculado_em timestamptz,
 desvinculado_por uuid REFERENCES auth.users(id),
 desvinculo_operacao_id uuid UNIQUE,
 desvinculo_motivo text
);
CREATE INDEX IF NOT EXISTS ew_comp_nfe_conc_despesa_idx
 ON public.ew_compras_nfe_conciliacoes(empresa_id,despesa_id,criado_em DESC);
CREATE INDEX IF NOT EXISTS ew_comp_nfe_conc_pedido_idx
 ON public.ew_compras_nfe_conciliacoes(empresa_id,pedido_id,criado_em DESC);

CREATE TABLE IF NOT EXISTS public.ew_compras_nfe_vinculos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 conciliacao_id uuid NOT NULL REFERENCES public.ew_compras_nfe_conciliacoes(id),
 despesa_item_id uuid NOT NULL REFERENCES public.ew_obra_despesas_itens(id),
 recebimento_id uuid NOT NULL,
 chave text NOT NULL,
 quantidade_nota numeric(16,3) NOT NULL CHECK(quantidade_nota>0),
 quantidade_fisica numeric(16,3) NOT NULL CHECK(quantidade_fisica>0),
 unidade_nota text NOT NULL,
 desvinculado_em timestamptz,
 criado_em timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(recebimento_id,chave) REFERENCES public.ew_compras_recebimentos_movimentos(recebimento_id,chave)
);
-- Uma entrada física não pode ser faturada como a mesma entrega por duas notas ativas.
-- Uma linha de pedido só pode ter uma conciliação fiscal ATIVA.
-- A conciliação desfeita permanece no histórico.
CREATE UNIQUE INDEX IF NOT EXISTS ew_compras_nf_recebimento_ativo_unico
 ON public.ew_compras_nfe_vinculos(recebimento_id,chave)
 WHERE desvinculado_em IS NULL;
CREATE INDEX IF NOT EXISTS ew_compras_nf_despesa_item_idx
 ON public.ew_compras_nfe_vinculos(empresa_id,despesa_item_id);

ALTER TABLE public.ew_compras_nfe_conciliacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_compras_nfe_vinculos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ew_compras_nfe_conc_leitura" ON public.ew_compras_nfe_conciliacoes
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'compras.consultar_valores')
  AND public.ew_pode(empresa_id,'financeiro.consultar'));
CREATE POLICY "ew_compras_nfe_vinc_leitura" ON public.ew_compras_nfe_vinculos
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'compras.consultar_valores')
  AND public.ew_pode(empresa_id,'financeiro.consultar'));
GRANT SELECT ON public.ew_compras_nfe_conciliacoes,public.ew_compras_nfe_vinculos TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.ew_compras_nfe_conciliacoes,public.ew_compras_nfe_vinculos
 FROM anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_compras_vincular_nfe_pedido(
 p_pedido_id uuid,p_despesa_id uuid,p_vinculos jsonb,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_uid uuid:=auth.uid();
 v_p public.ew_compras_pedidos%ROWTYPE;v_d public.ew_obra_despesas%ROWTYPE;
 v_fornecedor text;v_conc uuid;v_i jsonb;v_item public.ew_obra_despesas_itens%ROWTYPE;
 v_r public.ew_compras_recebimentos%ROWTYPE;v_mov record;v_line jsonb;
 v_var public.ew_materiais_variacoes%ROWTYPE;
 v_soma numeric;v_nota_qty numeric;v_fis_qty numeric;
 v_unit text;v_order_unit text;v_length integer;v_total int:=0;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_uid IS NULL OR p_operacao_id IS NULL OR p_pedido_id IS NULL OR p_despesa_id IS NULL
 THEN RAISE EXCEPTION 'Sessão e documentos obrigatórios.';END IF;

 SELECT * INTO v_p FROM public.ew_compras_pedidos WHERE id=p_pedido_id FOR UPDATE;
 IF NOT FOUND OR v_p.obra_id IS NULL OR v_p.status='CANCELADO'
 THEN RAISE EXCEPTION 'A conciliação fiscal por obra exige pedido ativo vinculado a uma obra real.';END IF;
 IF NOT(public.ew_pode(v_p.empresa_id,'financeiro.despesas')
   AND public.ew_pode(v_p.empresa_id,'compras.consultar_valores'))
 THEN RAISE EXCEPTION 'Sem permissão financeira para conciliar esta compra.';END IF;
 SELECT * INTO v_d FROM public.ew_obra_despesas WHERE id=p_despesa_id
  AND empresa_id=v_p.empresa_id AND obra_id=v_p.obra_id FOR UPDATE;
 IF NOT FOUND OR v_d.status<>'aprovada' OR v_d.categoria NOT IN ('aluminio','acessorios')
 THEN RAISE EXCEPTION 'Nota não aprovada, incompatível ou de outra obra.';END IF;

 SELECT nome INTO v_fornecedor FROM public.ew_fornecedores
 WHERE id=v_p.fornecedor_id AND empresa_id=v_p.empresa_id;
 IF v_fornecedor IS NULL OR lower(btrim(v_fornecedor))<>lower(btrim(v_d.fornecedor))
 THEN RAISE EXCEPTION 'Fornecedor da nota não corresponde ao fornecedor do pedido.';END IF;
 IF jsonb_typeof(p_vinculos) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_vinculos) NOT BETWEEN 1 AND 150
 THEN RAISE EXCEPTION 'Selecione de 1 a 150 linhas físicas para vincular à nota.';END IF;
 SELECT id INTO v_conc FROM public.ew_compras_nfe_conciliacoes
 WHERE operacao_id=p_operacao_id;
 IF v_conc IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.ew_compras_nfe_conciliacoes
    WHERE id=v_conc AND empresa_id=v_p.empresa_id
     AND pedido_id=v_p.id AND despesa_id=v_d.id AND desvinculado_em IS NULL)
  THEN RAISE EXCEPTION 'Identificador de conciliação já utilizado.';END IF;
  IF (SELECT count(*) FROM public.ew_compras_nfe_vinculos
       WHERE conciliacao_id=v_conc AND desvinculado_em IS NULL)
    <>jsonb_array_length(p_vinculos)
   OR EXISTS(
    SELECT 1 FROM jsonb_array_elements(p_vinculos) entrada(value)
    WHERE NOT EXISTS(SELECT 1 FROM public.ew_compras_nfe_vinculos x
      WHERE x.conciliacao_id=v_conc AND x.desvinculado_em IS NULL
        AND x.despesa_item_id=(entrada.value->>'despesa_item_id')::uuid
        AND x.recebimento_id=(entrada.value->>'recebimento_id')::uuid
        AND x.chave=entrada.value->>'chave')
   )
  THEN RAISE EXCEPTION 'Identificador utilizado anteriormente com itens diferentes.';END IF;
  RETURN jsonb_build_object('id',v_conc,'repetida',true);
 END IF;
 INSERT INTO public.ew_compras_nfe_conciliacoes
  (empresa_id,pedido_id,despesa_id,operacao_id,criado_por)
 VALUES(v_p.empresa_id,v_p.id,v_d.id,p_operacao_id,v_uid)
 RETURNING id INTO v_conc;

 FOR v_i IN
  SELECT value FROM jsonb_array_elements(p_vinculos)
  ORDER BY value->>'despesa_item_id',value->>'recebimento_id',value->>'chave'
 LOOP
  IF jsonb_typeof(v_i) IS DISTINCT FROM 'object'
  THEN RAISE EXCEPTION 'Associação fiscal inválida.';END IF;
  SELECT * INTO v_item FROM public.ew_obra_despesas_itens
  WHERE id=(v_i->>'despesa_item_id')::uuid AND despesa_id=v_d.id
   AND empresa_id=v_p.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item fiscal não pertence à nota selecionada.';END IF;
  SELECT * INTO v_r FROM public.ew_compras_recebimentos
  WHERE id=(v_i->>'recebimento_id')::uuid AND pedido_id=v_p.id AND
   empresa_id=v_p.empresa_id FOR UPDATE;
  IF NOT FOUND OR v_r.estornado_em IS NOT NULL THEN
   RAISE EXCEPTION 'O recebimento físico foi estornado ou pertence a outro pedido.';END IF;
  SELECT * INTO v_mov FROM public.ew_compras_recebimentos_movimentos
  WHERE recebimento_id=v_r.id AND chave=v_i->>'chave'
   AND empresa_id=v_p.empresa_id AND movimento_obra_id IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Movimento de estoque da obra não vinculado ao recebimento.';END IF;
  IF EXISTS(SELECT 1 FROM public.ew_compras_nfe_vinculos
   WHERE recebimento_id=v_r.id AND chave=v_i->>'chave' AND desvinculado_em IS NULL)
  THEN RAISE EXCEPTION 'Esta entrada física já foi vinculada a uma nota. Verifique o histórico.';END IF;
  SELECT value INTO v_line FROM jsonb_array_elements(v_p.itens)
  WHERE value->>'chave'=v_i->>'chave';
  IF NOT FOUND THEN RAISE EXCEPTION 'Linha do pedido não localizada.';END IF;
  SELECT * INTO v_var FROM public.ew_materiais_variacoes
  WHERE id=(v_line->>'variacao_id')::uuid AND empresa_id=v_p.empresa_id;
  IF NOT FOUND OR (v_d.categoria='aluminio'
   AND (v_var.tipo<>'perfil' OR v_item.perfil_id IS DISTINCT FROM v_var.perfil_id))
   OR (v_d.categoria='acessorios'
   AND (v_var.tipo<>'acessorio' OR v_item.acessorio_id IS DISTINCT FROM v_var.acessorio_id))
  THEN RAISE EXCEPTION 'Material do pedido diverge do material/categoria do item fiscal.';END IF;
  SELECT (j.value->>'quantidade')::numeric INTO v_fis_qty
   FROM jsonb_array_elements(v_r.itens) j(value)
   WHERE j.value->>'chave'=v_i->>'chave';
  IF v_fis_qty IS NULL OR v_fis_qty<=0 THEN
   RAISE EXCEPTION 'Quantidade física não encontrada para a linha selecionada.';END IF;
  v_order_unit:=upper(btrim(v_line->>'unidade'));
  v_length:=(v_line->>'comprimento_mm')::integer;
  v_unit:=upper(btrim(v_item.unidade));
  v_unit:=CASE v_unit WHEN 'M' THEN 'MT'
    WHEN 'METRO' THEN 'MT' WHEN 'BR' THEN 'BARRA'
    WHEN 'PEÇA' THEN 'PC' WHEN 'PECA' THEN 'PC'
    WHEN 'UNIDADE' THEN 'UN' ELSE v_unit END;
  v_nota_qty:=CASE WHEN v_order_unit=v_unit THEN v_fis_qty
   WHEN v_order_unit='BARRA' AND v_unit='MT'
    AND v_length BETWEEN 100 AND 20000 THEN round(v_fis_qty*v_length/1000,3)
   WHEN v_order_unit='PC' AND v_unit='UN' THEN v_fis_qty
   WHEN v_order_unit='UN' AND v_unit='PC' THEN v_fis_qty
   ELSE NULL END;
  IF v_nota_qty IS NULL OR v_nota_qty<=0
  THEN RAISE EXCEPTION 'Unidade da nota (%) incompatível com a unidade do pedido (%).',v_unit,v_order_unit;END IF;
  SELECT coalesce(sum(x.quantidade_nota),0) INTO v_soma
  FROM public.ew_compras_nfe_vinculos x JOIN public.ew_compras_nfe_conciliacoes h
   ON h.id=x.conciliacao_id
  WHERE x.despesa_item_id=v_item.id AND h.desvinculado_em IS NULL;
  IF v_soma+v_nota_qty>v_item.quantidade+0.0001
  THEN RAISE EXCEPTION 'Quantidade conciliada excede a quantidade da nota (% %).',v_item.quantidade,v_unit;END IF;
  IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos n
    WHERE n.despesa_item_id=v_item.id AND n.estornado_em IS NULL)
  THEN RAISE EXCEPTION 'O item desta nota já gerou entrada física. Estorne essa entrada antes de vincular ao pedido.';END IF;
  INSERT INTO public.ew_compras_nfe_vinculos(
   empresa_id,conciliacao_id,despesa_item_id,recebimento_id,chave,
   quantidade_nota,quantidade_fisica,unidade_nota)
  VALUES(v_p.empresa_id,v_conc,v_item.id,v_r.id,v_i->>'chave',
   v_nota_qty,v_fis_qty,v_unit);
  v_total:=v_total+1;
 END LOOP;
 RETURN jsonb_build_object('id',v_conc,'repetida',false,'itens_vinculados',v_total,
  'entrada_fisica_duplicada',false,'despesa_id',v_d.id);
END;$fn$;

-- Um vínculo desfeito mantém a proibição de relançar a mesma nota fisicamente.
-- Para corrigir a nota, o financeiro pode desassociar o vínculo com motivo registrado.
CREATE OR REPLACE FUNCTION public.ew_compras_desvincular_nfe(
 p_conciliacao_id uuid,p_motivo text,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_h public.ew_compras_nfe_conciliacoes%ROWTYPE;
 v_reason text:=btrim(coalesce(p_motivo,''));
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF p_conciliacao_id IS NULL OR p_operacao_id IS NULL
 OR char_length(v_reason) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Associação, operação e motivo de 5 a 400 caracteres são obrigatórios.';END IF;
 SELECT * INTO v_h FROM public.ew_compras_nfe_conciliacoes
 WHERE id=p_conciliacao_id FOR UPDATE;
 IF NOT FOUND OR NOT(public.ew_pode(v_h.empresa_id,'financeiro.cancelar_despesas')
  AND public.ew_pode(v_h.empresa_id,'compras.consultar_valores'))
 THEN RAISE EXCEPTION 'Associação não encontrada ou sem autorização de estorno financeiro.';END IF;
 IF v_h.desvinculado_em IS NOT NULL THEN
  IF v_h.desvinculo_operacao_id=p_operacao_id THEN
   RETURN jsonb_build_object('id',v_h.id,'repetida',true);END IF;
  RAISE EXCEPTION 'Conciliação fiscal já desvinculada.';END IF;
 UPDATE public.ew_compras_nfe_vinculos SET desvinculado_em=now()
 WHERE conciliacao_id=v_h.id AND desvinculado_em IS NULL;
 UPDATE public.ew_compras_nfe_conciliacoes SET
  desvinculado_em=now(),desvinculado_por=auth.uid(),
  desvinculo_motivo=v_reason,desvinculo_operacao_id=p_operacao_id
 WHERE id=v_h.id;
 RETURN jsonb_build_object('id',v_h.id,'desvinculada',true,
  'estoque_alterado',false,'historico_preservado',true);
END;$fn$;

-- Proteção em banco: a nota associada ao pedido jamais pode gerar um segundo estoque,
-- inclusive se a UI antiga tentar registrar recebimento via NF-e/manual.
CREATE OR REPLACE FUNCTION public.ew_compras_proteger_recebimento_nfe()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_fornecedor text;
BEGIN
 -- Compartilha a chave de serialização do recebimento por pedido.
 -- O fluxo de NF legado já criou seu movimento na MESMA transação;
 -- se um pedido confirmar o mesmo item em paralelo, a transação da
 -- NF aborta integralmente ao detectar a entrada do pedido, sem dupla baixa.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  NEW.obra_id::text||'|'||NEW.variacao_id::text||'|'||
  coalesce(NEW.comprimento_mm::text,'-')||'|'||NEW.unidade,34777));
 IF EXISTS(SELECT 1 FROM public.ew_compras_nfe_vinculos x
  WHERE x.despesa_item_id=NEW.despesa_item_id)
 THEN RAISE EXCEPTION
  'Este item fiscal já foi vinculado a um recebimento de pedido; não pode dar entrada física novamente.';
 END IF;
 -- Impedir duplicidade entre nota e compra ainda NÃO conciliadas para a mesma
 -- obra, fornecedor e variação. Sem identificação única da mercadoria, exigir
 -- conciliação explícita é mais seguro do que duplicar o saldo.
 SELECT d.fornecedor INTO v_fornecedor FROM public.ew_obra_despesas_itens i
 JOIN public.ew_obra_despesas d ON d.id=i.despesa_id
 WHERE i.id=NEW.despesa_item_id AND d.empresa_id=NEW.empresa_id;
 IF EXISTS(
  SELECT 1 FROM public.ew_compras_pedidos p
  JOIN public.ew_fornecedores f ON f.id=p.fornecedor_id AND f.empresa_id=p.empresa_id
  JOIN public.ew_compras_recebimentos r ON r.pedido_id=p.id AND r.estornado_em IS NULL
  JOIN public.ew_compras_recebimentos_movimentos x ON x.recebimento_id=r.id
  JOIN public.ew_estoque_obras_movimentos m ON m.id=x.movimento_obra_id
  WHERE p.empresa_id=NEW.empresa_id AND p.obra_id=NEW.obra_id
   AND lower(btrim(f.nome))=lower(btrim(coalesce(v_fornecedor,'')))
   AND m.variacao_id=NEW.variacao_id
   AND m.comprimento_mm IS NOT DISTINCT FROM NEW.comprimento_mm
   AND m.unidade=NEW.unidade
   AND NOT EXISTS(SELECT 1 FROM public.ew_compras_nfe_vinculos z
      WHERE z.recebimento_id=r.id AND z.chave=x.chave AND z.desvinculado_em IS NULL)
 ) THEN RAISE EXCEPTION
  'Há materiais recebidos por pedido deste fornecedor na obra. Vincule a nota ao recebimento existente para evitar duplicidade.';
 END IF;
 RETURN NEW;
END;$fn$;
DROP TRIGGER IF EXISTS ew_compras_bloquear_nf_duplicada ON public.ew_nfe_recebimentos;
CREATE TRIGGER ew_compras_bloquear_nf_duplicada
 BEFORE INSERT ON public.ew_nfe_recebimentos
 FOR EACH ROW EXECUTE FUNCTION public.ew_compras_proteger_recebimento_nfe();

CREATE OR REPLACE FUNCTION public.ew_compras_proteger_cancelamento_nfe()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.status='cancelada' AND OLD.status IS DISTINCT FROM NEW.status
 AND EXISTS(SELECT 1 FROM public.ew_compras_nfe_conciliacoes h
  WHERE h.despesa_id=NEW.id AND h.desvinculado_em IS NULL)
 THEN RAISE EXCEPTION
  'Nota vinculada a pedido recebido. Desvincule a conciliação antes do cancelamento.';
 END IF;
 RETURN NEW;
END;$fn$;
DROP TRIGGER IF EXISTS ew_compras_bloquear_cancel_nf ON public.ew_obra_despesas;
CREATE TRIGGER ew_compras_bloquear_cancel_nf
 BEFORE UPDATE OF status ON public.ew_obra_despesas
 FOR EACH ROW EXECUTE FUNCTION public.ew_compras_proteger_cancelamento_nfe();

CREATE OR REPLACE FUNCTION public.ew_compras_proteger_estorno_recebimento_conciliado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.estornado_em IS NOT NULL AND OLD.estornado_em IS NULL
 AND EXISTS(SELECT 1 FROM public.ew_compras_nfe_vinculos x
  JOIN public.ew_compras_nfe_conciliacoes h ON h.id=x.conciliacao_id
  WHERE x.recebimento_id=NEW.id AND h.desvinculado_em IS NULL)
 THEN RAISE EXCEPTION
  'Recebimento vinculado à nota fiscal. Desvincule a conciliação fiscal antes de estornar o material.';
 END IF;
 RETURN NEW;
END;$fn$;
DROP TRIGGER IF EXISTS ew_compras_bloquear_estorno_receb_conc ON public.ew_compras_recebimentos;
CREATE TRIGGER ew_compras_bloquear_estorno_receb_conc
 BEFORE UPDATE OF estornado_em ON public.ew_compras_recebimentos
 FOR EACH ROW EXECUTE FUNCTION public.ew_compras_proteger_estorno_recebimento_conciliado();

REVOKE ALL ON FUNCTION public.ew_compras_vincular_nfe_pedido(uuid,uuid,jsonb,uuid),
 public.ew_compras_desvincular_nfe(uuid,text,uuid) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.ew_compras_vincular_nfe_pedido(uuid,uuid,jsonb,uuid),
 public.ew_compras_desvincular_nfe(uuid,text,uuid) TO authenticated;
COMMIT;
