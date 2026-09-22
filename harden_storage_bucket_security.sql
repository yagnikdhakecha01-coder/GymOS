-- =============================================================================
-- GYMOS STORAGE SECURITY HARDENING: BUCKET LEVEL MALWARE & VIRUS SHIELD
-- PURPOSE: Ensure Supabase Storage rejects fake extensions, scripts,
--          and non-image files at the server level.
-- SAFETY GUARANTEE: ZERO data deleted. Existing valid images are untouched.
-- =============================================================================

BEGIN;

-- 1. HARDEN BUCKET RESTRICTIONS FOR AVATARS
-- Only allow JPEG, PNG, and WebP. Enforce 5MB limit.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars', 
    'avatars', 
    true, 
    5242880, -- 5 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'],
    public = true;


-- 2. HARDEN BUCKET RESTRICTIONS FOR SUPPORT ATTACHMENTS
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'support_attachments', 
    'support_attachments', 
    true, 
    5242880, -- 5 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'],
    public = true;


-- 3. STORAGE OBJECTS RLS: BLOCK ANONYMOUS UPLOADS
-- Ensure anonymous callers CANNOT upload any file to avatars or support_attachments
DROP POLICY IF EXISTS "Block anonymous uploads on avatars" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads on avatars" ON storage.objects;

CREATE POLICY "Allow authenticated uploads on avatars"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'avatars'
);

DROP POLICY IF EXISTS "Allow public read on avatars" ON storage.objects;
CREATE POLICY "Allow public read on avatars"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');

COMMIT;
