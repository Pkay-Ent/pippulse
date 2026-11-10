-- One current pinned community-chat message per community.
create table if not exists public.community_chat_pin (
  slot text primary key default 'community' check (slot = 'community'),
  message_id uuid not null references public.community_chat_messages(id) on delete cascade,
  pinned_by uuid not null references auth.users(id) on delete restrict,
  pinned_at timestamptz not null default now()
);

alter table public.community_chat_pin enable row level security;

drop policy if exists "Signed-in users can view community chat pin" on public.community_chat_pin;
create policy "Signed-in users can view community chat pin"
on public.community_chat_pin for select to authenticated
using (true);

revoke all on public.community_chat_pin from anon, authenticated;
grant select on public.community_chat_pin to authenticated;

create or replace function public.admin_pin_community_chat_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;
  if p_message_id is null or not exists (
    select 1 from public.community_chat_messages where id = p_message_id
  ) then
    raise exception 'Community message not found';
  end if;

  insert into public.community_chat_pin(slot, message_id, pinned_by, pinned_at)
  values ('community', p_message_id, auth.uid(), now())
  on conflict (slot) do update
    set message_id = excluded.message_id,
        pinned_by = excluded.pinned_by,
        pinned_at = excluded.pinned_at;
end;
$$;

create or replace function public.admin_unpin_community_chat_message()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;
  delete from public.community_chat_pin where slot = 'community';
end;
$$;

revoke all on function public.admin_pin_community_chat_message(uuid) from public, anon;
revoke all on function public.admin_unpin_community_chat_message() from public, anon;
grant execute on function public.admin_pin_community_chat_message(uuid) to authenticated;
grant execute on function public.admin_unpin_community_chat_message() to authenticated;

-- Enable live pin-change notifications where Supabase Realtime is available.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'community_chat_pin'
     ) then
    alter publication supabase_realtime add table public.community_chat_pin;
  end if;
end;
$$;
