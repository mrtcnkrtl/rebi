-- =============================================
-- REBI: Eksik tabloları oluştur
-- Bu SQL'i Supabase Dashboard -> SQL Editor'de çalıştır:
-- https://supabase.com/dashboard/project/eulcargzcatxdbjevkpm/sql/new
-- =============================================

-- 1. Profiles tablosu
CREATE TABLE IF NOT EXISTS public.profiles (
    id TEXT PRIMARY KEY,
    full_name TEXT,
    skin_type TEXT,
    age INTEGER,
    gender TEXT,
    city TEXT,
    location_lat DOUBLE PRECISION,
    location_lon DOUBLE PRECISION,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Assessments tablosu
CREATE TABLE IF NOT EXISTS public.assessments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    concern TEXT NOT NULL,
    severity_score INTEGER,
    lifestyle_data JSONB DEFAULT '{}'::jsonb,
    photo_url TEXT,
    ai_analysis TEXT,
    weather_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Routines tablosu
CREATE TABLE IF NOT EXISTS public.routines (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    assessment_id TEXT,
    active_routine JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Eski metadata'sız verileri temizle (duplike kayıtlar)
DELETE FROM public.knowledge_base WHERE metadata->>'kategori' IS NULL;

-- 5. Indeksler
CREATE INDEX IF NOT EXISTS idx_assessments_user ON public.assessments(user_id);
CREATE INDEX IF NOT EXISTS idx_routines_user ON public.routines(user_id);
CREATE INDEX IF NOT EXISTS idx_routines_active ON public.routines(user_id, is_active);

-- 6. Knowledge base metadata indeksi (hızlı filtreleme için)
CREATE INDEX IF NOT EXISTS idx_kb_kategori ON public.knowledge_base USING gin (metadata jsonb_path_ops);
