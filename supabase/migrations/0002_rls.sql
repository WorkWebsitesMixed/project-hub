-- Project Hub — Row Level Security
--
-- The access rules live here, in the database, not in the Astro pages. A bug in
-- the UI must not be able to leak a colleague's project or let a student read
-- staff work. Every policy below routes through `is_approved()`.
--
-- Helper functions are SECURITY DEFINER so that reading `profiles` or
-- `project_members` from inside a policy does not re-enter that table's own
-- policy and recurse forever.

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_approved()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved' and role = 'admin'
  );
$$;

-- May this user change the project's content?
create or replace function public.can_edit_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.project_members
    where project_id = p_project_id
      and user_id = auth.uid()
      and role in ('owner', 'editor')
  );
$$;

-- May this user change who is on the project, or delete it? Owner only.
create or replace function public.can_manage_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.project_members
    where project_id = p_project_id
      and user_id = auth.uid()
      and role = 'owner'
  );
$$;

grant execute on function public.is_approved()                to authenticated;
grant execute on function public.is_admin()                   to authenticated;
grant execute on function public.can_edit_project(uuid)       to authenticated;
grant execute on function public.can_manage_project(uuid)     to authenticated;

-- A teacher must never be able to approve themselves or hand themselves the
-- admin role by PATCHing their own profile row.
create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- No JWT means the service-role key, which is already trusted.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  if new.status is distinct from old.status
     or new.role is distinct from old.role then
    raise exception 'Only an administrator may change approval status or role.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

create trigger profiles_guard_privileges
  before update on public.profiles
  for each row execute function public.guard_profile_privileges();

-- ─────────────────────────────────────────────────────────────────────────────
-- Enable RLS everywhere. Default-deny: a table with RLS on and no matching
-- policy returns zero rows.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.profiles               enable row level security;
alter table public.subjects               enable row level security;
alter table public.grade_subjects         enable row level security;
alter table public.projects               enable row level security;
alter table public.project_grades         enable row level security;
alter table public.project_subjects       enable row level security;
alter table public.project_members        enable row level security;
alter table public.collaboration_requests enable row level security;
alter table public.project_attachments    enable row level security;

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles
-- ─────────────────────────────────────────────────────────────────────────────

-- Own row is always readable — a pending teacher needs it to render the
-- "waiting for approval" screen.
create policy profiles_select_self on public.profiles
  for select to authenticated
  using (id = auth.uid());

create policy profiles_select_approved on public.profiles
  for select to authenticated
  using (public.is_approved() and status = 'approved');

create policy profiles_select_admin on public.profiles
  for select to authenticated
  using (public.is_admin());

-- Name, department, avatar. Status and role are blocked by the trigger above.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_update_admin on public.profiles
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- Subject catalog — readable by any signed-in account so the posting form can
-- populate. It is a public curriculum list; nothing sensitive lives here.
-- ─────────────────────────────────────────────────────────────────────────────

create policy subjects_select on public.subjects
  for select to authenticated using (true);

create policy subjects_write_admin on public.subjects
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy grade_subjects_select on public.grade_subjects
  for select to authenticated using (true);

create policy grade_subjects_write_admin on public.grade_subjects
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- projects
-- ─────────────────────────────────────────────────────────────────────────────

create policy projects_select on public.projects
  for select to authenticated
  using (public.is_approved());

create policy projects_insert on public.projects
  for insert to authenticated
  with check (public.is_approved() and owner_id = auth.uid());

create policy projects_update on public.projects
  for update to authenticated
  using (public.can_edit_project(id))
  with check (public.can_edit_project(id));

create policy projects_delete on public.projects
  for delete to authenticated
  using (public.can_manage_project(id));

-- ─────────────────────────────────────────────────────────────────────────────
-- Tags. Readable by every approved teacher — discovery is the whole point.
-- Writable only by the people who can edit the parent project.
-- ─────────────────────────────────────────────────────────────────────────────

create policy project_grades_select on public.project_grades
  for select to authenticated using (public.is_approved());

create policy project_grades_write on public.project_grades
  for all to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

create policy project_subjects_select on public.project_subjects
  for select to authenticated using (public.is_approved());

create policy project_subjects_write on public.project_subjects
  for all to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- project_members
-- ─────────────────────────────────────────────────────────────────────────────

create policy project_members_select on public.project_members
  for select to authenticated using (public.is_approved());

create policy project_members_write on public.project_members
  for all to authenticated
  using (public.can_manage_project(project_id))
  with check (public.can_manage_project(project_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- collaboration_requests
--
-- Deliberately narrower than everything else. A teacher seeing their own
-- interest declined is one thing; the whole staff seeing it is another.
-- ─────────────────────────────────────────────────────────────────────────────

create policy collab_select_own on public.collaboration_requests
  for select to authenticated
  using (public.is_approved() and user_id = auth.uid());

create policy collab_select_project_side on public.collaboration_requests
  for select to authenticated
  using (public.can_edit_project(project_id));

-- You may only express interest on your own behalf.
create policy collab_insert_self on public.collaboration_requests
  for insert to authenticated
  with check (public.is_approved() and user_id = auth.uid());

-- Withdraw your own request.
create policy collab_update_own on public.collaboration_requests
  for update to authenticated
  using (public.is_approved() and user_id = auth.uid())
  with check (user_id = auth.uid());

create policy collab_delete_own on public.collaboration_requests
  for delete to authenticated
  using (public.is_approved() and user_id = auth.uid());

-- Accept or decline, from the project side.
create policy collab_update_project_side on public.collaboration_requests
  for update to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

-- ─────────────────────────────────────────────────────────────────────────────
-- project_attachments
-- ─────────────────────────────────────────────────────────────────────────────

create policy attachments_select on public.project_attachments
  for select to authenticated using (public.is_approved());

create policy attachments_write on public.project_attachments
  for all to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));
