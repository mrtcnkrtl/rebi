-- Core personal-data schema. supabase/migrations is the authoritative migration
-- source; legacy database/*.sql files are documentation only.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  skin_type text,
  age integer,
  gender text,
  city text,
  location_lat double precision,
  location_lon double precision,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assessments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  concern text not null,
  severity_score integer,
  lifestyle_data jsonb not null default '{}'::jsonb,
  photo_url text,
  ai_analysis text,
  weather_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  assessment_id uuid references public.assessments(id) on delete set null,
  active_routine jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.daily_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null default current_date,
  sleep_hours double precision,
  stress_level integer,
  skin_feeling text,
  applied_routine boolean not null default false,
  notes text,
  weather_data jsonb not null default '{}'::jsonb,
  risk_score integer,
  adaptation jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, log_date)
);

create index if not exists assessments_user_created_idx
  on public.assessments (user_id, created_at desc);
create index if not exists routines_user_active_idx
  on public.routines (user_id, is_active);
create index if not exists daily_logs_user_date_idx
  on public.daily_logs (user_id, log_date desc);

alter table public.profiles enable row level security;
alter table public.assessments enable row level security;
alter table public.routines enable row level security;
alter table public.daily_logs enable row level security;

drop policy if exists "Users can view own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can delete own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles
  for select to authenticated using (auth.uid()::text = id::text);
create policy "Users can insert own profile" on public.profiles
  for insert to authenticated with check (auth.uid()::text = id::text);
create policy "Users can update own profile" on public.profiles
  for update to authenticated
  using (auth.uid()::text = id::text)
  with check (auth.uid()::text = id::text);
create policy "Users can delete own profile" on public.profiles
  for delete to authenticated using (auth.uid()::text = id::text);

drop policy if exists "Users can view own assessments" on public.assessments;
drop policy if exists "Users can insert own assessments" on public.assessments;
drop policy if exists "Users can update own assessments" on public.assessments;
drop policy if exists "Users can delete own assessments" on public.assessments;
create policy "Users can view own assessments" on public.assessments
  for select to authenticated using (auth.uid()::text = user_id::text);
create policy "Users can insert own assessments" on public.assessments
  for insert to authenticated with check (auth.uid()::text = user_id::text);
create policy "Users can update own assessments" on public.assessments
  for update to authenticated
  using (auth.uid()::text = user_id::text)
  with check (auth.uid()::text = user_id::text);
create policy "Users can delete own assessments" on public.assessments
  for delete to authenticated using (auth.uid()::text = user_id::text);

drop policy if exists "Users can view own routines" on public.routines;
drop policy if exists "Users can insert own routines" on public.routines;
drop policy if exists "Users can update own routines" on public.routines;
drop policy if exists "Users can delete own routines" on public.routines;
create policy "Users can view own routines" on public.routines
  for select to authenticated using (auth.uid()::text = user_id::text);
create policy "Users can insert own routines" on public.routines
  for insert to authenticated with check (auth.uid()::text = user_id::text);
create policy "Users can update own routines" on public.routines
  for update to authenticated
  using (auth.uid()::text = user_id::text)
  with check (auth.uid()::text = user_id::text);
create policy "Users can delete own routines" on public.routines
  for delete to authenticated using (auth.uid()::text = user_id::text);

drop policy if exists "Users can view own daily_logs" on public.daily_logs;
drop policy if exists "Users can insert own daily_logs" on public.daily_logs;
drop policy if exists "Users can update own daily_logs" on public.daily_logs;
drop policy if exists "Users can delete own daily_logs" on public.daily_logs;
create policy "Users can view own daily_logs" on public.daily_logs
  for select to authenticated using (auth.uid()::text = user_id::text);
create policy "Users can insert own daily_logs" on public.daily_logs
  for insert to authenticated with check (auth.uid()::text = user_id::text);
create policy "Users can update own daily_logs" on public.daily_logs
  for update to authenticated
  using (auth.uid()::text = user_id::text)
  with check (auth.uid()::text = user_id::text);
create policy "Users can delete own daily_logs" on public.daily_logs
  for delete to authenticated using (auth.uid()::text = user_id::text);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
