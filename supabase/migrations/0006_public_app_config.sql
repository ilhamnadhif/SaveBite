-- SaveBite: expose non-secret business values used by client calculations.

begin;

create or replace function public.get_public_app_config()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  select jsonb_build_object(
    'service_fee', private.setting_int('service_fee'),
    'merchant_commission_bps', private.setting_int('merchant_commission_bps'),
    'withdrawal_fee', private.setting_int('withdrawal_fee'),
    'minimum_withdrawal', private.setting_int('minimum_withdrawal')
  )
$$;

revoke all on function public.get_public_app_config() from public;
grant execute on function public.get_public_app_config() to anon, authenticated;

comment on function public.get_public_app_config() is
  'Returns only non-secret fees and limits required to render consistent client totals.';

commit;
