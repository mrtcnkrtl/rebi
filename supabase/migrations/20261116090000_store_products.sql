-- Ürün mağazası kataloğu. Ürünler burada durur; seçilen ticaret altyapısı (ödeme / sipariş) sonradan
-- `external_ref` üzerinden bağlanır. Tablo istemciye kapalıdır: site ve mobil, backend'in `/store/*`
-- uçlarından okur; yazma yalnız service_role ile yapılır.

create table if not exists public.store_products (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique,
  name_tr         text not null,
  name_en         text,
  summary_tr      text,
  summary_en      text,
  description_tr  text,
  description_en  text,
  usage_tr        text,
  usage_en        text,
  -- Ambalajdaki tam içerik listesi (INCI).
  inci            text,
  size_label      text,
  -- Rutin ve Rafım eşlemesi: ürünün türü, rutindeki adım sırası (10 temizlik, 20 serum, 30 nemlendirici,
  -- 40 güneş koruyucu) ve içerdiği maddelerin canonical_ingredients kimlikleri.
  product_type    text not null default 'other'
                  check (product_type in ('cleanser', 'toner', 'serum', 'moisturizer', 'sunscreen', 'mask', 'other')),
  step_order      integer,
  ingredient_ids  jsonb not null default '[]'::jsonb,
  -- KDV dahil satış fiyatı, kuruş cinsinden. Boşsa fiyat henüz açıklanmamıştır ve ürün sepete eklenemez.
  price_minor     integer check (price_minor is null or price_minor > 0),
  currency        text not null default 'TRY',
  vat_rate        numeric(5, 2),
  -- [{"url": "...", "alt_tr": "...", "alt_en": "..."}]
  images          jsonb not null default '[]'::jsonb,
  -- draft: yalnız yönetimde; coming_soon: vitrinde, satın alınamaz; active: satışta; archived: kaldırıldı.
  status          text not null default 'draft'
                  check (status in ('draft', 'coming_soon', 'active', 'archived')),
  in_stock        boolean not null default true,
  sort_order      integer not null default 100,
  -- Ticaret altyapısındaki karşılığı, ör. {"provider": "...", "product_id": "...", "variant_id": "..."}.
  external_ref    jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists store_products_status_sort_idx
  on public.store_products (status, sort_order);

alter table public.store_products enable row level security;

revoke all on public.store_products from anon;
revoke all on public.store_products from authenticated;

comment on table public.store_products is
  'Store catalogue. No client policy: anon and authenticated cannot read or write; the backend serves /store/* with service_role.';
