-- Kullanıcının değiştiremeyeceği, sürümlü ve append-only hukuki onay kaydı.

create table if not exists public.legal_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_version text not null,
  kvkk_accepted boolean not null,
  explicit_consent_accepted boolean not null,
  accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, document_version)
);

create index if not exists legal_consents_user_accepted_idx
  on public.legal_consents (user_id, accepted_at desc);

alter table public.legal_consents enable row level security;

drop policy if exists "Users can view own legal consents" on public.legal_consents;
create policy "Users can view own legal consents"
  on public.legal_consents for select
  to authenticated
  using (auth.uid() = user_id);

-- INSERT/UPDATE/DELETE policy intentionally omitted. Only the backend
-- service_role records consent; users can read but cannot rewrite evidence.

comment on table public.legal_consents is
  'Append-only KVKK and explicit-consent evidence written by backend service_role.';
