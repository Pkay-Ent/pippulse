-- PipPulse customer announcements and admin-initiated private conversations.
-- Keeps admin_notifications (administrator payment alerts) separate.
begin;

create table if not exists public.admin_announcements (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users(id) on delete restrict,
  title text not null,
  body text not null,
  target_type text not null check (target_type in ('all', 'selected')),
  recipient_count integer not null default 0 check (recipient_count >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null check (
    notification_type in ('announcement', 'private_chat_invite', 'private_message')
  ),
  title text not null,
  body text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists user_notifications_recipient_created_idx
  on public.user_notifications(recipient_id, created_at desc);

create table if not exists public.admin_announcement_recipients (
  announcement_id uuid not null references public.admin_announcements(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  notification_id uuid not null references public.user_notifications(id) on delete cascade,
  primary key (announcement_id, recipient_id)
);

create table if not exists public.private_conversations (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (admin_id, user_id),
  check (admin_id <> user_id)
);

create index if not exists private_conversations_admin_recent_idx
  on public.private_conversations(admin_id, last_message_at desc);
create index if not exists private_conversations_user_recent_idx
  on public.private_conversations(user_id, last_message_at desc);

create table if not exists public.private_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.private_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '',
  image_path text,
  created_at timestamptz not null default now()
);

create index if not exists private_messages_conversation_created_idx
  on public.private_messages(conversation_id, created_at asc);

alter table public.admin_announcements enable row level security;
alter table public.admin_announcement_recipients enable row level security;
alter table public.user_notifications enable row level security;
alter table public.private_conversations enable row level security;
alter table public.private_messages enable row level security;

revoke all on public.admin_announcements, public.admin_announcement_recipients,
  public.user_notifications, public.private_conversations, public.private_messages
  from anon, authenticated;

grant select on public.admin_announcements, public.admin_announcement_recipients to authenticated;
grant select, update (read_at) on public.user_notifications to authenticated;
grant select on public.private_conversations to authenticated;
grant select, insert on public.private_messages to authenticated;

drop policy if exists "Admins read their announcements" on public.admin_announcements;
create policy "Admins read their announcements"
  on public.admin_announcements for select to authenticated
  using (coalesce(public.is_admin(), false));

drop policy if exists "Admins read announcement recipients" on public.admin_announcement_recipients;
create policy "Admins read announcement recipients"
  on public.admin_announcement_recipients for select to authenticated
  using (coalesce(public.is_admin(), false));

drop policy if exists "Users read their notifications" on public.user_notifications;
create policy "Users read their notifications"
  on public.user_notifications for select to authenticated
  using (recipient_id = (select auth.uid()));

drop policy if exists "Users mark their notifications read" on public.user_notifications;
create policy "Users mark their notifications read"
  on public.user_notifications for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

drop policy if exists "Conversation participants read private conversations" on public.private_conversations;
create policy "Conversation participants read private conversations"
  on public.private_conversations for select to authenticated
  using (
    admin_id = (select auth.uid())
    or user_id = (select auth.uid())
  );

drop policy if exists "Conversation participants read private messages" on public.private_messages;
create policy "Conversation participants read private messages"
  on public.private_messages for select to authenticated
  using (
    exists (
      select 1 from public.private_conversations c
      where c.id = private_messages.conversation_id
        and ((select auth.uid()) = c.admin_id or (select auth.uid()) = c.user_id)
    )
  );

drop policy if exists "Conversation participants send as themselves" on public.private_messages;
create policy "Conversation participants send as themselves"
  on public.private_messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.private_conversations c
      where c.id = private_messages.conversation_id
        and ((select auth.uid()) = c.admin_id or (select auth.uid()) = c.user_id)
    )
  );

-- Admin-only RPC: null recipient list means all registered profiles; an explicit
-- list means only those customer accounts. Admin accounts are excluded as recipients.
create or replace function public.admin_send_announcement(
  p_title text,
  p_body text,
  p_recipient_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_ids uuid[];
  v_announcement_id uuid;
  v_recipient uuid;
  v_notification_id uuid;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required.';
  end if;
  if v_title = '' or char_length(v_title) > 100 then
    raise exception 'Announcement title must be between 1 and 100 characters.';
  end if;
  if v_body = '' or char_length(v_body) > 2000 then
    raise exception 'Announcement message must be between 1 and 2000 characters.';
  end if;

  if p_recipient_ids is null then
    select coalesce(array_agg(p.id order by p.id), array[]::uuid[])
      into v_ids
    from public.profiles p
    where p.role <> 'admin';
  else
    if cardinality(p_recipient_ids) = 0 then
      raise exception 'Select at least one customer.';
    end if;
    if exists (
      select 1
      from unnest(p_recipient_ids) selected(id)
      left join public.profiles p on p.id = selected.id
      where p.id is null or p.role = 'admin'
    ) then
      raise exception 'One or more selected recipients are invalid.';
    end if;
    select array_agg(distinct selected.id order by selected.id)
      into v_ids
    from unnest(p_recipient_ids) selected(id);
  end if;

  if coalesce(cardinality(v_ids), 0) = 0 then
    raise exception 'There are no customer accounts to receive this announcement.';
  end if;

  insert into public.admin_announcements(admin_id, title, body, target_type, recipient_count)
  values ((select auth.uid()), v_title, v_body,
          case when p_recipient_ids is null then 'all' else 'selected' end,
          cardinality(v_ids))
  returning id into v_announcement_id;

  foreach v_recipient in array v_ids loop
    insert into public.user_notifications(recipient_id, notification_type, title, body, details)
    values (v_recipient, 'announcement', v_title, v_body,
            jsonb_build_object('announcement_id', v_announcement_id))
    returning id into v_notification_id;

    insert into public.admin_announcement_recipients(announcement_id, recipient_id, notification_id)
    values (v_announcement_id, v_recipient, v_notification_id);
  end loop;

  return v_announcement_id;
end;
$$;

revoke all on function public.admin_send_announcement(text, text, uuid[]) from public, anon;
grant execute on function public.admin_send_announcement(text, text, uuid[]) to authenticated;

-- Admin-only RPC: creates (or reopens) a conversation started by this admin.
create or replace function public.admin_start_private_conversation(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conversation_id uuid;
  v_created boolean := false;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required.';
  end if;
  if p_user_id is null or p_user_id = (select auth.uid()) then
    raise exception 'Choose a valid customer account.';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_user_id and p.role <> 'admin'
  ) then
    raise exception 'Customer account not found.';
  end if;

  insert into public.private_conversations(admin_id, user_id)
  values ((select auth.uid()), p_user_id)
  on conflict (admin_id, user_id) do nothing
  returning id into v_conversation_id;

  if v_conversation_id is not null then
    v_created := true;
  else
    select c.id into v_conversation_id
    from public.private_conversations c
    where c.admin_id = (select auth.uid()) and c.user_id = p_user_id;
  end if;

  if v_created then
    insert into public.user_notifications(recipient_id, notification_type, title, body, details)
    values (
      p_user_id,
      'private_chat_invite',
      'Private chat invitation',
      'PipPulse Admin has opened a private conversation with you. Open PipPulse to reply.',
      jsonb_build_object('conversation_id', v_conversation_id)
    );
  end if;

  return v_conversation_id;
end;
$$;

revoke all on function public.admin_start_private_conversation(uuid) from public, anon;
grant execute on function public.admin_start_private_conversation(uuid) to authenticated;

-- Validate message authorship and keep private message contents separate from Community Chat.
create or replace function public.prepare_private_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid;
  v_user_id uuid;
begin
  if (select auth.uid()) is null or new.sender_id <> (select auth.uid()) then
    raise exception 'Sign in to send a private message as yourself.';
  end if;

  select c.admin_id, c.user_id into v_admin_id, v_user_id
  from public.private_conversations c
  where c.id = new.conversation_id;

  if v_admin_id is null or (select auth.uid()) not in (v_admin_id, v_user_id) then
    raise exception 'You are not a participant in this private conversation.';
  end if;

  new.body := btrim(coalesce(new.body, ''));
  if new.body = '' and new.image_path is null then
    raise exception 'Write a message or attach an image.';
  end if;
  if char_length(new.body) > 2000 then
    raise exception 'Private messages are limited to 2000 characters.';
  end if;
  if new.image_path is not null and new.image_path not like
      new.conversation_id::text || '/' || (select auth.uid())::text || '/%' then
    raise exception 'The attached image path is not valid for this conversation.';
  end if;

  new.created_at := now();
  return new;
end;
$$;

revoke all on function public.prepare_private_message() from public, anon, authenticated;

drop trigger if exists private_messages_prepare on public.private_messages;
create trigger private_messages_prepare
  before insert on public.private_messages
  for each row execute function public.prepare_private_message();

create or replace function public.after_private_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid;
  v_user_id uuid;
  v_recipient uuid;
begin
  select c.admin_id, c.user_id into v_admin_id, v_user_id
  from public.private_conversations c
  where c.id = new.conversation_id;

  update public.private_conversations
  set last_message_at = new.created_at
  where id = new.conversation_id;

  v_recipient := case when new.sender_id = v_admin_id then v_user_id else v_admin_id end;

  insert into public.user_notifications(recipient_id, notification_type, title, body, details)
  values (
    v_recipient,
    'private_message',
    'New private message',
    coalesce(nullif(new.body, ''), 'Sent an image'),
    jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id)
  );

  return new;
end;
$$;

revoke all on function public.after_private_message_insert() from public, anon, authenticated;

drop trigger if exists private_messages_after_insert on public.private_messages;
create trigger private_messages_after_insert
  after insert on public.private_messages
  for each row execute function public.after_private_message_insert();

-- Push each customer notification to that recipient only. This reuses the
-- existing send-signal-push Edge Function and Vault-held URL/secret.
create or replace function public.dispatch_user_notification_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_target_url text := '/';
  v_push_body text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets
  where name = 'pippulse_push_function_url'
  limit 1;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'pippulse_push_function_secret'
  limit 1;

  if v_url is null or v_secret is null then
    raise warning 'PipPulse customer push is not configured; missing Vault URL or secret.';
    return new;
  end if;

  if new.notification_type in ('private_chat_invite', 'private_message') then
    if new.details ? 'conversation_id' then
      v_target_url := '/?private_chat=' || (new.details->>'conversation_id');
    end if;
  end if;

  v_push_body := case
    when new.notification_type = 'private_chat_invite'
      then 'PipPulse Admin has opened a private conversation with you.'
    else left(new.body, 180)
  end;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'type', new.notification_type,
      'user_id', new.recipient_id,
      'notification_id', new.id,
      'title', new.title,
      'body', v_push_body,
      'url', v_target_url
    )
  );

  return new;
end;
$$;

revoke all on function public.dispatch_user_notification_push() from public, anon, authenticated;

drop trigger if exists user_notifications_dispatch_push on public.user_notifications;
create trigger user_notifications_dispatch_push
  after insert on public.user_notifications
  for each row execute function public.dispatch_user_notification_push();

-- Private image storage is isolated from the shared Community Chat bucket.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'private-chat-images',
  'private-chat-images',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "Private chat participants view their images" on storage.objects;
create policy "Private chat participants view their images"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'private-chat-images'
    and exists (
      select 1 from public.private_conversations c
      where c.id::text = (storage.foldername(name))[1]
        and ((select auth.uid()) = c.admin_id or (select auth.uid()) = c.user_id)
    )
  );

drop policy if exists "Private chat participants upload their images" on storage.objects;
create policy "Private chat participants upload their images"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'private-chat-images'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and exists (
      select 1 from public.private_conversations c
      where c.id::text = (storage.foldername(name))[1]
        and ((select auth.uid()) = c.admin_id or (select auth.uid()) = c.user_id)
    )
  );

drop policy if exists "Users delete own private chat images" on storage.objects;
create policy "Users delete own private chat images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'private-chat-images'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and exists (
      select 1 from public.private_conversations c
      where c.id::text = (storage.foldername(name))[1]
        and ((select auth.uid()) = c.admin_id or (select auth.uid()) = c.user_id)
    )
  );

-- Enable realtime delivery for private messages and customer notifications.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'private_messages'
    ) then
      alter publication supabase_realtime add table public.private_messages;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_notifications'
    ) then
      alter publication supabase_realtime add table public.user_notifications;
    end if;
  end if;
end;
$$;

commit;
