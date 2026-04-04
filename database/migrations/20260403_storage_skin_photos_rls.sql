-- REBI: skin-photos bucket — herkes okuyabilir (public URL), yükleme/silme yalnızca kendi klasörü
-- Klasör yapısı: {auth.uid()}/dosya.ext  (Analyze.jsx ile uyumlu)
-- Backend service_role ile yapılan upload RLS'i bypass eder.

DROP POLICY IF EXISTS "skin_photos_public_read" ON storage.objects;
CREATE POLICY "skin_photos_public_read"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'skin-photos');

DROP POLICY IF EXISTS "skin_photos_authenticated_insert_own" ON storage.objects;
CREATE POLICY "skin_photos_authenticated_insert_own"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'skin-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "skin_photos_authenticated_update_own" ON storage.objects;
CREATE POLICY "skin_photos_authenticated_update_own"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'skin-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
        bucket_id = 'skin-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "skin_photos_authenticated_delete_own" ON storage.objects;
CREATE POLICY "skin_photos_authenticated_delete_own"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'skin-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
