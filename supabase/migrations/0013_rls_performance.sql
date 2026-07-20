-- Cache request-scoped auth helpers as init plans instead of evaluating them
-- once for every row inspected by these RLS policies. The authorization logic
-- is intentionally unchanged; only direct auth.uid() calls are wrapped in a
-- scalar SELECT, as recommended by Supabase's auth_rls_initplan advisor.
-- Apply after 0012_midtrans_payments.sql.

begin;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
for select
using ((select auth.uid()) = id);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert
with check ((select auth.uid()) = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update
using (
  (select auth.uid()) = id
  and deleted_at is null
)
with check (
  (select auth.uid()) = id
  and deleted_at is null
);

drop policy if exists notif_select_self on public.notifications;
create policy notif_select_self on public.notifications
for select
using (user_id = (select auth.uid()));

drop policy if exists notif_update_self on public.notifications;
create policy notif_update_self on public.notifications
for update
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists merchants_read on public.merchants;
create policy merchants_read on public.merchants
for select
using (
  public.merchant_is_public(id)
  or user_id = (select auth.uid())
);

drop policy if exists merchants_insert_owner on public.merchants;
create policy merchants_insert_owner on public.merchants
for insert
with check (
  (select auth.uid()) = user_id
  and public.current_account_is_active()
);

drop policy if exists merchants_update_owner on public.merchants;
create policy merchants_update_owner on public.merchants
for update
using (
  (select auth.uid()) = user_id
  and public.current_account_is_active()
)
with check (
  (select auth.uid()) = user_id
  and public.current_account_is_active()
);

drop policy if exists favorites_self on public.favorites;
create policy favorites_self on public.favorites
for all
using (
  (select auth.uid()) = consumer_id
  and public.current_account_is_active()
)
with check (
  (select auth.uid()) = consumer_id
  and public.current_account_is_active()
);

drop policy if exists payment_attempts_read_own on public.payment_attempts;
create policy payment_attempts_read_own on public.payment_attempts
for select
using (consumer_id = (select auth.uid()));

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
for select
using (
  consumer_id = (select auth.uid())
  or (
    public.current_user_owns_merchant(merchant_id)
    and payment_verified_at is not null
  )
);

commit;
