-- Proposta de razão de custos internos; não ativar antes da integração com lotes fiscais.
-- Não há RPC pública nem alteração das flags. Não é substituto do rastreamento de lotes.
CREATE TABLE ew_compras_interna.transferencia_custo_apropriacoes (
 empresa_id uuid NOT NULL,
 fluxo text NOT NULL CHECK (fluxo IN ('OBRAS','LOCAIS','INSUMOS')),
 transferencia_id uuid NOT NULL,
 origem_tipo text NOT NULL CHECK (origem_tipo IN ('OBRA','EMPRESA')),
 origem_id uuid NOT NULL,
 destino_tipo text NOT NULL CHECK (destino_tipo IN ('OBRA','EMPRESA')),
 destino_id uuid NOT NULL,
 categoria text NOT NULL CHECK (categoria IN ('aluminio','acessorios','vidros','outros')),
 custo_centavos bigint NOT NULL CHECK (custo_centavos>=0),
 evidencias jsonb NOT NULL CHECK (CASE WHEN jsonb_typeof(evidencias)='array' THEN jsonb_array_length(evidencias)>0 ELSE false END),
 criado_por uuid NOT NULL,
 criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (empresa_id,fluxo,transferencia_id),
 CHECK ((origem_tipo,origem_id)<>(destino_tipo,destino_id)),
 CHECK (origem_tipo='OBRA' OR destino_tipo='OBRA')
);
CREATE TABLE ew_compras_interna.transferencia_custo_estornos (
 empresa_id uuid NOT NULL,
 fluxo text NOT NULL,
 transferencia_id uuid NOT NULL,
 operacao_id uuid NOT NULL,
 motivo text NOT NULL CHECK (length(btrim(motivo)) BETWEEN 5 AND 350),
 criado_por uuid NOT NULL,
 criado_em timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (empresa_id,fluxo,transferencia_id),
 UNIQUE (empresa_id,operacao_id),
 FOREIGN KEY (empresa_id,fluxo,transferencia_id)
 REFERENCES ew_compras_interna.transferencia_custo_apropriacoes(empresa_id,fluxo,transferencia_id)
 ON DELETE RESTRICT
);
ALTER TABLE ew_compras_interna.transferencia_custo_apropriacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ew_compras_interna.transferencia_custo_estornos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ew_compras_interna.transferencia_custo_apropriacoes,ew_compras_interna.transferencia_custo_estornos FROM PUBLIC,anon,authenticated;
CREATE VIEW ew_compras_interna.transferencia_custo_razao WITH (security_invoker=true) AS
 SELECT a.empresa_id,a.fluxo,a.transferencia_id,a.categoria,a.criado_em,
 v.tipo,v.local_id,v.delta_centavos,'APROPRIACAO'::text evento
 FROM ew_compras_interna.transferencia_custo_apropriacoes a
 CROSS JOIN LATERAL (VALUES (a.origem_tipo,a.origem_id,-a.custo_centavos),(a.destino_tipo,a.destino_id,a.custo_centavos)) v(tipo,local_id,delta_centavos)
 UNION ALL
 SELECT a.empresa_id,a.fluxo,a.transferencia_id,a.categoria,e.criado_em,
 v.tipo,v.local_id,v.delta_centavos,'ESTORNO'::text evento
 FROM ew_compras_interna.transferencia_custo_apropriacoes a
 JOIN ew_compras_interna.transferencia_custo_estornos e USING (empresa_id,fluxo,transferencia_id)
 CROSS JOIN LATERAL (VALUES (a.origem_tipo,a.origem_id,a.custo_centavos),(a.destino_tipo,a.destino_id,-a.custo_centavos)) v(tipo,local_id,delta_centavos);
REVOKE ALL ON ew_compras_interna.transferencia_custo_razao FROM PUBLIC,anon,authenticated;
-- Integração obrigatória antes de ativar:
-- 1. resolver identidade canônica do fluxo físico e validar empresa, material, categoria e quantidade;
-- 2. validar evidências contra lotes/documentos reais e reservar intervalos de custo sob lock;
-- 3. inserir e estornar somente em rotinas internas autorizadas, atomicamente com estoque;
-- 4. não aceitar custo, categoria ou evidências livres vindos do navegador;
-- 5. bloquear UPDATE/DELETE de lançamentos nas rotinas e preservar registros históricos;
-- 6. vincular o razão ao financeiro e só remover pendência após apropriação comprovada.
