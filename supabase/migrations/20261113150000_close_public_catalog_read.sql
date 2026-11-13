-- Katalog ve kural tabloları istemciye kapalıdır. Sunucu postgres / service_role ile okur.
-- Anon rolünün public şemada tablo okuma ve fonksiyon çağırma yetkisi de kalkar.
-- Giriş yapmış kullanıcının kendi satır politikaları durur.

drop policy if exists skincare_graph_kb_read_all on public.ingredient_profiles;
drop policy if exists skincare_graph_kb_read_all on public.skin_conditions;
drop policy if exists skincare_graph_kb_read_all on public.ingredient_relationships;
drop policy if exists skincare_graph_kb_read_all on public.condition_ingredient_map;
drop policy if exists skincare_graph_kb_read_all on public.safety_rules;
drop policy if exists data_catalog_read_all on public.canonical_ingredients;
drop policy if exists data_catalog_read_all on public.canonical_concerns;
drop policy if exists data_catalog_read_all on public.ingredient_concern_links;
drop policy if exists active_rules_public_read on public.active_rules;

alter table public.ingredient_profiles enable row level security;
alter table public.skin_conditions enable row level security;
alter table public.ingredient_relationships enable row level security;
alter table public.condition_ingredient_map enable row level security;
alter table public.safety_rules enable row level security;
alter table public.canonical_ingredients enable row level security;
alter table public.canonical_concerns enable row level security;
alter table public.ingredient_concern_links enable row level security;
alter table public.active_rules enable row level security;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

revoke all on all functions in schema public from public;
grant execute on all functions in schema public to authenticated;
grant execute on all functions in schema public to service_role;

revoke all on function public.purge_expired_rebi_data() from public;
revoke all on function public.purge_expired_rebi_data() from anon;
revoke all on function public.purge_expired_rebi_data() from authenticated;
grant execute on function public.purge_expired_rebi_data() to service_role;

do $lock$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end
$lock$;
