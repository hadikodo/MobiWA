-- Security hardening.
--
-- 1. Admin rights require a session verified with a second factor (TOTP):
--    the JWT claim "aal" must be "aal2". A stolen admin password alone is not
--    enough to read other users' data or manage accounts.
-- 2. No hard-coded admin email in the sign-up trigger (admins are only made by
--    an existing admin through the admin-users function).
-- 3. Per-user AI quota so a leaked account can't run up the Gemini bill.

-- ------------------------------------------------------------------ 1. MFA
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
     and exists (
       select 1 from public.profiles
       where id = auth.uid() and role = 'admin' and active
     );
$$;

-- ------------------------------------------------------ 2. sign-up trigger
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
    -- app_metadata can only be set server-side (service role).
    case when new.raw_app_meta_data ->> 'role' = 'admin' then 'admin' else 'user' end
  );
  return new;
end;
$$;

-- --------------------------------------------------------------- 3. AI quota
create table public.ai_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index ai_usage_user_created_idx on public.ai_usage (user_id, created_at desc);
alter table public.ai_usage enable row level security; -- no policies: only the function below touches it

-- Records one AI call for the signed-in user. Returns false when over quota
-- (300 per hour, 2000 per day). Called by the ai-classify Edge Function.
create or replace function public.ai_quota_take()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  last_hour int;
  last_day int;
begin
  if uid is null then
    return false;
  end if;
  select count(*) filter (where created_at > now() - interval '1 hour'),
         count(*)
    into last_hour, last_day
    from public.ai_usage
   where user_id = uid and created_at > now() - interval '1 day';
  if last_hour >= 300 or last_day >= 2000 then
    return false;
  end if;
  insert into public.ai_usage (user_id) values (uid);
  -- Housekeeping: keep two days of history.
  if random() < 0.01 then
    delete from public.ai_usage where created_at < now() - interval '2 days';
  end if;
  return true;
end;
$$;

revoke execute on function public.ai_quota_take() from anon, public;
grant execute on function public.ai_quota_take() to authenticated;
revoke all on public.ai_usage from anon, authenticated;
