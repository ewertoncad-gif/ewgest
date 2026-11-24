-- EWGEST v46.21: documentos fiscais de compras para ESTOQUE PRÓPRIO da empresa.
-- Não cria uma obra fictícia nem duplica a entrada física já feita por pedido.
-- A apuração de custos empresariais usa este livro fiscal independente.
-- Aplicar somente após as quatro propostas v46.21 precedentes.
BEGIN;

CREATE TABLE IF NOT EXISTS public.ew_compras_notas_empresa(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 local_empresa_id uuid NOT NULL REFERENCES public.ew_compras_locais_empresa(id),
 pedido_id uuid NOT NULL REFERENCES public.ew_compras_pedidos(id),
 fornecedor_id uuid NOT NULL REFERENCES public.ew_fornecedores(id),
 numero_documento text NOT NULL CHECK(length(btrim(numero_documento)) BETWEEN 1 AND 100),
 data_documento date NOT NULL,
 chave_nfe text CHECK(chave_nfe IS NULL OR chave_nfe ~ '^[0-9]{44}$'),
 valor_centavos bigint NOT NULL CHECK(valor_centavos>0),
 operacao_id uuid NOT NULL UNIQUE,
 status text NOT NULL DEFAULT 'ATIVA' CHECK(status IN ('ATIVA','CANCELADA')),
 observacoes text NOT NULL DEFAULT '',
 criado_em timestamptz NOT NULL DEFAULT now(),
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 cancelado_em timestamptz,
 cancelado_por uuid REFERENCES auth.users(id),
 cancelamento_operacao_id uuid UNIQUE,
 cancelamento_motivo text
);
CREATE UNIQUE INDEX IF NOT EXISTS ew_compras_nf_empresa_unica_ativa
 ON public.ew_compras_notas_empresa(empresa_id,fornecedor_id,upper(btrim(numero_documento)))
 WHERE status='ATIVA';
CREATE UNIQUE INDEX IF NOT EXISTS ew_compras_nf_empresa_chave_unica
 ON public.ew_compras_notas_empresa(empresa_id,chave_nfe)
 WHERE status='ATIVA' AND chave_nfe IS NOT NULL;
CREATE INDEX IF NOT EXISTS ew_compras_nf_empresa_local_idx
 ON public.ew_compras_notas_empresa(empresa_id,local_empresa_id,criado_em DESC);

CREATE TABLE IF NOT EXISTS public.ew_compras_notas_empresa_itens(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 nota_id uuid NOT NULL REFERENCES public.ew_compras_notas_empresa(id),
 recebimento_id uuid NOT NULL,
 chave text NOT NULL,
 variacao_id uuid NOT NULL REFERENCES public.ew_materiais_variacoes(id),
 quantidade_fisica numeric(16,3) NOT NULL CHECK(quantidade_fisica>0),
 unidade text NOT NULL,
 comprimento_mm integer,
 valor_total_centavos bigint NOT NULL CHECK(valor_total_centavos>=0),
 cancelado_em timestamptz,
 criado_em timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(recebimento_id,chave)
  REFERENCES public.ew_compras_recebimentos_movimentos(recebimento_id,chave)
);
CREATE UNIQUE INDEX IF NOT EXISTS ew_compras_nf_empresa_mov_ativo_unico
 ON public.ew_compras_notas_empresa_itens(recebimento_id,chave)
 WHERE cancelado_em IS NULL;

ALTER TABLE public.ew_compras_notas_empresa ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ew_compras_notas_empresa_itens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ew_compras_nf_empresa_leitura" ON public.ew_compras_notas_empresa
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'compras.consultar_valores')
  AND public.ew_pode(empresa_id,'financeiro.consultar'));
CREATE POLICY "ew_compras_nf_empresa_itens_leitura" ON public.ew_compras_notas_empresa_itens
 FOR SELECT TO authenticated USING(public.ew_pode(empresa_id,'compras.consultar_valores')
  AND public.ew_pode(empresa_id,'financeiro.consultar'));
GRANT SELECT ON public.ew_compras_notas_empresa,public.ew_compras_notas_empresa_itens TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.ew_compras_notas_empresa,
 public.ew_compras_notas_empresa_itens FROM anon,authenticated;

CREATE OR REPLACE FUNCTION public.ew_compras_registrar_nota_empresa(
 p_pedido_id uuid,p_numero_documento text,p_data_documento date,
 p_chave_nfe text,p_valor_centavos bigint,p_itens jsonb,
 p_observacoes text,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_user uuid:=auth.uid();v_p public.ew_compras_pedidos%ROWTYPE;
 v_nota_id uuid;v_numero text:=btrim(coalesce(p_numero_documento,''));
 v_chave text:=nullif(btrim(coalesce(p_chave_nfe,'')),'');
 v_i jsonb;v_r public.ew_compras_recebimentos%ROWTYPE;
 v_line jsonb;v_q numeric;v_amount bigint;v_soma bigint:=0;
 v_n int:=0;
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF v_user IS NULL OR p_operacao_id IS NULL THEN
  RAISE EXCEPTION 'Sessão ou identificador de operação inválido.';END IF;
 SELECT * INTO v_p FROM public.ew_compras_pedidos WHERE id=p_pedido_id FOR UPDATE;
 IF NOT FOUND OR v_p.local_empresa_id IS NULL OR v_p.status='CANCELADO'
 THEN RAISE EXCEPTION 'Pedido deve pertencer a um estoque próprio ativo da empresa.';END IF;
 IF NOT(public.ew_pode(v_p.empresa_id,'financeiro.despesas')
  AND public.ew_pode(v_p.empresa_id,'compras.consultar_valores'))
 THEN RAISE EXCEPTION 'Sem permissão para registrar nota de compra empresarial.';END IF;
 SELECT id INTO v_nota_id FROM public.ew_compras_notas_empresa
 WHERE operacao_id=p_operacao_id;
 IF v_nota_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.ew_compras_notas_empresa
   WHERE id=v_nota_id AND pedido_id=v_p.id AND status='ATIVA')
  THEN RAISE EXCEPTION 'Identificador reutilizado em outra nota ou nota cancelada.';END IF;
  RETURN jsonb_build_object('id',v_nota_id,'repetida',true);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ew_compras_locais_empresa
   WHERE id=v_p.local_empresa_id AND empresa_id=v_p.empresa_id AND ativo)
 THEN RAISE EXCEPTION 'Local da empresa inexistente ou inativo.';END IF;
 IF length(v_numero) NOT BETWEEN 1 AND 100 OR p_data_documento IS NULL OR
  p_data_documento>current_date+30 OR p_data_documento<date '2000-01-01'
 THEN RAISE EXCEPTION 'Número ou data da nota inválidos.';END IF;
 IF v_chave IS NOT NULL AND v_chave !~ '^[0-9]{44}$'
 THEN RAISE EXCEPTION 'Chave NF-e inválida: são necessários 44 dígitos.';END IF;
 IF p_valor_centavos IS NULL OR p_valor_centavos<=0 OR p_valor_centavos>99999999999999
 OR jsonb_typeof(p_itens) IS DISTINCT FROM 'array'
 OR jsonb_array_length(p_itens) NOT BETWEEN 1 AND 150
 OR length(coalesce(p_observacoes,''))>1000
 THEN RAISE EXCEPTION 'Valor, observações ou itens inválidos.';END IF;
 IF EXISTS(SELECT 1 FROM public.ew_compras_notas_empresa
  WHERE empresa_id=v_p.empresa_id AND fornecedor_id=v_p.fornecedor_id
   AND upper(btrim(numero_documento))=upper(v_numero) AND status='ATIVA')
 THEN RAISE EXCEPTION 'Esta nota já existe para o fornecedor.';END IF;
 INSERT INTO public.ew_compras_notas_empresa(
  empresa_id,local_empresa_id,pedido_id,fornecedor_id,
  numero_documento,data_documento,chave_nfe,valor_centavos,
  observacoes,operacao_id,criado_por)
 VALUES(v_p.empresa_id,v_p.local_empresa_id,v_p.id,v_p.fornecedor_id,
  v_numero,p_data_documento,v_chave,p_valor_centavos,
  coalesce(p_observacoes,''),p_operacao_id,v_user)
 RETURNING id INTO v_nota_id;
 FOR v_i IN SELECT value FROM jsonb_array_elements(p_itens)
  ORDER BY value->>'recebimento_id',value->>'chave' LOOP
  SELECT * INTO v_r FROM public.ew_compras_recebimentos
  WHERE id=(v_i->>'recebimento_id')::uuid AND empresa_id=v_p.empresa_id
   AND pedido_id=v_p.id FOR UPDATE;
  IF NOT FOUND OR v_r.estornado_em IS NOT NULL THEN
   RAISE EXCEPTION 'Recebimento selecionado está estornado ou não pertence ao pedido.';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.ew_compras_recebimentos_movimentos x
   WHERE x.recebimento_id=v_r.id AND x.chave=v_i->>'chave'
    AND x.movimento_empresa_id IS NOT NULL AND x.empresa_id=v_p.empresa_id)
  THEN RAISE EXCEPTION 'Movimento físico da empresa não encontrado.';END IF;
  SELECT value INTO v_line FROM jsonb_array_elements(v_p.itens)
  WHERE value->>'chave'=v_i->>'chave';
  IF NOT FOUND THEN RAISE EXCEPTION 'Item não pertence ao pedido.';END IF;
  SELECT (j.value->>'quantidade')::numeric INTO v_q
  FROM jsonb_array_elements(v_r.itens) j(value)
  WHERE j.value->>'chave'=v_i->>'chave';
  IF v_q IS NULL OR v_q<=0 THEN RAISE EXCEPTION 'Quantidade física inválida.';END IF;
  IF EXISTS(SELECT 1 FROM public.ew_compras_notas_empresa_itens x
   WHERE x.recebimento_id=v_r.id AND x.chave=v_i->>'chave' AND x.cancelado_em IS NULL)
  THEN RAISE EXCEPTION 'Recebimento já está atribuído a uma nota empresarial ativa.';END IF;
  v_amount:=(v_i->>'valor_total_centavos')::bigint;
  IF v_amount IS NULL OR v_amount<0 OR v_amount>99999999999999
  THEN RAISE EXCEPTION 'Custo por item inválido.';END IF;
  INSERT INTO public.ew_compras_notas_empresa_itens(
   empresa_id,nota_id,recebimento_id,chave,variacao_id,
   quantidade_fisica,unidade,comprimento_mm,valor_total_centavos)
  VALUES(v_p.empresa_id,v_nota_id,v_r.id,v_i->>'chave',
   (v_line->>'variacao_id')::uuid,v_q,
   v_line->>'unidade',(v_line->>'comprimento_mm')::integer,v_amount);
  v_soma:=v_soma+v_amount;v_n:=v_n+1;
 END LOOP;
 IF v_soma<>p_valor_centavos
 THEN RAISE EXCEPTION 'Soma dos itens (%) diverge do total da nota (%).',v_soma,p_valor_centavos;END IF;
 RETURN jsonb_build_object('id',v_nota_id,'itens',v_n,'valor_centavos',v_soma,
  'repetida',false,'novo_movimento_fisico',false);
END;$fn$;

CREATE OR REPLACE FUNCTION public.ew_compras_cancelar_nota_empresa(
 p_nota_id uuid,p_motivo text,p_operacao_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_n public.ew_compras_notas_empresa%ROWTYPE;
 v_motivo text:=btrim(coalesce(p_motivo,''));
BEGIN
 PERFORM public.ew_exigir_sessao_atual();
 IF p_nota_id IS NULL OR p_operacao_id IS NULL OR char_length(v_motivo) NOT BETWEEN 5 AND 400
 THEN RAISE EXCEPTION 'Nota, operação e motivo de 5 a 400 caracteres são obrigatórios.';END IF;
 SELECT * INTO v_n FROM public.ew_compras_notas_empresa WHERE id=p_nota_id FOR UPDATE;
 IF NOT FOUND OR NOT(public.ew_pode(v_n.empresa_id,'financeiro.cancelar_despesas')
  AND public.ew_pode(v_n.empresa_id,'compras.consultar_valores'))
 THEN RAISE EXCEPTION 'Nota inexistente ou sem autorização para cancelar.';END IF;
 IF v_n.status='CANCELADA' THEN
  IF v_n.cancelamento_operacao_id=p_operacao_id
  THEN RETURN jsonb_build_object('id',v_n.id,'repetida',true);END IF;
  RAISE EXCEPTION 'Nota já cancelada anteriormente.';END IF;
 UPDATE public.ew_compras_notas_empresa_itens
 SET cancelado_em=now() WHERE nota_id=v_n.id AND cancelado_em IS NULL;
 UPDATE public.ew_compras_notas_empresa SET status='CANCELADA',
  cancelado_em=now(),cancelado_por=auth.uid(),
  cancelamento_operacao_id=p_operacao_id,cancelamento_motivo=v_motivo
 WHERE id=v_n.id;
 RETURN jsonb_build_object('id',v_n.id,'cancelada',true,
  'movimento_fisico_alterado',false,'historico_preservado',true);
END;$fn$;

-- Uma nota empresarial ativa impede desfazer o recebimento vinculado,
-- até que a nota seja cancelada por quem tenha autorização financeira.
CREATE OR REPLACE FUNCTION public.ew_compras_proteger_estorno_rec_empresa()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NEW.estornado_em IS NOT NULL AND OLD.estornado_em IS NULL
 AND EXISTS(SELECT 1 FROM public.ew_compras_notas_empresa_itens x
  WHERE x.recebimento_id=NEW.id AND x.cancelado_em IS NULL)
 THEN RAISE EXCEPTION
  'Recebimento vinculado a nota de estoque da empresa. Cancele a nota fiscal antes de estornar o estoque.';
 END IF;
 RETURN NEW;
END;$fn$;
DROP TRIGGER IF EXISTS ew_compras_proteger_estorno_empresa ON public.ew_compras_recebimentos;
CREATE TRIGGER ew_compras_proteger_estorno_empresa
 BEFORE UPDATE OF estornado_em ON public.ew_compras_recebimentos
 FOR EACH ROW EXECUTE FUNCTION public.ew_compras_proteger_estorno_rec_empresa();

REVOKE ALL ON FUNCTION public.ew_compras_registrar_nota_empresa(uuid,text,date,text,bigint,jsonb,text,uuid),
 public.ew_compras_cancelar_nota_empresa(uuid,text,uuid) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.ew_compras_registrar_nota_empresa(uuid,text,date,text,bigint,jsonb,text,uuid),
 public.ew_compras_cancelar_nota_empresa(uuid,text,uuid) TO authenticated;
COMMIT;
