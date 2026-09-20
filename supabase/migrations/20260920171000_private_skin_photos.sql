-- Cilt fotoğrafları özel nitelikli veri olabilir: bucket private ve kullanıcı
-- yalnızca kendi UUID klasörüne erişebilir.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'skin-photos',
  'skin-photos',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "skin_photos_public_read" on storage.objects;
drop policy if exists "Anyone can view skin photos" on storage.objects;
drop policy if exists "Users can upload own photos" on storage.objects;
drop policy if exists "Users can delete own photos" on storage.objects;
drop policy if exists "skin_photos_authenticated_select_own" on storage.objects;
drop policy if exists "skin_photos_authenticated_insert_own" on storage.objects;
drop policy if exists "skin_photos_authenticated_update_own" on storage.objects;
drop policy if exists "skin_photos_authenticated_delete_own" on storage.objects;

create policy "skin_photos_authenticated_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "skin_photos_authenticated_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "skin_photos_authenticated_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "skin_photos_authenticated_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
