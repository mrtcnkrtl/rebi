-- RLS for public.chat_messages (PostgREST exposed)
-- Fix: "RLS Disabled in Public" for public.chat_messages

alter table if exists public.chat_messages enable row level security;

-- IMPORTANT:
-- Bu projedeki mevcut public.chat_messages tablosunda user_id yok (id, phone_normalized, created_at).
-- Bu yüzden en güvenli çözüm: RLS aç → policy tanımlama (PostgREST üzerinden erişim kapanır).
-- Backend service_role RLS'yi bypass eder; gerekiyorsa backend bu tabloyu servis anahtarıyla yönetir.

drop policy if exists "Users can view own chat_messages" on public.chat_messages;
drop policy if exists "Users can insert own chat_messages" on public.chat_messages;
drop policy if exists "Users can update own chat_messages" on public.chat_messages;
drop policy if exists "Users can delete own chat_messages" on public.chat_messages;

comment on table public.chat_messages is 'Rebi: chat_messages (RLS enabled; no per-user policies because user_id column is absent).';

