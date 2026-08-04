-- Project Hub — schema behaviour and Row Level Security tests.
--
-- Run against a throwaway Postgres, never against Supabase:  npm run db:test
--
-- Every check prints PASS or FAIL. The RLS half matters most: it proves a
-- student who signs in with their school Google account — same email domain as
-- the staff — sees nothing at all until an admin approves them.

\set ON_ERROR_STOP on

-- Supabase grants these to `authenticated` out of the box. The stub must match,
-- or the RLS tests would "pass" for the wrong reason (permission denied rather
-- than a policy correctly returning zero rows).
grant usage on schema public, storage, auth to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema storage to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Sign-up gate
-- ─────────────────────────────────────────────────────────────────────────────

do $$ begin
  begin
    insert into auth.users (email) values ('someone@gmail.com');
    raise notice 'FAIL  outside-domain sign-in was accepted';
  exception when check_violation then
    raise notice 'PASS  outside-domain sign-in rejected';
  end;
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ana@marymount.edu.co',
   '{"full_name":"Ana Restrepo"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'luis@marymount.edu.co',
   '{"full_name":"Luis Gomez"}'::jsonb),
  -- A student. Same domain as the staff — this is the case the approval gate
  -- exists for.
  ('33333333-3333-3333-3333-333333333333', 'student@marymount.edu.co',
   '{"full_name":"Estudiante"}'::jsonb);

do $$ declare s text; begin
  select status into s from public.profiles where email = 'ana@marymount.edu.co';
  if s = 'pending' then raise notice 'PASS  new sign-in lands as pending';
  else raise notice 'FAIL  expected pending, got %', s; end if;
end $$;

update public.profiles set status = 'approved', role = 'admin'
  where email = 'ana@marymount.edu.co';
update public.profiles set status = 'approved'
  where email = 'luis@marymount.edu.co';
-- The student deliberately stays pending.

-- ─────────────────────────────────────────────────────────────────────────────
-- Projects and tagging
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.projects
  (id, owner_id, title, description, status, duration, resources, language)
values
  ('aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'Bridge load testing with real data',
   'Students build model bridges, then model the load curves mathematically.',
   'in_progress', 'About 4 weeks in Q2', 'Balsa wood, force sensors', 'en');

do $$ declare r text; begin
  select role::text into r from public.project_members
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and user_id = '11111111-1111-1111-1111-111111111111';
  if r = 'owner' then raise notice 'PASS  owner auto-added as project member';
  else raise notice 'FAIL  owner membership not created (got %)', r; end if;
end $$;

insert into public.project_grades values ('aaaaaaaa-0000-0000-0000-000000000001', 11);

insert into public.project_subjects (project_id, grade_subject_id, role)
select 'aaaaaaaa-0000-0000-0000-000000000001', gs.id, 'primary'
from public.grade_subjects gs where gs.subject_slug = 'physics' and gs.grade = 11;

insert into public.project_subjects (project_id, grade_subject_id, role)
select 'aaaaaaaa-0000-0000-0000-000000000001', gs.id, 'cross'
from public.grade_subjects gs
where (gs.subject_slug = 'calculus' and gs.grade = 12)
   or (gs.subject_slug = 'design-technology' and gs.grade = 10);

do $$ begin
  begin
    insert into public.project_subjects (project_id, grade_subject_id, role)
    select 'aaaaaaaa-0000-0000-0000-000000000001', gs.id, 'primary'
    from public.grade_subjects gs where gs.subject_slug = 'biology' and gs.grade = 11;
    raise notice 'FAIL  a second primary subject was accepted';
  exception when unique_violation then
    raise notice 'PASS  second primary subject rejected';
  end;
end $$;

-- A second project, in Spanish, so the filters have something to discriminate.
insert into public.projects (id, owner_id, title, description, status, language)
values ('aaaaaaaa-0000-0000-0000-000000000002',
        '22222222-2222-2222-2222-222222222222',
        'Poesía y protesta en América Latina',
        'Lectura crítica de poesía de protesta junto con el contexto histórico.',
        'idea', 'es');
insert into public.project_grades values ('aaaaaaaa-0000-0000-0000-000000000002', 12);
insert into public.project_subjects (project_id, grade_subject_id, role)
select 'aaaaaaaa-0000-0000-0000-000000000002', gs.id, 'primary'
from public.grade_subjects gs where gs.subject_slug = 'spanish' and gs.grade = 12;
insert into public.project_subjects (project_id, grade_subject_id, role)
select 'aaaaaaaa-0000-0000-0000-000000000002', gs.id, 'cross'
from public.grade_subjects gs where gs.subject_slug = 'social-studies' and gs.grade = 12;

insert into public.collaboration_requests (project_id, user_id, message)
values ('aaaaaaaa-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222',
        'I teach Calculus — happy to help.');

-- ─────────────────────────────────────────────────────────────────────────────
-- search_projects
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare failures int := 0; actual int;
begin
  select count(*) into actual from public.search_projects();
  if actual <> 2 then failures := failures + 1;
    raise notice 'FAIL  no filter: expected 2, got %', actual; end if;

  select count(*) into actual from public.search_projects(p_grades := array[11]::smallint[]);
  if actual <> 1 then failures := failures + 1;
    raise notice 'FAIL  grade=11: expected 1, got %', actual; end if;

  select count(*) into actual from public.search_projects(p_subject_slugs := array['physics']);
  if actual <> 1 then failures := failures + 1;
    raise notice 'FAIL  subject=physics: expected 1, got %', actual; end if;

  -- OR mode widens the net; AND mode finds genuine intersections.
  select count(*) into actual from public.search_projects(
    p_subject_slugs := array['physics','spanish']);
  if actual <> 2 then failures := failures + 1;
    raise notice 'FAIL  physics OR spanish: expected 2, got %', actual; end if;

  select count(*) into actual from public.search_projects(
    p_subject_slugs := array['physics','calculus'], p_match_all := true);
  if actual <> 1 then failures := failures + 1;
    raise notice 'FAIL  physics AND calculus: expected 1, got %', actual; end if;

  select count(*) into actual from public.search_projects(
    p_subject_slugs := array['physics','spanish'], p_match_all := true);
  if actual <> 0 then failures := failures + 1;
    raise notice 'FAIL  physics AND spanish: expected 0, got %', actual; end if;

  -- Calculus is tagged cross on that project, not primary.
  select count(*) into actual from public.search_projects(
    p_subject_slugs := array['calculus'], p_subject_role := 'primary');
  if actual <> 0 then failures := failures + 1;
    raise notice 'FAIL  calculus-as-primary: expected 0, got %', actual; end if;

  select count(*) into actual from public.search_projects(
    p_statuses := array['idea']::public.project_status[]);
  if actual <> 1 then failures := failures + 1;
    raise notice 'FAIL  status=idea: expected 1, got %', actual; end if;

  select count(*) into actual from public.search_projects(p_query := 'bridge');
  if actual <> 1 then failures := failures + 1;
    raise notice 'FAIL  text=bridge: expected 1, got %', actual; end if;

  -- Accented Spanish must match.
  select count(*) into actual from public.search_projects(p_query := 'poesía');
  if actual <> 1 then failures := failures + 1;
    raise notice 'FAIL  text=poesía: expected 1, got %', actual; end if;

  select count(*) into actual from public.search_projects(p_query := 'xyzzy');
  if actual <> 0 then failures := failures + 1;
    raise notice 'FAIL  text=nonsense: expected 0, got %', actual; end if;

  if failures = 0 then
    raise notice 'PASS  all 11 search_projects filter cases';
  end if;
end $$;

do $$ declare n int; begin
  select count(*) into n from public.subject_connections();
  -- Project 1 links 3 subjects (3 pairs), project 2 links 2 subjects (1 pair).
  if n = 4 then raise notice 'PASS  subject_connections found 4 subject pairs';
  else raise notice 'FAIL  subject_connections: expected 4 pairs, got %', n; end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security
-- ─────────────────────────────────────────────────────────────────────────────

set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';  -- the student

do $$
declare projects_seen int; profiles_seen int; own int; requests_seen int; catalog int;
begin
  select count(*) into projects_seen from public.projects;
  select count(*) into profiles_seen from public.profiles where id <> auth.uid();
  select count(*) into own           from public.profiles where id =  auth.uid();
  select count(*) into requests_seen from public.collaboration_requests;
  select count(*) into catalog       from public.subjects;

  if projects_seen = 0 and profiles_seen = 0 and requests_seen = 0 then
    raise notice 'PASS  pending account sees no projects, profiles or requests';
  else
    raise notice 'FAIL  pending account saw % projects, % profiles, % requests',
      projects_seen, profiles_seen, requests_seen;
  end if;

  -- Own row must stay readable, or the "awaiting approval" screen cannot render.
  if own = 1 then raise notice 'PASS  pending account can still read its own profile';
  else raise notice 'FAIL  pending account cannot read its own profile'; end if;

  -- The curriculum list is deliberately readable by any signed-in account.
  if catalog = 22 then raise notice 'PASS  subject catalog readable (22 subjects)';
  else raise notice 'FAIL  subject catalog: expected 22, got %', catalog; end if;
end $$;

do $$ begin
  begin
    update public.profiles set status = 'approved', role = 'admin' where id = auth.uid();
    raise notice 'FAIL  self-approval succeeded';
  exception when insufficient_privilege then
    raise notice 'PASS  self-approval blocked';
  end;
end $$;

reset role;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';  -- Luis, approved

do $$ declare n int; begin
  select count(*) into n from public.search_projects();
  if n = 2 then raise notice 'PASS  approved teacher sees all projects';
  else raise notice 'FAIL  approved teacher saw % of 2 projects', n; end if;
end $$;

do $$ declare n int; begin
  update public.projects set title = 'hijacked'
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  if n = 0 then raise notice 'PASS  non-member cannot edit another teacher''s project';
  else raise notice 'FAIL  non-member edited % row(s)', n; end if;
end $$;

do $$ declare n int; begin
  update public.projects set status = 'in_progress'
   where id = 'aaaaaaaa-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  if n = 1 then raise notice 'PASS  owner can edit their own project';
  else raise notice 'FAIL  owner could not edit own project (% rows)', n; end if;
end $$;

do $$ begin
  begin
    insert into public.collaboration_requests (project_id, user_id)
    values ('aaaaaaaa-0000-0000-0000-000000000001',
            '33333333-3333-3333-3333-333333333333');
    raise notice 'FAIL  impersonated collaboration request accepted';
  exception when insufficient_privilege then
    raise notice 'PASS  impersonated collaboration request blocked';
  end;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- upsert_project — still as Luis, an approved teacher
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare new_id uuid; n_primary int; n_cross int; n_grades int;
begin
  new_id := public.upsert_project(
    p_title           := 'Sound waves and the physics of the school choir',
    p_description     := 'Recording the choir, then analysing harmonics.',
    p_status          := 'idea',
    p_duration        := 'Two or three weeks, flexible',
    p_resources       := 'Microphones, the music room',
    p_language        := 'en',
    p_grades          := array[11]::smallint[],
    p_primary_subject := 'physics@11',
    -- 'physics@11' is repeated on purpose: a teacher who also ticks their own
    -- subject in the big list should not be punished for it.
    p_cross_subjects  := array['music@11', 'trigonometry@11', 'physics@11']
  );

  select count(*) into n_primary from public.project_subjects
   where project_id = new_id and role = 'primary';
  select count(*) into n_cross from public.project_subjects
   where project_id = new_id and role = 'cross';
  select count(*) into n_grades from public.project_grades where project_id = new_id;

  if n_primary = 1 and n_cross = 2 and n_grades = 1 then
    raise notice 'PASS  upsert_project created project with 1 primary + 2 cross tags';
  else
    raise notice 'FAIL  upsert_project tags: % primary, % cross, % grades',
      n_primary, n_cross, n_grades;
  end if;

  -- Re-tagging must replace, not accumulate.
  perform public.upsert_project(
    p_title           := 'Sound waves and the physics of the school choir',
    p_description     := 'Recording the choir, then analysing harmonics.',
    p_status          := 'in_progress',
    p_duration        := 'Two or three weeks, flexible',
    p_resources       := 'Microphones, the music room',
    p_language        := 'en',
    p_grades          := array[11, 12]::smallint[],
    p_primary_subject := 'physics@11',
    p_cross_subjects  := array['music@11'],
    p_id              := new_id
  );

  select count(*) into n_cross from public.project_subjects
   where project_id = new_id and role = 'cross';
  select count(*) into n_grades from public.project_grades where project_id = new_id;

  if n_cross = 1 and n_grades = 2 then
    raise notice 'PASS  re-tagging replaces rather than accumulates';
  else
    raise notice 'FAIL  after re-tag: % cross tags, % grades', n_cross, n_grades;
  end if;
end $$;

do $$ begin
  begin
    perform public.upsert_project(
      p_title := 'hijack attempt', p_description := '', p_status := 'idea',
      p_duration := '', p_resources := '', p_language := 'en',
      p_grades := array[11]::smallint[], p_primary_subject := 'physics@11',
      p_id := 'aaaaaaaa-0000-0000-0000-000000000001'  -- Ana's project
    );
    raise notice 'FAIL  edited another teacher''s project through the RPC';
  exception when insufficient_privilege then
    raise notice 'PASS  RPC refuses to edit another teacher''s project';
  end;
end $$;

do $$ begin
  begin
    perform public.upsert_project(
      p_title := 'bad tag', p_description := '', p_status := 'idea',
      p_duration := '', p_resources := '', p_language := 'en',
      p_grades := array[11]::smallint[],
      -- Calculus is a 12th-grade subject; there is no calculus@11.
      p_primary_subject := 'calculus@11'
    );
    raise notice 'FAIL  a subject not offered at that grade was accepted';
  exception when foreign_key_violation then
    raise notice 'PASS  subject not offered at that grade rejected';
  end;
end $$;

reset role;
