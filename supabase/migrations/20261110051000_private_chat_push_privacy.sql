-- Keep private message contents off device lock screens and external push surfaces.
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
