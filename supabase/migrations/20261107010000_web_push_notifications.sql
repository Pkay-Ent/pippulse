-- PipPulse opt-in web push subscriptions.
begin;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_id_idx
  on public.push_subscriptions(user_id);

alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;
grant all on public.push_subscriptions to service_role;

-- Private configuration used by the database trigger to call the push Edge Function.
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create or replace function public.dispatch_signal_push()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_temp
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'pippulse_push_function_url' limit 1;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'pippulse_push_function_secret' limit 1;

  if v_url is null or v_secret is null then
    raise warning 'PipPulse push is not configured; missing Vault URL or secret.';
    return new;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'notification_id', new.id,
      'title', 'New XAUUSD signal available',
      'body', 'A new trading signal is available. Open PipPulse to view it.',
      'url', '/'
    )
  );
  return new;
end;
$$;

revoke all on function public.dispatch_signal_push() from public, anon, authenticated;
drop trigger if exists signal_notifications_dispatch_push on public.signal_notifications;
create trigger signal_notifications_dispatch_push
  after insert on public.signal_notifications
  for each row execute function public.dispatch_signal_push();

commit;

-- After deploying the Edge Function, run these two commands with your real values:
-- select vault.create_secret('https://okuotuehtvsxtibjgjsi.supabase.co/functions/v1/send-signal-push', 'pippulse_push_function_url');
-- select vault.create_secret('<GENERATE_A_LONG_RANDOM_SECRET>', 'pippulse_push_function_secret');
