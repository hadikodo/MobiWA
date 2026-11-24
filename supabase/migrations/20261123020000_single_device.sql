-- One account = one device (for role "user"; admins are not locked).
--
-- The app sends its Android device id in the "x-device-id" header with every
-- request. A user's data is only readable/writable from the device the account
-- is bound to. Logging out releases the device; an admin can force it.

alter table public.profiles
  add column device_id text,
  add column device_name text not null default '',
  add column device_bound_at timestamptz;

-- Device id sent by the app with this request (null if missing).
create or replace function public.request_device_id()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(coalesce(current_setting('request.headers', true)::json ->> 'x-device-id', ''), '');
$$;

-- True when the signed-in user may use their data from this device.
create or replace function public.device_ok()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.active
      and (p.role = 'admin' or (p.device_id is not null and p.device_id = public.request_device_id()))
  );
$$;

-- Called right after a successful password sign-in.
-- → {"ok": true} or {"ok": false, "reason": "other_device", "device_name", "since"}
create or replace function public.claim_device(p_device_id text, p_device_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.profiles;
begin
  if coalesce(p_device_id, '') = '' then
    raise exception 'Missing device id';
  end if;
  select * into p from public.profiles where id = auth.uid() for update;
  if not found then
    raise exception 'No profile';
  end if;
  if not p.active then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if p.role = 'admin' or p.device_id is null or p.device_id = p_device_id then
    update public.profiles
      set device_id = p_device_id,
          device_name = left(coalesce(p_device_name, ''), 80),
          device_bound_at = case when p.device_id = p_device_id then coalesce(p.device_bound_at, now()) else now() end
      where id = p.id;
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object(
    'ok', false,
    'reason', 'other_device',
    'device_name', p.device_name,
    'since', p.device_bound_at
  );
end;
$$;

-- Called on logout from the bound device.
create or replace function public.release_device(p_device_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles
    set device_id = null, device_name = '', device_bound_at = null
    where id = auth.uid() and device_id = p_device_id;
$$;

-- Used by the admin-users Edge Function (service role only): ends every
-- session of a user so their refresh tokens stop working.
create or replace function public.revoke_user_sessions(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.sessions where user_id = p_user_id;
$$;

revoke execute on function public.claim_device(text, text) from anon, public;
revoke execute on function public.release_device(text) from anon, public;
revoke execute on function public.device_ok() from anon, public;
revoke execute on function public.revoke_user_sessions(uuid) from anon, authenticated, public;
grant execute on function public.claim_device(text, text) to authenticated;
grant execute on function public.release_device(text) to authenticated;
grant execute on function public.device_ok() to authenticated;
grant execute on function public.revoke_user_sessions(uuid) to service_role;

-- Device is not user-editable directly (only via the functions above).
-- (Column grants from the first migration don't include these columns.)

-- ----------------------------------------------- data only from bound device
drop policy "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) and (select public.device_ok()))
  with check (id = (select auth.uid()));

drop policy "categories: own or admin" on public.categories;
create policy "categories: own or admin" on public.categories
  for all to authenticated
  using ((user_id = (select auth.uid()) and (select public.device_ok())) or (select public.is_admin()))
  with check ((user_id = (select auth.uid()) and (select public.device_ok())) or (select public.is_admin()));

drop policy "contacts: own or admin" on public.contacts;
create policy "contacts: own or admin" on public.contacts
  for all to authenticated
  using ((user_id = (select auth.uid()) and (select public.device_ok())) or (select public.is_admin()))
  with check ((user_id = (select auth.uid()) and (select public.device_ok())) or (select public.is_admin()));

drop policy "activity: read own or admin" on public.activity;
create policy "activity: read own or admin" on public.activity
  for select to authenticated
  using ((user_id = (select auth.uid()) and (select public.device_ok())) or (select public.is_admin()));

drop policy "activity: insert own" on public.activity;
create policy "activity: insert own" on public.activity
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.device_ok()));

-- ------------------------------------------- admin stats now include device
drop function public.admin_user_stats();
create function public.admin_user_stats()
returns table (
  user_id uuid,
  username text,
  full_name text,
  role text,
  active boolean,
  business_name text,
  business_description text,
  created_at timestamptz,
  last_seen_at timestamptz,
  device_name text,
  device_bound_at timestamptz,
  signed_in boolean,
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
    p.id, p.username, p.full_name, p.role, p.active, p.business_name, p.business_description,
    p.created_at, p.last_seen_at, p.device_name, p.device_bound_at, p.device_id is not null,
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
revoke execute on function public.admin_user_stats() from anon, public;
grant execute on function public.admin_user_stats() to authenticated;
