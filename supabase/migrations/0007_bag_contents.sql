-- SaveBite: make estimated bag contents editable by merchants.

begin;

alter table public.surprise_bags drop constraint if exists bags_content_check;
drop function if exists private.valid_bag_contents(text[]);

create or replace function private.normalize_bag_contents()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_contents text[];
begin
  if exists (
    select 1
    from unnest(coalesce(new.contents, '{}'::text[])) as raw(item)
    where item is null or length(btrim(item)) > 80
  ) then
    raise exception 'each content item must contain at most 80 characters';
  end if;

  select coalesce(array_agg(value order by ordinal), '{}'::text[])
  into v_contents
  from (
    select distinct on (lower(value)) value, ordinal
    from (
      select btrim(item) as value, ord as ordinal
      from unnest(coalesce(new.contents, '{}'::text[]))
        with ordinality as source(item, ord)
      where btrim(item) <> ''
    ) prepared
    order by lower(value), ordinal
  ) normalized;

  if cardinality(v_contents) > 20 then
    raise exception 'contents must contain at most 20 items';
  end if;
  new.contents := v_contents;
  return new;
end
$$;

revoke all on function private.normalize_bag_contents()
  from public, anon, authenticated;

drop trigger if exists normalize_bag_contents on public.surprise_bags;
create trigger normalize_bag_contents
  before insert or update of contents on public.surprise_bags
  for each row execute function private.normalize_bag_contents();

-- Normalize legacy values before applying the per-item constraint.
update public.surprise_bags b
set contents = coalesce((
  select array_agg(value order by ord)
  from (
    select value, ord
    from (
      select distinct on (lower(value)) value, ord
      from (
        select left(btrim(item), 80) as value, ord
        from unnest(coalesce(b.contents, '{}'::text[]))
          with ordinality as source(item, ord)
        where btrim(item) <> ''
      ) prepared
      order by lower(value), ord
    ) deduplicated
    order by ord
    limit 20
  ) limited
), '{}'::text[]);

alter table public.surprise_bags add constraint bags_content_check check (
  length(btrim(title)) between 2 and 120
  and length(description) <= 2000
  and length(pickup_window) <= 100
  and cardinality(contents) <= 20
  and length(array_to_string(contents, '')) <= 1600
);

drop function if exists public.update_surprise_bag(
  uuid,text,text,integer,integer,integer,text,text,date,timestamptz,timestamptz
);

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
  p_pickup_end_at timestamptz,
  p_contents text[]
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
  v_contents text[];
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

  if exists (
    select 1
    from unnest(coalesce(p_contents, '{}'::text[])) as raw(item)
    where item is null or length(btrim(item)) > 80
  ) then
    raise exception 'each content item must contain at most 80 characters';
  end if;

  select coalesce(array_agg(value order by ordinal), '{}'::text[])
  into v_contents
  from (
    select distinct on (lower(value)) value, ordinal
    from (
      select btrim(item) as value, ord as ordinal
      from unnest(coalesce(p_contents, '{}'::text[]))
        with ordinality as u(item, ord)
      where btrim(item) <> ''
    ) prepared
    order by lower(value), ordinal
  ) normalized;

  if cardinality(v_contents) > 20 then
    raise exception 'contents must contain at most 20 items';
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
      contents = v_contents,
      status = v_status
  where id = v_bag.id
  returning * into v_bag;

  return to_jsonb(v_bag);
end
$$;

revoke all on function public.update_surprise_bag(
  uuid,text,text,integer,integer,integer,text,text,date,timestamptz,timestamptz,text[]
) from public, anon, authenticated;
grant execute on function public.update_surprise_bag(
  uuid,text,text,integer,integer,integer,text,text,date,timestamptz,timestamptz,text[]
) to authenticated;

commit;
