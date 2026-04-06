-- Günlük mikro-olaylar (su, SPF yenileme, rutin adımı, foto meta, check-in geri bildirimi).
-- Supabase SQL Editor veya CLI ile uygulayın.

create table if not exists public.daily_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  event_time timestamptz not null default now(),
  log_date date not null,
  type text not null,
  payload jsonb not null default '{}'::jsonb,
  source text not null default 'mobile',
  created_at timestamptz not null default now()
);

create index if not exists daily_events_user_date_idx
  on public.daily_events (user_id, log_date);

create index if not exists daily_events_user_time_idx
  on public.daily_events (user_id, event_time desc);

alter table public.daily_events enable row level security;

-- Backend service_role RLS'yi bypass eder. Aşağıdakiler: doğrudan Supabase istemci (anon + kullanıcı JWT).
drop policy if exists "Users can view own daily_events" on public.daily_events;
create policy "Users can view own daily_events"
  on public.daily_events for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own daily_events" on public.daily_events;
create policy "Users can insert own daily_events"
  on public.daily_events for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own daily_events" on public.daily_events;
create policy "Users can delete own daily_events"
  on public.daily_events for delete
  using (auth.uid() = user_id);

comment on table public.daily_events is 'Rebi: gün içi tracking olayları (web/mobil ingest).';
