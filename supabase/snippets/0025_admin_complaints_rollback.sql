-- Manual rollback for 0025_admin_complaints.sql. Run only with an operator
-- session, then delete the row for version 0025 from
-- supabase_migrations.schema_migrations. Complaints and admin grants are lost.

begin;

drop function if exists public.admin_transaction_report(date, date);
drop function if exists public.admin_dashboard_stats();
drop function if exists private.verified_orders_between(date, date);
drop function if exists public.admin_update_complaint(uuid, text, text);
drop function if exists public.admin_list_complaints(text);
drop function if exists public.submit_complaint(uuid, text, text);
drop table if exists public.complaints;
drop function if exists public.admin_set_user_suspended(uuid, boolean, text);
drop function if exists public.admin_list_users(text);
drop function if exists public.admin_set_merchant_verification(uuid, text, text);
drop function if exists public.admin_list_merchants(text);

drop trigger if exists reject_unverified_merchant_order on public.orders;
drop function if exists public.reject_unverified_merchant_order();
drop trigger if exists requeue_rejected_merchant on public.merchants;
drop function if exists public.requeue_rejected_merchant();

create or replace function public.get_my_merchant()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select to_jsonb(owned)
  from (
    select m.id, m.store_name, m.description, m.address, m.distance,
           m.lat, m.lng, m.category, m.open_time, m.close_time, m.logo_url,
           m.status, m.rating, m.review_count, m.bags_saved,
           m.created_at, m.updated_at, m.deleted_at
    from public.merchants m
    where m.user_id = auth.uid()
      and m.deleted_at is null
    limit 1
  ) owned
$$;

create or replace function public.merchant_is_public(p_merchant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1
    from public.merchants m
    join public.profiles p on p.id = m.user_id
    where m.id = p_merchant_id
      and m.status = 'active'
      and m.user_id is not null
      and p.deleted_at is null
  )
$$;

alter table public.merchants
  drop column if exists verified_at,
  drop column if exists verification_note,
  drop column if exists verification_status;

drop function if exists private.require_admin();
drop function if exists public.current_user_is_admin();
drop table if exists public.admin_users;

create or replace function private.assert_account_active(p_uid uuid)
returns void
language plpgsql
volatile
security definer
set search_path = private, public, pg_catalog
as $$
declare
  v_deleted_at timestamptz;
begin
  if p_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select p.deleted_at
  into v_deleted_at
  from public.profiles p
  where p.id = p_uid
  for share;

  if not found then
    raise exception 'account is unavailable' using errcode = '55000';
  end if;
  if v_deleted_at is not null then
    raise exception 'account deletion is pending' using errcode = '55000';
  end if;
end
$$;

create or replace function public.current_account_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.deleted_at is null
  )
$$;

alter table public.profiles
  drop column if exists suspended_reason,
  drop column if exists suspended_at;

commit;
