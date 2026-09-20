-- Kişisel veri minimizasyonu: aktif hesaplarda yalnızca ürünün çalışması için
-- gereken geçmiş tutulur. Hesap silme endpoint'i bu süreleri beklemeden siler.

create or replace function public.purge_expired_rebi_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_intro integer := 0;
  n_events integer := 0;
  n_logs integer := 0;
  n_routines integer := 0;
  n_assessments integer := 0;
begin
  delete from public.intro_seen_ips
  where seen_at < now() - interval '180 days';
  get diagnostics n_intro = row_count;

  delete from public.daily_events
  where event_time < now() - interval '400 days';
  get diagnostics n_events = row_count;

  delete from public.daily_logs
  where log_date < current_date - 730;
  get diagnostics n_logs = row_count;

  delete from public.routines
  where is_active is false
    and created_at < now() - interval '730 days';
  get diagnostics n_routines = row_count;

  delete from public.assessments a
  where a.created_at < now() - interval '730 days'
    and not exists (
      select 1
      from public.routines r
      where r.assessment_id = a.id
    );
  get diagnostics n_assessments = row_count;

  return jsonb_build_object(
    'intro_seen_ips', n_intro,
    'daily_events', n_events,
    'daily_logs', n_logs,
    'inactive_routines', n_routines,
    'assessments', n_assessments
  );
end;
$$;

revoke all on function public.purge_expired_rebi_data() from public;
revoke all on function public.purge_expired_rebi_data() from anon;
revoke all on function public.purge_expired_rebi_data() from authenticated;
grant execute on function public.purge_expired_rebi_data() to service_role;

-- Supabase'te pg_cron açıksa her gün 03:20 UTC'de çalıştır. pg_cron yoksa
-- deploy operasyonu bu fonksiyonu günlük çağırmalıdır.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'rebi-data-retention-daily';

    perform cron.schedule(
      'rebi-data-retention-daily',
      '20 3 * * *',
      'select public.purge_expired_rebi_data()'
    );
  end if;
end;
$$;

comment on function public.purge_expired_rebi_data() is
  'Rebi retention: intro 180g, daily events 400g, daily logs and unused historical records 730g.';
