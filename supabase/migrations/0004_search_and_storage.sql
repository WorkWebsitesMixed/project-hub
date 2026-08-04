-- Project Hub — search RPC and file storage

-- ─────────────────────────────────────────────────────────────────────────────
-- search_projects
--
-- Every browse/filter query in the app goes through this one function, so the
-- card grid is a single round trip: the projects, their tags, their owner and
-- the total match count all come back together.
--
-- SECURITY INVOKER (the default) is load-bearing — RLS on `projects` still
-- applies, so an unapproved account calling this RPC directly gets nothing.
--
-- p_match_all decides how multiple subject filters combine:
--   false → "touches Physics OR Calculus"  (widen the net, the default)
--   true  → "touches Physics AND Calculus" (find genuine intersections)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.search_projects(
  p_query         text                    default null,
  p_grades        smallint[]              default null,
  p_subject_slugs text[]                  default null,
  p_statuses      public.project_status[] default null,
  p_subject_role  public.subject_role     default null,
  p_match_all     boolean                 default false,
  p_limit         integer                 default 50,
  p_offset        integer                 default 0
)
returns table (
  id                 uuid,
  title              text,
  description        text,
  status             public.project_status,
  duration           text,
  resources          text,
  language           public.content_lang,
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
  public.subject_role, boolean, integer, integer
) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- subject_connections
--
-- Feeds the connection graph: for every pair of subjects that share at least
-- one project, how many projects join them. This is the view that makes
-- interdisciplinary overlap visible rather than merely filterable.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.subject_connections()
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
  group by 1, 2;
$$;

grant execute on function public.subject_connections() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Attachments bucket
--
-- Private bucket. Files are addressed as `<project_id>/<filename>`, which lets
-- the storage policies below reuse the same can_edit_project() check the rest
-- of the schema uses. 10 MB cap, images and PDFs only.
-- ─────────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'project-files',
  'project-files',
  false,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'application/pdf']
)
on conflict (id) do nothing;

drop policy if exists project_files_read on storage.objects;
create policy project_files_read
  on storage.objects
  for select to authenticated
  using (bucket_id = 'project-files' and public.is_approved());

drop policy if exists project_files_write on storage.objects;
create policy project_files_write
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'project-files'
    and public.can_edit_project(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists project_files_delete on storage.objects;
create policy project_files_delete
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'project-files'
    and public.can_edit_project(((storage.foldername(name))[1])::uuid)
  );
