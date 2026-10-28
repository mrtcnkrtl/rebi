-- Bildirim butonlarıyla günlük veri toplama: cihazın butonları destekleyip
-- desteklemediği ve gönderim defterinde kullanıcının verdiği cevap.

alter table public.device_tokens
  add column if not exists actions_supported boolean not null default false;

comment on column public.device_tokens.actions_supported is
  'Uygulama bildirim butonlarını kendisi çiziyor; Android''e yalnızca veri taşıyan mesaj gider.';

alter table public.push_sends
  add column if not exists action_id text,
  add column if not exists responded_at timestamptz;

comment on column public.push_sends.action_id is
  'Bildirimde basılan buton (ör. ml_250); cevap yoksa boş.';
