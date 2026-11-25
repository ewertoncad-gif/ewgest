-- Executar na restauração com propostas base, conciliação NF, cancelamentos (até cancelar pedido), agrupamento e preços/compromissos em uma transação revertida.
DO $t$
DECLARE u uuid;e uuid;o uuid;p uuid;v uuid;f uuid;s uuid;q uuid;ped uuid;rec uuid;d uuid;di uuid;conc uuid;r jsonb;it jsonb;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_permissoes_catalogo(chave,grupo,descricao,ordem) VALUES('financeiro.consultar','Financeiro','Consultar',1) ON CONFLICT DO NOTHING;
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
 SELECT e,1,k,true FROM unnest(ARRAY['compras.solicitar','compras.consultar','compras.cotar','compras.pedir','compras.receber','compras.consultar_valores','compras.aprovar_pedido','compras.historico_precos','financeiro.consultar']) k ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE 88','TESTE-88-FIN') RETURNING id INTO o;
 INSERT INTO public.ew_estoques_locais(empresa_id,obra_id,criado_por) VALUES(e,o,u);
 INSERT INTO public.ew_locais_fisicos(empresa_id,nome) VALUES(e,'AFOGADOS') ON CONFLICT DO NOTHING;
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-88-FIN-P','Perfil','Teste') RETURNING id INTO p;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
 INSERT INTO public.ew_fornecedores(empresa_id,nome) VALUES(e,'Fornecedor teste 88') RETURNING id INTO f;
 it:=jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v,'quantidade',4,'unidade','BARRA','comprimento_mm',6000));
 r:=public.ew_compras_criar_solicitacao(e,o,null,it,'Teste',gen_random_uuid());s:=(r->>'id')::uuid;
 r:=public.ew_compras_criar_cotacao(s,f,'[{"chave":"1","preco_unitario_centavos":12500}]',gen_random_uuid());q:=(r->>'id')::uuid;
 IF jsonb_array_length(public.ew_compras_historico_precos(e,f,v,0))<>1 THEN RAISE EXCEPTION 'histórico ausente';END IF;
 IF jsonb_array_length(public.ew_compras_compromissos_obra(e,o))<>0 THEN RAISE EXCEPTION 'cotação consumiu orçamento';END IF;
 r:=public.ew_compras_criar_pedido(q,gen_random_uuid());ped:=(r->>'id')::uuid;
 r:=public.ew_compras_compromissos_obra(e,o);
 IF (r->0->>'comprometido_pendente_centavos')::numeric<>50000 OR (r->0->>'consumido_centavos')::numeric<>50000 THEN RAISE EXCEPTION 'compromisso incorreto %',r;END IF;
 r:=public.ew_compras_receber_pedido(ped,'AFOGADOS','[{"chave":"1","quantidade":2}]',gen_random_uuid());rec:=(r->>'id')::uuid;
 r:=public.ew_compras_compromissos_obra(e,o);
 IF (r->0->>'consumido_centavos')::numeric<>50000 THEN RAISE EXCEPTION 'recebimento duplicou gasto %',r;END IF;
 INSERT INTO public.ew_obra_despesas(empresa_id,obra_id,categoria,valor,origem,fornecedor,status,criado_por) VALUES(e,o,'aluminio',250,'manual','Fornecedor teste 88','aprovada',u) RETURNING id INTO d;
 INSERT INTO public.ew_obra_despesas_itens(despesa_id,empresa_id,codigo_fornecedor,descricao,unidade,quantidade,valor_unitario,valor_total,perfil_id) VALUES(d,e,'TESTE-88-FIN-P','Perfil','BARRA',2,125,250,p) RETURNING id INTO di;
 INSERT INTO public.ew_compras_nfe_conciliacoes(empresa_id,pedido_id,despesa_id,operacao_id,criado_por) VALUES(e,ped,d,gen_random_uuid(),u) RETURNING id INTO conc;
 INSERT INTO public.ew_compras_nfe_vinculos(empresa_id,conciliacao_id,despesa_item_id,recebimento_id,chave,quantidade_nota,quantidade_fisica,unidade_nota) VALUES(e,conc,di,rec,'1',2,2,'BARRA');
 r:=public.ew_compras_compromissos_obra(e,o);
 IF (r->0->>'realizado_centavos')::numeric<>25000 OR (r->0->>'comprometido_pendente_centavos')::numeric<>25000 OR (r->0->>'consumido_centavos')::numeric<>50000 THEN RAISE EXCEPTION 'conciliação incorreta %',r;END IF;
END;$t$;
SELECT 'PASS: cotação não compromete; pedido R$500; recebimento parcial mantém R$500; NF R$250 conciliada mantém R$500 total' AS resultado;