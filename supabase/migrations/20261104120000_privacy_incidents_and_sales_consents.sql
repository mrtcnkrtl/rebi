-- Veri ihlali kaydı: istemciye kapalı. service_role yazar.
-- Kurul bildirimi bu tabloyla otomatik gitmez; notify_kurul_by, öğrenmeden 72 saat sonradır.

create table if not exists public.privacy_incidents (
  id uuid primary key default gen_random_uuid(),
  summary text not null,
  discovered_at timestamptz not null,
  notify_kurul_by timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.privacy_incidents enable row level security;

comment on table public.privacy_incidents is
  'KVKK breach log. No client policy: anon and authenticated cannot read or write. service_role records the 72-hour deadline.';

-- Rebi Plus ön bilgilendirme + mesafeli satış onayı. Kullanıcı kendi satırını okur; yazma yalnız backend.

create table if not exists public.sales_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_version text not null,
  pre_info_accepted boolean not null,
  distance_contract_accepted boolean not null,
  accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, document_version)
);

create index if not exists sales_consents_user_accepted_idx
  on public.sales_consents (user_id, accepted_at desc);

alter table public.sales_consents enable row level security;

drop policy if exists "Users can view own sales consents" on public.sales_consents;
create policy "Users can view own sales consents"
  on public.sales_consents for select
  to authenticated
  using (auth.uid() = user_id);

comment on table public.sales_consents is
  'Append-only Rebi Plus pre-contract and distance-sales evidence written by backend service_role.';
