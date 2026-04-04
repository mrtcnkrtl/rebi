-- REBI: daily_events tablosu + RLS; assessments için kullanıcı UPDATE politikası
-- Supabase SQL Editor'de bir kez çalıştırın. Şema önbelleğini gerekirse yenileyin.

-- ---------------------------------------------------------------------------
-- daily_events (backend/main.py ile uyumlu)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.daily_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    log_date DATE NOT NULL DEFAULT (timezone('utc', now()))::date,
    type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    source TEXT NOT NULL DEFAULT 'mobile',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS daily_events_user_log_date_idx
    ON public.daily_events (user_id, log_date DESC);

CREATE INDEX IF NOT EXISTS daily_events_user_event_time_idx
    ON public.daily_events (user_id, event_time DESC);

ALTER TABLE public.daily_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own daily_events" ON public.daily_events;
CREATE POLICY "Users can view own daily_events"
    ON public.daily_events FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own daily_events" ON public.daily_events;
CREATE POLICY "Users can insert own daily_events"
    ON public.daily_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- İsteğe bağlı: kullanıcı kendi satırlarını silebilir (GDPR / temizlik)
DROP POLICY IF EXISTS "Users can delete own daily_events" ON public.daily_events;
CREATE POLICY "Users can delete own daily_events"
    ON public.daily_events FOR DELETE
    USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- assessments: doğrudan istemci güncellemesi (ör. yaşam tarzı alanları)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can update own assessments" ON public.assessments;
CREATE POLICY "Users can update own assessments"
    ON public.assessments FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
