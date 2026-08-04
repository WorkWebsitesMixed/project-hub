-- Project Hub — core schema
-- Marymount School Medellín, Grades 10-12
--
-- Design note that explains most of what follows: a subject tag is a
-- (subject, grade) PAIR. Spanish, English, Art and eleven others are taught at
-- all three grades, and the entire point of this hub is to distinguish
-- "11th-grade Physics" from "12th-grade Physics" so the two can be linked.
-- Hence `subjects` (the name) + `grade_subjects` (the taggable pair).

-- ─────────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────────

do $$ begin
  create type public.profile_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.app_role       as enum ('teacher', 'admin');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.project_status as enum ('idea', 'in_progress', 'completed');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.subject_role   as enum ('primary', 'cross');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.member_role    as enum ('owner', 'editor', 'collaborator');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.request_status as enum ('interested', 'accepted', 'declined');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.content_lang   as enum ('en', 'es', 'fr');
exception when duplicate_object then null;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- People
-- ─────────────────────────────────────────────────────────────────────────────

-- Students share the marymount.edu.co domain with staff, so the email domain
-- alone cannot identify a teacher. Every new sign-in lands as 'pending' and
-- sees nothing until an admin approves it. This column is the real access gate;
-- see 0002_rls.sql where it is enforced.
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null unique,
  full_name   text,
  avatar_url  text,
  department  text,
  status      public.profile_status not null default 'pending',
  role        public.app_role       not null default 'teacher',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists profiles_status_idx on public.profiles (status);

-- ─────────────────────────────────────────────────────────────────────────────
-- Subject catalog
-- ─────────────────────────────────────────────────────────────────────────────

-- Seeded from src/lib/subjects.ts — edit that file and regenerate, never
-- hand-edit the seed. `family` drives the accent colour of every chip and
-- graph node in the UI.
create table if not exists public.subjects (
  slug       text primary key,
  name_en    text not null,
  name_es    text not null,
  name_fr    text not null,
  family     text not null,
  sort_order integer not null default 0
);

-- The taggable unit: one row per (subject, grade) the school actually offers.
create table if not exists public.grade_subjects (
  id           uuid primary key default gen_random_uuid(),
  subject_slug text     not null references public.subjects (slug)
                          on update cascade on delete cascade,
  grade        smallint not null check (grade in (10, 11, 12)),
  unique (subject_slug, grade)
);

create index if not exists grade_subjects_grade_idx on public.grade_subjects (grade);

-- ─────────────────────────────────────────────────────────────────────────────
-- Projects
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  title       text not null check (char_length(trim(title)) between 3 and 200),
  description text not null default '',
  status      public.project_status not null default 'idea',

  -- Free text by design: "about three weeks in Q2", "the whole first semester".
  -- Teachers describe time the way they actually think about it.
  duration    text not null default '',
  resources   text not null default '',

  -- The language the teacher wrote in. The UI is translated; their words are
  -- not. This lets us label and filter, not translate.
  language    public.content_lang not null default 'en',

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- 'simple' rather than a language-specific config on purpose: with English,
  -- Spanish and French mixed in one column, stemming for the wrong language is
  -- worse than no stemming at all.
  search_vector tsvector generated always as (
    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(description, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(resources, '')), 'C')
  ) stored
);

create index if not exists projects_search_idx  on public.projects using gin (search_vector);
create index if not exists projects_owner_idx   on public.projects (owner_id);
create index if not exists projects_status_idx  on public.projects (status);
create index if not exists projects_created_idx on public.projects (created_at desc);

-- Which grades the project is aimed at. Separate from the subject tags because
-- a project can target 11th graders while connecting to a 12th-grade subject.
create table if not exists public.project_grades (
  project_id uuid     not null references public.projects (id) on delete cascade,
  grade      smallint not null check (grade in (10, 11, 12)),
  primary key (project_id, grade)
);

create index if not exists project_grades_grade_idx on public.project_grades (grade);

-- The cross-disciplinary web. One row per tag; `role` separates the project's
-- own subject from the subjects it reaches into.
create table if not exists public.project_subjects (
  project_id       uuid not null references public.projects (id) on delete cascade,
  grade_subject_id uuid not null references public.grade_subjects (id) on delete restrict,
  role             public.subject_role not null default 'cross',
  primary key (project_id, grade_subject_id)
);

-- Exactly one primary subject per project.
create unique index if not exists project_subjects_one_primary_idx
  on public.project_subjects (project_id)
  where role = 'primary';

create index if not exists project_subjects_lookup_idx
  on public.project_subjects (grade_subject_id, role);

-- Who may act on a project. The owner is seeded here as a member with role
-- 'owner' (see the trigger below), so promoting a collaborator to co-editor is
-- a one-row update rather than a schema change.
create table if not exists public.project_members (
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.member_role not null default 'collaborator',
  added_at   timestamptz not null default now(),
  primary key (project_id, user_id)
);

create index if not exists project_members_user_idx on public.project_members (user_id);

-- "I want to collaborate". Distinct from project_members: this is the request,
-- membership is the grant. Unique per (project, teacher) so the button is
-- idempotent — clicking twice never creates a second request.
create table if not exists public.collaboration_requests (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  message      text not null default '',
  status       public.request_status not null default 'interested',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  unique (project_id, user_id)
);

create index if not exists collab_requests_project_idx on public.collaboration_requests (project_id, status);
create index if not exists collab_requests_user_idx    on public.collaboration_requests (user_id);

-- Optional images and documents, stored in the 'project-files' bucket.
create table if not exists public.project_attachments (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects (id) on delete cascade,
  storage_path text not null unique,
  file_name    text not null,
  mime_type    text,
  size_bytes   bigint,
  uploaded_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists project_attachments_project_idx on public.project_attachments (project_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Triggers
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists projects_touch_updated_at on public.projects;
create trigger projects_touch_updated_at
  before update on public.projects
  for each row execute function public.touch_updated_at();

-- Whoever creates a project is immediately its owning member.
create or replace function public.add_owner_as_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.project_members (project_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (project_id, user_id) do update set role = 'owner';
  return new;
end;
$$;

drop trigger if exists projects_add_owner_member on public.projects;
create trigger projects_add_owner_member
  after insert on public.projects
  for each row execute function public.add_owner_as_member();

-- First gate: reject any Google account outside the school outright, then
-- create the profile as 'pending' for an admin to approve.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is null or new.email !~* '@marymount\.edu\.co$' then
    raise exception 'Only marymount.edu.co accounts may sign in.'
      using errcode = 'check_violation';
  end if;

  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    lower(new.email),
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
