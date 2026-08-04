-- Project Hub — atomic project write
--
-- A project is spread across three tables (projects, project_grades,
-- project_subjects). Writing them as three separate calls from the browser
-- would leave a half-tagged project behind whenever the network drops between
-- them. One function, one transaction, no orphans.
--
-- SECURITY INVOKER (the default) is deliberate: RLS still decides whether this
-- caller may create or edit the project. The function is a convenience for the
-- client, not a way around the policies.
--
-- Subject tags arrive as 'slug@grade' strings — 'physics@11', 'calculus@12' —
-- which is the same shape the UI puts in the URL when filtering, so one
-- notation covers posting, editing and sharing a filtered link.

create or replace function public.upsert_project(
  p_title           text,
  p_description     text,
  p_status          public.project_status,
  p_duration        text,
  p_resources       text,
  p_language        public.content_lang,
  p_grades          smallint[],
  p_primary_subject text,
  p_cross_subjects  text[] default '{}',
  p_id              uuid   default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
  v_tag text;
  v_gs_id uuid;
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

  if p_id is null then
    insert into public.projects
      (owner_id, title, description, status, duration, resources, language)
    values
      (auth.uid(), p_title, p_description, p_status,
       coalesce(p_duration, ''), coalesce(p_resources, ''), p_language)
    returning id into v_id;
  else
    -- No rows updated means RLS refused: not the owner, not an editor, not an
    -- admin. Report that plainly instead of silently doing nothing.
    update public.projects
       set title       = p_title,
           description = p_description,
           status      = p_status,
           duration    = coalesce(p_duration, ''),
           resources   = coalesce(p_resources, ''),
           language    = p_language
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
  smallint[], text, text[], uuid
) to authenticated;
