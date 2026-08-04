-- Project Hub — the owner's side of "I want to collaborate"
--
-- Expressing interest writes one row. Answering it touches two tables: the
-- request's status, and — on acceptance — a project_members row that actually
-- grants the colleague edit rights. Doing that as two calls from the browser
-- would let an accepted request exist with no membership behind it.
--
-- SECURITY DEFINER with an explicit can_edit_project() guard, rather than
-- SECURITY INVOKER: the membership insert is governed by can_manage_project
-- (owner only), but a co-editor should be able to answer requests too. One
-- permission model, checked once, at the top.

create or replace function public.respond_to_collaboration(
  p_request_id uuid,
  p_accept     boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project uuid;
  v_user    uuid;
begin
  select project_id, user_id into v_project, v_user
  from public.collaboration_requests
  where id = p_request_id;

  if v_project is null then
    raise exception 'That collaboration request no longer exists.'
      using errcode = 'no_data_found';
  end if;

  if not public.can_edit_project(v_project) then
    raise exception 'Only the project team can answer this request.'
      using errcode = 'insufficient_privilege';
  end if;

  update public.collaboration_requests
     set status       = case when p_accept then 'accepted'::public.request_status
                             else 'declined'::public.request_status end,
         responded_at = now()
   where id = p_request_id;

  if p_accept then
    insert into public.project_members (project_id, user_id, role)
    values (v_project, v_user, 'collaborator')
    on conflict (project_id, user_id) do nothing;
  else
    -- Declining after an earlier acceptance withdraws the access too. The
    -- role filter means an owner or co-editor is never demoted by this.
    delete from public.project_members
     where project_id = v_project
       and user_id    = v_user
       and role       = 'collaborator';
  end if;
end;
$$;

grant execute on function public.respond_to_collaboration(uuid, boolean) to authenticated;
