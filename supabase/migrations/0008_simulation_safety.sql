-- SaveBite: fail-closed money safety while consumer payment is simulated.
-- Simulation orders can exercise pickup UX, but can never create withdrawable
-- balance. Payout requests stay disabled until a real payout operation is
-- explicitly enabled by a later production migration.

begin;

insert into private.app_settings (key, int_value, text_value)
values
  ('payments_enabled', 0, null),
  ('payouts_enabled', 0, null)
on conflict (key) do nothing;

alter table public.orders
  add column if not exists is_simulation boolean not null default true,
  add column if not exists payment_verified_at timestamptz,
  add column if not exists payment_provider_reference text;

-- No historical order predates a real gateway in this codebase.
update public.orders
set is_simulation = true,
    payment_verified_at = null,
    payment_provider_reference = null;

create or replace function private.enforce_order_money_safety()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
declare
  v_merchant_user uuid;
begin
  select user_id into v_merchant_user
  from public.merchants
  where id = new.merchant_id;

  if new.consumer_id is not null and new.consumer_id = v_merchant_user then
    raise exception 'merchant cannot purchase from their own store';
  end if;

  if new.payment_verified_at is null
     or nullif(btrim(coalesce(new.payment_provider_reference, '')), '') is null then
    new.is_simulation := true;
    new.payment_verified_at := null;
    new.payment_provider_reference := null;
  else
    -- A future gateway webhook/service worker must be the only writer of a
    -- verified payment. API client roles are never trusted for this flag.
    if current_user in ('anon', 'authenticated') then
      raise exception 'payment verification is server-managed' using errcode = '42501';
    end if;
    new.is_simulation := false;
  end if;
  return new;
end
$$;

drop trigger if exists enforce_order_money_safety on public.orders;
create trigger enforce_order_money_safety
before insert or update of consumer_id, merchant_id, payment_verified_at,
  payment_provider_reference, is_simulation
on public.orders
for each row execute function private.enforce_order_money_safety();

create or replace function private.mark_simulation_ledger_untrusted()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  if new.kind = 'income'
     and new.reference_type = 'order'
     and exists (
       select 1 from public.orders o
       where o.id = new.reference_id and o.is_simulation
     ) then
    new.trusted := false;
    new.subtitle := 'Simulasi — tidak dapat ditarik';
    new.metadata := coalesce(new.metadata, '{}'::jsonb)
      || jsonb_build_object('simulation', true);
  end if;
  return new;
end
$$;

drop trigger if exists mark_simulation_ledger_untrusted on public.transactions;
create trigger mark_simulation_ledger_untrusted
before insert on public.transactions
for each row execute function private.mark_simulation_ledger_untrusted();

-- Reclassify any ledger reconstructed by 0002 before this safety marker
-- existed. Temporarily disable only the immutable-update guard.
alter table public.transactions disable trigger transactions_immutable;
update public.transactions t
set trusted = false,
    subtitle = 'Simulasi — tidak dapat ditarik',
    metadata = coalesce(t.metadata, '{}'::jsonb)
      || jsonb_build_object('simulation', true)
where t.kind = 'income'
  and t.reference_type = 'order'
  and exists (
    select 1 from public.orders o
    where o.id = t.reference_id and o.is_simulation
  );
alter table public.transactions enable trigger transactions_immutable;

create or replace function private.reject_disabled_payouts()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  if private.setting_int('payouts_enabled') <> 1 then
    raise exception 'payouts are disabled while checkout is in simulation mode';
  end if;
  return new;
end
$$;

drop trigger if exists reject_disabled_payouts on public.payout_requests;
create trigger reject_disabled_payouts
before insert on public.payout_requests
for each row execute function private.reject_disabled_payouts();

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
    'minimum_withdrawal', private.setting_int('minimum_withdrawal'),
    'payments_enabled', private.setting_int('payments_enabled') = 1,
    'payouts_enabled', private.setting_int('payouts_enabled') = 1
  )
$$;

revoke all on function private.enforce_order_money_safety() from public, anon, authenticated;
revoke all on function private.mark_simulation_ledger_untrusted() from public, anon, authenticated;
revoke all on function private.reject_disabled_payouts() from public, anon, authenticated;
revoke all on function public.get_public_app_config() from public;
grant execute on function public.get_public_app_config() to anon, authenticated;

comment on column public.orders.is_simulation is
  'True unless a trusted server worker supplies a verified provider payment reference.';

commit;
