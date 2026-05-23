-- Unified data catalog ("cabinet" folders) for lookup-before-LLM chat routing.
-- Merges graph KB, INGREDIENT_DB keys, and manual seeds into canonical IDs + concern links.

create table if not exists public.canonical_ingredients (
  ingredient_id        text primary key,
  slug                 text not null unique,
  name_tr              text not null,
  name_en              text,
  kind                 text not null default 'active',
  folder_slug          text not null default 'ingredients/actives',
  aliases              jsonb not null default '[]'::jsonb,
  summary_tr           text,
  graph_ingredient_id  text references public.ingredient_profiles (ingredient_id) on delete set null,
  ingredient_db_key    text,
  sources              jsonb not null default '[]'::jsonb,
  updated_at           timestamptz not null default now()
);

create index if not exists idx_canonical_ingredients_kind
  on public.canonical_ingredients (kind);
create index if not exists idx_canonical_ingredients_graph
  on public.canonical_ingredients (graph_ingredient_id);

create table if not exists public.canonical_concerns (
  concern_id           text primary key,
  slug                 text not null unique,
  name_tr              text not null,
  name_en              text,
  body_area            text not null default 'face',
  folder_slug          text not null default 'concerns/skin',
  aliases              jsonb not null default '[]'::jsonb,
  graph_condition_id   text references public.skin_conditions (condition_id) on delete set null,
  updated_at           timestamptz not null default now()
);

create index if not exists idx_canonical_concerns_body
  on public.canonical_concerns (body_area);

create table if not exists public.ingredient_concern_links (
  link_id              text primary key,
  ingredient_id        text not null references public.canonical_ingredients (ingredient_id) on delete cascade,
  concern_id           text not null references public.canonical_concerns (concern_id) on delete cascade,
  effect_status        text not null default 'supports',
  priority             integer,
  notes_tr             text,
  min_conc_recommended text,
  max_conc_recommended text,
  time_of_day          text,
  source               text,
  confidence           double precision,
  updated_at           timestamptz not null default now(),
  constraint ingredient_concern_links_effect_chk
    check (effect_status in ('supports', 'neutral', 'avoid', 'insufficient_data')),
  constraint ingredient_concern_links_priority_chk
    check (priority is null or (priority between 1 and 4)),
  unique (ingredient_id, concern_id)
);

create index if not exists idx_icl_ingredient on public.ingredient_concern_links (ingredient_id);
create index if not exists idx_icl_concern on public.ingredient_concern_links (concern_id);

alter table public.canonical_ingredients enable row level security;
alter table public.canonical_concerns enable row level security;
alter table public.ingredient_concern_links enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'canonical_ingredients'
      and policyname = 'data_catalog_read_all'
  ) then
    create policy data_catalog_read_all on public.canonical_ingredients
      for select to anon, authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'canonical_concerns'
      and policyname = 'data_catalog_read_all'
  ) then
    create policy data_catalog_read_all on public.canonical_concerns
      for select to anon, authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'ingredient_concern_links'
      and policyname = 'data_catalog_read_all'
  ) then
    create policy data_catalog_read_all on public.ingredient_concern_links
      for select to anon, authenticated using (true);
  end if;
end $$;
