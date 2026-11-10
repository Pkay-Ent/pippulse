-- End-to-end encryption foundation for admin-initiated private conversations.
-- Existing version-0 messages remain legacy plaintext; new sends must be version 1.
begin;

create table if not exists public.private_chat_public_keys (
  user_id uuid primary key references auth.users(id) on delete cascade,
  public_jwk jsonb not null,
  key_version smallint not null default 1 check (key_version = 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.private_chat_key_vault (
  user_id uuid primary key references auth.users(id) on delete cascade,
  wrapped_private_key text not null,
  salt text not null,
  iv text not null,
  kdf_iterations integer not null check (kdf_iterations between 100000 and 1000000),
  key_version smallint not null default 1 check (key_version = 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.private_chat_public_keys enable row level security;
alter table public.private_chat_key_vault enable row level security;

revoke all on public.private_chat_public_keys, public.private_chat_key_vault from anon, authenticated;
grant select, insert, update on public.private_chat_public_keys to authenticated;
grant select, insert, update on public.private_chat_key_vault to authenticated;

drop policy if exists "Private chat participants read peer public keys" on public.private_chat_public_keys;
create policy "Private chat participants read peer public keys"
  on public.private_chat_public_keys for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.private_conversations c
      where (c.admin_id = (select auth.uid()) and c.user_id = private_chat_public_keys.user_id)
         or (c.user_id = (select auth.uid()) and c.admin_id = private_chat_public_keys.user_id)
    )
  );

drop policy if exists "Users manage their own public key" on public.private_chat_public_keys;
create policy "Users manage their own public key"
  on public.private_chat_public_keys for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users update their own public key" on public.private_chat_public_keys;
create policy "Users update their own public key"
  on public.private_chat_public_keys for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users read their own encrypted key vault" on public.private_chat_key_vault;
create policy "Users read their own encrypted key vault"
  on public.private_chat_key_vault for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users create their own encrypted key vault" on public.private_chat_key_vault;
create policy "Users create their own encrypted key vault"
  on public.private_chat_key_vault for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users update their own encrypted key vault" on public.private_chat_key_vault;
create policy "Users update their own encrypted key vault"
  on public.private_chat_key_vault for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update on public.private_chat_public_keys, public.private_chat_key_vault to authenticated;

alter table public.private_messages
  add column if not exists encryption_version smallint not null default 0,
  add column if not exists body_iv text,
  add column if not exists image_iv text;

alter table public.private_messages
  drop constraint if exists private_messages_encryption_version_check;
alter table public.private_messages
  add constraint private_messages_encryption_version_check
  check (encryption_version in (0, 1));

comment on column public.private_messages.encryption_version is
  '0 = legacy plaintext message created before E2EE rollout; 1 = client-side AES-GCM ciphertext.';
comment on column public.private_messages.body_iv is
  'Base64 AES-GCM 96-bit IV for encrypted message body; null when body is empty.';
comment on column public.private_messages.image_iv is
  'Base64 AES-GCM 96-bit IV for encrypted image bytes; null when no image is attached.';

-- Reject new plaintext inserts. Old version-0 rows remain readable only as legacy history.
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

  new.body := coalesce(new.body, '');
  if new.encryption_version <> 1 then
    raise exception 'Private messages must be end-to-end encrypted. Please refresh PipPulse.';
  end if;
  if new.body = '' and new.image_path is null then
    raise exception 'Write a message or attach an image.';
  end if;
  if char_length(new.body) > 12000 then
    raise exception 'Encrypted message is too large.';
  end if;
  if new.body <> '' and (
      new.body_iv is null
      or new.body_iv !~ '^[A-Za-z0-9+/]{16}$'
      or new.body !~ '^[A-Za-z0-9+/]+={0,2}$'
  ) then
    raise exception 'The encrypted message payload is invalid.';
  end if;
  if new.body = '' and new.body_iv is not null then
    raise exception 'Unexpected message encryption metadata.';
  end if;
  if new.image_path is not null then
    if new.image_path not like
        new.conversation_id::text || '/' || (select auth.uid())::text || '/%.enc'
       or new.image_iv is null
       or new.image_iv !~ '^[A-Za-z0-9+/]{16}$' then
      raise exception 'The encrypted image attachment is invalid.';
    end if;
  elsif new.image_iv is not null then
    raise exception 'Unexpected image encryption metadata.';
  end if;

  new.created_at := now();
  return new;
end;
$$;

revoke all on function public.prepare_private_message() from public, anon, authenticated;

-- Never put message text or ciphertext in database or push notification previews.
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
    'You have a new private message. Open PipPulse to view it.',
    jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id)
  );

  return new;
end;
$$;

revoke all on function public.after_private_message_insert() from public, anon, authenticated;

-- Keep push alerts generic, including encrypted messages and legacy notifications.
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

  if new.notification_type in ('private_chat_invite', 'private_message')
     and new.details ? 'conversation_id' then
    v_target_url := '/?private_chat=' || (new.details->>'conversation_id');
  end if;

  v_push_body := case
    when new.notification_type = 'private_chat_invite'
      then 'PipPulse Admin has opened a private conversation with you.'
    when new.notification_type = 'private_message'
      then 'You have a new private message. Open PipPulse to view it.'
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

-- Encrypted image bytes are stored as opaque application/octet-stream objects.
update storage.buckets
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['application/octet-stream']
where id = 'private-chat-images';

commit;
