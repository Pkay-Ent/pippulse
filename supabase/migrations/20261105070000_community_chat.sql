-- PipPulse signed-in community chat.
-- Members can read and post messages; they can delete their own messages.
-- Admins can remove any message. No private messages or file uploads are enabled.

begin;

create table if not exists public.community_chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists community_chat_messages_created_idx
  on public.community_chat_messages (created_at desc);
create index if not exists community_chat_messages_user_created_idx
  on public.community_chat_messages (user_id, created_at desc);

alter table public.community_chat_messages enable row level security;

revoke all on public.community_chat_messages from anon, authenticated;
grant select, insert, delete on public.community_chat_messages to authenticated;

drop policy if exists "Signed-in members read community chat" on public.community_chat_messages;
create policy "Signed-in members read community chat"
  on public.community_chat_messages
  for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "Members post as themselves" on public.community_chat_messages;
create policy "Members post as themselves"
  on public.community_chat_messages
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Members and admins delete chat messages" on public.community_chat_messages;
create policy "Members and admins delete chat messages"
  on public.community_chat_messages
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    or coalesce(public.is_admin(), false)
  );

create or replace function public.prepare_community_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_username text;
  v_display_name text;
  v_last_message timestamptz;
begin
  if auth.uid() is null or new.user_id <> auth.uid() then
    raise exception 'You must be signed in to post a chat message.';
  end if;

  new.body := btrim(coalesce(new.body, ''));
  if new.body = '' then
    raise exception 'Write a message before sending.';
  end if;
  if char_length(new.body) > 1000 then
    raise exception 'Messages are limited to 1000 characters.';
  end if;

  -- Serialize posts per member so rapid repeat submissions are throttled.
  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  select max(created_at) into v_last_message
  from public.community_chat_messages
  where user_id = new.user_id;

  if v_last_message is not null and v_last_message > now() - interval '2 seconds' then
    raise exception 'Please wait a moment before sending another message.';
  end if;

  select username, display_name
    into v_username, v_display_name
  from public.profiles
  where id = new.user_id;

  new.author_name := case
    when nullif(btrim(v_username), '') is not null then '@' || btrim(v_username)
    when nullif(btrim(v_display_name), '') is not null then btrim(v_display_name)
    else 'PipPulse member'
  end;
  new.created_at := now();
  return new;
end;
$$;

revoke all on function public.prepare_community_chat_message() from public, anon, authenticated;

drop trigger if exists community_chat_prepare_message on public.community_chat_messages;
create trigger community_chat_prepare_message
  before insert on public.community_chat_messages
  for each row
  execute function public.prepare_community_chat_message();

-- Enable live message delivery in Supabase Realtime.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'community_chat_messages'
     ) then
    alter publication supabase_realtime add table public.community_chat_messages;
  end if;
end;
$$;

commit;
