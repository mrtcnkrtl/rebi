-- Entity/ingredient index for knowledge chunks.
-- Goal: allow fast lookup by ingredient/extract/oil without scanning all chunks.

create extension if not exists pgcrypto;

create table if not exists public.knowledge_entities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  folder_id uuid references public.knowledge_folders(id) on delete cascade,
  name text not null,         -- canonical: "niacinamide"
  kind text not null default 'ingredient', -- ingredient|oil|extract|compound|other
  aliases jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, folder_id, name)
);

create table if not exists public.knowledge_chunk_entities (
  chunk_id uuid not null references public.knowledge_chunks(id) on delete cascade,
  entity_id uuid not null references public.knowledge_entities(id) on delete cascade,
  user_id uuid not null,
  folder_id uuid,
  created_at timestamptz not null default now(),
  primary key (chunk_id, entity_id)
);

create index if not exists knowledge_entities_lookup_idx
  on public.knowledge_entities (user_id, folder_id, name);

create index if not exists knowledge_chunk_entities_entity_idx
  on public.knowledge_chunk_entities (user_id, folder_id, entity_id);

alter table public.knowledge_entities enable row level security;
alter table public.knowledge_chunk_entities enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_entities' and policyname='knowledge_entities_select_own'
  ) then
    create policy knowledge_entities_select_own on public.knowledge_entities
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_entities' and policyname='knowledge_entities_insert_own'
  ) then
    create policy knowledge_entities_insert_own on public.knowledge_entities
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_entities' and policyname='knowledge_entities_update_own'
  ) then
    create policy knowledge_entities_update_own on public.knowledge_entities
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_entities' and policyname='knowledge_entities_delete_own'
  ) then
    create policy knowledge_entities_delete_own on public.knowledge_entities
      for delete using (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunk_entities' and policyname='knowledge_chunk_entities_select_own'
  ) then
    create policy knowledge_chunk_entities_select_own on public.knowledge_chunk_entities
      for select using (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunk_entities' and policyname='knowledge_chunk_entities_insert_own'
  ) then
    create policy knowledge_chunk_entities_insert_own on public.knowledge_chunk_entities
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='knowledge_chunk_entities' and policyname='knowledge_chunk_entities_delete_own'
  ) then
    create policy knowledge_chunk_entities_delete_own on public.knowledge_chunk_entities
      for delete using (auth.uid() = user_id);
  end if;
end $$;

