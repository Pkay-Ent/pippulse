-- In-app signal notifications for all signed-in PipPulse users.
-- Creates one safe preview notification whenever a signal is published.
-- Full signal details remain protected by the existing signal access rules.

begin;

create table if not exists public.signal_notifications (
  id uuid primary key default gen_random_uuid(),
  signal_id uuid not null unique references public.signals(id) on delete cascade,
  title text not null default 'New XAUUSD signal published',
  body text not null default 'A new trading signal is available. Open PipPulse to view it.',
  created_at timestamptz not null default now()
);

create table if not exists public.signal_notification_reads (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.signal_notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  unique (notification_id, user_id)
);

create index if not exists signal_notifications_created_at_idx
  on public.signal_notifications (created_at desc);
create index if not exists signal_notification_reads_user_idx
  on public.signal_notification_reads (user_id, notification_id);

create or replace function public.can_receive_signal_notifications()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null;
$$;

revoke all on function public.can_receive_signal_notifications() from public, anon;
grant execute on function public.can_receive_signal_notifications() to authenticated;

alter table public.signal_notifications enable row level security;
alter table public.signal_notification_reads enable row level security;

revoke all on public.signal_notifications from anon, authenticated;
grant select on public.signal_notifications to authenticated;
revoke all on public.signal_notification_reads from anon, authenticated;
grant select, insert, update on public.signal_notification_reads to authenticated;

drop policy if exists "Premium users read signal notifications" on public.signal_notifications;
drop policy if exists "Signed-in users read signal notifications" on public.signal_notifications;
create policy "Signed-in users read signal notifications"
  on public.signal_notifications
  for select
  to authenticated
  using (public.can_receive_signal_notifications());

drop policy if exists "Premium users read their notification receipts" on public.signal_notification_reads;
drop policy if exists "Signed-in users read their notification receipts" on public.signal_notification_reads;
create policy "Signed-in users read their notification receipts"
  on public.signal_notification_reads
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Premium users create their notification receipts" on public.signal_notification_reads;
drop policy if exists "Signed-in users create their notification receipts" on public.signal_notification_reads;
create policy "Signed-in users create their notification receipts"
  on public.signal_notification_reads
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Premium users update their notification receipts" on public.signal_notification_reads;
drop policy if exists "Signed-in users update their notification receipts" on public.signal_notification_reads;
create policy "Signed-in users update their notification receipts"
  on public.signal_notification_reads
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.create_signal_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'published' and new.published_at is not null then
    insert into public.signal_notifications (signal_id)
    values (new.id)
    on conflict (signal_id) do nothing;
  end if;
  return new;
end;
$$;

revoke all on function public.create_signal_notification() from public, anon, authenticated;

drop trigger if exists signals_create_notification on public.signals;
create trigger signals_create_notification
  after insert or update of status, published_at
  on public.signals
  for each row
  execute function public.create_signal_notification();

-- Enable realtime delivery for the notification bell.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'signal_notifications'
     ) then
    alter publication supabase_realtime add table public.signal_notifications;
  end if;
end;
$$;

commit;
