-- Compatibilidade transitória do banco de restauração; executar apenas com rollback.
CREATE TABLE IF NOT EXISTS public.ew_obra_faturamentos_itens(id uuid primary key default gen_random_uuid(),faturamento_id uuid not null,empresa_id uuid not null,esquadria_id uuid not null,quantidade numeric(14,6) not null,valor_unitario numeric(14,4) not null,valor_total numeric(14,2) not null);
CREATE TABLE IF NOT EXISTS public.esquadrias_saida_config(esquadria_id uuid primary key,folhas_por_unidade integer not null);
ALTER TABLE public.ew_obra_faturamentos ADD COLUMN IF NOT EXISTS data_faturamento date, ADD COLUMN IF NOT EXISTS numero_documento text, ADD COLUMN IF NOT EXISTS observacoes text, ADD COLUMN IF NOT EXISTS criado_por uuid, ADD COLUMN IF NOT EXISTS operacao_id uuid;
DO $t$ DECLARE u uuid;e uuid;o uuid;a uuid;s uuid;rom uuid;fat uuid;r jsonb; BEGIN
SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE M2 FAT','TESTE-M2-4624') RETURNING id INTO o;
INSERT INTO public.esquadrias(empresa_id,obra_id,codigo,descricao,largura_mm,altura_mm,quantidade,qtd_liberada) VALUES(e,o,'EA1','JANELA',1200,1000,5,2) RETURNING id INTO a;
INSERT INTO public.ew_obra_orcamento(empresa_id,obra_id,valor_total,aluminio,acessorios,vidros,outros,fabricacao,instalacao,criado_por) VALUES(e,o,1000,0,0,0,0,1000,0,u);
INSERT INTO public.saidas_producao(esquadria_id,tipo,quantidade) VALUES(a,'completo',2) RETURNING id INTO s;
INSERT INTO public.romaneios(empresa_id,obra_id,numero,chave_operacao,data_saida,motorista,placa,criado_por) VALUES(e,o,'RMTESTM2',gen_random_uuid(),current_date,'TESTE','ABC1234',u) RETURNING id INTO rom;
INSERT INTO public.romaneios_itens(romaneio_id,sequencia,natureza,esquadria_id,saida_producao_id,descricao,quantidade,tipo_saida) VALUES(rom,1,'esquadria',a,s,'TESTE',2,'completo');
r:=public.ew_registrar_faturamento_financeiro(e,o,'fabricacao',current_date,'FAT M2 TESTE','',jsonb_build_array(jsonb_build_object('esquadria_id',a,'quantidade',1,'valor_unitario',180,'area_m2',1.2,'preco_m2',150)),gen_random_uuid(),false);
fat:=(r->>'id')::uuid;
IF (r->>'valor_total')::numeric<>180 OR NOT EXISTS(SELECT 1 FROM public.ew_obra_faturamentos_itens WHERE faturamento_id=fat AND area_m2=1.2 AND preco_m2=150 AND quantidade=1) THEN RAISE EXCEPTION 'Valor ou unidade incorretos: %',r; END IF;
BEGIN
 PERFORM public.ew_registrar_faturamento_financeiro(e,o,'fabricacao',current_date,'FAT INV','',jsonb_build_array(jsonb_build_object('esquadria_id',a,'quantidade',1,'valor_unitario',180,'area_m2',2.4,'preco_m2',150)),gen_random_uuid(),false);
 RAISE EXCEPTION 'FALHA: área indevida aceita';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Área ou preço por m² incompatível%' THEN RAISE; END IF; END;
r:=public.ew_registrar_faturamento_financeiro(e,o,'fabricacao',current_date,'FAT M2 FINAL','',jsonb_build_array(jsonb_build_object('esquadria_id',a,'quantidade',1,'valor_unitario',180,'area_m2',1.2,'preco_m2',150)),gen_random_uuid(),false);
IF (SELECT sum(valor_total) FROM public.ew_obra_faturamentos WHERE obra_id=o AND status='emitido')<>360 THEN RAISE EXCEPTION 'Total faturado incorreto'; END IF;
END $t$;