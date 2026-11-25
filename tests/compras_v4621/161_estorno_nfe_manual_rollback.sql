DO $t$ DECLARE u uuid;e uuid;o uuid;p uuid;v uuid;d uuid;i uuid;m uuid;rec uuid;rr uuid;op uuid:=gen_random_uuid();r jsonb; BEGIN
SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste',true);
INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE NF MANUAL','TESTE-NF-46297') RETURNING id INTO o;
INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por) VALUES(e,o,u);
INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-NF-MANUAL','Perfil teste','TESTE') RETURNING id INTO p;
INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(e,'AFOGADOS');
INSERT INTO public.ew_obra_despesas(empresa_id,obra_id,categoria,valor,origem,fornecedor,numero_documento,chave_nfe,status,observacoes,criado_por,aprovado_por,aprovado_em)
VALUES(e,o,'aluminio',300,'manual','TESTE','NF MANUAL TESTE 46297',NULL,'aprovada','',u,u,now()) RETURNING id INTO d;
FOR n IN 1..2 LOOP
 INSERT INTO public.ew_obra_despesas_itens(despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,valor_unitario,valor_total,perfil_id) VALUES(d,e,'P','Perfil','BARRA',1,150,150,p) RETURNING id INTO i;
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,o,v,4000+n*1000,'BARRA',1,'COMPRA',gen_random_uuid(),u,'AFOGADOS') RETURNING id INTO m;
 INSERT INTO public.ew_nfe_recebimentos(empresa_id,obra_id,despesa_item_id,variacao_id,comprimento_mm,unidade,quantidade,local_estoque,movimento_id,usuario_id) VALUES(e,o,i,v,4000+n*1000,'BARRA',1,'AFOGADOS',m,u) RETURNING id INTO rec;
 IF n=1 THEN rr:=rec; END IF;
END LOOP;
-- Bloqueio atômico: uma das duas entradas já consumida.
BEGIN
 INSERT INTO public.ew_estoque_obras_movimentos(empresa_id,obra_id,variacao_id,comprimento_mm,unidade,quantidade_delta,origem,operacao_id,usuario_id,local_estoque) VALUES(e,o,v,6000,'BARRA',-1,'SAIDA_MANUAL',gen_random_uuid(),u,'AFOGADOS');
 PERFORM public.ew_estornar_nfe_com_recebimentos(e,rr,'Teste bloqueio consumo',op);
 RAISE EXCEPTION 'FALHA: estorno de material consumido aceito';
EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Estorno bloqueado:%' THEN RAISE; END IF; END;
IF EXISTS(SELECT 1 FROM public.ew_nfe_recebimentos WHERE obra_id=o AND estornado_em IS NOT NULL) OR (SELECT status FROM public.ew_obra_despesas WHERE id=d)<>'aprovada' THEN RAISE EXCEPTION 'Estorno parcial indevido'; END IF;
r:=public.ew_estornar_nfe_com_recebimentos(e,rr,'Teste devolução integral',op);
IF (r->>'valor_restaurado')::numeric<>300 OR (r->>'recebimentos_estornados')::int<>2 OR (SELECT status FROM public.ew_obra_despesas WHERE id=d)<>'cancelada' OR (SELECT sum(quantidade_delta) FROM public.ew_estoque_obras_movimentos WHERE obra_id=o)<>0 THEN RAISE EXCEPTION 'Saldo financeiro ou estoque incorreto: %',r; END IF;
r:=public.ew_estornar_nfe_com_recebimentos(e,rr,'Teste devolução integral',op);
IF NOT (r->>'ja_estornado')::boolean THEN RAISE EXCEPTION 'Repetição indevida'; END IF;
END $t$;