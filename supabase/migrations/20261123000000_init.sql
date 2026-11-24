-- MobiWA schema: profiles (users + roles), categories, contacts, activity log.
-- Users only see their own data; admins see and manage everything.

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  full_name text not null default '',
  role text not null default 'user' check (role in ('user', 'admin')),
  active boolean not null default true,
  business_name text not null default '',
  business_description text not null default '',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

-- True when the signed-in user is an active admin. SECURITY DEFINER avoids
-- recursive RLS checks on profiles.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and active
  );
$$;

-- ------------------------------------------------------------- categories
create table public.categories (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  kind text not null default 'custom' check (kind in ('unnamed', 'junk', 'custom')),
  description text not null default '',
  created_at timestamptz not null default now()
);
create unique index categories_user_name_key on public.categories (user_id, lower(name));
create unique index categories_user_system_key on public.categories (user_id, kind)
  where kind in ('unnamed', 'junk');

-- --------------------------------------------------------------- contacts
create table public.contacts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  phone text not null,
  name text not null default '',
  category_id bigint not null references public.categories (id),
  source_app text not null default '',
  ai_status text not null default 'pending' check (ai_status in ('pending', 'sorted', 'skipped', 'error')),
  ai_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, phone)
);
create index contacts_category_idx on public.contacts (category_id);

-- --------------------------------------------------------------- activity
-- One row per finished action (scan / sort / send) with its numbers.
create table public.activity (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('scan', 'sort', 'send')),
  stats jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index activity_user_created_idx on public.activity (user_id, created_at desc);

-- ---------------------------------------------------------------- triggers

-- New auth user → profile. Username comes from the metadata set by the
-- admin-users function, otherwise from the email.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, full_name, role)
  values (
    new.id,
    lower(coalesce(nullif(new.raw_user_meta_data ->> 'username', ''), new.email)),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case
      when lower(new.email) = 'hadi.jaber@supertechlb.com' then 'admin'
      when new.raw_app_meta_data ->> 'role' = 'admin' then 'admin'
      else 'user'
    end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Every profile gets its two fixed categories.
create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (user_id, name, kind) values
    (new.id, 'Unnamed', 'unnamed'),
    (new.id, 'Junk', 'junk');
  return new;
end;
$$;

create trigger on_profile_created
  after insert on public.profiles
  for each row execute function public.handle_new_profile();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger contacts_touch
  before update on public.contacts
  for each row execute function public.touch_updated_at();

-- A contact's category must belong to the same user.
create or replace function public.check_contact_category()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.categories c
    where c.id = new.category_id and c.user_id = new.user_id
  ) then
    raise exception 'Category % does not belong to this user', new.category_id;
  end if;
  return new;
end;
$$;

create trigger contacts_category_owner
  before insert or update of category_id, user_id on public.contacts
  for each row execute function public.check_contact_category();

-- Unnamed / Junk cannot be renamed or deleted.
create or replace function public.protect_system_categories()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.kind <> 'custom' and exists (select 1 from public.profiles where id = old.user_id) then
      raise exception 'System categories cannot be deleted';
    end if;
    return old;
  end if;
  if old.kind <> 'custom' and (new.name <> old.name or new.kind <> old.kind) then
    raise exception 'System categories cannot be changed';
  end if;
  return new;
end;
$$;

create trigger categories_protect
  before update or delete on public.categories
  for each row execute function public.protect_system_categories();

-- ------------------------------------------------------------------- RLS
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.contacts enable row level security;
alter table public.activity enable row level security;

create policy "profiles: read own or admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

-- Users may edit only their business info (column grants below); admins
-- change roles / status through the admin-users Edge Function.
create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

revoke update on public.profiles from authenticated, anon;
grant update (full_name, business_name, business_description, last_seen_at)
  on public.profiles to authenticated;

create policy "categories: own or admin" on public.categories
  for all to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "contacts: own or admin" on public.contacts
  for all to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "activity: read own or admin" on public.activity
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "activity: insert own" on public.activity
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- ------------------------------------------------------------ admin views

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
    (select coalesce(sum((a.stats ->> 'sent')::bigint), 0) from public.activity a
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
    coalesce(sum((a.stats ->> 'added')::bigint) filter (where a.kind = 'scan'), 0),
    coalesce(sum(coalesce((a.stats ->> 'customers')::bigint, 0) + coalesce((a.stats ->> 'junk')::bigint, 0))
      filter (where a.kind = 'sort'), 0),
    coalesce(sum((a.stats ->> 'sent')::bigint) filter (where a.kind = 'send'), 0)
  from generate_series(current_date - (days - 1), current_date, interval '1 day') d
  left join public.activity a on a.created_at::date = d::date
  group by d
  order by d;
end;
$$;

revoke execute on function public.admin_user_stats() from anon, public;
revoke execute on function public.admin_daily_activity(int) from anon, public;
grant execute on function public.admin_user_stats() to authenticated;
grant execute on function public.admin_daily_activity(int) to authenticated;
