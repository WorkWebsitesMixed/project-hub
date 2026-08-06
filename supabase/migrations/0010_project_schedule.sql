-- Project Hub — when a project actually runs
--
-- `duration` was free text ("unas tres semanas en el segundo periodo"). It
-- reads fine and compares to nothing. Two projects can look perfectly
-- complementary on the connection graph and be impossible to run together,
-- because one is in T1 and the other in T3 — and nothing in the hub could say
-- so.
--
-- This adds a structured schedule: academic year, term, and a week range within
-- that term. The free-text column stays, demoted to an optional note, because
-- teachers wrote real nuance in it ("depende de cuándo esté libre el
-- laboratorio") that dropdowns cannot hold.
--
-- One term per project, by decision: nothing at the school runs across a term
-- boundary. If that changes, this needs an end_term column rather than a
-- reinterpretation of week_end.

-- ─────────────────────────────────────────────────────────────────────────────
-- Columns
-- ─────────────────────────────────────────────────────────────────────────────

do $$ begin
  create type public.term_code as enum ('T1', 'T2', 'T3');
exception when duplicate_object then null;
end $$;

alter table public.projects
  add column if not exists academic_year smallint,
  add column if not exists term          public.term_code,
  add column if not exists week_start    smallint,
  add column if not exists week_end      smallint;

comment on column public.projects.academic_year is
  'Calendar year the academic year STARTS in: 2026 means 2026–2027. The school year begins in August.';

-- A flat 1–12 ceiling. If terms turn out to have different lengths, the form is
-- where that belongs — the database only needs to reject nonsense.
alter table public.projects drop constraint if exists projects_weeks_ck;
alter table public.projects add constraint projects_weeks_ck check (
  (week_start is null and week_end is null)
  or (
    term is not null
    and week_start between 1 and 12
    and week_end   between 1 and 12
    and week_end >= week_start
  )
);

alter table public.projects drop constraint if exists projects_academic_year_ck;
alter table public.projects add constraint projects_academic_year_ck check (
  academic_year is null or academic_year between 2000 and 2100
);

create index if not exists projects_schedule_idx
  on public.projects (academic_year, term);

-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill
--
-- Existing projects were posted for the year they were posted in, so derive it
-- from created_at rather than hardcoding one. `where academic_year is null`
-- keeps this idempotent and stops a re-run from overwriting a corrected value.
-- Term is deliberately left null: nobody knows it, and guessing would put wrong
-- data on the board. Those projects read as "sin programar" until someone edits
-- them.
-- ─────────────────────────────────────────────────────────────────────────────

update public.projects
   set academic_year = (
     extract(year from created_at)::smallint
     - case when extract(month from created_at) >= 8 then 0 else 1 end
   )
 where academic_year is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- upsert_project — four more parameters
--
-- The old signature has to be dropped explicitly. `create or replace` with
-- extra defaulted arguments creates an OVERLOAD rather than replacing, and two
-- overloads is exactly the ambiguity PostgREST answers with HTTP 300.
-- ─────────────────────────────────────────────────────────────────────────────

drop function if exists public.upsert_project(
  text, text, public.project_status, text, text, public.content_lang,
  smallint[], text, text[], uuid
);

create or replace function public.upsert_project(
  p_title           text,
  p_description     text,
  p_status          public.project_status,
  p_duration        text,
  p_resources       text,
  p_language        public.content_lang,
  p_grades          smallint[],
  p_primary_subject text,
  p_cross_subjects  text[]            default '{}',
  p_id              uuid              default null,
  p_academic_year   smallint          default null,
  p_term            public.term_code  default null,
  p_week_start      smallint          default null,
  p_week_end        smallint          default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_id    uuid;
  v_tag   text;
  v_gs_id uuid;
  v_year  smallint;
  v_from  smallint;
  v_to    smallint;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to post a project.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_grades is null or cardinality(p_grades) = 0 then
    raise exception 'Choose at least one target grade.'
      using errcode = 'check_violation';
  end if;

  if p_primary_subject is null or btrim(p_primary_subject) = '' then
    raise exception 'Choose a primary subject.'
      using errcode = 'check_violation';
  end if;

  -- A project always belongs to a year, even when the client forgets to say
  -- which — otherwise next August the board cannot tell this year's T1 from
  -- last year's.
  v_year := coalesce(
    p_academic_year,
    (extract(year from now())::smallint
      - case when extract(month from now()) >= 8 then 0 else 1 end)
  );

  -- Weeks only mean something inside a term.
  if p_term is null then
    v_from := null;
    v_to   := null;
  else
    v_from := p_week_start;
    v_to   := p_week_end;

    -- One week given is a one-week project, not half a range.
    v_from := coalesce(v_from, v_to);
    v_to   := coalesce(v_to, v_from);

    -- Reversed bounds are unambiguous about what was meant, so mean it rather
    -- than refusing a form the teacher filled in correctly-but-backwards.
    if v_from is not null and v_to < v_from then
      v_from := p_week_end;
      v_to   := p_week_start;
    end if;

    if v_from is not null and (v_from < 1 or v_to > 12) then
      raise exception 'Weeks must fall between 1 and 12.'
        using errcode = 'check_violation';
    end if;
  end if;

  if p_id is null then
    insert into public.projects
      (owner_id, title, description, status, duration, resources, language,
       academic_year, term, week_start, week_end)
    values
      (auth.uid(), p_title, p_description, p_status,
       coalesce(p_duration, ''), coalesce(p_resources, ''), p_language,
       v_year, p_term, v_from, v_to)
    returning id into v_id;
  else
    -- No rows updated means RLS refused: not the owner, not an editor, not an
    -- admin. Report that plainly instead of silently doing nothing.
    update public.projects
       set title         = p_title,
           description   = p_description,
           status        = p_status,
           duration      = coalesce(p_duration, ''),
           resources     = coalesce(p_resources, ''),
           language      = p_language,
           academic_year = v_year,
           term          = p_term,
           week_start    = v_from,
           week_end      = v_to
     where id = p_id
    returning id into v_id;

    if v_id is null then
      raise exception 'You do not have permission to edit this project.'
        using errcode = 'insufficient_privilege';
    end if;

    delete from public.project_grades   where project_id = v_id;
    delete from public.project_subjects where project_id = v_id;
  end if;

  insert into public.project_grades (project_id, grade)
  select v_id, unnest(p_grades)
  on conflict do nothing;

  -- Primary subject.
  select gs.id into v_gs_id
  from public.grade_subjects gs
  where gs.subject_slug = split_part(p_primary_subject, '@', 1)
    and gs.grade = split_part(p_primary_subject, '@', 2)::smallint;

  if v_gs_id is null then
    raise exception 'Unknown subject tag: %', p_primary_subject
      using errcode = 'foreign_key_violation';
  end if;

  insert into public.project_subjects (project_id, grade_subject_id, role)
  values (v_id, v_gs_id, 'primary');

  -- Cross-disciplinary subjects. The primary one is skipped rather than
  -- rejected, so a teacher who also ticks it in the big list is not scolded
  -- for it.
  foreach v_tag in array coalesce(p_cross_subjects, '{}')
  loop
    if v_tag is not null and btrim(v_tag) <> '' and v_tag <> p_primary_subject then
      select gs.id into v_gs_id
      from public.grade_subjects gs
      where gs.subject_slug = split_part(v_tag, '@', 1)
        and gs.grade = split_part(v_tag, '@', 2)::smallint;

      if v_gs_id is null then
        raise exception 'Unknown subject tag: %', v_tag
          using errcode = 'foreign_key_violation';
      end if;

      insert into public.project_subjects (project_id, grade_subject_id, role)
      values (v_id, v_gs_id, 'cross')
      on conflict (project_id, grade_subject_id) do nothing;
    end if;
  end loop;

  return v_id;
end;
$$;

grant execute on function public.upsert_project(
  text, text, public.project_status, text, text, public.content_lang,
  smallint[], text, text[], uuid, smallint, public.term_code, smallint, smallint
) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- search_projects — return the schedule, and filter on it
--
-- Dropped rather than replaced: the return type gains four columns, and
-- `create or replace` cannot change a function's return type.
-- ─────────────────────────────────────────────────────────────────────────────

drop function if exists public.search_projects(
  text, smallint[], text[], public.project_status[],
  public.subject_role, boolean, integer, integer
);

create or replace function public.search_projects(
  p_query         text                    default null,
  p_grades        smallint[]              default null,
  p_subject_slugs text[]                  default null,
  p_statuses      public.project_status[] default null,
  p_subject_role  public.subject_role     default null,
  p_match_all     boolean                 default false,
  p_limit         integer                 default 50,
  p_offset        integer                 default 0,
  p_terms         public.term_code[]      default null,
  p_academic_year smallint                default null
)
returns table (
  id                 uuid,
  title              text,
  description        text,
  status             public.project_status,
  duration           text,
  resources          text,
  language           public.content_lang,
  academic_year      smallint,
  term               public.term_code,
  week_start         smallint,
  week_end           smallint,
  owner_id           uuid,
  owner_name         text,
  owner_email        text,
  created_at         timestamptz,
  updated_at         timestamptz,
  grades             smallint[],
  subjects           jsonb,
  interest_count     integer,
  attachment_count   integer,
  total_count        bigint
)
language sql
stable
set search_path = public
as $$
  with matched as (
    select p.*
    from public.projects p
    where
      (p_query is null or btrim(p_query) = ''
        or p.search_vector @@ websearch_to_tsquery('simple', p_query))

      and (p_statuses is null or cardinality(p_statuses) = 0
        or p.status = any (p_statuses))

      -- Filtering by term excludes the unscheduled on purpose: "what runs in
      -- T2" is a question about scheduled work, and a project with no term is
      -- not an answer to it.
      and (p_terms is null or cardinality(p_terms) = 0
        or p.term = any (p_terms))

      and (p_academic_year is null or p.academic_year = p_academic_year)

      -- Targets at least one of the requested grades.
      and (p_grades is null or cardinality(p_grades) = 0 or exists (
        select 1 from public.project_grades pg
        where pg.project_id = p.id and pg.grade = any (p_grades)
      ))

      -- Tagged with the requested subjects, in whichever combining mode.
      and (
        p_subject_slugs is null or cardinality(p_subject_slugs) = 0
        or (
          case when p_match_all then
            (
              select count(distinct gs.subject_slug)
              from public.project_subjects ps
              join public.grade_subjects gs on gs.id = ps.grade_subject_id
              where ps.project_id = p.id
                and gs.subject_slug = any (p_subject_slugs)
                and (p_subject_role is null or ps.role = p_subject_role)
            ) = cardinality(p_subject_slugs)
          else
            exists (
              select 1
              from public.project_subjects ps
              join public.grade_subjects gs on gs.id = ps.grade_subject_id
              where ps.project_id = p.id
                and gs.subject_slug = any (p_subject_slugs)
                and (p_subject_role is null or ps.role = p_subject_role)
            )
          end
        )
      )
  )
  select
    m.id,
    m.title,
    m.description,
    m.status,
    m.duration,
    m.resources,
    m.language,
    m.academic_year,
    m.term,
    m.week_start,
    m.week_end,
    m.owner_id,
    owner.full_name as owner_name,
    owner.email     as owner_email,
    m.created_at,
    m.updated_at,

    coalesce((
      select array_agg(pg.grade order by pg.grade)
      from public.project_grades pg where pg.project_id = m.id
    ), '{}'::smallint[]) as grades,

    coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'slug',   gs.subject_slug,
                 'grade',  gs.grade,
                 'role',   ps.role,
                 'family', s.family,
                 'name',   jsonb_build_object(
                             'en', s.name_en, 'es', s.name_es, 'fr', s.name_fr
                           )
               )
               -- Primary subject first, then catalog order.
               order by (ps.role <> 'primary'), s.sort_order, gs.grade
             )
      from public.project_subjects ps
      join public.grade_subjects gs on gs.id = ps.grade_subject_id
      join public.subjects s        on s.slug = gs.subject_slug
      where ps.project_id = m.id
    ), '[]'::jsonb) as subjects,

    (select count(*)::integer from public.collaboration_requests cr
      where cr.project_id = m.id and cr.status <> 'declined') as interest_count,

    (select count(*)::integer from public.project_attachments pa
      where pa.project_id = m.id) as attachment_count,

    count(*) over () as total_count

  from matched m
  left join public.profiles owner on owner.id = m.owner_id
  order by
    -- Text relevance when searching, recency otherwise.
    case when p_query is null or btrim(p_query) = '' then 0
         else ts_rank(m.search_vector, websearch_to_tsquery('simple', p_query))
    end desc,
    m.updated_at desc
  limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

grant execute on function public.search_projects(
  text, smallint[], text[], public.project_status[],
  public.subject_role, boolean, integer, integer,
  public.term_code[], smallint
) to authenticated;
