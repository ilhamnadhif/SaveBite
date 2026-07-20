-- SaveBite: true-positive Supabase Security Advisor hardening.
-- Apply after 0013_rls_performance.sql.

begin;

-- This generic trigger only needs pg_catalog.now(); pinning its search path
-- prevents caller-controlled schemas from affecting name resolution.
alter function public.touch_updated_at()
  set search_path = pg_catalog;

-- Trigger functions are invoked by their registered triggers, never through
-- PostgREST RPC. Remove inherited/default EXECUTE privileges so neither an
-- anonymous nor an authenticated client can address them directly.
revoke all on function public.touch_updated_at()
  from public, anon, authenticated, service_role;
revoke all on function public.notify_payout_change()
  from public, anon, authenticated, service_role;
revoke all on function public.recompute_merchant_rating()
  from public, anon, authenticated, service_role;
revoke all on function public.sync_profile_email_from_auth()
  from public, anon, authenticated, service_role;

commit;
