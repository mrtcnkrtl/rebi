-- Rafım ("ürün bitti" -> "aldım") durumu gün içi olaylardan türetilir: kullanıcının bir yıllık
-- olayları arasından yalnızca ürün olayları okunur. Tür sütunu da indekste olunca bu sorgu
-- kullanıcının su/adım gibi binlerce olayını taramaz.

create index if not exists daily_events_user_type_time_idx
  on public.daily_events (user_id, type, event_time desc);
