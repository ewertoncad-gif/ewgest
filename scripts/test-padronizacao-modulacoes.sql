-- Casos do erro observado: reuso do ID -03, regra exata e rollback.
DO $$
DECLARE
 emp constant uuid:='10000000-0000-0000-0000-000000000001';
 outra constant uuid:='10000000-0000-0000-0000-000000000002';
 t constant uuid:='20000000-0000-0000-0000-000000000001';
 m constant uuid:='30000000-0000-0000-0000-000000000003';
 e1 constant uuid:='40000000-0000-0000-0000-000000000001';
 e2 constant uuid:='40000000-0000-0000-0000-000000000002';
 e3 constant uuid:='40000000-0000-0000-0000-000000000003';
 e4 constant uuid:='40000000-0000-0000-0000-000000000004';
 e5 constant uuid:='40000000-0000-0000-0000-000000000005';
 obra constant uuid:='50000000-0000-0000-0000-000000000001';
 antiga constant text:='GRADIL 6 MODULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
 mestre constant text:='GUARDA CORPO - 8 MÓDULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
 oficial constant text:='GUARDA CORPO - 6 MÓDULO(S) - COM VIDRO - UNIVERSAL - HYDRO';
 r jsonb; v uuid; m4 uuid; n integer;
BEGIN
 PERFORM set_config('test.uid','60000000-0000-0000-0000-000000000001',true);
 IF ew_tipologias_interna.descricao_padronizada(mestre,6) IS DISTINCT FROM oficial OR ew_tipologias_interna.modulos_explicitos('2 MODULOS - 3 MÓDULOS') IS NOT NULL OR ew_tipologias_interna.modulos_explicitos('JANELA 2 FOLHAS') IS NOT NULL THEN RAISE EXCEPTION 'parser'; END IF;
 INSERT INTO public.tipologias VALUES(t,emp,'UNIV-R08-GRADN00',mestre,NULL,false);
 INSERT INTO public.tipologias_modulacoes(id,empresa_id,tipologia_principal_id,descricao,quantidade_modulos) VALUES(m,emp,t,antiga,6);
 INSERT INTO public.esquadrias VALUES(e1,emp,obra,antiga,6,t,m),(e2,emp,obra,antiga,6,NULL,NULL),(e3,emp,obra,'GRADIL 4 MODULO(S)',4,NULL,NULL),(e4,emp,obra,antiga,6,NULL,NULL),(e5,outra,obra,antiga,6,NULL,NULL);
 INSERT INTO public.classificacoes_tipologias_auditoria VALUES(emp,m,antiga);
 BEGIN
  PERFORM public.ew_resolver_modulacao_padronizada(e2,t,m,oficial,6,false,true);
  RAISE EXCEPTION 'FALHOU: aceitou sem confirmação';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'FALHOU:%' THEN RAISE; END IF; END;
 IF (SELECT descricao FROM public.tipologias_modulacoes WHERE id=m)<>antiga THEN RAISE EXCEPTION 'mudou sem autorização'; END IF;
 r:=public.ew_resolver_modulacao_padronizada(e2,t,m,oficial,6,true,true);
 IF r->>'modulacao_id' IS DISTINCT FROM m::text OR r->>'modulacao_padronizada' IS DISTINCT FROM 'true' OR r->>'regra_autorizada' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'reuso/regra falhou: %',r; END IF;
 IF (SELECT count(*) FROM public.tipologias_modulacoes)<>1 OR (SELECT descricao FROM public.tipologias_modulacoes WHERE id=m)<>oficial THEN RAISE EXCEPTION 'duplicou ou não padronizou'; END IF;
 IF EXISTS(SELECT 1 FROM public.esquadrias WHERE id IN(e1,e2) AND (modulacao_id IS DISTINCT FROM m OR descricao<>antiga)) THEN RAISE EXCEPTION 'histórico alterado'; END IF;
 IF (SELECT count(*) FROM ew_tipologias_interna.padronizacoes_modulacoes WHERE modulacao_id=m AND descricao_anterior=antiga AND descricao_nova=oficial)<>1 THEN RAISE EXCEPTION 'sem auditoria'; END IF;
 v:=public.ew_buscar_regra_cem(emp,antiga,6);
 IF v IS NULL OR public.ew_buscar_regra_cem(emp,antiga,7) IS NOT NULL THEN RAISE EXCEPTION 'regra futura inválida'; END IF;
 r:=public.ew_resolver_modulacao_padronizada(e4,t,m,oficial,6,true,true);
 IF r->>'modulacao_padronizada'<>'false' OR r->>'regra_autorizada'<>'true' THEN RAISE EXCEPTION 'reuso repetido'; END IF;
 -- Variação incompatível com origem exata: erro atômico, não cria por quantidade.
 INSERT INTO public.tipologias_modulacoes(empresa_id,tipologia_principal_id,descricao,quantidade_modulos) VALUES(emp,t,'OUTRO 4 MODULOS - SEM VIDRO',4) RETURNING id INTO m4;
 BEGIN
  PERFORM public.ew_resolver_modulacao_padronizada(e3,t,NULL,replace(mestre,'8 MÓDULO','4 MÓDULO'),4,true,false);
  RAISE EXCEPTION 'FALHOU: criou duplicidade';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'FALHOU:%' THEN RAISE; END IF; END;
 IF (SELECT count(*) FROM public.tipologias_modulacoes)<>2 OR (SELECT modulacao_id FROM public.esquadrias WHERE id=e3) IS NOT NULL THEN RAISE EXCEPTION 'rollback falhou'; END IF;
 BEGIN
  PERFORM public.ew_resolver_modulacao_padronizada(e5,t,m,oficial,6,true,true);
  RAISE EXCEPTION 'FALHOU: outra empresa';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'FALHOU:%' THEN RAISE; END IF; END;
 IF (SELECT modulacao_id FROM public.esquadrias WHERE id=e5) IS NOT NULL THEN RAISE EXCEPTION 'isolamento falhou'; END IF;
 RAISE NOTICE 'Padronização, reconhecimento futuro, auditoria, histórico, duplicidade e isolamento aprovados.';
END $$;
