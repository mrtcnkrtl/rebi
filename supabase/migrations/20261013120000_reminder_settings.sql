-- Kullanıcının hatırlatıcı ayarları: gün düzeni (uyanma / uyku saati), su aralığı ve
-- kapatılan hatırlatıcı kategorileri. Sunucu hatırlatıcı pencerelerini buna göre kurar.

create table if not exists public.reminder_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.reminder_settings enable row level security;

-- Yazma yalnızca backend'e (service_role) ait; kullanıcı kendi ayarını görebilir ve silebilir.
drop policy if exists "Users can view own reminder_settings" on public.reminder_settings;
create policy "Users can view own reminder_settings"
  on public.reminder_settings for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own reminder_settings" on public.reminder_settings;
create policy "Users can delete own reminder_settings"
  on public.reminder_settings for delete
  to authenticated
  using (auth.uid() = user_id);

comment on table public.reminder_settings is
  'Rebi: kullanıcının hatırlatıcı ayarları (backend yazar).';
