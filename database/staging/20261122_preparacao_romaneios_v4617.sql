-- Somente ambiente ewgest-restauracao-teste. Completa o contrato fictício da tabela de romaneios.
-- Não contém registros produtivos nem é aplicado em produção.
BEGIN;
CREATE SEQUENCE IF NOT EXISTS public.romaneios_numero_seq START WITH 1;
ALTER TABLE public.romaneios
 ADD COLUMN IF NOT EXISTS empresa_id uuid,
 ADD COLUMN IF NOT EXISTS numero text DEFAULT ('RM'||lpad(nextval('public.romaneios_numero_seq')::text,3,'0')),
 ADD COLUMN IF NOT EXISTS chave_operacao uuid,
 ADD COLUMN IF NOT EXISTS data_saida date,
 ADD COLUMN IF NOT EXISTS motorista text DEFAULT '',
 ADD COLUMN IF NOT EXISTS placa text DEFAULT '',
 ADD COLUMN IF NOT EXISTS observacoes text DEFAULT '',
 ADD COLUMN IF NOT EXISTS criado_por uuid,
 ADD COLUMN IF NOT EXISTS criado_em timestamptz DEFAULT now(),
 ADD COLUMN IF NOT EXISTS cancelado_em timestamptz,
 ADD COLUMN IF NOT EXISTS cancelado_por uuid,
 ADD COLUMN IF NOT EXISTS motivo_cancelamento text;
CREATE TABLE IF NOT EXISTS public.romaneios_itens(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 romaneio_id uuid NOT NULL REFERENCES public.romaneios(id),
 sequencia integer NOT NULL,natureza text NOT NULL,
 esquadria_id uuid,saida_producao_id uuid,codigo text NOT NULL DEFAULT '',
 localizacao text NOT NULL DEFAULT '',descricao text NOT NULL DEFAULT '',
 medida text NOT NULL DEFAULT '',quantidade integer NOT NULL,unidade text NOT NULL DEFAULT 'UNID.',
 area_m2 numeric,fabrica text,prazo_liberacao_saida_dias numeric,
 tipo_saida text,descricao_impressao_definida boolean NOT NULL DEFAULT false
);
ALTER TABLE public.romaneios_itens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.romaneios_itens FROM PUBLIC,anon,authenticated;
COMMIT;