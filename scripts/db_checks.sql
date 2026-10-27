-- Rebi canlı veritabanı kontrolleri — YALNIZCA OKUR (select).
-- Supabase Dashboard > SQL Editor'da bölüm bölüm çalıştırın. Hiçbir sorgu veri değiştirmez ya da silmez.
-- Yorumlar neyin beklendiğini ve sonuca göre ne yapılacağını anlatır. (API de aynı denetimi yapar: GET /health -> db_integrity.)

-- ═══ 1) Beklenen indeksler ═══════════════════════════════════════════════════════════════════════
-- Beklenen: daily_events_user_client_event_idx, daily_events_user_type_time_idx, daily_events_user_date_idx,
-- chat_history_user_seq_idx ve push_sends üzerinde (user_id, reminder_id, log_date, slot) için bir UNIQUE indeks.
-- daily_events_user_client_event_idx yoksa olay yazımındaki ON CONFLICT hata verir (sunucu 503 döner, mobil olayı kuyrukta tutar).
-- Eksik olan varsa ilgili supabase/migrations/*.sql dosyasını SQL Editor'da çalıştırın.
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('daily_events', 'push_sends', 'chat_history', 'daily_logs', 'device_tokens')
order by tablename, indexname;

-- ═══ 2) Gerekli fonksiyonlar ═════════════════════════════════════════════════════════════════════
-- Beklenen: match_knowledge_chunks (sohbetin vektör araması) ve purge_expired_rebi_data (retention temizliği).
select proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and proname in ('match_knowledge_chunks', 'purge_expired_rebi_data');

-- ═══ 3) Retention zamanlayıcısı (pg_cron) ════════════════════════════════════════════════════════
-- "cron" şeması yoksa pg_cron kapalıdır: Dashboard > Database > Extensions'tan açın ve
-- supabase/migrations/20260920174000_data_retention.sql dosyasını yeniden çalıştırın (işi zamanlar).
-- Hâlâ pg_cron kullanamıyorsanız deploy/.env.api'ye RETENTION_PURGE_DAILY=1 ekleyin (docs/DEPLOY.md).
select jobname, schedule, active from cron.job where jobname = 'rebi-data-retention-daily';

-- Son çalışmalar (status = 'succeeded' olmalı).
select status, start_time, return_message
from cron.job_run_details
order by start_time desc
limit 5;

-- ═══ 4) Boyut ve büyüme ══════════════════════════════════════════════════════════════════════════
select pg_size_pretty(pg_database_size(current_database())) as veritabani_boyutu;

select relname as tablo, n_live_tup as satir, pg_size_pretty(pg_total_relation_size(relid)) as toplam_boyut
from pg_stat_user_tables
order by pg_total_relation_size(relid) desc
limit 10;

-- Kullanıcı başına günlük olay sayısı (dünkü gün): daily_events büyümesini öngörmek için.
-- Tahmin: satır başına ~0,7 KB (indeksler dahil) x olay/gün x 400 gün x kullanıcı sayısı.
select count(*) as olay,
       count(distinct user_id) as kullanici,
       round(count(*)::numeric / nullif(count(distinct user_id), 0), 1) as kullanici_basina_olay
from public.daily_events
where log_date = current_date - 1;

-- ═══ 5) Kullanılmayan indeks adayları ════════════════════════════════════════════════════════════
-- İstatistikler son sıfırlamadan beri biriktiği için trafikle birkaç gün geçtikten sonra bakın.
-- idx_scan günlerce 0 ise (özellikle daily_events_user_time_idx) kaldırma adayıdır. BENZERSİZ indekslere
-- (daily_events_user_client_event_idx, push_sends benzersiz indeksi) dokunmayın.
select relname as tablo, indexrelname as indeks, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) as boyut
from pg_stat_user_indexes
where schemaname = 'public' and relname in ('daily_events', 'chat_history', 'push_sends')
order by idx_scan, pg_relation_size(indexrelid) desc;

-- ═══ 6) Retention ÖNİZLEMESİ: temizlik çalışırsa kaç satır silinirdi (silmez, yalnızca sayar) ═════
-- Ölçütler purge_expired_rebi_data() ile aynıdır (docs/DATA_RETENTION.md). Sayılar büyükse ilk temizliği
-- SQL Editor'da elle çalıştırmak (select public.purge_expired_rebi_data();) API üzerinden çalıştırmaktan güvenlidir:
-- API istekleri zaman aşımına uğrayabilir, SQL Editor'ın uzun sorgu sınırı daha geniştir.
select 'intro_seen_ips' as tablo, count(*) as silinecek from public.intro_seen_ips where seen_at < now() - interval '180 days'
union all select 'daily_events', count(*) from public.daily_events where event_time < now() - interval '400 days'
union all select 'daily_logs', count(*) from public.daily_logs where log_date < current_date - 730
union all select 'routines (pasif)', count(*) from public.routines where is_active is false and created_at < now() - interval '730 days'
union all select 'assessments (kullanılmayan)', count(*) from public.assessments a
          where a.created_at < now() - interval '730 days'
            and not exists (select 1 from public.routines r where r.assessment_id = a.id)
union all select 'chat_history', count(*) from public.chat_history where created_at < now() - interval '365 days'
union all select 'device_tokens (atıl)', count(*) from public.device_tokens where last_seen_at < now() - interval '180 days'
union all select 'push_sends', count(*) from public.push_sends where log_date < current_date - 30;

-- ═══ 7) Satır düzeyi güvenlik (RLS) ═════════════════════════════════════════════════════════════
-- Kullanıcı verisi taşıyan her tabloda rls_acik = true olmalı (service_role dışındaki erişimi sınırlar).
select tablename, rowsecurity as rls_acik
from pg_tables
where schemaname = 'public'
  and tablename in ('profiles', 'assessments', 'routines', 'daily_logs', 'daily_events', 'chat_history',
                    'device_tokens', 'push_sends', 'reminder_settings', 'legal_consents', 'privacy_preferences')
order by tablename;

-- ═══ 8) Bildirim altyapısı ═══════════════════════════════════════════════════════════════════════
-- Push açık kullanıcı/cihaz sayısı ve en eski "son görülme": atıl cihazlar 180 günde temizlenir.
select count(*) filter (where push_enabled) as push_acik_cihaz,
       count(distinct user_id) filter (where push_enabled) as push_acik_kullanici,
       min(last_seen_at) as en_eski_son_gorulme
from public.device_tokens;
