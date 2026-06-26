-- Self-organizing cabinet infra: tag every raw passage with its source kind and
-- the canonical ingredient/concern boxes it belongs to, so the "literature/"
-- section of each ingredient box can pull raw evidence across all sources.

alter table public.knowledge_chunks
  add column if not exists source_kind text;

alter table public.knowledge_chunks
  add column if not exists canonical_ingredient_ids text[] not null default '{}'::text[];

alter table public.knowledge_chunks
  add column if not exists canonical_concern_ids text[] not null default '{}'::text[];

-- Optional provenance for non-PDF sources (master_veri row / graph id / pdf page).
alter table public.knowledge_chunks
  add column if not exists source_ref text;

comment on column public.knowledge_chunks.source_kind is
  'graph | master_veri | pdf | chat_guide — origin of the raw passage';
comment on column public.knowledge_chunks.canonical_ingredient_ids is
  'canonical_ingredients.ingredient_id values this passage is evidence for';
comment on column public.knowledge_chunks.canonical_concern_ids is
  'canonical_concerns.concern_id values this passage is evidence for';

-- GIN indexes for "give me all raw passages in this ingredient/concern box".
create index if not exists knowledge_chunks_canon_ing_idx
  on public.knowledge_chunks using gin (canonical_ingredient_ids);
create index if not exists knowledge_chunks_canon_cnd_idx
  on public.knowledge_chunks using gin (canonical_concern_ids);
create index if not exists knowledge_chunks_source_kind_idx
  on public.knowledge_chunks (source_kind);
