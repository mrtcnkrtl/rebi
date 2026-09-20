-- v2: AI zorunlu; konum ve fotoğraf ayrı, isteğe bağlı izinler.

alter table public.legal_consents
  add column if not exists ai_processing_accepted boolean not null default false,
  add column if not exists location_processing_accepted boolean not null default false,
  add column if not exists photo_processing_accepted boolean not null default false;

-- Fotoğraf yükleme, kullanıcının güncel v2 fotoğraf izni olmadan yapılamaz.
drop policy if exists "skin_photos_authenticated_insert_own" on storage.objects;
create policy "skin_photos_authenticated_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'skin-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1
      from public.legal_consents lc
      where lc.user_id = auth.uid()
        and lc.document_version = 'v2'
        and lc.ai_processing_accepted is true
        and lc.photo_processing_accepted is true
    )
  );
