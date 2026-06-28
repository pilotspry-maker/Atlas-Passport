-- 025_public_stats_view.sql
-- Kaelo Atlas Command — public dashboard aggregates.
--
-- Exposes a single-row aggregate of network-wide counts (current totals + last-24h
-- deltas + last-hour active threads) so the public dashboard can read them under
-- the publishable (anon) key WITHOUT exposing any row-level data.
--
-- Pattern: SECURITY DEFINER function (locked search_path, stable) + security_invoker
-- view that calls it. This satisfies the supabase database linter — a plain
-- SECURITY DEFINER view triggers the ERROR-level `security_definer_view` advisor.
-- The function approach raises only the intentional WARN advisors for an
-- anon-callable SECURITY DEFINER function, which is documented and required here.
--
-- Fixture filter on corridors/nodes mirrors the public dashboard's client-side
-- filter so REST aggregate counts stay consistent with what the published site
-- already displays.

-- 1) Idempotent teardown.
drop view if exists public.public_stats cascade;
drop function if exists public.get_public_stats() cascade;

-- 2) SECURITY DEFINER function with locked search_path.
create or replace function public.get_public_stats()
returns table (
  total_users        bigint,
  total_passports    bigint,
  total_checkins     bigint,
  total_waitlist     bigint,
  active_corridors   bigint,
  active_nodes       bigint,
  new_users_24h      bigint,
  new_passports_24h  bigint,
  new_checkins_24h   bigint,
  new_waitlist_24h   bigint,
  ap_events_24h      bigint,
  referrals_24h      bigint,
  active_threads_1h  bigint,
  as_of              timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    (select count(*) from public.profiles),
    (select count(*) from public.passports),
    (select count(*) from public.check_ins),
    (select count(*) from public.waitlist_entries),
    (
      select count(*) from public.corridors
      where is_active = true
        and coalesce(slug, '') !~* '^(ci[-_]|.*\btest\b|.*\bdev\b)'
        and coalesce(name, '') !~* '\b(test|dev)\b'
    ),
    (
      select count(*) from public.nodes n
      where n.is_active = true
        and exists (
          select 1 from public.corridors c
          where c.id = n.corridor_id
            and c.is_active = true
            and coalesce(c.slug, '') !~* '^(ci[-_]|.*\btest\b|.*\bdev\b)'
            and coalesce(c.name, '') !~* '\b(test|dev)\b'
        )
        and coalesce(n.name, '') !~* '\b(test|dev)\b'
    ),
    (select count(*) from public.profiles         where created_at   >= now() - interval '24 hours'),
    (select count(*) from public.passports        where created_at   >= now() - interval '24 hours'),
    (select count(*) from public.check_ins        where submitted_at >= now() - interval '24 hours'),
    (select count(*) from public.waitlist_entries where joined_at    >= now() - interval '24 hours'),
    (select count(*) from public.ap_events        where created_at   >= now() - interval '24 hours'),
    (select count(*) from public.referral_events  where created_at   >= now() - interval '24 hours'),
    (select count(*) from public.mission_progress where updated_at   >= now() - interval '1 hour'),
    now();
$$;

revoke all on function public.get_public_stats() from public;
grant execute on function public.get_public_stats() to anon, authenticated;

comment on function public.get_public_stats() is
  'Kaelo Atlas Command public dashboard aggregates. Anon-executable. SECURITY DEFINER with locked search_path. Returns a single row of network-wide counts. No row-level data exposed.';

-- 3) Security-invoker view wrapping the function so REST clients can keep
--    using GET /rest/v1/public_stats?select=* alongside the RPC.
create view public.public_stats
with (security_invoker = true) as
select * from public.get_public_stats();

revoke all on public.public_stats from public;
grant select on public.public_stats to anon, authenticated;

comment on view public.public_stats is
  'Security-invoker view wrapping public.get_public_stats(). Read via REST or RPC.';
