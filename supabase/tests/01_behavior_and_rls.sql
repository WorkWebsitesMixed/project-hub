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


-- ─────────────────────────────────────────────────────────────────────────────
-- respond_to_collaboration
-- ─────────────────────────────────────────────────────────────────────────────

reset role;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';  -- Luis

-- Luis does not own Ana's project, so he must not be able to accept his own
-- request to join it.
do $$
declare v_req uuid;
begin
  select id into v_req from public.collaboration_requests
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  begin
    perform public.respond_to_collaboration(v_req, true);
    raise notice 'FAIL  a non-owner accepted their own collaboration request';
  exception when insufficient_privilege then
    raise notice 'PASS  non-owner cannot answer a collaboration request';
  end;
end $$;

reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';  -- Ana, the owner

do $$
declare v_req uuid; v_status text; v_member text;
begin
  select id into v_req from public.collaboration_requests
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000001';

  perform public.respond_to_collaboration(v_req, true);

  select status::text into v_status from public.collaboration_requests where id = v_req;
  select role::text into v_member from public.project_members
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and user_id = '22222222-2222-2222-2222-222222222222';

  if v_status = 'accepted' and v_member = 'collaborator' then
    raise notice 'PASS  accepting a request grants project membership';
  else
    raise notice 'FAIL  after accept: status=%, membership=%', v_status, v_member;
  end if;

  -- Declining afterwards must withdraw the access again.
  perform public.respond_to_collaboration(v_req, false);

  select status::text into v_status from public.collaboration_requests where id = v_req;
  select role::text into v_member from public.project_members
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and user_id = '22222222-2222-2222-2222-222222222222';

  if v_status = 'declined' and v_member is null then
    raise notice 'PASS  declining withdraws membership again';
  else
    raise notice 'FAIL  after decline: status=%, membership=%', v_status, v_member;
  end if;

  -- The owner's own membership must survive all of this.
  select role::text into v_member from public.project_members
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and user_id = '11111111-1111-1111-1111-111111111111';
  if v_member = 'owner' then
    raise notice 'PASS  owner membership untouched by decline';
  else
    raise notice 'FAIL  owner membership became %', v_member;
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- Graph grade filtering
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare all_pairs int; g11 int; g12 int; g10 int; usage_all int; usage_11 int;
begin
  select count(*) into all_pairs from public.subject_connections();
  select count(*) into g11 from public.subject_connections(array[11]::smallint[]);
  select count(*) into g12 from public.subject_connections(array[12]::smallint[]);
  select count(*) into g10 from public.subject_connections(array[10]::smallint[]);

  -- Project 1 targets grade 11 and links 3 subjects (3 pairs); the choir
  -- project also targets 11 and 12. Project 2 targets grade 12, 1 pair.
  -- Nothing targets grade 10.
  if g10 = 0 and g11 > 0 and g12 > 0 and all_pairs >= g11 then
    raise notice 'PASS  subject_connections filters by target grade (10:%, 11:%, 12:%, all:%)',
      g10, g11, g12, all_pairs;
  else
    raise notice 'FAIL  grade filter: 10=%, 11=%, 12=%, all=%', g10, g11, g12, all_pairs;
  end if;

  -- A grade-11 project tagged into 12th-grade Calculus must keep that edge:
  -- erasing it would hide exactly the cross-grade reach the graph is for.
  if exists (
    select 1 from public.subject_connections(array[11]::smallint[])
    where 'calculus' in (source_slug, target_slug)
  ) then
    raise notice 'PASS  cross-grade edges survive the grade filter';
  else
    raise notice 'FAIL  filtering to grade 11 dropped the calculus edge';
  end if;

  select count(*) into usage_all from public.subject_usage();
  select count(*) into usage_11 from public.subject_usage(array[11]::smallint[]);
  if usage_all > 0 and usage_11 > 0 and usage_11 <= usage_all then
    raise notice 'PASS  subject_usage returns node weights (all:%, g11:%)', usage_all, usage_11;
  else
    raise notice 'FAIL  subject_usage: all=%, g11=%', usage_all, usage_11;
  end if;
end $$;

do $$ declare v boolean; begin
  select email_notifications into v from public.profiles
   where email = 'ana@marymount.edu.co';
  if v then raise notice 'PASS  email notifications default to on';
  else raise notice 'FAIL  email_notifications defaulted to %', v; end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- Confirmed collaborations
--
-- The point of these: one accepted partner on a project tagged across four
-- subjects must produce ONE line, not six.
-- ─────────────────────────────────────────────────────────────────────────────

reset role;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';  -- Luis

-- Luis offers to help on Ana's project, bringing 12th-grade Calculus. Her
-- project is tagged across three subjects (physics primary, calculus and
-- design-technology cross).
do $$ begin
  perform public.offer_collaboration(
    'aaaaaaaa-0000-0000-0000-000000000001',
    'I can take the modelling side.',
    'calculus@12'
  );
  raise notice 'PASS  offer_collaboration recorded the subject offered';
exception when others then
  raise notice 'FAIL  offer_collaboration raised: %', sqlerrm;
end $$;

do $$ begin
  begin
    perform public.offer_collaboration(
      'aaaaaaaa-0000-0000-0000-000000000001', '', 'calculus@11');
    raise notice 'FAIL  a subject not offered at that grade was accepted';
  exception when foreign_key_violation then
    raise notice 'PASS  offer rejects a subject not taught at that grade';
  end;
end $$;

reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';  -- Ana, owner

do $$
declare n_conf int; n_possible int;
begin
  -- Before acceptance there is nothing confirmed, however it is tagged.
  select count(*) into n_conf from public.collaboration_connections();
  if n_conf = 0 then
    raise notice 'PASS  an unanswered offer draws no confirmed line';
  else
    raise notice 'FAIL  unanswered offer produced % confirmed lines', n_conf;
  end if;

  perform public.respond_to_collaboration(
    (select id from public.collaboration_requests
      where project_id = 'aaaaaaaa-0000-0000-0000-000000000001'
        and user_id = '22222222-2222-2222-2222-222222222222'),
    true);

  select count(*) into n_conf from public.collaboration_connections();
  select count(*) into n_possible from public.subject_connections();

  -- physics (owner's primary) <-> calculus (what Luis brought). Exactly one.
  if n_conf = 1 then
    raise notice 'PASS  one acceptance draws exactly one confirmed line (tagged view still shows %)', n_possible;
  else
    raise notice 'FAIL  expected 1 confirmed line, got %', n_conf;
  end if;

  if exists (
    select 1 from public.collaboration_connections()
    where source_slug = 'calculus' and target_slug = 'physics'
  ) then
    raise notice 'PASS  the confirmed line joins the two stated subjects';
  else
    raise notice 'FAIL  confirmed line is not physics <-> calculus';
  end if;

  -- The tagged view must be strictly richer, or the toggle has no purpose.
  if n_possible > n_conf then
    raise notice 'PASS  confirmed view is narrower than the tagged view';
  else
    raise notice 'FAIL  confirmed % vs tagged %', n_conf, n_possible;
  end if;
end $$;

do $$
declare n int; partners jsonb; pcount int;
begin
  select count(*) into n from public.joint_projects();
  if n = 1 then raise notice 'PASS  joint_projects lists the one project with a partner';
  else raise notice 'FAIL  joint_projects returned % rows', n; end if;

  select jp.partners, jp.partner_count into partners, pcount
  from public.joint_projects() jp limit 1;

  if pcount = 1 and partners -> 0 ->> 'subject' = 'calculus'
     and partners -> 0 ->> 'email' = 'luis@marymount.edu.co' then
    raise notice 'PASS  joint_projects names the partner and their subject';
  else
    raise notice 'FAIL  partners payload was %', partners;
  end if;
end $$;

-- Grade filtering must apply to the confirmed view too.
do $$ declare g11 int; g10 int; begin
  select count(*) into g11 from public.collaboration_connections(array[11]::smallint[]);
  select count(*) into g10 from public.collaboration_connections(array[10]::smallint[]);
  if g11 = 1 and g10 = 0 then
    raise notice 'PASS  grade filter applies to confirmed collaborations';
  else
    raise notice 'FAIL  confirmed grade filter: g11=%, g10=%', g11, g10;
  end if;
end $$;

-- A third teacher, on neither side of the collaboration, must still see it —
-- that is what the learning director needs — while pending and declined
-- offers stay private.
reset role;
update public.profiles set status = 'approved'
  where email = 'student@marymount.edu.co';
set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

do $$ declare visible int; total int; begin
  select count(*) into visible from public.collaboration_requests;
  select count(*) into total from public.joint_projects();
  if visible = 1 and total = 1 then
    raise notice 'PASS  an uninvolved teacher sees accepted collaborations only';
  else
    raise notice 'FAIL  uninvolved teacher saw % requests, % joint projects', visible, total;
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- Administering the hub is not the same as being on a project
--
-- Ana is an admin. Luis owns project 2. A third teacher offers to help on it.
-- Ana must not receive that offer, and must not be able to answer it — being
-- able to moderate a project is not the same as being part of it.
-- ─────────────────────────────────────────────────────────────────────────────

reset role;
set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';  -- approved earlier

do $$ begin
  perform public.offer_collaboration(
    'aaaaaaaa-0000-0000-0000-000000000002', 'Puedo aportar desde Arte.', 'art@12');
end $$;

reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';  -- Ana, the admin

do $$ declare n int; begin
  select count(*) into n from public.collaboration_requests
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000002'
     and status = 'interested';
  if n = 0 then
    raise notice 'PASS  admin does not see a pending offer on another teacher''s project';
  else
    raise notice 'FAIL  admin saw % pending offer(s) they are not party to', n;
  end if;
end $$;

do $$ declare v_req uuid; begin
  reset role;
  select id into v_req from public.collaboration_requests
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000002' and status = 'interested';
  set role authenticated;
  set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  begin
    perform public.respond_to_collaboration(v_req, true);
    raise notice 'FAIL  admin answered an offer on a project they do not lead';
  exception when insufficient_privilege then
    raise notice 'PASS  admin cannot answer an offer on a project they do not lead';
  end;
end $$;

-- The owner must still be able to see and answer it.
reset role;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';  -- Luis, the owner

do $$ declare n int; begin
  select count(*) into n from public.collaboration_requests
   where project_id = 'aaaaaaaa-0000-0000-0000-000000000002'
     and status = 'interested';
  if n = 1 then
    raise notice 'PASS  the owner still receives the offer on their own project';
  else
    raise notice 'FAIL  owner saw % offers on their own project', n;
  end if;
end $$;

-- And admin moderation of the project itself is untouched.
reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare n int; begin
  update public.projects set status = 'in_progress'
   where id = 'aaaaaaaa-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  if n = 1 then
    raise notice 'PASS  admin can still moderate any project';
  else
    raise notice 'FAIL  admin lost the ability to edit a project (% rows)', n;
  end if;
end $$;

reset role;
