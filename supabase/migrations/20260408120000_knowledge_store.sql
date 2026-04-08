-- Knowledge store (folders -> documents -> chunks) with pgvector embeddings.
-- Designed for scientific Q/A RAG.

-- Extensions
create extension if not exists vector;
create extension if not exists pgcrypto;

-- Folders / collections
create table if not exists public.knowledge_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  slug text not null,
  title text not null,
  description text,
  created_at timestamptz not null default now(),
  unique (user_id, slug)
);

-- Documents
create table if not exists public.knowledge_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  folder_id uuid references public.knowledge_folders(id) on delete set null,
  source_url text,
  source_type text, -- pdf|html|md|txt|other
  title text not null,
  author text,
  published_year int,
  tags jsonb not null default '[]'::jsonb,
  raw_text text, -- optional (can be large)
  created_at timestamptz not null default now()
);

-- Chunks
create table if not exists public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  folder_id uuid references public.knowledge_folders(id) on delete set null,
  document_id uuid references public.knowledge_documents(id) on delete cascade,
  chunk_index int not null,
  chunk_text text not null,
  -- Google text-embedding-004 is 768 dims
  embedding vector(768),
  -- classification / debug
  klass jsonb not null default '{}'::jsonb,
  embed_model text,
  embed_ok boolean not null default false,
  embed_error text,
  created_at timestamptz not null default now(),
  unique (document_id, chunk_index)
);

-- Vector index (ivfflat) - requires analyze and enough rows to be effective.
-- Cosine distance via vector_cosine_ops
create index if not exists knowledge_chunks_embedding_idx
  on public.knowledge_chunks using ivfflat (embedding vector_cosine_ops) with (lists = 100);

create index if not exists knowledge_chunks_user_folder_idx
  on public.knowledge_chunks (user_id, folder_id, document_id, chunk_index);

alter table public.knowledge_folders enable row level security;
alter table public.knowledge_documents enable row level security;
alter table public.knowledge_chunks enable row level security;

-- Similarity search helper (used by backend)
-- NOTE: This uses cosine distance operator (<=>). Similarity score returned as 1 - distance.
create or replace function public.match_knowledge_chunks(
  p_user_id uuid,
  p_query_embedding vector(768),
  p_match_count int default 8,
  p_folder_id uuid default null
)
returns table (
  chunk_id uuid,
  document_id uuid,
  chunk_text text,
  similarity float
)
language sql
stable
as $$
  select
    c.id as chunk_id,
    c.document_id,
    c.chunk_text,
    (1 - (c.embedding <=> p_query_embedding))::float as similarity
  from public.knowledge_chunks c
  where c.user_id = p_user_id
    and c.embed_ok is true
    and c.embedding is not null
    and (p_folder_id is null or c.folder_id = p_folder_id)
  order by c.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$$;

-- RLS policies: user can only access own rows
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_folders' and policyname='knowledge_folders_select_own'
  ) then
    create policy knowledge_folders_select_own on public.knowledge_folders
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_folders' and policyname='knowledge_folders_insert_own'
  ) then
    create policy knowledge_folders_insert_own on public.knowledge_folders
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_folders' and policyname='knowledge_folders_update_own'
  ) then
    create policy knowledge_folders_update_own on public.knowledge_folders
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_folders' and policyname='knowledge_folders_delete_own'
  ) then
    create policy knowledge_folders_delete_own on public.knowledge_folders
      for delete using (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_documents' and policyname='knowledge_documents_select_own'
  ) then
    create policy knowledge_documents_select_own on public.knowledge_documents
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_documents' and policyname='knowledge_documents_insert_own'
  ) then
    create policy knowledge_documents_insert_own on public.knowledge_documents
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_documents' and policyname='knowledge_documents_update_own'
  ) then
    create policy knowledge_documents_update_own on public.knowledge_documents
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_documents' and policyname='knowledge_documents_delete_own'
  ) then
    create policy knowledge_documents_delete_own on public.knowledge_documents
      for delete using (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunks' and policyname='knowledge_chunks_select_own'
  ) then
    create policy knowledge_chunks_select_own on public.knowledge_chunks
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunks' and policyname='knowledge_chunks_insert_own'
  ) then
    create policy knowledge_chunks_insert_own on public.knowledge_chunks
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunks' and policyname='knowledge_chunks_update_own'
  ) then
    create policy knowledge_chunks_update_own on public.knowledge_chunks
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunks' and policyname='knowledge_chunks_delete_own'
  ) then
    create policy knowledge_chunks_delete_own on public.knowledge_chunks
      for delete using (auth.uid() = user_id);
  end if;
end $$;

