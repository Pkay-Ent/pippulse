-- PipPulse community chat upgrades: replies, edits, mentions and member image uploads.
begin;

alter table public.community_chat_messages
  add column if not exists reply_to_id uuid references public.community_chat_messages(id) on delete set null,
  add column if not exists image_path text,
  add column if not exists updated_at timestamptz;

create index if not exists community_chat_messages_reply_idx
  on public.community_chat_messages(reply_to_id);

grant update (body) on public.community_chat_messages to authenticated;
drop policy if exists "Members edit own chat messages" on public.community_chat_messages;
create policy "Members edit own chat messages"
  on public.community_chat_messages for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Replaces the original insert-only guard while retaining identity, length and rate-limit checks.
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
  if auth.uid() is null then
    raise exception 'You must be signed in to use community chat.';
  end if;

  if tg_op = 'UPDATE' then
    if old.user_id <> auth.uid() or new.user_id <> old.user_id then
      raise exception 'You can only edit your own messages.';
    end if;
    if new.reply_to_id is distinct from old.reply_to_id
       or new.image_path is distinct from old.image_path then
      raise exception 'Replies and uploaded images cannot be changed while editing.';
    end if;
    new.body := btrim(coalesce(new.body, ''));
    if new.body = '' and new.image_path is null then
      raise exception 'A message must contain text or an image.';
    end if;
    if char_length(new.body) > 1000 then
      raise exception 'Messages are limited to 1000 characters.';
    end if;
    new.author_name := old.author_name;
    new.created_at := old.created_at;
    new.updated_at := now();
    return new;
  end if;

  if new.user_id <> auth.uid() then
    raise exception 'You must post as yourself.';
  end if;
  new.body := btrim(coalesce(new.body, ''));
  if new.body = '' and new.image_path is null then
    raise exception 'Write a message or attach an image.';
  end if;
  if char_length(new.body) > 1000 then
    raise exception 'Messages are limited to 1000 characters.';
  end if;

  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  select max(created_at) into v_last_message
  from public.community_chat_messages
  where user_id = new.user_id;
  if v_last_message is not null and v_last_message > now() - interval '2 seconds' then
    raise exception 'Please wait a moment before sending another message.';
  end if;

  select username, display_name into v_username, v_display_name
  from public.profiles where id = new.user_id;
  new.author_name := case
    when nullif(btrim(v_username), '') is not null then '@' || btrim(v_username)
    when nullif(btrim(v_display_name), '') is not null then btrim(v_display_name)
    else 'PipPulse member'
  end;
  new.created_at := now();
  new.updated_at := null;
  return new;
end;
$$;

drop trigger if exists community_chat_prepare_message on public.community_chat_messages;
create trigger community_chat_prepare_message
  before insert or update on public.community_chat_messages
  for each row execute function public.prepare_community_chat_message();

-- Private bucket: members can view chat images; each member can upload/delete only their own files.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('community-chat-images', 'community-chat-images', false, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Chat members view shared chat images" on storage.objects;
create policy "Chat members view shared chat images"
  on storage.objects for select to authenticated
  using (bucket_id = 'community-chat-images');

drop policy if exists "Members upload own chat images" on storage.objects;
create policy "Members upload own chat images"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'community-chat-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Members delete own chat images" on storage.objects;
create policy "Members delete own chat images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'community-chat-images'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or coalesce(public.is_admin(), false)
    )
  );

commit;
