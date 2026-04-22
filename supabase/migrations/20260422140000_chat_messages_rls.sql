-- RLS for chat messages (PostgREST exposed)
-- Fix: "RLS Disabled in Public" for public.chat_messages

alter table if exists public.chat_messages enable row level security;

-- Backend service_role RLS'yi bypass eder. Aşağıdakiler: doğrudan Supabase istemci (anon + kullanıcı JWT).
-- Varsayım: public.chat_messages tablosunda user_id UUID kolonu var (auth.users(id)).

drop policy if exists "Users can view own chat_messages" on public.chat_messages;
create policy "Users can view own chat_messages"
  on public.chat_messages for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own chat_messages" on public.chat_messages;
create policy "Users can insert own chat_messages"
  on public.chat_messages for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own chat_messages" on public.chat_messages;
create policy "Users can update own chat_messages"
  on public.chat_messages for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own chat_messages" on public.chat_messages;
create policy "Users can delete own chat_messages"
  on public.chat_messages for delete
  using (auth.uid() = user_id);

comment on table public.chat_messages is 'Rebi: kullanıcı sohbet mesajları (RLS enabled).';

