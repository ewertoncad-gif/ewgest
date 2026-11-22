-- Fixture estendida apenas após os testes das RPCs de devolução.
-- Nenhuma linha comercial ou esquema de produção é importado.
\set ON_ERROR_STOP on
CREATE TABLE public.esquadrias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 obra_id uuid REFERENCES public.obras(id),
 qtd_liberada integer NOT NULL DEFAULT 0,
 qtd_fabricada integer NOT NULL DEFAULT 0
);
CREATE TABLE public.liberacoes_corte (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 esquadria_id uuid REFERENCES public.esquadrias(id),
 cancelado_em timestamptz
);
CREATE TABLE public.ew_liberacoes_lotes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 obra_id uuid REFERENCES public.obras(id),
 cancelado_em timestamptz
);
CREATE TABLE public.ew_planos_liberados(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 obra_id uuid REFERENCES public.obras(id),
 liberacao_id uuid REFERENCES public.liberacoes_corte(id)
);
CREATE TABLE public.romaneios(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 obra_id uuid REFERENCES public.obras(id),
 status text NOT NULL DEFAULT 'emitido'
);
CREATE TABLE public.saidas_producao(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 esquadria_id uuid REFERENCES public.esquadrias(id),
 cancelado_em timestamptz
);
CREATE TABLE public.ew_insumos_movimentos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid REFERENCES public.empresas(id),
 obra_id uuid REFERENCES public.obras(id),
 insumo_id uuid,
 local_estoque text,
 quantidade_delta numeric NOT NULL
);
CREATE TABLE public.classificacoes_tipologias_auditoria(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 obra_id uuid REFERENCES public.obras(id),
 esquadria_referencia_id uuid REFERENCES public.esquadrias(id)
);
CREATE TABLE public.esquadrias_descricoes_revisoes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 obra_id uuid REFERENCES public.obras(id),
 esquadria_referencia_id uuid REFERENCES public.esquadrias(id)
);
-- Somente para os cenários fictícios SEM NF-e ativa;
-- a função real de estorno NF-e tem teste separado e permanece inalterada.
CREATE FUNCTION public.ew_transferencias_nfe_conciliadas(p_obra_id uuid)
 RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path TO ''
 AS $$ SELECT 0 $$;
