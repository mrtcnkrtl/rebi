-- Supabase security hardening for warnings:
-- - Function Search Path Mutable: public.match_knowledge_chunks, public.match_documents
-- - Extension in Public: vector
-- - Public Bucket Allows Listing: storage.skin-photos
--
-- NOTE: "Leaked Password Protection Disabled" is an Auth setting; enable in Supabase Dashboard.

-- 1) Move pgvector extension out of public schema (if present)
create schema if not exists extensions;
do $$
begin
  if exists (
    select 1
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'vector' and n.nspname = 'public'
  ) then
    execute 'alter extension vector set schema extensions';
  end if;
exception when insufficient_privilege then
  -- Some managed environments restrict this; keep best-effort.
  null;
end $$;

-- 2) Lock down function search_path
-- 2a) match_knowledge_chunks (latest signature with klass_topics)
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='match_knowledge_chunks'
  ) then
    execute 'alter function public.match_knowledge_chunks(uuid, vector, int, uuid, text[]) set search_path = public, extensions';
  end if;
exception when undefined_function then
  -- older signature may exist
  begin
    execute 'alter function public.match_knowledge_chunks(uuid, vector, int, uuid) set search_path = public, extensions';
  exception when undefined_function then
    null;
  end;
end $$;

-- 2b) match_documents (from database/schema.sql)
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='match_documents'
  ) then
    execute 'alter function public.match_documents(vector, int, jsonb) set search_path = public, extensions';
  end if;
exception when undefined_function then
  null;
end $$;

-- 3) Storage: prevent public listing on skin-photos bucket
-- Replace broad SELECT policy (TO public) with authenticated-only + own folder read.
drop policy if exists "skin_photos_public_read" on storage.objects;

drop policy if exists "skin_photos_authenticated_select_own" on storage.objects;
create policy "skin_photos_authenticated_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

