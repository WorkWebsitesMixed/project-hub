/**
 * Row shapes for the tables and RPCs this app touches.
 *
 * Hand-written on purpose: `supabase gen types typescript` needs a project
 * access token, and this covers what we actually query. If the schema grows
 * past what is here, generate the full file and replace this one.
 */

import type { Grade, ProjectStatus } from './subjects';
import type { Term } from './terms';
import type { Locale } from '../i18n/ui';

export type ProfileStatus = 'pending' | 'approved' | 'rejected';
export type AppRole = 'teacher' | 'admin';
export type SubjectRole = 'primary' | 'cross';
export type MemberRole = 'owner' | 'editor' | 'collaborator';
export type RequestStatus = 'interested' | 'accepted' | 'declined';

export interface Profile {
  id: string;
  email: string;
  full_name: string | null;
  avatar_url: string | null;
  department: string | null;
  status: ProfileStatus;
  role: AppRole;
  /** Opt-out for collaboration emails. */
  email_notifications: boolean;
  created_at: string;
  updated_at: string;
}

/** One (subject, grade) tag as returned by `search_projects`. */
export interface ProjectSubjectTag {
  slug: string;
  grade: Grade;
  role: SubjectRole;
  family: string;
  name: Record<Locale, string>;
}

/** A row from the `search_projects` RPC. */
export interface ProjectSearchRow {
  id: string;
  title: string;
  description: string;
  status: ProjectStatus;
  duration: string;
  resources: string;
  language: Locale;
  /** Calendar year the academic year starts in: 2026 means 2026–2027. */
  academic_year: number | null;
  term: Term | null;
  week_start: number | null;
  week_end: number | null;
  owner_id: string;
  owner_name: string | null;
  owner_email: string | null;
  created_at: string;
  updated_at: string;
  grades: Grade[];
  subjects: ProjectSubjectTag[];
  interest_count: number;
  attachment_count: number;
  total_count: number;
}

export interface SearchProjectsArgs {
  p_query?: string | null;
  p_grades?: Grade[] | null;
  p_subject_slugs?: string[] | null;
  p_statuses?: ProjectStatus[] | null;
  p_subject_role?: SubjectRole | null;
  p_match_all?: boolean;
  p_limit?: number;
  p_offset?: number;
  p_terms?: Term[] | null;
  p_academic_year?: number | null;
}

export interface SubjectConnection {
  source_slug: string;
  target_slug: string;
  project_count: number;
}
