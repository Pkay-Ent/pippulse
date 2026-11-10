-- Permanently delete an administrator-owned private conversation and its app records.
-- Storage objects are removed through the Storage API by the admin client before this RPC runs.
begin;

drop policy if exists "Admins delete images in their private conversations" on storage.objects;
create policy "Admins delete images in their private conversations"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'private-chat-images'
    and exists (
      select 1 from public.private_conversations c
      where c.id::text = (storage.foldername(name))[1]
        and c.admin_id = (select auth.uid())
    )
  );

create or replace function public.admin_delete_private_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required.';
  end if;

  if p_conversation_id is null then
    raise exception 'Choose a valid private conversation.';
  end if;

  if not exists (
    select 1
    from public.private_conversations c
    where c.id = p_conversation_id
      and c.admin_id = (select auth.uid())
  ) then
    raise exception 'This private conversation does not belong to your administrator account.';
  end if;

  -- Remove invite/message notifications for both participants, including read items.
  delete from public.user_notifications n
  where n.notification_type in ('private_chat_invite', 'private_message')
    and n.details ->> 'conversation_id' = p_conversation_id::text;

  -- private_messages are removed by the conversation's ON DELETE CASCADE foreign key.
  delete from public.private_conversations c
  where c.id = p_conversation_id
    and c.admin_id = (select auth.uid());

  if not found then
    raise exception 'The private conversation could not be deleted.';
  end if;
end;
$$;

revoke all on function public.admin_delete_private_conversation(uuid) from public, anon;
grant execute on function public.admin_delete_private_conversation(uuid) to authenticated;

commit;
