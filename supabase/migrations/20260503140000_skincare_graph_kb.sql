-- Rebi GraphRAG skincare catalog (from rebi_skincare_graph_kb.xlsx SQL_schema sheet).
-- Global read-only reference tables for chat evidence; no pgvector here.

-- ================================================
-- ingredient_profiles
-- ================================================
create table if not exists public.ingredient_profiles (
  ingredient_id       text primary key,
  ingredient_tr       text not null,
  ingredient_en       text,
  category            text,
  min_conc_pct        double precision,
  max_conc_pct        double precision,
  effective_conc_pct  double precision,
  ph_min              double precision,
  ph_max              double precision,
  solubility          text,
  penetration         text,
  skin_type_suitable  text,
  pregnancy_safe      boolean,
  evidence_level      text,
  pubmed_source       text,
  updated_at          timestamptz not null default now()
);

create index if not exists idx_ingredient_profiles_tr_lower
  on public.ingredient_profiles (lower(ingredient_tr));
create index if not exists idx_ingredient_profiles_en_lower
  on public.ingredient_profiles (lower(ingredient_en));

-- ================================================
-- skin_conditions
-- ================================================
create table if not exists public.skin_conditions (
  condition_id     text primary key,
  condition_tr     text not null,
  condition_en     text,
  category         text,
  description_tr   text,
  icd10_code       text,
  severity_scale   text,
  affected_layer   text,
  trigger_factors  text,
  evidence_notes   text,
  updated_at       timestamptz not null default now()
);

create index if not exists idx_skin_conditions_tr_lower
  on public.skin_conditions (lower(condition_tr));
create index if not exists idx_skin_conditions_en_lower
  on public.skin_conditions (lower(condition_en));

-- ================================================
-- ingredient_relationships
-- ================================================
create table if not exists public.ingredient_relationships (
  relation_id      text primary key,
  entity_a_id      text,
  entity_a_tr      text,
  relation_type    text not null,
  entity_b_id      text,
  entity_b_tr      text,
  strength         double precision,
  direction        text,
  condition_note   text,
  safety_critical  boolean,
  evidence_level   text,
  pubmed_ref       text,
  updated_at       timestamptz not null default now(),
  constraint ingredient_relationships_strength_chk
    check (strength is null or (strength >= 0 and strength <= 1))
);

create index if not exists idx_rel_entity_a on public.ingredient_relationships (entity_a_id);
create index if not exists idx_rel_entity_b on public.ingredient_relationships (entity_b_id);
create index if not exists idx_rel_type on public.ingredient_relationships (relation_type);

-- ================================================
-- condition_ingredient_map
-- ================================================
create table if not exists public.condition_ingredient_map (
  map_id                 text primary key,
  condition_id           text references public.skin_conditions (condition_id) on delete cascade,
  condition_tr           text,
  ingredient_id          text references public.ingredient_profiles (ingredient_id) on delete cascade,
  ingredient_tr          text,
  priority               integer,
  use_case               text,
  min_conc_recommended   text,
  max_conc_recommended   text,
  time_of_day            text,
  notes_tr               text,
  updated_at             timestamptz not null default now(),
  constraint condition_ingredient_map_priority_chk
    check (priority is null or (priority between 1 and 4))
);

create index if not exists idx_cim_condition on public.condition_ingredient_map (condition_id);
create index if not exists idx_cim_ingredient on public.condition_ingredient_map (ingredient_id);

-- ================================================
-- safety_rules
-- ================================================
create table if not exists public.safety_rules (
  rule_id                      text primary key,
  rule_category                text,
  trigger_condition            text not null,
  blocked_ingredient           text,
  safe_alternative             text,
  severity                     text,
  user_message_tr              text,
  evidence                     text,
  always_refer_dermatologist   boolean,
  pubmed_ref                   text,
  updated_at                   timestamptz not null default now(),
  constraint safety_rules_severity_chk
    check (
      severity is null
      or severity in ('KRİTİK', 'YÜKSEK', 'ORTA', 'DÜŞÜK')
    )
);

create index if not exists idx_safety_severity on public.safety_rules (severity);

-- RLS: catalog readable by API clients if needed; no per-user rows.
alter table public.ingredient_profiles enable row level security;
alter table public.skin_conditions enable row level security;
alter table public.ingredient_relationships enable row level security;
alter table public.condition_ingredient_map enable row level security;
alter table public.safety_rules enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ingredient_profiles' and policyname = 'skincare_graph_kb_read_all'
  ) then
    create policy skincare_graph_kb_read_all on public.ingredient_profiles
      for select to anon, authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'skin_conditions' and policyname = 'skincare_graph_kb_read_all'
  ) then
    create policy skincare_graph_kb_read_all on public.skin_conditions
      for select to anon, authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ingredient_relationships' and policyname = 'skincare_graph_kb_read_all'
  ) then
    create policy skincare_graph_kb_read_all on public.ingredient_relationships
      for select to anon, authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'condition_ingredient_map' and policyname = 'skincare_graph_kb_read_all'
  ) then
    create policy skincare_graph_kb_read_all on public.condition_ingredient_map
      for select to anon, authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'safety_rules' and policyname = 'skincare_graph_kb_read_all'
  ) then
    create policy skincare_graph_kb_read_all on public.safety_rules
      for select to anon, authenticated using (true);
  end if;
end $$;
