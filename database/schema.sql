-- ============================================
-- REBI: Holistic Skincare AI Platform
-- Supabase Database Schema
-- ============================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- 2. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    full_name TEXT,
    skin_type TEXT CHECK (skin_type IN ('oily', 'dry', 'combination', 'sensitive', 'normal')),
    age INTEGER CHECK (age >= 10 AND age <= 120),
    gender TEXT CHECK (gender IN ('male', 'female', 'other')),
    city TEXT,
    location_lat DOUBLE PRECISION,
    location_lon DOUBLE PRECISION,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- 3. Assessments Table
CREATE TABLE IF NOT EXISTS public.assessments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    concern TEXT NOT NULL CHECK (concern IN ('acne', 'aging', 'dryness', 'pigmentation', 'sensitivity')),
    severity_score INTEGER CHECK (severity_score >= 1 AND severity_score <= 10),
    lifestyle_data JSONB DEFAULT '{}'::jsonb,
    -- Expected structure:
    -- {
    --   "water_intake": 2.0,       -- liters per day
    --   "sleep_hours": 7,          -- hours per night
    --   "stress_score": 5,         -- PSS-4 calculated score (0-16)
    --   "smoking": false,
    --   "alcohol": false
    -- }
    photo_url TEXT,
    ai_analysis TEXT,
    weather_data JSONB DEFAULT '{}'::jsonb,
    -- Expected structure:
    -- {
    --   "humidity": 65,
    --   "uv_index": 6,
    --   "temperature": 22,
    --   "description": "Partly cloudy"
    -- }
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on assessments
ALTER TABLE public.assessments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own assessments"
    ON public.assessments FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own assessments"
    ON public.assessments FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own assessments"
    ON public.assessments FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 4. Knowledge Base Table (for RAG)
CREATE TABLE IF NOT EXISTS public.knowledge_base (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    -- Expected structure:
    -- {
    --   "source": "dermatology_guide.pdf",
    --   "topic": "acne",
    --   "page": 15,
    --   "chunk_index": 3
    -- }
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create an index for fast vector similarity search
CREATE INDEX IF NOT EXISTS knowledge_base_embedding_idx
    ON public.knowledge_base
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

ALTER TABLE public.knowledge_base ENABLE ROW LEVEL SECURITY;

-- 5. Routines Table
CREATE TABLE IF NOT EXISTS public.routines (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    assessment_id UUID REFERENCES public.assessments(id) ON DELETE SET NULL,
    active_routine JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- Expected structure:
    -- [
    --   {
    --     "time": "Sabah",
    --     "category": "Koruma",
    --     "icon": "🛡️",
    --     "action": "Güneş Kremi",
    --     "detail": "Bugün UV yüksek (6), sakın atlama."
    --   }
    -- ]
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on routines
ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own routines"
    ON public.routines FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own routines"
    ON public.routines FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own routines"
    ON public.routines FOR UPDATE
    USING (auth.uid() = user_id);

-- 6. Daily Logs Table (Günlük Check-in Verisi)
CREATE TABLE IF NOT EXISTS public.daily_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    log_date DATE NOT NULL DEFAULT CURRENT_DATE,
    sleep_hours FLOAT,
    stress_level INT CHECK (stress_level >= 1 AND stress_level <= 5),
    skin_feeling TEXT CHECK (skin_feeling IN ('iyi', 'kuru', 'yagli', 'kirik', 'irritasyon')),
    applied_routine BOOLEAN DEFAULT false,
    notes TEXT,
    weather_data JSONB DEFAULT '{}'::jsonb,
    risk_score INT,
    adaptation JSONB DEFAULT '{}'::jsonb,
    -- Expected structure:
    -- {
    --   "type": "minor" | "major",
    --   "changes": [{"item": "...", "old": "...", "new": "...", "reason": "..."}],
    --   "ai_note": "..."
    -- }
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, log_date)
);

-- Enable RLS on daily_logs
ALTER TABLE public.daily_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own daily_logs"
    ON public.daily_logs FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own daily_logs"
    ON public.daily_logs FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own daily_logs"
    ON public.daily_logs FOR UPDATE
    USING (auth.uid() = user_id);

-- Index for efficient date-range queries
CREATE INDEX IF NOT EXISTS daily_logs_user_date_idx
    ON public.daily_logs (user_id, log_date DESC);

-- 6b. Daily Events (mobil: su, uyku, stres, konum vb.)
CREATE TABLE IF NOT EXISTS public.daily_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    event_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    log_date DATE NOT NULL DEFAULT (timezone('utc', now()))::date,
    type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    source TEXT NOT NULL DEFAULT 'mobile',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.daily_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own daily_events"
    ON public.daily_events FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own daily_events"
    ON public.daily_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own daily_events"
    ON public.daily_events FOR DELETE
    USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS daily_events_user_log_date_idx
    ON public.daily_events (user_id, log_date DESC);

CREATE INDEX IF NOT EXISTS daily_events_user_event_time_idx
    ON public.daily_events (user_id, event_time DESC);

-- 7. Create a match_documents function for RAG similarity search
CREATE OR REPLACE FUNCTION match_documents(
    query_embedding vector(1536),
    match_count INT DEFAULT 5,
    filter JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    metadata JSONB,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        kb.id,
        kb.content,
        kb.metadata,
        1 - (kb.embedding <=> query_embedding) AS similarity
    FROM public.knowledge_base kb
    WHERE
        CASE
            WHEN filter ? 'topic' THEN kb.metadata->>'topic' = filter->>'topic'
            ELSE true
        END
    ORDER BY kb.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- 7. Auto-create profile on user signup (trigger)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', '')
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 8. Storage Bucket for skin photos
-- Note: Run this via Supabase Dashboard or API:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('skin-photos', 'skin-photos', true);

-- Storage RLS: bkz. database/migrations/20260403_storage_skin_photos_rls.sql
