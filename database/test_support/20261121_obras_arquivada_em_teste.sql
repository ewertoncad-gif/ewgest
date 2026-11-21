-- Apenas ambiente de homologação: campo arquivada_em ausente do snapshot antigo.
alter table public.obras add column if not exists arquivada_em timestamptz;