-- "Contact us" form on the landing page (mobiwa.com). Anyone may submit;
-- only admins can read. Lengths are capped and senders are rate-limited.

create table public.contact_messages (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 100),
  email text not null check (char_length(email) between 3 and 200 and email like '%_@_%._%'),
  business text not null default '' check (char_length(business) <= 150),
  topic text not null default 'general' check (topic in ('general', 'sales', 'support', 'account_deletion', 'privacy')),
  message text not null check (char_length(message) between 5 and 4000),
  handled boolean not null default false,
  created_at timestamptz not null default now()
);
create index contact_messages_created_idx on public.contact_messages (created_at desc);

alter table public.contact_messages enable row level security;

create policy "contact: anyone can submit" on public.contact_messages
  for insert to anon, authenticated
  with check (handled = false);

create policy "contact: admins read" on public.contact_messages
  for select to authenticated
  using ((select public.is_admin()));

create policy "contact: admins update" on public.contact_messages
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "contact: admins delete" on public.contact_messages
  for delete to authenticated
  using ((select public.is_admin()));

-- Max 5 messages per email per hour, and 200 per hour overall.
create or replace function public.contact_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) from public.contact_messages
      where lower(email) = lower(new.email) and created_at > now() - interval '1 hour') >= 5
     or (select count(*) from public.contact_messages
      where created_at > now() - interval '1 hour') >= 200 then
    raise exception 'Too many messages. Please try again later.';
  end if;
  return new;
end;
$$;

create trigger contact_messages_rate_limit
  before insert on public.contact_messages
  for each row execute function public.contact_rate_limit();

-- anon may only insert (no select of what others sent).
revoke all on public.contact_messages from anon;
grant insert (name, email, business, topic, message) on public.contact_messages to anon;
grant insert (name, email, business, topic, message) on public.contact_messages to authenticated;
grant select, update (handled), delete on public.contact_messages to authenticated;
