-- sum(bigint) returns numeric; cast to match the declared bigint columns.

-- Per-user totals for the admin dashboard.
create or replace function public.admin_user_stats()
returns table (
  user_id uuid,
  username text,
  full_name text,
  role text,
  active boolean,
  business_name text,
  created_at timestamptz,
  last_seen_at timestamptz,
  numbers bigint,
  unnamed bigint,
  customers bigint,
  junk bigint,
  categories bigint,
  messages_sent bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  return query
  select
    p.id, p.username, p.full_name, p.role, p.active, p.business_name, p.created_at, p.last_seen_at,
    (select count(*) from public.contacts k where k.user_id = p.id),
    (select count(*) from public.contacts k join public.categories c on c.id = k.category_id
       where k.user_id = p.id and c.kind = 'unnamed'),
    (select count(*) from public.contacts k join public.categories c on c.id = k.category_id
       where k.user_id = p.id and c.kind = 'custom'),
    (select count(*) from public.contacts k join public.categories c on c.id = k.category_id
       where k.user_id = p.id and c.kind = 'junk'),
    (select count(*) from public.categories c where c.user_id = p.id and c.kind = 'custom'),
    (select coalesce(sum((a.stats ->> 'sent')::bigint), 0)::bigint from public.activity a
       where a.user_id = p.id and a.kind = 'send')
  from public.profiles p
  order by p.created_at;
end;
$$;

-- Daily totals across all users for the last [days] days.
create or replace function public.admin_daily_activity(days int default 14)
returns table (day date, numbers_found bigint, sorted bigint, messages_sent bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  return query
  select
    d::date,
    coalesce(sum((a.stats ->> 'added')::bigint) filter (where a.kind = 'scan'), 0)::bigint,
    coalesce(sum(coalesce((a.stats ->> 'customers')::bigint, 0) + coalesce((a.stats ->> 'junk')::bigint, 0))
      filter (where a.kind = 'sort'), 0)::bigint,
    coalesce(sum((a.stats ->> 'sent')::bigint) filter (where a.kind = 'send'), 0)::bigint
  from generate_series(current_date - (days - 1), current_date, interval '1 day') d
  left join public.activity a on a.created_at::date = d::date
  group by d
  order by d;
end;
$$;

