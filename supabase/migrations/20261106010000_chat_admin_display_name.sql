-- Show a clear administrator label on community chat messages.
-- Existing members continue to display their username/display name.
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
  v_is_admin boolean := false;
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

  select coalesce(public.is_admin(), false) into v_is_admin;

  new.author_name := case
    when v_is_admin then 'PipPulse Admin'
    when nullif(btrim(v_username), '') is not null then '@' || btrim(v_username)
    when nullif(btrim(v_display_name), '') is not null then btrim(v_display_name)
    else 'PipPulse member'
  end;

  new.created_at := now();
  return new;
end;
$$;

revoke all on function public.prepare_community_chat_message() from public, anon, authenticated;
