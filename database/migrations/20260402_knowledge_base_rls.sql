-- REBI: knowledge_base — RLS açık, politika yok
-- PostgREST (anon/authenticated) ile doğrudan tablo erişimi kapanır.
-- Backend / ingest scriptleri service_role kullandığı için RLS'i bypass eder.

ALTER TABLE public.knowledge_base ENABLE ROW LEVEL SECURITY;
