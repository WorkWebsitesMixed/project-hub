-- Project Hub — confirmed collaborations
--
-- The existing graph answers "who might I work with?" from one teacher's tags.
-- This adds the other question, the one a learning director asks: "what joint
-- work is actually happening?"
--
-- The difference matters. A project tagged across four subjects, with one
-- accepted partner, is ONE collaboration — not six. Drawing it from the tags
-- would inflate a single acceptance into a web of connections nobody agreed to.
--
-- So a confirmed edge is built from two things people actually stated: the
-- project's primary subject, and the subject the partner said they were
-- bringing when they offered to help. One line per real pairing.

-- ─────────────────────────────────────────────────────────────────────────────
-- What the partner brings
--
-- Recorded on the offer rather than on the teacher's profile. A teacher who
-- takes both Chemistry and Physics knows exactly which one they are bringing
-- to THIS project; a profile field would force a guess and would go stale the
-- next time a timetable changed.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.collaboration_requests
  add column if not exists offered_grade_subject_id uuid
    references public.grade_subjects (id) on delete restrict;

-- Nullable on purpose: the form requires it, but a row written before this
-- migration must never be able to break the graph.
create index if not exists collab_requests_offered_idx
  on public.collaboration_requests (offered_grade_subject_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Visibility
--
-- Until now a collaboration request was visible only to the two people
-- involved, which is right for an offer that is pending or was turned down.
-- An ACCEPTED one is different: it is joint work happening in the school, and
-- both the graph and the director's report need to see it. Pending and
-- declined offers stay private.
-- ─────────────────────────────────────────────────────────────────────────────

create policy collab_select_accepted on public.collaboration_requests
  for select to authenticated
  using (public.is_approved() and status = 'accepted');

-- ─────────────────────────────────────────────────────────────────────────────
-- Making an offer
--
-- One function so the subject tag is resolved and validated in the same
-- statement that writes the row.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.offer_collaboration(
  p_project_id  uuid,
  p_message     text default '',
  p_subject_tag text default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_gs_id uuid;
  v_id    uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to offer to collaborate.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_subject_tag is not null and btrim(p_subject_tag) <> '' then
    select gs.id into v_gs_id
    from public.grade_subjects gs
    where gs.subject_slug = split_part(p_subject_tag, '@', 1)
      and gs.grade = split_part(p_subject_tag, '@', 2)::smallint;

    if v_gs_id is null then
      raise exception 'Unknown subject tag: %', p_subject_tag
        using errcode = 'foreign_key_violation';
    end if;
  end if;

  insert into public.collaboration_requests
    (project_id, user_id, message, offered_grade_subject_id)
  values
    (p_project_id, auth.uid(), coalesce(p_message, ''), v_gs_id)
  -- Clicking twice must not raise. Update rather than ignore, so a teacher who
  -- resubmits with a different subject gets the corrected one.
  on conflict (project_id, user_id) do update
    set message                  = excluded.message,
        offered_grade_subject_id = excluded.offered_grade_subject_id
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.offer_collaboration(uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- The confirmed graph
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.collaboration_connections(
  p_grades smallint[] default null
)
returns table (
  source_slug   text,
  target_slug   text,
  project_count integer
)
language sql
stable
set search_path = public
as $$
  with pairings as (
    select
      cr.project_id,
      owner_gs.subject_slug   as owner_slug,
      partner_gs.subject_slug as partner_slug
    from public.collaboration_requests cr
    join public.project_subjects ps
      on ps.project_id = cr.project_id and ps.role = 'primary'
    join public.grade_subjects owner_gs   on owner_gs.id = ps.grade_subject_id
    join public.grade_subjects partner_gs on partner_gs.id = cr.offered_grade_subject_id
    where cr.status = 'accepted'
      and (
        p_grades is null or cardinality(p_grades) = 0 or exists (
          select 1 from public.project_grades pg
          where pg.project_id = cr.project_id and pg.grade = any (p_grades)
        )
      )
  )
  select
    least(owner_slug, partner_slug)        as source_slug,
    greatest(owner_slug, partner_slug)     as target_slug,
    count(distinct project_id)::integer    as project_count
  from pairings
  -- Two teachers of the same subject working together is real, and it is
  -- counted in joint_projects() below — but it is not an interdisciplinary
  -- line, and drawing it as a loop would only muddy the picture.
  where owner_slug <> partner_slug
  group by 1, 2;
$$;

grant execute on function public.collaboration_connections(smallint[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- The director's list
--
-- Every project with at least one accepted partner, with the names and
-- subjects on both sides. Includes same-subject partnerships, which the graph
-- deliberately omits.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.joint_projects(
  p_grades smallint[] default null
)
returns table (
  project_id    uuid,
  title         text,
  status        public.project_status,
  grades        smallint[],
  owner_name    text,
  owner_email   text,
  owner_subject text,
  owner_grade   smallint,
  partners      jsonb,
  partner_count integer,
  updated_at    timestamptz
)
language sql
stable
set search_path = public
as $$
  select
    p.id,
    p.title,
    p.status,
    coalesce((
      select array_agg(pg.grade order by pg.grade)
      from public.project_grades pg where pg.project_id = p.id
    ), '{}'::smallint[]),
    owner.full_name,
    owner.email,
    ogs.subject_slug,
    ogs.grade,
    coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'name',    pr.full_name,
                 'email',   pr.email,
                 'subject', pgs.subject_slug,
                 'grade',   pgs.grade
               )
               order by pr.full_name
             )
      from public.collaboration_requests cr
      join public.profiles pr on pr.id = cr.user_id
      left join public.grade_subjects pgs on pgs.id = cr.offered_grade_subject_id
      where cr.project_id = p.id and cr.status = 'accepted'
    ), '[]'::jsonb),
    (
      select count(*)::integer from public.collaboration_requests cr
      where cr.project_id = p.id and cr.status = 'accepted'
    ),
    p.updated_at
  from public.projects p
  left join public.profiles owner on owner.id = p.owner_id
  left join public.project_subjects ps
    on ps.project_id = p.id and ps.role = 'primary'
  left join public.grade_subjects ogs on ogs.id = ps.grade_subject_id
  where exists (
      select 1 from public.collaboration_requests cr
      where cr.project_id = p.id and cr.status = 'accepted'
    )
    and (
      p_grades is null or cardinality(p_grades) = 0 or exists (
        select 1 from public.project_grades pg
        where pg.project_id = p.id and pg.grade = any (p_grades)
      )
    )
  order by p.updated_at desc;
$$;

grant execute on function public.joint_projects(smallint[]) to authenticated;
