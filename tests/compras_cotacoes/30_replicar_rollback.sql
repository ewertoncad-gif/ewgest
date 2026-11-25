-- Restauração: base compras; cancelamentos até antes de cancelar cotação; agrupamento; replicação; fixture, dentro de BEGIN/ROLLBACK.
DO $t$
DECLARE u uuid;e uuid;o uuid;p uuid;v uuid;f uuid;f2 uuid;f3 uuid;s uuid;q uuid;r jsonb;it jsonb;blocked boolean;
BEGIN
 SELECT usuario_id,empresa_id INTO STRICT u,e FROM public.usuarios_empresas WHERE nivel_acesso=1 LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 INSERT INTO public.usuarios_login(usuario_id,empresa_id,perfil,nivel_acesso,nome,ativo) VALUES(u,e,'administrador',1,'Teste sintético',true);
 INSERT INTO public.ew_niveis_permissoes(empresa_id,nivel,chave,permitido)
 SELECT e,1,k,true FROM unnest(ARRAY['compras.solicitar','compras.consultar','compras.cotar','compras.consultar_valores','compras.replicar_cotacao']) k ON CONFLICT(empresa_id,nivel,chave) DO UPDATE SET permitido=true;
 INSERT INTO public.obras(empresa_id,nome,codigo) VALUES(e,'TESTE 88','TESTE-88-LOTE') RETURNING id INTO o;
 INSERT INTO public.ew_perfis(empresa_id,codigo,descricao,fabricante) VALUES(e,'TESTE-88-LOTE-P','Perfil','Teste') RETURNING id INTO p;
 INSERT INTO public.ew_materiais_variacoes(empresa_id,tipo,perfil_id,cor,acabamento) VALUES(e,'perfil',p,'NATURAL','NATURAL') RETURNING id INTO v;
 INSERT INTO public.ew_fornecedores(empresa_id,nome) VALUES(e,'Fornecedor teste lote A') RETURNING id INTO f;
 INSERT INTO public.ew_fornecedores(empresa_id,nome) VALUES(e,'Fornecedor teste lote B') RETURNING id INTO f2;
 INSERT INTO public.ew_fornecedores(empresa_id,nome,ativo) VALUES(e,'Fornecedor inativo lote',false) RETURNING id INTO f3;
 it:=jsonb_build_array(jsonb_build_object('chave','1','variacao_id',v,'quantidade',4,'unidade','BARRA','comprimento_mm',6000));
 r:=public.ew_compras_criar_solicitacao(e,o,null,it,'Teste',gen_random_uuid());s:=(r->>'id')::uuid;
 blocked:=false;BEGIN PERFORM public.ew_compras_replicar_cotacao(e,s,ARRAY[f,f3]);EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Fornecedor indisponível%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked OR (SELECT count(*) FROM ew_compras_interna.convites WHERE solicitacao_id=s)<>0 THEN RAISE EXCEPTION 'Lote inválido gravado';END IF;
 PERFORM public.ew_compras_replicar_cotacao(e,s,ARRAY[f,f2]);
 PERFORM public.ew_compras_replicar_cotacao(e,s,ARRAY[f2,f]);
 IF (SELECT count(*) FROM ew_compras_interna.convites WHERE solicitacao_id=s)<>2 THEN RAISE EXCEPTION 'duplicação convite';END IF;
 r:=public.ew_compras_convites_cotacao(e,s);
 IF (SELECT count(*) FROM jsonb_array_elements(r) x WHERE x->>'status'='AGUARDANDO_RETORNO')<>2 THEN RAISE EXCEPTION 'status incorreto %',r;END IF;
 r:=public.ew_compras_criar_cotacao(s,f,'[{"chave":"1","preco_unitario_centavos":12500}]',gen_random_uuid());q:=(r->>'id')::uuid;
 r:=public.ew_compras_convites_cotacao(e,s);
 IF (SELECT count(*) FROM jsonb_array_elements(r) x WHERE x->>'status'='RESPONDIDA')<>1 THEN RAISE EXCEPTION 'retorno incorreto %',r;END IF;
 IF (SELECT count(*) FROM public.ew_compras_solicitacoes WHERE obra_id=o)<>1 OR (SELECT (x.itens->0->>'quantidade')::numeric FROM public.ew_compras_solicitacoes x WHERE id=s)<>4 THEN RAISE EXCEPTION 'demanda duplicada';END IF;
END;$t$;
SELECT 'PASS: lote atômico, fornecedor inválido bloqueado, repetição sem duplicidade, resposta individual e demanda preservada' AS resultado;