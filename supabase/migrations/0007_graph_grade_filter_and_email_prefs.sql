-- Project Hub — grade filtering for the connection graph, and an email opt-out.

-- ─────────────────────────────────────────────────────────────────────────────
-- Grade filtering
--
-- The filter matches on the project's TARGET grade, the same thing the grade
-- checkboxes on the browse page mean. Consistency across the two screens beats
-- theoretical purity here: a teacher who filters to Grade 11 in one place
-- should get the same set of projects in the other.
--
-- Note what this deliberately keeps: filtering to Grade 11 still shows the
-- lines running out to 12th-grade Calculus, because those edges belong to an
-- 11th-grade project. Hiding them would erase exactly the cross-grade reach
-- the graph exists to make visible.
-- ─────────────────────────────────────────────────────────────────────────────

-- Dropped rather than replaced: adding a defaulted argument creates a second
-- overload, and subject_connections() would then be ambiguous.
drop function if exists public.subject_connections();

create or replace function public.subject_connections(
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
  select
    least(a.subject_slug, b.subject_slug)    as source_slug,
    greatest(a.subject_slug, b.subject_slug) as target_slug,
    count(distinct pa.project_id)::integer   as project_count
  from public.project_subjects pa
  join public.grade_subjects a on a.id = pa.grade_subject_id
  join public.project_subjects pb on pb.project_id = pa.project_id
  join public.grade_subjects b on b.id = pb.grade_subject_id
  where a.subject_slug < b.subject_slug
    and (
      p_grades is null or cardinality(p_grades) = 0 or exists (
        select 1 from public.project_grades pg
        where pg.project_id = pa.project_id and pg.grade = any (p_grades)
      )
    )
  group by 1, 2;
$$;

grant execute on function public.subject_connections(smallint[]) to authenticated;

-- Node weights for the same graph: how many projects each subject carries,
-- under the same grade filter.
create or replace function public.subject_usage(
  p_grades smallint[] default null
)
returns table (
  subject_slug  text,
  project_count integer
)
language sql
stable
set search_path = public
as $$
  select
    gs.subject_slug,
    count(distinct ps.project_id)::integer as project_count
  from public.project_subjects ps
  join public.grade_subjects gs on gs.id = ps.grade_subject_id
  where
    p_grades is null or cardinality(p_grades) = 0 or exists (
      select 1 from public.project_grades pg
      where pg.project_id = ps.project_id and pg.grade = any (p_grades)
    )
  group by gs.subject_slug;
$$;

grant execute on function public.subject_usage(smallint[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Email opt-out
--
-- Teachers get enough email. This is cheap to add now and unpleasant to
-- retrofit once addresses are in flight.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.profiles
  add column if not exists email_notifications boolean not null default true;
