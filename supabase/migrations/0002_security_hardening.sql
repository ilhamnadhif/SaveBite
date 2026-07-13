-- SaveBite - security and lifecycle hardening.
--
-- Upgrade target: 0001_init.sql. This migration intentionally does not add a
-- payment gateway. `purchase_bag` therefore still creates a paid order as a
-- temporary application contract; a future gateway migration must change that
-- transition to pending -> paid from a verified webhook.
--
-- Security properties introduced here:
--   * monetary ledgers are append-only and cannot be written by API clients;
--   * checkout, pickup, reviews, and withdrawals are server-validated RPCs;
--   * raw pickup tokens are returned only by an RPC and are never persisted;
--   * merchant reputation and order lifecycle fields are server-managed;
--   * consumer/merchant order views expose snapshots, not protected token data;
--   * account deletion anonymizes records which must be kept for accounting.

begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- Private configuration is readable only by SECURITY DEFINER functions. The
-- bank pepper is database-local, so low-entropy account numbers are not stored
-- as a reversible or unsalted hash.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.app_settings (
  key text primary key,
  int_value bigint,
  text_value text,
  updated_at timestamptz not null default now()
);

revoke all on table private.app_settings from public, anon, authenticated;

insert into private.app_settings (key, int_value, text_value)
values
  ('service_fee', 1000, null),
  ('merchant_commission_bps', 1000, null),
  ('withdrawal_fee', 2500, null),
  ('minimum_withdrawal', 50000, null),
  ('bank_hash_pepper', null, encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (key) do nothing;

create or replace function private.setting_int(p_key text)
returns integer
language sql
stable
security definer
set search_path = private, pg_catalog
as $$
  select int_value::integer
  from private.app_settings
  where key = p_key
$$;

revoke all on function private.setting_int(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Columns and tables
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists deleted_at timestamptz;

alter table public.merchants
  add column if not exists deleted_at timestamptz;

alter table public.surprise_bags
  add column if not exists available_on date,
  add column if not exists pickup_start_at timestamptz,
  add column if not exists pickup_end_at timestamptz;

alter table public.orders
  add column if not exists order_reference text,
  add column if not exists subtotal integer,
  add column if not exists service_fee integer,
  add column if not exists unit_price integer,
  add column if not exists original_price_snapshot integer,
  add column if not exists commission_amount integer,
  add column if not exists merchant_net_amount integer,
  add column if not exists bag_title text,
  add column if not exists bag_description text,
  add column if not exists bag_image_url text,
  add column if not exists pickup_window_snapshot text,
  add column if not exists merchant_name_snapshot text,
  add column if not exists merchant_category_snapshot text,
  add column if not exists merchant_address_snapshot text,
  add column if not exists merchant_logo_url_snapshot text,
  add column if not exists merchant_rating_snapshot numeric(2,1),
  add column if not exists merchant_review_count_snapshot integer,
  add column if not exists idempotency_key text,
  add column if not exists pickup_token_hash bytea,
  add column if not exists pickup_code_hint text,
  add column if not exists pickup_token_issued_at timestamptz,
  add column if not exists pickup_token_used_at timestamptz,
  add column if not exists pickup_start_at timestamptz,
  add column if not exists pickup_end_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists paid_at timestamptz,
  add column if not exists ready_at timestamptz,
  add column if not exists redeemed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists expired_at timestamptz,
  add column if not exists updated_at timestamptz default now(),
  add column if not exists consumer_anonymized boolean not null default false;

alter table public.transactions
  add column if not exists reference_type text,
  add column if not exists reference_id uuid,
  add column if not exists idempotency_key text,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists created_by uuid,
  add column if not exists trusted boolean not null default false;

alter table public.notifications
  add column if not exists dedupe_key text,
  add column if not exists entity_type text,
  add column if not exists entity_id uuid,
  add column if not exists data jsonb not null default '{}'::jsonb;

create table if not exists public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  bank_code text not null,
  bank_name text not null,
  account_holder text not null,
  account_number_hash bytea not null,
  account_number_last4 text not null,
  provider_recipient_id text,
  status text not null default 'pending',
  is_default boolean not null default false,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete restrict,
  bank_account_id uuid references public.bank_accounts(id) on delete set null,
  bank_code text not null,
  bank_name text not null,
  account_number_last4 text not null,
  amount integer not null,
  fee_amount integer not null,
  net_amount integer not null,
  status text not null default 'requested',
  idempotency_key text not null,
  provider_reference text,
  failure_reason text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Keep accounting and order snapshots when an auth account is deleted. The
-- delete RPC nulls/anonymizes these references before deleting auth.users.
alter table public.orders alter column consumer_id drop not null;
alter table public.reviews alter column consumer_id drop not null;

alter table public.orders drop constraint if exists orders_consumer_id_fkey;
alter table public.orders
  add constraint orders_consumer_id_fkey foreign key (consumer_id)
  references auth.users(id) on delete set null;

alter table public.reviews drop constraint if exists reviews_consumer_id_fkey;
alter table public.reviews
  add constraint reviews_consumer_id_fkey foreign key (consumer_id)
  references auth.users(id) on delete set null;

alter table public.merchants drop constraint if exists merchants_user_id_fkey;
alter table public.merchants
  add constraint merchants_user_id_fkey foreign key (user_id)
  references auth.users(id) on delete set null;

-- Keep created_by as an audit UUID rather than a foreign key. A FK with
-- ON DELETE SET NULL would mutate an immutable ledger during account deletion.
alter table public.transactions drop constraint if exists transactions_created_by_fkey;

-- ---------------------------------------------------------------------------
-- Normalize 0001 data before adding strict constraints
-- ---------------------------------------------------------------------------

update public.profiles
set last_mode = 'consumer'
where last_mode is null or last_mode not in ('consumer', 'merchant');

update public.merchants
set status = 'active'
where status is null or status not in ('pending', 'active', 'inactive', 'suspended', 'deleted');

update public.merchants set rating = 0 where rating is null or rating < 0 or rating > 5;
update public.merchants set review_count = 0 where review_count is null or review_count < 0;
update public.merchants set bags_saved = 0 where bags_saved is null or bags_saved < 0;

update public.surprise_bags
set sale_price = least(greatest(coalesce(sale_price, 1), 1), 10000000),
    original_price = least(
      greatest(coalesce(original_price, sale_price, 1), coalesce(sale_price, 1), 1),
      100000000
    ),
    quantity_total = least(greatest(coalesce(quantity_total, 1), 1), 1000),
    quantity_left = least(
      greatest(coalesce(quantity_left, 0), 0),
      least(greatest(coalesce(quantity_total, 1), 1), 1000)
    ),
    available_on = coalesce(available_on, (now() at time zone 'Asia/Jakarta')::date),
    title = coalesce(nullif(btrim(title), ''), 'Surprise Bag'),
    description = coalesce(description, ''),
    pickup_window = coalesce(pickup_window, ''),
    contents = coalesce(contents, '{}'::text[]);

update public.surprise_bags
set status = case
  when quantity_left = 0 then 'sold_out'
  when status not in ('active', 'sold_out', 'inactive') or status is null then 'inactive'
  when status = 'sold_out' and quantity_left > 0 then 'inactive'
  else status
end;

update public.surprise_bags
set pickup_start_at = null, pickup_end_at = null
where (pickup_start_at is null) <> (pickup_end_at is null)
   or (pickup_start_at is not null and pickup_end_at <= pickup_start_at)
   or (
     pickup_start_at is not null
     and (pickup_start_at at time zone 'Asia/Jakarta')::date <> available_on
   );

update public.orders set quantity = least(greatest(coalesce(quantity, 1), 1), 100);

-- Snapshot current bag/store data. Existing 0001 totals did not include a
-- service fee, so they are backfilled with fee=0 and remain financially stable.
update public.orders o
set unit_price = greatest(coalesce(o.unit_price, b.sale_price, 1), 1),
    original_price_snapshot = greatest(
      coalesce(o.original_price_snapshot, b.original_price, b.sale_price, 1),
      greatest(coalesce(o.unit_price, b.sale_price, 1), 1)
    ),
    subtotal = greatest(coalesce(o.subtotal, b.sale_price * o.quantity, o.total_amount, 1), 1),
    service_fee = greatest(coalesce(o.service_fee, 0), 0),
    bag_title = coalesce(nullif(o.bag_title, ''), b.title, 'Surprise Bag'),
    bag_description = coalesce(o.bag_description, b.description, ''),
    bag_image_url = coalesce(o.bag_image_url, b.image_url),
    pickup_window_snapshot = coalesce(o.pickup_window_snapshot, b.pickup_window, ''),
    merchant_name_snapshot = coalesce(nullif(o.merchant_name_snapshot, ''), m.store_name, 'Merchant'),
    merchant_category_snapshot = coalesce(o.merchant_category_snapshot, m.category, ''),
    merchant_address_snapshot = coalesce(o.merchant_address_snapshot, m.address, ''),
    merchant_logo_url_snapshot = coalesce(o.merchant_logo_url_snapshot, m.logo_url),
    merchant_rating_snapshot = coalesce(o.merchant_rating_snapshot, m.rating, 0),
    merchant_review_count_snapshot = coalesce(o.merchant_review_count_snapshot, m.review_count, 0),
    pickup_start_at = coalesce(o.pickup_start_at, b.pickup_start_at),
    pickup_end_at = coalesce(o.pickup_end_at, b.pickup_end_at)
from public.surprise_bags b
join public.merchants m on m.id = b.merchant_id
where b.id = o.bag_id;

-- Enforce exact arithmetic instead of trusting historical client totals.
update public.orders
set subtotal = unit_price * quantity,
    total_amount = unit_price * quantity + service_fee,
    commission_amount = round(
      (unit_price * quantity) * private.setting_int('merchant_commission_bps') / 10000.0
    )::integer,
    merchant_net_amount = (unit_price * quantity) - round(
      (unit_price * quantity) * private.setting_int('merchant_commission_bps') / 10000.0
    )::integer,
    created_at = coalesce(created_at, now()),
    updated_at = coalesce(updated_at, created_at, now()),
    order_reference = coalesce(
      nullif(order_reference, ''),
      'SB-' || upper(replace(id::text, '-', ''))
    ),
    payment_method = coalesce(nullif(btrim(payment_method), ''), 'Belum ditentukan');

update public.orders
set status = 'cancelled'
where status is null
   or status not in ('pending', 'paid', 'ready', 'redeemed', 'cancelled', 'expired', 'refunded');

update public.orders
set paid_at = coalesce(paid_at, created_at)
where status in ('paid', 'ready', 'redeemed', 'expired', 'refunded');

update public.orders set ready_at = coalesce(ready_at, created_at) where status = 'ready';
update public.orders set redeemed_at = coalesce(redeemed_at, created_at) where status = 'redeemed';
update public.orders set cancelled_at = coalesce(cancelled_at, created_at) where status = 'cancelled';
update public.orders set expired_at = coalesce(expired_at, created_at) where status = 'expired';

update public.orders
set expires_at = coalesce(
  expires_at,
  case
    when pickup_end_at is not null and pickup_end_at > created_at then pickup_end_at
    else created_at + interval '72 hours'
  end
);

update public.orders
set pickup_start_at = null, pickup_end_at = null
where (pickup_start_at is null) <> (pickup_end_at is null)
   or (pickup_start_at is not null and pickup_end_at <= pickup_start_at);

-- Migrate every legacy plaintext pickup code to a one-way hash, then erase it.
update public.orders
set pickup_token_hash = coalesce(pickup_token_hash, extensions.digest(pickup_code, 'sha256')),
    pickup_code_hint = coalesce(pickup_code_hint, right(pickup_code, 6)),
    pickup_token_issued_at = coalesce(pickup_token_issued_at, created_at)
where pickup_code is not null and pickup_code <> '';

alter table public.orders alter column pickup_code drop not null;
update public.orders set pickup_code = null where pickup_code is not null;

update public.transactions
set amount = greatest(abs(coalesce(amount, 0)), 1),
    kind = case when kind in ('income', 'withdrawal', 'withdrawal_reversal')
                then kind else 'income' end,
    title = coalesce(nullif(btrim(title), ''), 'Transaksi'),
    subtitle = coalesce(subtitle, ''),
    metadata = coalesce(metadata, '{}'::jsonb);

-- 0001 allowed clients to forge arbitrary ledger rows, so none of those rows
-- can be treated as spendable. Preserve them as untrusted forensic history and
-- reconstruct trusted income from redeemed orders only.
update public.transactions set trusted = false where trusted is distinct from true;
insert into public.transactions (
  merchant_id, title, subtitle, amount, kind, reference_type,
  reference_id, idempotency_key, metadata, trusted
)
select o.merchant_id,
       'Order ' || o.order_reference,
       'Rekonstruksi pendapatan tervalidasi',
       o.merchant_net_amount,
       'income', 'order', o.id, 'order:' || o.id,
       jsonb_build_object(
         'subtotal', o.subtotal,
         'commission_amount', o.commission_amount,
         'service_fee', o.service_fee,
         'reconstructed_by_migration', true
       ),
       true
from public.orders o
where o.status = 'redeemed'
  and not exists (
    select 1 from public.transactions t
    where t.reference_type = 'order' and t.reference_id = o.id
      and t.kind = 'income' and t.trusted
  );
alter table public.transactions alter column trusted set default true;

update public.notifications
set type = case when type in ('payment', 'ready', 'newBag', 'rating', 'order', 'payout', 'system')
                then type else 'system' end,
    title = coalesce(nullif(btrim(title), ''), 'SaveBite'),
    body = coalesce(body, ''),
    group_label = coalesce(nullif(group_label, ''), 'Hari ini'),
    read = coalesce(read, false),
    data = coalesce(data, '{}'::jsonb);

-- 0001 allowed reviews unrelated to an order. They cannot be safely retained.
delete from public.reviews r
where r.order_id is null
   or not exists (
     select 1
     from public.orders o
     where o.id = r.order_id
       and o.status = 'redeemed'
       and o.consumer_id = r.consumer_id
       and o.merchant_id = r.merchant_id
   );

update public.reviews
set tags = coalesce(tags, '{}'::text[]),
    comment = coalesce(comment, ''),
    created_at = coalesce(created_at, now());

delete from public.reviews r
using public.reviews keep
where r.order_id = keep.order_id
  and (r.created_at, r.id) > (keep.created_at, keep.id);

alter table public.reviews alter column order_id set not null;

-- ---------------------------------------------------------------------------
-- Constraints
-- ---------------------------------------------------------------------------

alter table public.profiles drop constraint if exists profiles_last_mode_check;
alter table public.profiles add constraint profiles_last_mode_check
  check (last_mode in ('consumer', 'merchant'));

alter table public.merchants drop constraint if exists merchants_status_check;
alter table public.merchants add constraint merchants_status_check
  check (status in ('pending', 'active', 'inactive', 'suspended', 'deleted'));
alter table public.merchants drop constraint if exists merchants_rating_check;
alter table public.merchants add constraint merchants_rating_check check (rating between 0 and 5);
alter table public.merchants drop constraint if exists merchants_review_count_check;
alter table public.merchants add constraint merchants_review_count_check check (review_count >= 0);
alter table public.merchants drop constraint if exists merchants_bags_saved_check;
alter table public.merchants add constraint merchants_bags_saved_check check (bags_saved >= 0);

alter table public.surprise_bags drop constraint if exists bags_price_check;
alter table public.surprise_bags add constraint bags_price_check
  check (sale_price between 1 and 10000000
     and original_price between sale_price and 100000000);
alter table public.surprise_bags drop constraint if exists bags_quantity_check;
alter table public.surprise_bags add constraint bags_quantity_check
  check (quantity_total between 1 and 1000
     and quantity_left between 0 and quantity_total);
alter table public.surprise_bags drop constraint if exists bags_status_check;
alter table public.surprise_bags add constraint bags_status_check
  check (status in ('active', 'sold_out', 'inactive'));
alter table public.surprise_bags drop constraint if exists bags_status_stock_check;
alter table public.surprise_bags add constraint bags_status_stock_check
  check ((status <> 'active' or quantity_left > 0)
     and (status <> 'sold_out' or quantity_left = 0));
alter table public.surprise_bags drop constraint if exists bags_pickup_times_check;
alter table public.surprise_bags add constraint bags_pickup_times_check
  check (
    (pickup_start_at is null and pickup_end_at is null)
    or (
      pickup_start_at is not null
      and pickup_end_at is not null
      and pickup_end_at > pickup_start_at
      and (pickup_start_at at time zone 'Asia/Jakarta')::date = available_on
    )
  );
alter table public.surprise_bags drop constraint if exists bags_content_check;
alter table public.surprise_bags add constraint bags_content_check check (
  length(btrim(title)) between 2 and 120
  and length(description) <= 2000
  and length(pickup_window) <= 100
  and cardinality(contents) <= 20
  and octet_length(array_to_string(contents, '')) <= 2000
);
alter table public.surprise_bags alter column available_on set not null;
alter table public.surprise_bags alter column description set not null;
alter table public.surprise_bags alter column pickup_window set not null;
alter table public.surprise_bags alter column contents set not null;

alter table public.orders drop constraint if exists orders_quantity_check;
alter table public.orders add constraint orders_quantity_check check (quantity between 1 and 100);
alter table public.orders drop constraint if exists orders_reference_check;
alter table public.orders add constraint orders_reference_check
  check (order_reference ~ '^SB-[A-Z0-9]{8,40}$');
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('pending', 'paid', 'ready', 'redeemed', 'cancelled', 'expired', 'refunded'));
alter table public.orders drop constraint if exists orders_amounts_check;
alter table public.orders add constraint orders_amounts_check check (
  unit_price > 0
  and original_price_snapshot >= unit_price
  and subtotal = unit_price * quantity
  and service_fee >= 0
  and total_amount = subtotal + service_fee
  and commission_amount between 0 and subtotal
  and merchant_net_amount = subtotal - commission_amount
);
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check
  check (length(btrim(payment_method)) between 1 and 64);
alter table public.orders drop constraint if exists orders_idempotency_key_check;
alter table public.orders add constraint orders_idempotency_key_check
  check (idempotency_key is null or length(idempotency_key) between 8 and 128);
alter table public.orders drop constraint if exists orders_pickup_hash_check;
alter table public.orders add constraint orders_pickup_hash_check
  check (pickup_token_hash is null or octet_length(pickup_token_hash) = 32);
alter table public.orders drop constraint if exists orders_pickup_times_check;
alter table public.orders add constraint orders_pickup_times_check
  check (
    (pickup_start_at is null and pickup_end_at is null)
    or (pickup_start_at is not null and pickup_end_at is not null
        and pickup_end_at > pickup_start_at)
  );
alter table public.orders drop constraint if exists orders_lifecycle_check;
alter table public.orders add constraint orders_lifecycle_check check (
  expires_at >= created_at
  and (status <> 'ready' or ready_at is not null)
  and (status <> 'redeemed' or redeemed_at is not null)
  and (status <> 'cancelled' or cancelled_at is not null)
  and (status <> 'expired' or expired_at is not null)
);

alter table public.orders alter column subtotal set not null;
alter table public.orders alter column order_reference set not null;
alter table public.orders alter column order_reference
  set default ('SB-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)));
alter table public.orders alter column service_fee set default 1000;
alter table public.orders alter column service_fee set not null;
alter table public.orders alter column unit_price set not null;
alter table public.orders alter column original_price_snapshot set not null;
alter table public.orders alter column commission_amount set not null;
alter table public.orders alter column merchant_net_amount set not null;
alter table public.orders alter column bag_title set not null;
alter table public.orders alter column merchant_name_snapshot set not null;
alter table public.orders alter column expires_at set not null;
alter table public.orders alter column updated_at set not null;
alter table public.orders alter column payment_method set not null;
alter table public.orders alter column created_at set not null;

alter table public.reviews drop constraint if exists reviews_rating_check;
alter table public.reviews add constraint reviews_rating_check check (rating between 1 and 5);
alter table public.reviews drop constraint if exists reviews_content_check;
alter table public.reviews add constraint reviews_content_check check (
  cardinality(tags) <= 10
  and octet_length(array_to_string(tags, '')) <= 500
  and length(comment) <= 1000
);
alter table public.reviews alter column tags set not null;
alter table public.reviews alter column comment set not null;

alter table public.transactions drop constraint if exists transactions_kind_check;
alter table public.transactions add constraint transactions_kind_check
  check (kind in ('income', 'withdrawal', 'withdrawal_reversal'));
alter table public.transactions drop constraint if exists transactions_amount_check;
alter table public.transactions add constraint transactions_amount_check check (amount > 0);
alter table public.transactions drop constraint if exists transactions_reference_check;
alter table public.transactions add constraint transactions_reference_check check (
  (reference_type is null and reference_id is null)
  or (reference_type is not null and reference_id is not null)
);

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('payment', 'ready', 'newBag', 'rating', 'order', 'payout', 'system'));
alter table public.notifications alter column type set not null;
alter table public.notifications alter column title set not null;
alter table public.notifications alter column body set not null;
alter table public.notifications alter column group_label set not null;
alter table public.notifications alter column read set not null;

alter table public.bank_accounts drop constraint if exists bank_accounts_bank_code_check;
alter table public.bank_accounts add constraint bank_accounts_bank_code_check
  check (bank_code ~ '^[A-Z0-9_]{2,20}$');
alter table public.bank_accounts drop constraint if exists bank_accounts_last4_check;
alter table public.bank_accounts add constraint bank_accounts_last4_check
  check (account_number_last4 ~ '^[0-9]{4}$');
alter table public.bank_accounts drop constraint if exists bank_accounts_status_check;
alter table public.bank_accounts add constraint bank_accounts_status_check
  check (status in ('pending', 'verified', 'rejected', 'disabled'));
alter table public.bank_accounts drop constraint if exists bank_accounts_holder_check;
alter table public.bank_accounts add constraint bank_accounts_holder_check
  check (length(btrim(account_holder)) between 2 and 100);

alter table public.payout_requests drop constraint if exists payout_requests_amounts_check;
alter table public.payout_requests add constraint payout_requests_amounts_check check (
  amount > 0 and fee_amount >= 0 and net_amount = amount - fee_amount and net_amount > 0
);
alter table public.payout_requests drop constraint if exists payout_requests_status_check;
alter table public.payout_requests add constraint payout_requests_status_check
  check (status in ('requested', 'processing', 'paid', 'failed', 'cancelled'));
alter table public.payout_requests drop constraint if exists payout_requests_idempotency_check;
alter table public.payout_requests add constraint payout_requests_idempotency_check
  check (length(idempotency_key) between 8 and 128);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists bags_discovery_idx
  on public.surprise_bags (status, available_on, pickup_end_at, created_at desc);
create index if not exists bags_merchant_status_idx
  on public.surprise_bags (merchant_id, status, available_on desc);
create index if not exists orders_consumer_status_created_idx
  on public.orders (consumer_id, status, created_at desc);
create index if not exists orders_merchant_status_created_idx
  on public.orders (merchant_id, status, created_at desc);
create index if not exists orders_expiry_idx
  on public.orders (expires_at)
  where status in ('paid', 'ready');
create unique index if not exists orders_pickup_token_hash_uidx
  on public.orders (pickup_token_hash)
  where pickup_token_hash is not null;
create unique index if not exists orders_consumer_idempotency_uidx
  on public.orders (consumer_id, idempotency_key)
  where consumer_id is not null and idempotency_key is not null;
create unique index if not exists orders_reference_uidx
  on public.orders (order_reference);
create unique index if not exists reviews_order_uidx on public.reviews (order_id);
create index if not exists reviews_merchant_created_idx
  on public.reviews (merchant_id, created_at desc);
create index if not exists favorites_merchant_idx on public.favorites (merchant_id);
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create unique index if not exists notifications_user_dedupe_uidx
  on public.notifications (user_id, dedupe_key);
create index if not exists transactions_merchant_created_idx
  on public.transactions (merchant_id, created_at desc);
create unique index if not exists transactions_reference_kind_uidx
  on public.transactions (reference_type, reference_id, kind)
  where reference_type is not null and reference_id is not null;
create unique index if not exists transactions_merchant_idempotency_uidx
  on public.transactions (merchant_id, idempotency_key)
  where idempotency_key is not null;
create unique index if not exists bank_accounts_active_number_uidx
  on public.bank_accounts (merchant_id, account_number_hash)
  where status in ('pending', 'verified');
create unique index if not exists bank_accounts_merchant_idempotency_uidx
  on public.bank_accounts (merchant_id, idempotency_key)
  where idempotency_key is not null;
create unique index if not exists bank_accounts_one_default_uidx
  on public.bank_accounts (merchant_id)
  where is_default and status in ('pending', 'verified');
create unique index if not exists payout_requests_merchant_idempotency_uidx
  on public.payout_requests (merchant_id, idempotency_key);
create index if not exists payout_requests_merchant_created_idx
  on public.payout_requests (merchant_id, requested_at desc);

-- ---------------------------------------------------------------------------
-- Generic and protective triggers
-- ---------------------------------------------------------------------------

drop trigger if exists t_orders_updated on public.orders;
create trigger t_orders_updated before update on public.orders
  for each row execute function public.touch_updated_at();

drop trigger if exists t_bank_accounts_updated on public.bank_accounts;
create trigger t_bank_accounts_updated before update on public.bank_accounts
  for each row execute function public.touch_updated_at();

drop trigger if exists t_payout_requests_updated on public.payout_requests;
create trigger t_payout_requests_updated before update on public.payout_requests
  for each row execute function public.touch_updated_at();

create or replace function public.protect_merchant_managed_fields()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if current_user in ('anon', 'authenticated') and (
    new.user_id is distinct from old.user_id
    or new.status is distinct from old.status
    or new.rating is distinct from old.rating
    or new.review_count is distinct from old.review_count
    or new.bags_saved is distinct from old.bags_saved
    or new.deleted_at is distinct from old.deleted_at
  ) then
    raise exception 'server-managed merchant fields cannot be changed by clients'
      using errcode = '42501';
  end if;
  return new;
end
$$;

drop trigger if exists protect_merchant_fields on public.merchants;
create trigger protect_merchant_fields
  before update on public.merchants
  for each row execute function public.protect_merchant_managed_fields();

create or replace function public.maintain_bag_inventory()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_sold integer;
begin
  new.available_on := coalesce(
    new.available_on,
    (now() at time zone 'Asia/Jakarta')::date
  );
  if tg_op = 'INSERT' then
    -- A client may provide quantity_left for compatibility, but cannot publish
    -- phantom sales at creation time.
    if current_user in ('anon', 'authenticated') then
      new.quantity_left := new.quantity_total;
    end if;
  elsif current_user in ('anon', 'authenticated') then
    if new.quantity_left is distinct from old.quantity_left then
      raise exception 'quantity_left is server-managed' using errcode = '42501';
    end if;
    if new.quantity_total is distinct from old.quantity_total then
      v_sold := old.quantity_total - old.quantity_left;
      if new.quantity_total < v_sold then
        raise exception 'quantity_total cannot be lower than already sold quantity';
      end if;
      new.quantity_left := new.quantity_total - v_sold;
    end if;
  end if;

  if new.quantity_left = 0 then
    new.status := 'sold_out';
  elsif new.status = 'sold_out' then
    new.status := 'inactive';
  end if;
  return new;
end
$$;

drop trigger if exists maintain_bag_inventory on public.surprise_bags;
create trigger maintain_bag_inventory
  before insert or update on public.surprise_bags
  for each row execute function public.maintain_bag_inventory();

create or replace function public.reject_ledger_mutation()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  raise exception 'ledger entries are immutable; append a compensating entry'
    using errcode = '42501';
end
$$;

drop trigger if exists transactions_immutable on public.transactions;
create trigger transactions_immutable
  before update or delete on public.transactions
  for each row execute function public.reject_ledger_mutation();

-- ---------------------------------------------------------------------------
-- Notification producers and reputation aggregation
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_notification(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text,
  p_dedupe_key text,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if p_user_id is null then return; end if;
  insert into public.notifications
    (user_id, title, body, type, group_label, read, dedupe_key,
     entity_type, entity_id, data)
  values
    (p_user_id, p_title, coalesce(p_body, ''), p_type, 'Hari ini', false,
     p_dedupe_key, p_entity_type, p_entity_id, coalesce(p_data, '{}'::jsonb))
  on conflict (user_id, dedupe_key) do nothing;
end
$$;

revoke all on function public.enqueue_notification(uuid,text,text,text,text,text,uuid,jsonb)
  from public, anon, authenticated;

create or replace function public.notify_order_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_merchant_user uuid;
begin
  select user_id into v_merchant_user from public.merchants where id = new.merchant_id;

  if tg_op = 'INSERT' then
    perform public.enqueue_notification(
      new.consumer_id,
      'Pesanan berhasil',
      new.bag_title || ' siap diproses. Total Rp' || new.total_amount,
      'payment', 'order:' || new.id || ':paid', 'order', new.id,
      jsonb_build_object('status', new.status)
    );
    perform public.enqueue_notification(
      v_merchant_user,
      'Pesanan baru',
      new.quantity || 'x ' || new.bag_title,
      'order', 'merchant-order:' || new.id || ':new', 'order', new.id,
      jsonb_build_object('status', new.status)
    );
  elsif new.status is distinct from old.status then
    if new.status = 'ready' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan siap diambil', new.bag_title || ' sudah siap.',
        'ready', 'order:' || new.id || ':ready', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'redeemed' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan selesai', 'Bag sudah diambil. Beri penilaian untuk merchant.',
        'rating', 'order:' || new.id || ':redeemed', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'expired' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan kedaluwarsa', new.bag_title || ' melewati batas pengambilan.',
        'order', 'order:' || new.id || ':expired', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'cancelled' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan dibatalkan', new.bag_title || ' telah dibatalkan.',
        'order', 'order:' || new.id || ':cancelled', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists notify_order_change on public.orders;
create trigger notify_order_change
  after insert or update of status on public.orders
  for each row execute function public.notify_order_change();

create or replace function public.recompute_merchant_rating()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_merchant_id uuid := coalesce(new.merchant_id, old.merchant_id);
begin
  update public.merchants m
  set rating = coalesce((
        select round(avg(r.rating)::numeric, 1)
        from public.reviews r where r.merchant_id = v_merchant_id
      ), 0),
      review_count = (
        select count(*)::integer
        from public.reviews r where r.merchant_id = v_merchant_id
      )
  where m.id = v_merchant_id;

  if tg_op = 'INSERT' then
    perform public.enqueue_notification(
      (select user_id from public.merchants where id = v_merchant_id),
      'Ulasan baru', new.rating || ' bintang untuk pesanan terbaru.',
      'rating', 'review:' || new.id, 'review', new.id,
      jsonb_build_object('rating', new.rating)
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists on_review_insert on public.reviews;
drop trigger if exists recompute_rating_after_review on public.reviews;
create trigger recompute_rating_after_review
  after insert or update of rating, merchant_id or delete on public.reviews
  for each row execute function public.recompute_merchant_rating();

create or replace function public.notify_new_bag()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.status = 'active' and (
    tg_op = 'INSERT'
    or old.status is distinct from new.status
    or old.available_on is distinct from new.available_on
  ) then
    insert into public.notifications
      (user_id, title, body, type, group_label, read, dedupe_key,
       entity_type, entity_id, data)
    select f.consumer_id,
           'Surprise Bag baru',
           new.title || ' tersedia dari merchant favoritmu.',
           'newBag', 'Hari ini', false,
           'bag:' || new.id || ':' || new.available_on,
           'bag', new.id,
           jsonb_build_object('available_on', new.available_on)
    from public.favorites f
    where f.merchant_id = new.merchant_id
    on conflict (user_id, dedupe_key) do nothing;
  end if;
  return new;
end
$$;

drop trigger if exists notify_new_bag on public.surprise_bags;
create trigger notify_new_bag
  after insert or update of status, available_on on public.surprise_bags
  for each row execute function public.notify_new_bag();

create or replace function public.notify_payout_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid;
begin
  select user_id into v_uid from public.merchants where id = new.merchant_id;
  if tg_op = 'INSERT' then
    perform public.enqueue_notification(
      v_uid, 'Penarikan diajukan',
      'Penarikan Rp' || new.amount || ' sedang diproses.',
      'payout', 'payout:' || new.id || ':requested', 'payout', new.id,
      jsonb_build_object('status', new.status)
    );
  elsif new.status is distinct from old.status then
    perform public.enqueue_notification(
      v_uid, 'Status penarikan: ' || new.status,
      case when new.status = 'paid'
        then 'Dana bersih Rp' || new.net_amount || ' telah dikirim.'
        when new.status in ('failed', 'cancelled')
        then 'Saldo Rp' || new.amount || ' telah dikembalikan.'
        else 'Permintaan penarikan sedang diproses.' end,
      'payout', 'payout:' || new.id || ':' || new.status, 'payout', new.id,
      jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end
$$;

drop trigger if exists notify_payout_change on public.payout_requests;
create trigger notify_payout_change
  after insert or update of status on public.payout_requests
  for each row execute function public.notify_payout_change();

-- profiles.email mirrors the verified Auth identity and cannot be edited via
-- the Data API independently from auth.users.
create or replace function public.sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end
$$;

drop trigger if exists on_auth_user_email_updated on auth.users;
create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row execute function public.sync_profile_email_from_auth();

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id and p.email is distinct from u.email;

-- Rebuild reputational values from trusted rows. Seed/demo counters from 0001
-- are intentionally discarded because they were client-writable.
update public.merchants m
set rating = coalesce((select round(avg(r.rating)::numeric, 1)
                       from public.reviews r where r.merchant_id = m.id), 0),
    review_count = (select count(*)::integer
                    from public.reviews r where r.merchant_id = m.id),
    bags_saved = coalesce((select sum(o.quantity)::integer
                           from public.orders o
                           where o.merchant_id = m.id and o.status = 'redeemed'), 0);

-- ---------------------------------------------------------------------------
-- Hardened checkout and pickup RPCs
-- ---------------------------------------------------------------------------

create or replace function public.update_surprise_bag(
  p_bag_id uuid,
  p_title text,
  p_description text,
  p_original_price integer,
  p_sale_price integer,
  p_quantity_total integer,
  p_pickup_window text,
  p_image_url text,
  p_available_on date,
  p_pickup_start_at timestamptz,
  p_pickup_end_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_bag public.surprise_bags;
  v_owner uuid;
  v_sold integer;
  v_left integer;
  v_status text;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into v_bag from public.surprise_bags where id = p_bag_id for update;
  if not found then raise exception 'bag not found'; end if;
  select user_id into v_owner from public.merchants where id = v_bag.merchant_id;
  if v_owner is distinct from v_uid then raise exception 'bag does not belong to your merchant'; end if;

  if length(btrim(coalesce(p_title, ''))) not between 2 and 120 then
    raise exception 'title must contain 2-120 characters';
  end if;
  if length(coalesce(p_description, '')) > 2000 then raise exception 'description is too long'; end if;
  if p_sale_price is null or p_sale_price <= 0
     or p_original_price is null or p_original_price < p_sale_price then
    raise exception 'invalid bag prices';
  end if;
  if p_quantity_total is null or p_quantity_total not between 1 and 1000 then
    raise exception 'quantity_total must be between 1 and 1000';
  end if;
  if p_available_on is null then raise exception 'available_on is required'; end if;
  if (p_pickup_start_at is null) <> (p_pickup_end_at is null) then
    raise exception 'pickup start and end must both be provided or both be null';
  end if;
  if p_pickup_start_at is not null and (
    p_pickup_end_at <= p_pickup_start_at
    or (p_pickup_start_at at time zone 'Asia/Jakarta')::date <> p_available_on
  ) then
    raise exception 'invalid pickup window';
  end if;

  v_sold := v_bag.quantity_total - v_bag.quantity_left;
  if p_quantity_total < v_sold then
    raise exception 'quantity_total cannot be lower than already sold quantity';
  end if;
  v_left := p_quantity_total - v_sold;
  v_status := case
    when v_left = 0 then 'sold_out'
    when v_bag.status = 'active' then 'active'
    else 'inactive'
  end;

  update public.surprise_bags
  set title = btrim(p_title),
      description = btrim(coalesce(p_description, '')),
      original_price = p_original_price,
      sale_price = p_sale_price,
      quantity_total = p_quantity_total,
      quantity_left = v_left,
      pickup_window = btrim(coalesce(p_pickup_window, '')),
      image_url = nullif(btrim(coalesce(p_image_url, '')), ''),
      available_on = p_available_on,
      pickup_start_at = p_pickup_start_at,
      pickup_end_at = p_pickup_end_at,
      status = v_status
  where id = v_bag.id
  returning * into v_bag;

  return to_jsonb(v_bag);
end
$$;

create or replace function public.set_bag_active(p_bag_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_bag public.surprise_bags;
  v_merchant public.merchants;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_active is null then raise exception 'active flag is required'; end if;
  select * into v_bag from public.surprise_bags where id = p_bag_id for update;
  if not found then raise exception 'bag not found'; end if;
  select * into v_merchant from public.merchants where id = v_bag.merchant_id;
  if not found or v_merchant.user_id is distinct from v_uid then
    raise exception 'bag does not belong to your merchant';
  end if;

  if p_active then
    if v_merchant.status <> 'active' then raise exception 'merchant is not active'; end if;
    if v_bag.quantity_left <= 0 then raise exception 'bag has no remaining stock'; end if;
    if v_bag.available_on < v_today then raise exception 'bag availability date has passed'; end if;
    if v_bag.pickup_end_at is not null and v_bag.pickup_end_at <= now() then
      raise exception 'pickup window has ended';
    end if;
  end if;

  update public.surprise_bags
  set status = case
    when p_active then 'active'
    when quantity_left = 0 then 'sold_out'
    else 'inactive'
  end
  where id = v_bag.id
  returning * into v_bag;
  return to_jsonb(v_bag);
end
$$;

drop function if exists public.purchase_bag(uuid, integer, text);
drop function if exists public.purchase_bag(uuid, integer, text, text);

create function public.purchase_bag(
  p_bag_id uuid,
  p_qty integer,
  p_method text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_bag public.surprise_bags;
  v_merchant public.merchants;
  v_order public.orders;
  v_existing public.orders;
  v_name text;
  v_token text;
  v_fee integer := private.setting_int('service_fee');
  v_commission_bps integer := private.setting_int('merchant_commission_bps');
  v_subtotal integer;
  v_commission integer;
  v_expires_at timestamptz;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 100 then raise exception 'quantity must be between 1 and 100'; end if;
  if p_method is null or length(btrim(p_method)) not between 1 and 64 then
    raise exception 'invalid payment method';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  -- Serialize retries before checking the unique key, including retries using
  -- a different bag while reusing the same key.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text || ':' || p_idempotency_key, 0));

  select * into v_existing
  from public.orders
  where consumer_id = v_uid and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.bag_id <> p_bag_id
       or v_existing.quantity <> p_qty
       or v_existing.payment_method <> btrim(p_method) then
      raise exception 'idempotency key was already used with different parameters';
    end if;
    if v_existing.status not in ('paid', 'ready') or v_existing.expires_at <= now() then
      return (to_jsonb(v_existing) - 'pickup_token_hash' - 'pickup_code')
        || jsonb_build_object('order_id', v_existing.id, 'pickup_code', null);
    end if;

    v_token := 'SB2_' || encode(extensions.gen_random_bytes(24), 'hex');
    update public.orders
    set pickup_token_hash = extensions.digest(v_token, 'sha256'),
        pickup_code_hint = right(v_token, 6),
        pickup_token_issued_at = now()
    where id = v_existing.id
    returning * into v_existing;

    return (to_jsonb(v_existing) - 'pickup_token_hash' - 'pickup_code')
      || jsonb_build_object('order_id', v_existing.id, 'pickup_code', v_token);
  end if;

  select * into v_bag from public.surprise_bags where id = p_bag_id for update;
  if not found then raise exception 'bag not found'; end if;

  select * into v_merchant from public.merchants where id = v_bag.merchant_id;
  if not found or v_merchant.status <> 'active' or v_merchant.user_id is null then
    raise exception 'merchant is unavailable';
  end if;
  if v_bag.status <> 'active' then raise exception 'bag is not active'; end if;
  if v_bag.available_on > v_today then raise exception 'bag is not available yet'; end if;
  if v_bag.pickup_end_at is not null and v_bag.pickup_end_at <= now() then
    raise exception 'pickup window has ended';
  end if;
  if v_bag.quantity_left < p_qty then raise exception 'insufficient stock'; end if;

  v_subtotal := v_bag.sale_price * p_qty;
  v_commission := round(v_subtotal * v_commission_bps / 10000.0)::integer;
  v_expires_at := case
    when v_bag.pickup_end_at is not null then v_bag.pickup_end_at
    else now() + interval '72 hours'
  end;
  v_token := 'SB2_' || encode(extensions.gen_random_bytes(24), 'hex');
  select name into v_name from public.profiles where id = v_uid;

  update public.surprise_bags
  set quantity_left = quantity_left - p_qty,
      status = case when quantity_left - p_qty = 0 then 'sold_out' else status end
  where id = p_bag_id;

  insert into public.orders (
    consumer_id, consumer_name, bag_id, merchant_id, quantity,
    subtotal, service_fee, total_amount, unit_price, original_price_snapshot,
    commission_amount, merchant_net_amount, payment_method, status,
    pickup_code, pickup_token_hash, pickup_code_hint, pickup_token_issued_at,
    bag_title, bag_description, bag_image_url, pickup_window_snapshot,
    merchant_name_snapshot, merchant_category_snapshot,
    merchant_address_snapshot, merchant_logo_url_snapshot,
    merchant_rating_snapshot, merchant_review_count_snapshot,
    pickup_start_at, pickup_end_at, expires_at, paid_at, idempotency_key
  ) values (
    v_uid, coalesce(v_name, 'Pelanggan'), v_bag.id, v_bag.merchant_id, p_qty,
    v_subtotal, v_fee, v_subtotal + v_fee, v_bag.sale_price, v_bag.original_price,
    v_commission, v_subtotal - v_commission, btrim(p_method), 'paid',
    null, extensions.digest(v_token, 'sha256'), right(v_token, 6), now(),
    v_bag.title, v_bag.description, v_bag.image_url, v_bag.pickup_window,
    v_merchant.store_name, v_merchant.category, v_merchant.address,
    v_merchant.logo_url, v_merchant.rating, v_merchant.review_count,
    v_bag.pickup_start_at, v_bag.pickup_end_at, v_expires_at, now(),
    p_idempotency_key
  ) returning * into v_order;

  return (to_jsonb(v_order) - 'pickup_token_hash' - 'pickup_code')
    || jsonb_build_object('order_id', v_order.id, 'pickup_code', v_token);
end
$$;

create or replace function public.issue_pickup_token(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_token text;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.consumer_id is distinct from v_uid then raise exception 'order not found'; end if;
  if v_order.status not in ('paid', 'ready') then raise exception 'order cannot be picked up'; end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;

  v_token := 'SB2_' || encode(extensions.gen_random_bytes(24), 'hex');
  update public.orders
  set pickup_token_hash = extensions.digest(v_token, 'sha256'),
      pickup_code_hint = right(v_token, 6),
      pickup_token_issued_at = now()
  where id = v_order.id;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_reference', v_order.order_reference,
    'pickup_code', v_token,
    'pickup_code_hint', right(v_token, 6),
    'expires_at', v_order.expires_at
  );
end
$$;

create or replace function public.mark_order_ready(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_owner uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order not found'; end if;
  select user_id into v_owner from public.merchants where id = v_order.merchant_id;
  if v_owner is distinct from v_uid then raise exception 'order does not belong to your merchant'; end if;
  if v_order.status <> 'paid' then raise exception 'only paid orders can be marked ready'; end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;

  update public.orders set status = 'ready', ready_at = now()
  where id = v_order.id returning * into v_order;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_reference', v_order.order_reference,
    'status', v_order.status,
    'ready_at', v_order.ready_at,
    'expires_at', v_order.expires_at
  );
end
$$;

create or replace function public.redeem_order(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_order public.orders;
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_code is null or length(p_code) < 32 then raise exception 'invalid pickup token'; end if;

  select * into v_order
  from public.orders
  where pickup_token_hash = extensions.digest(p_code, 'sha256')
  for update;
  if not found then raise exception 'order not found'; end if;

  select user_id into v_owner from public.merchants where id = v_order.merchant_id;
  if v_owner is distinct from v_uid then raise exception 'order does not belong to your merchant'; end if;
  if v_order.status = 'redeemed' then raise exception 'order was already redeemed'; end if;
  if v_order.status not in ('paid', 'ready') then raise exception 'order is not redeemable'; end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;
  if v_order.pickup_start_at is not null and now() < v_order.pickup_start_at then
    raise exception 'pickup window has not started';
  end if;
  if v_order.pickup_end_at is not null and now() >= v_order.pickup_end_at then
    raise exception 'pickup window has ended';
  end if;

  update public.orders
  set status = 'redeemed', redeemed_at = now(), pickup_token_used_at = now()
  where id = v_order.id
  returning * into v_order;

  insert into public.transactions
    (merchant_id, title, subtitle, amount, kind, reference_type,
     reference_id, idempotency_key, metadata, created_by)
  values
    (v_order.merchant_id,
     'Order ' || v_order.order_reference,
     'Pendapatan bersih setelah komisi Rp' || v_order.commission_amount,
     v_order.merchant_net_amount, 'income', 'order', v_order.id,
     'order:' || v_order.id, jsonb_build_object(
       'subtotal', v_order.subtotal,
       'commission_amount', v_order.commission_amount,
       'service_fee', v_order.service_fee
     ), v_uid)
  on conflict (reference_type, reference_id, kind)
    where reference_type is not null and reference_id is not null
    do nothing;

  update public.merchants
  set bags_saved = bags_saved + v_order.quantity
  where id = v_order.merchant_id;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_reference', v_order.order_reference,
    'pickup_code', v_order.order_reference,
    'quantity', v_order.quantity,
    'customer_name', v_order.consumer_name,
    'bag_title', v_order.bag_title,
    'created_at', v_order.created_at,
    'redeemed_at', v_order.redeemed_at,
    'merchant_net_amount', v_order.merchant_net_amount
  );
end
$$;

create or replace function public.expire_orders(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_count integer;
begin
  if session_user::text not in ('postgres', 'supabase_admin', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'limit must be between 1 and 5000';
  end if;

  with candidates as (
    select id from public.orders
    where status in ('paid', 'ready') and expires_at <= now()
    order by expires_at
    for update skip locked
    limit p_limit
  )
  update public.orders o
  set status = 'expired', expired_at = now()
  from candidates c
  where o.id = c.id;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

-- ---------------------------------------------------------------------------
-- Review RPC
-- ---------------------------------------------------------------------------

create or replace function public.submit_review(
  p_order_id uuid,
  p_rating integer,
  p_tags text[] default '{}'::text[],
  p_comment text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_review public.reviews;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'rating must be between 1 and 5';
  end if;
  if cardinality(coalesce(p_tags, '{}'::text[])) > 10 then raise exception 'too many review tags'; end if;
  if octet_length(array_to_string(coalesce(p_tags, '{}'::text[]), '')) > 500 then
    raise exception 'review tags are too long';
  end if;
  if length(coalesce(p_comment, '')) > 1000 then raise exception 'review comment is too long'; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.consumer_id is distinct from v_uid then raise exception 'order not found'; end if;
  if v_order.status <> 'redeemed' then raise exception 'only redeemed orders can be reviewed'; end if;

  insert into public.reviews (order_id, consumer_id, merchant_id, rating, tags, comment)
  values (v_order.id, v_uid, v_order.merchant_id, p_rating,
          coalesce(p_tags, '{}'::text[]), btrim(coalesce(p_comment, '')))
  on conflict (order_id) do nothing
  returning * into v_review;

  if v_review.id is null then raise exception 'order was already reviewed'; end if;
  return to_jsonb(v_review);
end
$$;

-- ---------------------------------------------------------------------------
-- Bank account and withdrawal RPCs
-- ---------------------------------------------------------------------------

create or replace function public.register_bank_account(
  p_bank_code text,
  p_account_holder text,
  p_account_number text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant_id uuid;
  v_number text;
  v_hash bytea;
  v_pepper text;
  v_bank_code text := upper(btrim(p_bank_code));
  v_bank_name text;
  v_account public.bank_accounts;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select id into v_merchant_id from public.merchants
  where user_id = v_uid and status in ('active', 'pending') for update;
  if not found then raise exception 'merchant not found'; end if;
  if v_bank_code is null or v_bank_code !~ '^[A-Z0-9_]{2,20}$' then
    raise exception 'invalid bank code';
  end if;
  if length(btrim(coalesce(p_account_holder, ''))) not between 2 and 100 then
    raise exception 'invalid account holder';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  v_number := regexp_replace(coalesce(p_account_number, ''), '[^0-9]', '', 'g');
  if length(v_number) not between 6 and 20 then raise exception 'invalid account number'; end if;
  select text_value into v_pepper from private.app_settings where key = 'bank_hash_pepper';
  v_hash := extensions.hmac(v_number, v_pepper, 'sha256');
  v_bank_name := case v_bank_code
    when 'BCA' then 'Bank Central Asia'
    when 'MANDIRI' then 'Bank Mandiri'
    when 'BNI' then 'Bank Negara Indonesia'
    when 'BRI' then 'Bank Rakyat Indonesia'
    else v_bank_code
  end;

  perform pg_advisory_xact_lock(hashtextextended(v_merchant_id::text || ':bank:' || p_idempotency_key, 0));
  select * into v_account from public.bank_accounts
  where merchant_id = v_merchant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_account.account_number_hash <> v_hash or v_account.bank_code <> v_bank_code then
      raise exception 'idempotency key was already used with different parameters';
    end if;
  else
    select * into v_account from public.bank_accounts
    where merchant_id = v_merchant_id and account_number_hash = v_hash
      and status in ('pending', 'verified')
    limit 1;
    if not found then
      insert into public.bank_accounts (
        merchant_id, bank_code, bank_name, account_holder,
        account_number_hash, account_number_last4, status,
        is_default, idempotency_key
      ) values (
        v_merchant_id, v_bank_code, v_bank_name, btrim(p_account_holder),
        v_hash, right(v_number, 4), 'pending',
        not exists (select 1 from public.bank_accounts
                    where merchant_id = v_merchant_id
                      and status in ('pending', 'verified')),
        p_idempotency_key
      ) returning * into v_account;
    end if;
  end if;

  return jsonb_build_object(
    'id', v_account.id,
    'merchant_id', v_account.merchant_id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_holder', v_account.account_holder,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status,
    'is_default', v_account.is_default,
    'created_at', v_account.created_at
  );
end
$$;

create or replace function public.set_default_bank_account(p_bank_account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant_id uuid;
  v_account public.bank_accounts;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select id into v_merchant_id from public.merchants where user_id = v_uid;
  if not found then raise exception 'merchant not found'; end if;
  select * into v_account from public.bank_accounts
  where id = p_bank_account_id and merchant_id = v_merchant_id
    and status in ('pending', 'verified')
  for update;
  if not found then raise exception 'bank account not found'; end if;

  update public.bank_accounts set is_default = false
  where merchant_id = v_merchant_id and is_default;
  update public.bank_accounts set is_default = true
  where id = v_account.id returning * into v_account;

  return jsonb_build_object(
    'id', v_account.id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status,
    'is_default', v_account.is_default
  );
end
$$;

-- Called by a trusted bank-account verification/tokenization worker. SaveBite
-- stores only a provider recipient identifier, a peppered hash, and last four
-- digits; the raw account number is discarded by register_bank_account.
create or replace function public.verify_bank_account(
  p_bank_account_id uuid,
  p_status text,
  p_provider_recipient_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_account public.bank_accounts;
  v_uid uuid;
begin
  if session_user::text not in ('postgres', 'supabase_admin', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('verified', 'rejected') then
    raise exception 'invalid verification status';
  end if;
  if p_status = 'verified' and length(btrim(coalesce(p_provider_recipient_id, ''))) < 3 then
    raise exception 'provider recipient id is required for a verified account';
  end if;

  select * into v_account from public.bank_accounts
  where id = p_bank_account_id and status in ('pending', 'verified') for update;
  if not found then raise exception 'bank account not found'; end if;

  update public.bank_accounts
  set status = p_status,
      provider_recipient_id = case when p_status = 'verified'
                                   then btrim(p_provider_recipient_id) else null end,
      is_default = case when p_status = 'rejected' then false else is_default end
  where id = v_account.id
  returning * into v_account;

  select user_id into v_uid from public.merchants where id = v_account.merchant_id;
  perform public.enqueue_notification(
    v_uid,
    case when p_status = 'verified' then 'Rekening terverifikasi' else 'Verifikasi rekening gagal' end,
    v_account.bank_name || ' *' || v_account.account_number_last4,
    'payout', 'bank-account:' || v_account.id || ':' || p_status,
    'bank_account', v_account.id, jsonb_build_object('status', p_status)
  );

  return jsonb_build_object(
    'id', v_account.id,
    'merchant_id', v_account.merchant_id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_holder', v_account.account_holder,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status,
    'is_default', v_account.is_default,
    'updated_at', v_account.updated_at
  );
end
$$;

create or replace function public.request_withdrawal(
  p_bank_account_id uuid,
  p_amount integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant public.merchants;
  v_bank public.bank_accounts;
  v_request public.payout_requests;
  v_available bigint;
  v_fee integer := private.setting_int('withdrawal_fee');
  v_minimum integer := private.setting_int('minimum_withdrawal');
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_amount is null or p_amount < v_minimum then
    raise exception 'minimum withdrawal is Rp% ', v_minimum;
  end if;
  if p_amount <= v_fee then raise exception 'withdrawal amount must exceed its fee'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  select * into v_merchant from public.merchants
  where user_id = v_uid and status = 'active' for update;
  if not found then raise exception 'active merchant not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_merchant.id::text || ':payout:' || p_idempotency_key, 0));
  select * into v_request from public.payout_requests
  where merchant_id = v_merchant.id and idempotency_key = p_idempotency_key;
  if found then
    if v_request.amount <> p_amount
       or v_request.bank_account_id is distinct from p_bank_account_id then
      raise exception 'idempotency key was already used with different parameters';
    end if;
    return to_jsonb(v_request);
  end if;

  select * into v_bank from public.bank_accounts
  where id = p_bank_account_id
    and merchant_id = v_merchant.id
    and status = 'verified'
  for update;
  if not found then raise exception 'verified bank account not found'; end if;

  select coalesce(sum(case t.kind
    when 'income' then t.amount
    when 'withdrawal' then -t.amount
    when 'withdrawal_reversal' then t.amount
    else 0 end), 0)
  into v_available
  from public.transactions t
  where t.merchant_id = v_merchant.id and t.trusted;

  if v_available < p_amount then raise exception 'insufficient available balance'; end if;

  insert into public.payout_requests (
    merchant_id, bank_account_id, bank_code, bank_name,
    account_number_last4, amount, fee_amount, net_amount,
    status, idempotency_key
  ) values (
    v_merchant.id, v_bank.id, v_bank.bank_code, v_bank.bank_name,
    v_bank.account_number_last4, p_amount, v_fee, p_amount - v_fee,
    'requested', p_idempotency_key
  ) returning * into v_request;

  -- Debit immediately to reserve funds and prevent concurrent overdraw. Failed
  -- payouts are restored with an immutable withdrawal_reversal entry.
  insert into public.transactions (
    merchant_id, title, subtitle, amount, kind, reference_type,
    reference_id, idempotency_key, metadata, created_by
  ) values (
    v_merchant.id,
    'Penarikan ke ' || v_bank.bank_name,
    'Diproses - rekening *' || v_bank.account_number_last4,
    p_amount, 'withdrawal', 'payout', v_request.id,
    'payout:' || p_idempotency_key,
    jsonb_build_object('fee_amount', v_fee, 'net_amount', p_amount - v_fee),
    v_uid
  );

  return to_jsonb(v_request);
end
$$;

create or replace function public.resolve_payout_request(
  p_request_id uuid,
  p_status text,
  p_provider_reference text default null,
  p_failure_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_request public.payout_requests;
begin
  if session_user::text not in ('postgres', 'supabase_admin', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('processing', 'paid', 'failed', 'cancelled') then
    raise exception 'invalid payout status';
  end if;

  select * into v_request from public.payout_requests where id = p_request_id for update;
  if not found then raise exception 'payout request not found'; end if;
  if v_request.status in ('paid', 'failed', 'cancelled') then
    if v_request.status <> p_status then raise exception 'payout is already final'; end if;
    return to_jsonb(v_request);
  end if;
  if p_status = 'paid' and v_request.status not in ('requested', 'processing') then
    raise exception 'invalid payout transition';
  end if;

  if p_status in ('failed', 'cancelled') then
    insert into public.transactions (
      merchant_id, title, subtitle, amount, kind,
      reference_type, reference_id, idempotency_key, metadata
    ) values (
      v_request.merchant_id, 'Pengembalian penarikan',
      coalesce(nullif(p_failure_reason, ''), 'Penarikan tidak berhasil'),
      v_request.amount, 'withdrawal_reversal', 'payout', v_request.id,
      'payout-reversal:' || v_request.id,
      jsonb_build_object('reason', p_failure_reason)
    )
    on conflict (reference_type, reference_id, kind)
      where reference_type is not null and reference_id is not null
      do nothing;
  end if;

  update public.payout_requests
  set status = p_status,
      provider_reference = coalesce(p_provider_reference, provider_reference),
      failure_reason = case when p_status in ('failed', 'cancelled')
                            then p_failure_reason else null end,
      processed_at = case when p_status in ('paid', 'failed', 'cancelled')
                          then now() else processed_at end
  where id = v_request.id
  returning * into v_request;
  return to_jsonb(v_request);
end
$$;

-- ---------------------------------------------------------------------------
-- Account deletion / anonymization
-- ---------------------------------------------------------------------------

create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select id into v_merchant_id from public.merchants where user_id = v_uid for update;

  if v_merchant_id is not null and exists (
    select 1 from public.payout_requests
    where merchant_id = v_merchant_id and status in ('requested', 'processing')
  ) then
    raise exception 'account cannot be deleted while a payout is in progress';
  end if;

  update public.orders
  set consumer_id = null,
      consumer_name = 'Pengguna dihapus',
      consumer_anonymized = true
  where consumer_id = v_uid;

  update public.reviews
  set consumer_id = null, tags = '{}'::text[], comment = ''
  where consumer_id = v_uid;

  if v_merchant_id is not null then
    delete from public.bank_accounts where merchant_id = v_merchant_id;
    update public.merchants
    set user_id = null,
        store_name = 'Toko ditutup',
        description = '', address = '', distance = '',
        lat = null, lng = null, logo_url = null,
        status = 'deleted', deleted_at = now()
    where id = v_merchant_id;
    update public.surprise_bags set status = 'inactive'
    where merchant_id = v_merchant_id and status = 'active';
  end if;

  -- Cascades remove profile, favorites, and notifications. Operational order,
  -- review, payout, and ledger records remain anonymized for integrity.
  delete from auth.users where id = v_uid;
  return jsonb_build_object('deleted', true, 'user_id', v_uid);
end
$$;

-- ---------------------------------------------------------------------------
-- RLS and privileges
-- ---------------------------------------------------------------------------

alter table public.bank_accounts enable row level security;
alter table public.payout_requests enable row level security;

drop policy if exists profiles_self on public.profiles;
drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_insert_self on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_select_self on public.profiles for select
  using (auth.uid() = id);
create policy profiles_insert_self on public.profiles for insert
  with check (auth.uid() = id);
create policy profiles_update_self on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists merchants_read on public.merchants;
create policy merchants_read on public.merchants for select using (
  (status = 'active' and user_id is not null) or user_id = auth.uid()
);
drop policy if exists merchants_write on public.merchants;
drop policy if exists merchants_insert_owner on public.merchants;
drop policy if exists merchants_update_owner on public.merchants;
create policy merchants_insert_owner on public.merchants for insert
  with check (auth.uid() = user_id);
create policy merchants_update_owner on public.merchants for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists bags_read on public.surprise_bags;
create policy bags_read on public.surprise_bags for select using (
  (
    status = 'active'
    and available_on <= (now() at time zone 'Asia/Jakarta')::date
    and (pickup_end_at is null or pickup_end_at > now())
    and exists (select 1 from public.merchants m
                where m.id = merchant_id
                  and m.status = 'active'
                  and m.user_id is not null)
  )
  or merchant_id in (select id from public.merchants where user_id = auth.uid())
  or exists (select 1 from public.orders o
             where o.bag_id = surprise_bags.id and o.consumer_id = auth.uid())
);
drop policy if exists bags_write on public.surprise_bags;
drop policy if exists bags_insert_owner on public.surprise_bags;
drop policy if exists bags_update_owner on public.surprise_bags;
create policy bags_insert_owner on public.surprise_bags for insert
  with check (merchant_id in (select id from public.merchants where user_id = auth.uid()));
create policy bags_update_owner on public.surprise_bags for update
  using (merchant_id in (select id from public.merchants where user_id = auth.uid()))
  with check (merchant_id in (select id from public.merchants where user_id = auth.uid()));

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select using (
  consumer_id = auth.uid()
  or merchant_id in (select id from public.merchants where user_id = auth.uid())
);

drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews for select using (true);
drop policy if exists reviews_insert on public.reviews;

drop policy if exists tx_owner on public.transactions;
drop policy if exists tx_owner_read on public.transactions;
create policy tx_owner_read on public.transactions for select using (
  trusted
  and merchant_id in (select id from public.merchants where user_id = auth.uid())
);

drop policy if exists notif_self on public.notifications;
drop policy if exists notif_select_self on public.notifications;
drop policy if exists notif_update_self on public.notifications;
create policy notif_select_self on public.notifications for select
  using (user_id = auth.uid());
create policy notif_update_self on public.notifications for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists bank_accounts_owner_read on public.bank_accounts;
create policy bank_accounts_owner_read on public.bank_accounts for select using (
  merchant_id in (select id from public.merchants where user_id = auth.uid())
);

drop policy if exists payout_requests_owner_read on public.payout_requests;
create policy payout_requests_owner_read on public.payout_requests for select using (
  merchant_id in (select id from public.merchants where user_id = auth.uid())
);

-- Remove broad 0001/default grants first, then expose only client-safe actions.
revoke all on public.profiles from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant update (name, avatar_url, phone, last_mode) on public.profiles to authenticated;

revoke all on public.merchants from public, anon, authenticated;
grant select (id, user_id, store_name, description, address, distance, lat, lng,
              category, open_time, close_time, logo_url, status, rating,
              review_count, bags_saved, created_at, updated_at, deleted_at)
  on public.merchants to authenticated;
grant select (id, store_name, description, address, distance, lat, lng,
              category, open_time, close_time, logo_url, status, rating,
              review_count, bags_saved, created_at, updated_at, deleted_at)
  on public.merchants to anon;
grant insert (user_id, store_name, description, address, distance, lat, lng,
              category, open_time, close_time, logo_url)
  on public.merchants to authenticated;
grant update (store_name, description, address, distance, lat, lng, category,
              open_time, close_time, logo_url)
  on public.merchants to authenticated;

revoke all on public.surprise_bags from public, anon, authenticated;
grant select on public.surprise_bags to anon, authenticated;
grant insert (merchant_id, title, description, original_price, sale_price,
              quantity_total, quantity_left, pickup_window, image_url,
              contents, status, available_on, pickup_start_at, pickup_end_at)
  on public.surprise_bags to authenticated;
grant update (title, description, original_price, sale_price,
              pickup_window, image_url, contents, available_on,
              pickup_start_at, pickup_end_at)
  on public.surprise_bags to authenticated;

-- Raw pickup tokens are not stored at all. Full row SELECT is needed by
-- Supabase `.stream()` for its initial snapshot; the exposed hash is a one-way
-- digest of a 192-bit token and cannot be presented to redeem_order.
revoke all on public.orders from public, anon, authenticated;
grant select on public.orders to authenticated;

revoke all on public.reviews from public, anon, authenticated;
grant select (id, order_id, merchant_id, rating, tags, comment, created_at)
  on public.reviews to anon, authenticated;

revoke all on public.transactions from public, anon, authenticated;
grant select on public.transactions to authenticated;

revoke all on public.notifications from public, anon, authenticated;
grant select on public.notifications to authenticated;
grant update (read) on public.notifications to authenticated;

revoke all on public.bank_accounts from public, anon, authenticated;
grant select (id, merchant_id, bank_code, bank_name, account_holder,
              account_number_last4, status, is_default, created_at, updated_at)
  on public.bank_accounts to authenticated;

revoke all on public.payout_requests from public, anon, authenticated;
grant select on public.payout_requests to authenticated;

-- RPCs are executable only by the intended API roles.
revoke all on function public.purchase_bag(uuid,integer,text,text) from public, anon;
revoke all on function public.update_surprise_bag(uuid,text,text,integer,integer,integer,text,text,date,timestamptz,timestamptz)
  from public, anon;
revoke all on function public.set_bag_active(uuid,boolean) from public, anon;
revoke all on function public.issue_pickup_token(uuid) from public, anon;
revoke all on function public.mark_order_ready(uuid) from public, anon;
revoke all on function public.redeem_order(text) from public, anon;
revoke all on function public.submit_review(uuid,integer,text[],text) from public, anon;
revoke all on function public.register_bank_account(text,text,text,text) from public, anon;
revoke all on function public.set_default_bank_account(uuid) from public, anon;
revoke all on function public.request_withdrawal(uuid,integer,text) from public, anon;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.purchase_bag(uuid,integer,text,text) to authenticated;
grant execute on function public.update_surprise_bag(uuid,text,text,integer,integer,integer,text,text,date,timestamptz,timestamptz)
  to authenticated;
grant execute on function public.set_bag_active(uuid,boolean) to authenticated;
grant execute on function public.issue_pickup_token(uuid) to authenticated;
grant execute on function public.mark_order_ready(uuid) to authenticated;
grant execute on function public.redeem_order(text) to authenticated;
grant execute on function public.submit_review(uuid,integer,text[],text) to authenticated;
grant execute on function public.register_bank_account(text,text,text,text) to authenticated;
grant execute on function public.set_default_bank_account(uuid) to authenticated;
grant execute on function public.request_withdrawal(uuid,integer,text) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

revoke all on function public.expire_orders(integer) from public, anon, authenticated;
revoke all on function public.resolve_payout_request(uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.verify_bank_account(uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.expire_orders(integer) to service_role;
grant execute on function public.resolve_payout_request(uuid,text,text,text) to service_role;
grant execute on function public.verify_bank_account(uuid,text,text) to service_role;

-- ---------------------------------------------------------------------------
-- Safe API views
-- ---------------------------------------------------------------------------

create or replace view public.public_merchants
with (security_invoker = true) as
select id, store_name, description, address, distance, lat, lng, category,
       open_time, close_time, logo_url, status, rating, review_count,
       bags_saved, created_at, updated_at
from public.merchants
where status = 'active' and user_id is not null;

create or replace view public.available_bags
with (security_invoker = true) as
select b.id, b.merchant_id, b.title, b.description, b.original_price,
       b.sale_price, b.quantity_total, b.quantity_left, b.pickup_window,
       b.image_url, b.contents, b.status, b.available_on,
       b.pickup_start_at, b.pickup_end_at, b.created_at, b.updated_at,
       m.store_name as merchant_name,
       m.category as merchant_category,
       m.address as merchant_address,
       m.distance as merchant_distance,
       m.lat as merchant_lat,
       m.lng as merchant_lng,
       m.open_time as merchant_open_time,
       m.close_time as merchant_close_time,
       m.logo_url as merchant_logo_url,
       m.rating as merchant_rating,
       m.review_count as merchant_review_count,
       m.bags_saved as merchant_bags_saved
from public.surprise_bags b
join public.merchants m
  on m.id = b.merchant_id and m.status = 'active' and m.user_id is not null
where b.status = 'active'
  and b.available_on <= (now() at time zone 'Asia/Jakarta')::date
  and (b.pickup_end_at is null or b.pickup_end_at > now());

create or replace view public.consumer_orders
with (security_invoker = true) as
select o.id, o.id as order_id, o.order_reference,
       o.consumer_id, o.merchant_id, o.bag_id,
       o.status, o.quantity, o.payment_method, o.created_at, o.updated_at,
       o.paid_at, o.ready_at, o.expires_at, o.redeemed_at,
       o.cancelled_at, o.expired_at,
       o.subtotal, o.service_fee, o.total_amount, o.commission_amount,
       o.merchant_net_amount,
       o.pickup_start_at, o.pickup_end_at,
       o.bag_title, o.bag_description, o.bag_image_url, o.unit_price,
       o.original_price_snapshot, o.pickup_window_snapshot,
       o.merchant_name_snapshot as merchant_name,
       o.merchant_category_snapshot as merchant_category,
       o.merchant_address_snapshot as merchant_address,
       o.merchant_logo_url_snapshot as merchant_logo_url,
       o.merchant_rating_snapshot as merchant_rating,
       o.merchant_review_count_snapshot as merchant_review_count,
       exists (select 1 from public.reviews r where r.order_id = o.id) as reviewed,
       (select r.id from public.reviews r where r.order_id = o.id limit 1) as review_id
from public.orders o
where o.consumer_id = auth.uid();

create or replace view public.merchant_orders
with (security_invoker = true) as
select o.id, o.id as order_id, o.order_reference,
       o.consumer_id, o.consumer_name,
       o.consumer_anonymized, o.merchant_id, o.bag_id, o.status, o.quantity,
       o.payment_method, o.created_at, o.updated_at, o.paid_at, o.ready_at,
       o.expires_at, o.redeemed_at, o.cancelled_at, o.expired_at,
       o.subtotal, o.service_fee, o.total_amount, o.commission_amount,
       o.merchant_net_amount,
       o.pickup_start_at, o.pickup_end_at,
       o.bag_title, o.bag_description, o.bag_image_url, o.unit_price,
       o.original_price_snapshot, o.pickup_window_snapshot,
       o.merchant_name_snapshot as merchant_name,
       o.merchant_category_snapshot as merchant_category,
       o.merchant_address_snapshot as merchant_address,
       o.merchant_logo_url_snapshot as merchant_logo_url,
       o.merchant_rating_snapshot as merchant_rating,
       o.merchant_review_count_snapshot as merchant_review_count
from public.orders o
where o.merchant_id in (
  select m.id from public.merchants m where m.user_id = auth.uid()
);

create or replace view public.public_reviews
with (security_invoker = true) as
select id, order_id, merchant_id, rating, tags, comment, created_at
from public.reviews;

create or replace view public.my_bank_accounts
with (security_invoker = true) as
select id, merchant_id, bank_code, bank_name, account_holder,
       account_number_last4, status, is_default, created_at, updated_at
from public.bank_accounts
where merchant_id in (
  select m.id from public.merchants m where m.user_id = auth.uid()
);

create or replace view public.merchant_balance
with (security_invoker = true) as
select m.id as merchant_id,
       coalesce(sum(case t.kind
         when 'income' then t.amount
         when 'withdrawal' then -t.amount
         when 'withdrawal_reversal' then t.amount
         else 0 end), 0)::integer as available
from public.merchants m
left join public.transactions t on t.merchant_id = m.id and t.trusted
where m.user_id = auth.uid()
group by m.id;

revoke all on public.public_merchants, public.available_bags,
  public.consumer_orders, public.merchant_orders, public.public_reviews,
  public.my_bank_accounts, public.merchant_balance
from public, anon, authenticated;
grant select on public.public_merchants, public.available_bags,
  public.public_reviews to anon, authenticated;
grant select on public.consumer_orders, public.merchant_orders,
  public.my_bank_accounts, public.merchant_balance to authenticated;

-- Realtime is opt-in per table. Column lists deliberately omit pickup hashes,
-- idempotency keys, and other internal-only fields from the WAL payload.
do $realtime$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'notifications'
    ) then
      execute 'alter publication supabase_realtime add table public.notifications';
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'orders'
    ) then
      execute $sql$
        alter publication supabase_realtime add table public.orders (
          id, order_reference, consumer_id, consumer_name, bag_id, merchant_id,
          quantity, total_amount, payment_method, status, created_at, subtotal,
          service_fee, unit_price, original_price_snapshot, commission_amount,
          merchant_net_amount, bag_title, bag_description, bag_image_url,
          pickup_window_snapshot, merchant_name_snapshot,
          merchant_category_snapshot, merchant_address_snapshot,
          merchant_logo_url_snapshot, merchant_rating_snapshot,
          merchant_review_count_snapshot, pickup_start_at, pickup_end_at,
          expires_at, paid_at, ready_at, redeemed_at, cancelled_at, expired_at,
          updated_at, consumer_anonymized
        )
      $sql$;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'transactions'
    ) then
      execute $sql$
        alter publication supabase_realtime add table public.transactions (
          id, merchant_id, title, subtitle, amount, kind, created_at,
          reference_type, reference_id, metadata
        )
      $sql$;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'payout_requests'
    ) then
      execute 'alter publication supabase_realtime add table public.payout_requests';
    end if;
  end if;
end
$realtime$;

-- ---------------------------------------------------------------------------
-- Storage hardening
-- ---------------------------------------------------------------------------

-- Modern Supabase Storage enforces these bucket fields before object writes.
update storage.buckets
set file_size_limit = 2097152,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
    ]::text[]
where id in ('bag-images', 'store-logos', 'avatars');

drop policy if exists storage_auth_write on storage.objects;
drop policy if exists storage_auth_update on storage.objects;
drop policy if exists storage_auth_delete on storage.objects;

create policy storage_auth_write on storage.objects
for insert to authenticated with check (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(coalesce(storage.extension(name), '')) in ('jpg', 'jpeg', 'png', 'webp', 'heic', 'heif')
  and (
    bucket_id in ('avatars', 'store-logos')
    or exists (select 1 from public.merchants m where m.user_id = auth.uid())
  )
);

create policy storage_auth_update on storage.objects
for update to authenticated using (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
) with check (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(coalesce(storage.extension(name), '')) in ('jpg', 'jpeg', 'png', 'webp', 'heic', 'heif')
  and (
    bucket_id in ('avatars', 'store-logos')
    or exists (select 1 from public.merchants m where m.user_id = auth.uid())
  )
);

create policy storage_auth_delete on storage.objects
for delete to authenticated using (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
);

comment on column public.orders.pickup_code is
  'Deprecated plaintext column. Always NULL after 0002; raw tokens are RPC-only.';
comment on column public.orders.pickup_token_hash is
  'SHA-256 of the current 192-bit pickup token; the raw token is never stored.';
comment on table public.transactions is
  'Append-only merchant ledger. Clients have SELECT only; RPCs append entries.';
comment on table public.payout_requests is
  'Withdrawal state machine. Requested amounts are reserved in transactions.';
comment on function public.purchase_bag(uuid,integer,text,text) is
  'Temporary no-gateway checkout. Requires idempotency and computes all money server-side.';
comment on function public.expire_orders(integer) is
  'Call periodically from a trusted scheduler/service-role worker.';

commit;
