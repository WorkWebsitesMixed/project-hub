-- Project Hub — separate "can moderate" from "is on this project"
--
-- can_edit_project() answers "may this person change this project?" and says
-- yes to admins on everything, which is right for moderation: an admin should
-- be able to fix or remove a bad post.
--
-- Collaboration requests were reusing that same test, and there it is wrong.
-- It made the admin the recipient of every teacher's offers — an offer on one
-- teacher's project turned up in the admin's inbox with Accept and Decline
-- buttons, which would have granted project membership and, once email is
-- switched on, sent an answer as though it came from the owner.
--
-- It also contradicted what teachers were told: that a pending or declined
-- offer is seen only by the two people involved. Being an administrator of the
-- hub is not the same as being part of someone's project.

-- ─────────────────────────────────────────────────────────────────────────────
-- Membership without the moderation override
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.leads_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.project_members
    where project_id = p_project_id
      and user_id = auth.uid()
      and role in ('owner', 'editor')
  );
$$;

grant execute on function public.leads_project(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Only the project's own team sees and answers its offers
--
-- Note what is deliberately unchanged: collab_select_accepted still lets every
-- approved teacher read ACCEPTED requests, because the connection graph and
-- the director's report are built from them. Pending and declined offers stay
-- between the two people concerned — including from admins.
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists collab_select_project_side on public.collaboration_requests;
create policy collab_select_project_side
  on public.collaboration_requests
  for select to authenticated
  using (public.leads_project(project_id));

drop policy if exists collab_update_project_side on public.collaboration_requests;
create policy collab_update_project_side
  on public.collaboration_requests
  for update to authenticated
  using (public.leads_project(project_id))
  with check (public.leads_project(project_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- Answering an offer requires being on the project, not administering the hub
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- leads_project(), not can_edit_project(): accepting grants a colleague
  -- access to someone else's project and answers in the owner's name. That is
  -- the owner's decision, not an administrator's.
  if not public.leads_project(v_project) then
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
