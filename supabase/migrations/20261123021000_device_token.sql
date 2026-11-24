-- Harden single-device sessions: the device id (Android ID) only identifies
-- the phone; access is proven by a random secret issued at each successful
-- claim and sent by the app in the "x-device-token" header.

alter table public.profiles add column device_token text;

-- Secret token sent by the app with this request (null if missing).
create or replace function public.request_device_token()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(coalesce(current_setting('request.headers', true)::json ->> 'x-device-token', ''), '');
$$;

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
      and (p.role = 'admin'
           or (p.device_token is not null and p.device_token = public.request_device_token()))
  );
$$;

-- → {"ok": true, "token": "..."} or {"ok": false, "reason": "other_device", ...}
create or replace function public.claim_device(p_device_id text, p_device_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.profiles;
  t text;
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
    t := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    update public.profiles
      set device_id = p_device_id,
          device_token = t,
          device_name = left(coalesce(p_device_name, ''), 80),
          device_bound_at = case when p.device_id = p_device_id then coalesce(p.device_bound_at, now()) else now() end
      where id = p.id;
    return jsonb_build_object('ok', true, 'token', t);
  end if;
  return jsonb_build_object(
    'ok', false,
    'reason', 'other_device',
    'device_name', p.device_name,
    'since', p.device_bound_at
  );
end;
$$;

-- Logout from the bound device (proved by its token header).
drop function public.release_device(text);
create function public.release_device()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles
    set device_id = null, device_token = null, device_name = '', device_bound_at = null
    where id = auth.uid()
      and device_token is not null
      and device_token = public.request_device_token();
$$;

revoke execute on function public.release_device() from anon, public;
grant execute on function public.release_device() to authenticated;

-- Never expose the token to clients (admins included).
revoke select on public.profiles from authenticated, anon;
grant select (id, username, full_name, role, active, business_name, business_description,
              created_at, last_seen_at, device_name, device_bound_at)
  on public.profiles to authenticated;
