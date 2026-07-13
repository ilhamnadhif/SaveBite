-- SaveBite: allow trusted Supabase CLI database sessions to run operator seed.
-- Apply after 0009_operational_hardening.sql.

begin;

-- Linked Supabase CLI connections use an ephemeral `cli_login_postgres` login
-- role and do not carry an end-user JWT. Treat that database-admin session like
-- postgres/supabase_admin, while regular anon/authenticated sessions still
-- require a live auth.uid() and an active account.
create or replace function public.guard_active_account_mutation()
returns trigger
language plpgsql
security definer
set search_path = private, public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.jwt() ->> 'role', '');
  v_trusted_database_actor boolean :=
    session_user::text in ('postgres', 'supabase_admin', 'service_role')
    or session_user::text like 'cli_login_postgres%'
    or pg_has_role(session_user, 'postgres', 'member');
begin
  if current_setting('savebite.account_deletion', true) = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_uid is null then
    if v_trusted_database_actor or v_role = 'service_role' then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  perform private.assert_account_active(v_uid);
  if tg_table_schema = 'public' and tg_table_name = 'surprise_bags' then
    perform private.assert_merchant_account_active(
      case when tg_op = 'DELETE' then old.merchant_id else new.merchant_id end
    );
  elsif tg_table_schema = 'public' and tg_table_name = 'orders' then
    perform private.assert_merchant_account_active(
      case when tg_op = 'DELETE' then old.merchant_id else new.merchant_id end
    );
  elsif tg_table_schema = 'public' and tg_table_name = 'reviews' then
    perform private.assert_merchant_account_active(
      case when tg_op = 'DELETE' then old.merchant_id else new.merchant_id end
    );
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

revoke all on function public.guard_active_account_mutation()
  from public, anon, authenticated;

comment on function public.guard_active_account_mutation() is
  'Blocks mutations from deleted/anonymous app accounts while allowing trusted database and Supabase CLI operator sessions.';

commit;
