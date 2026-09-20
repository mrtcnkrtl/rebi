-- Güncel izin durumu değiştirilebilir; legal_consents ise tarihsel kanıt olarak
-- append-only kalır. Kullanıcı yazımı yalnızca doğrulanmış backend üzerinden.

create table if not exists public.privacy_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  ai_processing_allowed boolean not null default true,
  location_processing_allowed boolean not null default false,
  photo_processing_allowed boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.privacy_preferences enable row level security;

drop policy if exists "Users can view own privacy preferences" on public.privacy_preferences;
create policy "Users can view own privacy preferences"
  on public.privacy_preferences for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "skin_photos_authenticated_insert_own" on storage.objects;
create policy "skin_photos_authenticated_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1
      from public.privacy_preferences pp
      where pp.user_id = auth.uid()
        and pp.ai_processing_allowed is true
        and pp.photo_processing_allowed is true
    )
  );

comment on table public.privacy_preferences is
  'Current AI/location/photo permission state; updates are mediated by backend.';
