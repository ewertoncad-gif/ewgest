-- Adaptação temporária: usar fixture de tests/composicao_expedicao/20_romaneio_faturamento_rollback.sql em ambiente isolado, aplicar as três propostas (catálogo, integração, numeração) antes dos blocos DO.
-- Executar exclusivamente na restauração, com BEGIN/ROLLBACK. Adaptações temporárias antes das propostas.
ALTER TABLE public.tipologias ADD COLUMN IF NOT EXISTS provisoria boolean NOT NULL DEFAULT false;
ALTER TABLE public.liberacoes_corte ADD COLUMN IF NOT EXISTS tipo_componente text NOT NULL DEFAULT 'completo';
ALTER TABLE public.saidas_producao ADD COLUMN IF NOT EXISTS data_saida date, ADD COLUMN IF NOT EXISTS usuario_id uuid;
ALTER TABLE public.saidas_producao ADD CONSTRAINT saidas_producao_tipo_check CHECK(tipo IN ('completo','marco','folha'));
ALTER TABLE public.romaneios_itens ADD CONSTRAINT romaneios_itens_tipo_saida_check CHECK ((natureza='esquadria' AND tipo_saida IN ('completo','marco','folha')) OR (natureza='material' AND tipo_saida IS NULL));
CREATE TABLE IF NOT EXISTS public.esquadrias_saida_config(esquadria_id uuid primary key,folhas_por_unidade integer not null,configurado_por uuid,configurado_em timestamptz);
CREATE TABLE IF NOT EXISTS public.ew_obra_faturamentos_itens(id uuid primary key default gen_random_uuid(),faturamento_id uuid not null,empresa_id uuid not null,esquadria_id uuid not null,quantidade numeric(14,6) not null,valor_unitario numeric(14,4) not null,valor_total numeric(14,2) not null,area_m2 numeric(18,6),preco_m2 numeric(16,4));
ALTER TABLE public.ew_obra_faturamentos ADD COLUMN IF NOT EXISTS data_faturamento date, ADD COLUMN IF NOT EXISTS numero_documento text, ADD COLUMN IF NOT EXISTS observacoes text, ADD COLUMN IF NOT EXISTS criado_por uuid, ADD COLUMN IF NOT EXISTS operacao_id uuid;
-- A sequência normal não é revertida; usar numeração temporária na homologação.
ALTER TABLE public.romaneios ALTER COLUMN numero SET DEFAULT ('RMT-'||gen_random_uuid()::text);

CREATE OR REPLACE FUNCTION public.consultar_proximo_romaneio() RETURNS jsonb LANGUAGE sql AS $$select '{}'::jsonb$$;
CREATE OR REPLACE FUNCTION public.adiantar_numero_romaneio(integer,text) RETURNS jsonb LANGUAGE sql AS $$select '{}'::jsonb$$;
-- Aplicar propostas aqui.
DO $t$
DECLARE u uuid;e uuid;o uuid;t uuid;a uuid;b uuid;rev uuid;revb uuid;rev2 uuid;r jsonb;est jsonb;doc uuid;doc2 uuid;fat uuid;blocked boolean; payload jsonb; op uuid; 
p jsonb:='[{"id":"marco","nome":"Marco","quantidade":1,"peso":5000},{"id":"folha","nome":"Folha","quantidade":2,"peso":5000}]';
p2 jsonb:='[{"id":"marco","nome":"Marco","quantidade":1,"peso":5000},{"id":"folha","nome":"Folha","quantidade":1,"peso":4000},{"id":"vidro","nome":"Vidro do peitoril","quantidade":1,"peso":1000}]';
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
 INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem)
 SELECT k,'Teste',k,1 FROM unnest(ARRAY['cadastros.consultar','cadastros.editar','cadastros.composicao_consultar','cadastros.composicao_editar','romaneios.emitir','romaneios.cancelar','obras.consultar','financeiro.faturar']) k ON CONFLICT(chave) DO NOTHING;
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
 SELECT e,1,k,true FROM unnest(ARRAY['cadastros.consultar','cadastros.editar','cadastros.composicao_consultar','cadastros.composicao_editar','romaneios.emitir','romaneios.cancelar','obras.consultar','financeiro.faturar']) k ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.tipologias(empresa_id,codigo,descricao,provisoria) VALUES(e,'TESTE-EXP-2F','JANELA 2 FOLHAS',false) RETURNING id INTO t;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE EXPEDICAO','TESTE-EXP-84') RETURNING id INTO o;
 INSERT INTO public.esquadrias(empresa_id,obra_id,tipologia_id,codigo,descricao,largura_mm,altura_mm,quantidade,qtd_liberada) VALUES(e,o,t,'EA2','JANELA 2 FOLHAS',1200,1150,2,2) RETURNING id INTO a;
 INSERT INTO public.liberacoes_corte(esquadria_id,quantidade,data_liberacao,usuario_id,fabrica,tipo_componente) VALUES(a,2,current_date,u,'AFOGADOS','completo');
 INSERT INTO public.ew_obra_orcamento(empresa_id,obra_id,valor_total,aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por) VALUES(e,o,1000,0,0,0,0,1000,0,u);
 r:=public.ew_salvar_composicoes_expedicao(e,jsonb_build_array(jsonb_build_object('tipologia_id',t,'revisao_id',null)),p,gen_random_uuid());rev:=(r->0->>'revisao_id')::uuid;
 est:=ew_expedicao_interna.estado_item(a);
 IF (est->'partes'->1->>'saldo')::int<>4 THEN RAISE EXCEPTION 'saldo 4 esperado: %',est;END IF;
 payload:=jsonb_build_array(jsonb_build_object('natureza','esquadria','esquadria_id',a,'tipo_saida','componente','quantidade',3,'composicao_revisao_id',rev,'componente_id','folha'));
 op:=gen_random_uuid();
 r:=public.emitir_romaneio_com_saidas(op,o,current_date,'Motorista teste','ABC1234','Teste',payload);doc:=(r->>'id')::uuid;
 IF r->>'numero'<>'RM001' THEN RAISE EXCEPTION 'Expedição inicial não recebeu RM001: %',r; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.romaneios_itens WHERE romaneio_id=doc AND equivalente_expedido=0.75 AND area_m2=1.035 AND componente_nome='Folha') THEN RAISE EXCEPTION 'area romaneio 1.035 esperada';END IF;
 r:=public.emitir_romaneio_com_saidas(op,o,current_date,'Motorista teste','ABC1234','Teste',payload);
 IF NOT (r->>'repetido')::boolean THEN RAISE EXCEPTION 'idempotência';END IF;
 est:=ew_expedicao_interna.estado_item(a);
 IF (est->'partes'->1->>'saldo')::int<>1 THEN RAISE EXCEPTION 'saldo 1 esperado %',est;END IF;
 blocked:=false;BEGIN PERFORM public.emitir_romaneio_com_saidas(gen_random_uuid(),o,current_date,'Motorista teste','ABC1234','Teste',payload);EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Componente inválido ou saldo insuficiente%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'excesso aceito';END IF;
 r:=public.ew_salvar_composicoes_expedicao(e,jsonb_build_array(jsonb_build_object('tipologia_id',t,'revisao_id',rev)),p2,gen_random_uuid());rev2:=(r->0->>'revisao_id')::uuid;
 IF (ew_expedicao_interna.estado_item(a)->>'revisao_id')::uuid<>rev THEN RAISE EXCEPTION 'revisão não congelada';END IF;
 r:=public.ew_registrar_faturamento_financeiro(e,o,'fabricacao',current_date,'TESTE-84-1','',jsonb_build_array(jsonb_build_object('esquadria_id',a,'quantidade',0.75,'valor_unitario',138,'area_m2',1.035,'preco_m2',100)),gen_random_uuid(),false);fat:=(r->>'id')::uuid;
 IF (r->>'valor_total')::numeric<>103.50 THEN RAISE EXCEPTION 'faturamento 103.50 esperado %',r;END IF;
 blocked:=false;BEGIN PERFORM public.cancelar_romaneio_com_estorno(doc,'Teste cancelamento com fatura');EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Estorne os faturamentos%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'cancelamento sem lastro';END IF;
 UPDATE public.ew_obra_faturamentos SET status='cancelado' WHERE id=fat;
 PERFORM public.cancelar_romaneio_com_estorno(doc,'Teste cancelamento sem fatura');
 est:=ew_expedicao_interna.estado_item(a);
 IF (est->>'revisao_id')::uuid<>rev2 THEN RAISE EXCEPTION 'nova revisão não selecionada';END IF;
 -- Com a nova composição, expedir 40% + 10% no mesmo romaneio.
 payload:=jsonb_build_array(jsonb_build_object('natureza','esquadria','esquadria_id',a,'tipo_saida','componente','quantidade',1,'composicao_revisao_id',rev2,'componente_id','folha'),jsonb_build_object('natureza','esquadria','esquadria_id',a,'tipo_saida','componente','quantidade',1,'composicao_revisao_id',rev2,'componente_id','vidro'));
 r:=public.emitir_romaneio_com_saidas(gen_random_uuid(),o,current_date,'Motorista teste','ABC1234','Teste',payload);doc2:=(r->>'id')::uuid;
 IF (SELECT sum(equivalente_expedido) FROM public.romaneios_itens WHERE romaneio_id=doc2)<>0.5 THEN RAISE EXCEPTION 'composição 40+10 incorreta';END IF;
 IF (SELECT sum(area_m2) FROM public.romaneios_itens WHERE romaneio_id=doc2)<>0.69 THEN RAISE EXCEPTION 'area 0.69 incorreta';END IF;
 r:=public.ew_registrar_faturamento_financeiro(e,o,'fabricacao',current_date,'TESTE-84-2','',jsonb_build_array(jsonb_build_object('esquadria_id',a,'quantidade',0.5,'valor_unitario',138,'area_m2',0.69,'preco_m2',100)),gen_random_uuid(),false);
 IF (r->>'valor_total')::numeric<>69 THEN RAISE EXCEPTION 'faturamento 69 esperado %',r;END IF;
END $t$;
SELECT 'PASS: expedição 3/4 folhas, faturamento 1.035 m², revisão congelada, estorno e composição 50/40/10' AS resultado;

DO $transfer$
DECLARE e uuid;u uuid;o uuid;p uuid;v uuid;tid uuid:=gen_random_uuid();d uuid;numero text;total numeric; n int;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 SELECT id INTO STRICT o FROM public.obras WHERE empresa_id=e AND codigo='TESTE-EXP-84';
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(e,'AFOGADOS'),(e,'IMBIRIBEIRA') ON CONFLICT DO NOTHING;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por) VALUES(e,o,u) ON CONFLICT DO NOTHING;
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-86-P','Perfil teste','Teste') RETURNING id INTO p;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque)
 VALUES(e,o,v,6000,'BARRA',5,'COMPRA',gen_random_uuid(),u,'AFOGADOS');
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque,transferencia_id)
 VALUES(e,o,v,6000,'BARRA',1,'TRANSFERENCIA',gen_random_uuid(),u,'IMBIRIBEIRA',tid);
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque,transferencia_id)
 VALUES(e,o,v,6000,'BARRA',-1,'TRANSFERENCIA',gen_random_uuid(),u,'AFOGADOS',tid);
 SELECT h.id,h.numero INTO STRICT d,numero FROM public.ew_romaneios_transferencia h JOIN public.ew_romaneios_transferencia_itens i ON i.documento_id=h.id WHERE i.transferencia_id=tid;
 IF numero<>'RM003' THEN RAISE EXCEPTION 'Transferência após duas expedições esperava RM003: %',numero;END IF;
 IF (public.consultar_proximo_romaneio(e,o)->>'codigo')<>'RM004' THEN RAISE EXCEPTION 'Próximo RM004 esperado';END IF;
 SELECT sum(quantidade_delta),count(*) INTO total,n FROM public.ew_estoque_obras_movimentos WHERE obra_id=o AND variacao_id=v;
 IF total<>5 OR n<>3 THEN RAISE EXCEPTION 'Estoque modificado pelo comprovante: %, %',total,n;END IF;
END;$transfer$;
SELECT 'PASS: RPC real de expedição com faturamento e estorno; trigger real de transferência compartilha sequência sem rebaixa' as resultado;