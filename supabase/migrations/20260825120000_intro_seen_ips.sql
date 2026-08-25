-- Giriş sunumu: IP hash başına bir kez. Ham IP saklanmaz.
-- Backend (Postgres rolü) yazar; anon istemcinin tablosu yoktur.

create table if not exists public.intro_seen_ips (
  ip_hash text primary key,
  seen_at timestamptz not null default now()
);

alter table public.intro_seen_ips enable row level security;

comment on table public.intro_seen_ips is 'Rebi: giriş sunumunu gören istemci IP hash’leri (KVKK: ham IP yok).';
