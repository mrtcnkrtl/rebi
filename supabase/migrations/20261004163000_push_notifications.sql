-- Hatırlatıcıları sunucudan gönderebilmek için cihaz kayıtları ve
-- gönderim defteri. Defter aynı hatırlatıcının iki kez gitmesini engeller.

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null unique,
  platform text not null,
  -- Hatırlatıcı saatleri yerel duvar saatidir; cihazın UTC farkı burada tutulur.
  utc_offset_minutes integer not null default 0,
  locale text,
  app_version text,
  push_enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint device_tokens_platform_chk check (platform in ('ios', 'android', 'web')),
  constraint device_tokens_offset_chk check (utc_offset_minutes between -840 and 840)
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);
create index if not exists device_tokens_enabled_seen_idx
  on public.device_tokens (push_enabled, last_seen_at desc);

alter table public.device_tokens enable row level security;

-- Yazma yalnızca backend'e (service_role) ait; kullanıcı kendi cihazlarını
-- görebilir ve kaldırabilir.
drop policy if exists "Users can view own device_tokens" on public.device_tokens;
create policy "Users can view own device_tokens"
  on public.device_tokens for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own device_tokens" on public.device_tokens;
create policy "Users can delete own device_tokens"
  on public.device_tokens for delete
  to authenticated
  using (auth.uid() = user_id);

comment on table public.device_tokens is
  'Rebi: push bildirim cihaz kayıtları (backend yazar).';

create table if not exists public.push_sends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  reminder_id text not null,
  log_date date not null,
  -- Tekrarlayan hatırlatıcılarda pencere içindeki gönderim saati (örn. "13:00").
  slot text not null,
  sent_at timestamptz not null default now(),
  unique (user_id, reminder_id, log_date, slot)
);

create index if not exists push_sends_log_date_idx
  on public.push_sends (log_date);

alter table public.push_sends enable row level security;

-- Politika tanımlanmaz: defter yalnızca backend'i ilgilendirir.
comment on table public.push_sends is
  'Rebi: gönderilen hatırlatıcı defteri (aynı hatırlatıcı tekrar gönderilmesin).';

create or replace function public.purge_expired_rebi_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_intro integer := 0;
  n_events integer := 0;
  n_logs integer := 0;
  n_routines integer := 0;
  n_assessments integer := 0;
  n_chat integer := 0;
  n_devices integer := 0;
  n_sends integer := 0;
begin
  delete from public.intro_seen_ips
  where seen_at < now() - interval '180 days';
  get diagnostics n_intro = row_count;

  delete from public.daily_events
  where event_time < now() - interval '400 days';
  get diagnostics n_events = row_count;

  delete from public.daily_logs
  where log_date < current_date - 730;
  get diagnostics n_logs = row_count;

  delete from public.routines
  where is_active is false
    and created_at < now() - interval '730 days';
  get diagnostics n_routines = row_count;

  delete from public.assessments a
  where a.created_at < now() - interval '730 days'
    and not exists (
      select 1
      from public.routines r
      where r.assessment_id = a.id
    );
  get diagnostics n_assessments = row_count;

  delete from public.chat_history
  where created_at < now() - interval '365 days';
  get diagnostics n_chat = row_count;

  delete from public.device_tokens
  where last_seen_at < now() - interval '180 days';
  get diagnostics n_devices = row_count;

  delete from public.push_sends
  where log_date < current_date - 30;
  get diagnostics n_sends = row_count;

  return jsonb_build_object(
    'intro_seen_ips', n_intro,
    'daily_events', n_events,
    'daily_logs', n_logs,
    'inactive_routines', n_routines,
    'assessments', n_assessments,
    'chat_history', n_chat,
    'device_tokens', n_devices,
    'push_sends', n_sends
  );
end;
$$;

revoke all on function public.purge_expired_rebi_data() from public;
revoke all on function public.purge_expired_rebi_data() from anon;
revoke all on function public.purge_expired_rebi_data() from authenticated;
grant execute on function public.purge_expired_rebi_data() to service_role;

comment on function public.purge_expired_rebi_data() is
  'Rebi retention: intro 180g, daily events 400g, chat 365g, push defteri 30g, atıl cihaz 180g, daily logs and unused historical records 730g.';
