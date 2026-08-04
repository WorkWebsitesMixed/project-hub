/**
 * Data loading and form handling for the project pages.
 *
 * Why this lives outside the .astro components: `Astro.redirect()` only
 * performs a redirect when it is returned from a **page**. Returned from a
 * nested component it is just a value Astro renders as nothing — which is how
 * a failed lookup turned into a blank white screen instead of a redirect.
 *
 * So loaders return a discriminated `{ kind: 'redirect' }` or `{ kind: 'ok' }`,
 * the thin page wrappers act on the redirect, and the components became pure
 * renderers that cannot silently swallow a response.
 */

import type {
  Profile,
  ProfileStatus,
  SubjectConnection,
} from "./database.types";
import { SUBJECTS, type Grade, type ProjectStatus } from "./subjects";
import type { Locale } from "../i18n/ui";
import { localizePath } from "../i18n/utils";
import { notifyCollaborationOffer, notifyCollaborationAnswer } from "./email";

export type LoadResult<T> =
  { kind: "redirect"; to: string } | { kind: "ok"; data: T };

const redirectTo = (to: string) => ({ kind: "redirect" as const, to });
const ok = <T>(data: T) => ({ kind: "ok" as const, data });

interface Ctx {
  request: Request;
  url: URL;
  locals: App.Locals;
}

/**
 * `projects` and `profiles` have more than one relationship — the owner_id
 * foreign key, and a many-to-many through project_members. PostgREST refuses
 * to guess (PGRST201), so the constraint name has to be explicit. Getting this
 * wrong returns HTTP 300 and no rows.
 */
const OWNER_EMBED = "owner:profiles!projects_owner_id_fkey(full_name, email)";

const OWNER_EMBED_NOTIFY =
  "owner:profiles!projects_owner_id_fkey(full_name, email, email_notifications)";

export interface ProjectDetailData {
  project: {
    id: string;
    title: string;
    description: string;
    status: ProjectStatus;
    duration: string;
    resources: string;
    language: Locale;
    created_at: string;
    owner_id: string;
  };
  owner: { full_name: string | null; email: string | null } | null;
  grades: Grade[];
  tags: { role: "primary" | "cross"; slug: string; grade: number }[];
  attachments: {
    id: string;
    file_name: string;
    mime_type: string | null;
    url: string | null;
  }[];
  hasOfferedToCollaborate: boolean;
  isOwner: boolean;
  canEdit: boolean;
  actionError: string | null;
}

export async function loadProjectDetail(
  ctx: Ctx,
  projectId: string,
  locale: Locale,
): Promise<LoadResult<ProjectDetailData>> {
  const { supabase, profile } = ctx.locals;
  if (!profile) return redirectTo(localizePath("/", locale));

  let actionError: string | null = null;

  if (ctx.request.method === "POST") {
    const form = await ctx.request.formData();
    const action = String(form.get("action") ?? "");

    if (action === "collaborate") {
      const { error } = await supabase.from("collaboration_requests").insert({
        project_id: projectId,
        user_id: profile.id,
        message: String(form.get("message") ?? "").slice(0, 1000),
      });
      // The unique (project_id, user_id) index makes the button idempotent —
      // a double click is not an error worth showing anyone.
      if (error && !/duplicate|unique/i.test(error.message)) {
        actionError = error.message;
      } else {
        // Only on a genuinely new offer — a double click must not send a
        // second email.
        if (!error) {
          const { data: target } = await supabase
            .from("projects")
            .select(`title, language, ${OWNER_EMBED_NOTIFY}`)
            .eq("id", projectId)
            .maybeSingle();
          const owner = (target as any)?.owner;
          if (owner?.email && owner.email_notifications) {
            await notifyCollaborationOffer({
              to: owner.email,
              requesterName: profile.full_name ?? profile.email,
              projectTitle: (target as any).title,
              projectId,
              message: String(form.get("message") ?? "").slice(0, 1000),
              language: (target as any).language as Locale,
              origin: ctx.url.origin,
            });
          }
        }
        return redirectTo(ctx.url.pathname);
      }
    }

    if (action === "delete") {
      const { error } = await supabase
        .from("projects")
        .delete()
        .eq("id", projectId);
      if (error) actionError = error.message;
      else return redirectTo(localizePath("/dashboard", locale));
    }
  }

  const { data: project } = await supabase
    .from("projects")
    .select(
      `id, title, description, status, duration, resources, language, created_at, owner_id, ${OWNER_EMBED}`,
    )
    .eq("id", projectId)
    .maybeSingle();

  // RLS hides projects this teacher may not see. A missing project and a
  // forbidden one look identical on purpose.
  if (!project) return redirectTo(localizePath("/projects", locale));

  const [
    { data: grades },
    { data: tags },
    { data: attachments },
    { data: myRequest },
  ] = await Promise.all([
    supabase.from("project_grades").select("grade").eq("project_id", projectId),
    supabase
      .from("project_subjects")
      .select("role, grade_subjects(subject_slug, grade)")
      .eq("project_id", projectId),
    supabase
      .from("project_attachments")
      .select("id, storage_path, file_name, mime_type")
      .eq("project_id", projectId),
    supabase
      .from("collaboration_requests")
      .select("id")
      .eq("project_id", projectId)
      .eq("user_id", profile.id)
      .maybeSingle(),
  ]);

  // The bucket is private, so every link has to be signed. An hour is plenty
  // for someone reading a project page.
  const signed = await Promise.all(
    (attachments ?? []).map(async (file) => {
      const { data } = await supabase.storage
        .from("project-files")
        .createSignedUrl(file.storage_path, 3600);
      return {
        id: file.id,
        file_name: file.file_name,
        mime_type: file.mime_type,
        url: data?.signedUrl ?? null,
      };
    }),
  );

  const isOwner = project.owner_id === profile.id;

  return ok({
    project: project as ProjectDetailData["project"],
    owner: (project as any).owner ?? null,
    grades: (grades ?? []).map((g) => g.grade as Grade),
    tags: (tags ?? []).map((row: any) => ({
      role: row.role,
      slug: row.grade_subjects.subject_slug,
      grade: row.grade_subjects.grade,
    })),
    attachments: signed,
    hasOfferedToCollaborate: Boolean(myRequest),
    isOwner,
    canEdit: isOwner || profile.role === "admin",
    actionError,
  });
}

export interface ProjectEditorData {
  initial?: {
    id: string;
    title: string;
    description: string;
    status: ProjectStatus;
    duration: string;
    resources: string;
    language: Locale;
    grades: Grade[];
    primarySubject: string | null;
    crossSubjects: string[];
  };
}

export async function loadProjectEditor(
  ctx: Ctx,
  projectId: string | undefined,
  locale: Locale,
): Promise<LoadResult<ProjectEditorData>> {
  if (!projectId) return ok({});

  const { supabase } = ctx.locals;

  const { data: project } = await supabase
    .from("projects")
    .select("id, title, description, status, duration, resources, language")
    .eq("id", projectId)
    .maybeSingle();

  if (!project) return redirectTo(localizePath("/dashboard", locale));

  const [{ data: grades }, { data: tags }] = await Promise.all([
    supabase.from("project_grades").select("grade").eq("project_id", projectId),
    supabase
      .from("project_subjects")
      .select("role, grade_subjects(subject_slug, grade)")
      .eq("project_id", projectId),
  ]);

  const toTag = (row: any) =>
    `${row.grade_subjects.subject_slug}@${row.grade_subjects.grade}`;
  const primaryRow = (tags ?? []).find((r: any) => r.role === "primary");

  return ok({
    initial: {
      id: project.id,
      title: project.title,
      description: project.description,
      status: project.status as ProjectStatus,
      duration: project.duration,
      resources: project.resources,
      language: project.language as Locale,
      grades: (grades ?? []).map((g) => g.grade as Grade),
      primarySubject: primaryRow ? toTag(primaryRow) : null,
      crossSubjects: (tags ?? [])
        .filter((r: any) => r.role === "cross")
        .map(toTag),
    },
  });
}

export interface ApprovalsData {
  pending: Profile[];
  approved: Profile[];
  error: string | null;
}

export async function loadApprovals(
  ctx: Ctx,
): Promise<LoadResult<ApprovalsData>> {
  const { supabase, profile } = ctx.locals;
  let error: string | null = null;

  if (ctx.request.method === "POST") {
    const form = await ctx.request.formData();
    const targetId = String(form.get("user_id") ?? "");
    const action = String(form.get("action") ?? "");

    const patch: { status?: ProfileStatus; role?: "teacher" | "admin" } | null =
      action === "approve"
        ? { status: "approved" }
        : action === "reject"
          ? { status: "rejected" }
          : action === "make_admin"
            ? { role: "admin" }
            : action === "revoke"
              ? { status: "rejected", role: "teacher" }
              : null;

    if (!targetId || !patch) {
      error = "Unrecognised action.";
    } else if (targetId === profile!.id) {
      // Revoking your own access could leave the hub with no administrator.
      error = "You cannot change your own access from this screen.";
    } else {
      const { error: updateError } = await supabase
        .from("profiles")
        .update(patch)
        .eq("id", targetId);
      if (updateError) error = updateError.message;
      else return redirectTo(ctx.url.pathname);
    }
  }

  const [{ data: pending }, { data: approved }] = await Promise.all([
    supabase
      .from("profiles")
      .select("*")
      .eq("status", "pending")
      .order("created_at", { ascending: true }),
    supabase
      .from("profiles")
      .select("*")
      .eq("status", "approved")
      .order("full_name", { ascending: true }),
  ]);

  return ok({
    pending: (pending ?? []) as Profile[],
    approved: (approved ?? []) as Profile[],
    error,
  });
}

export interface DashboardData {
  myProjects: {
    id: string;
    title: string;
    status: ProjectStatus;
    updated_at: string;
  }[];
  /** Offers to help on projects this teacher can act on. */
  received: {
    id: string;
    message: string;
    status: "interested" | "accepted" | "declined";
    created_at: string;
    project: { id: string; title: string } | null;
    requester: { full_name: string | null; email: string | null } | null;
  }[];
  /** Offers this teacher has made on other people's projects. */
  sent: {
    id: string;
    status: "interested" | "accepted" | "declined";
    project: { id: string; title: string } | null;
  }[];
  emailNotifications: boolean;
  error: string | null;
}

export async function loadDashboard(
  ctx: Ctx,
  locale: Locale,
): Promise<LoadResult<DashboardData>> {
  const { supabase, profile } = ctx.locals;
  if (!profile) return redirectTo(localizePath("/", locale));

  let error: string | null = null;

  if (ctx.request.method === "POST") {
    const form = await ctx.request.formData();
    if (String(form.get("action")) === "email_prefs") {
      // profiles_update_self allows this; the privilege guard trigger only
      // blocks changes to status and role.
      const { error: prefError } = await supabase
        .from("profiles")
        .update({ email_notifications: form.get("enabled") === "on" })
        .eq("id", profile.id);
      if (prefError) error = prefError.message;
      else return redirectTo(ctx.url.pathname);
    }

    if (String(form.get("action")) === "respond") {
      // One RPC flips the request status and grants or withdraws the
      // project_members row together — an accepted request must never exist
      // without the membership that actually gives the colleague access.
      const requestId = String(form.get("request_id") ?? "");
      const accepted = form.get("decision") === "accept";
      const { error: rpcError } = await supabase.rpc(
        "respond_to_collaboration",
        { p_request_id: requestId, p_accept: accepted },
      );
      if (rpcError) {
        error = rpcError.message;
      } else {
        const { data: answered } = await supabase
          .from("collaboration_requests")
          .select(
            "projects(id, title, language), profiles(full_name, email, email_notifications)",
          )
          .eq("id", requestId)
          .maybeSingle();
        const volunteer = (answered as any)?.profiles;
        const project = (answered as any)?.projects;
        if (volunteer?.email && volunteer.email_notifications && project) {
          await notifyCollaborationAnswer({
            to: volunteer.email,
            ownerName: profile.full_name ?? profile.email,
            projectTitle: project.title,
            projectId: project.id,
            accepted,
            language: project.language as Locale,
            origin: ctx.url.origin,
          });
        }
        return redirectTo(ctx.url.pathname);
      }
    }
  }

  const [{ data: myProjects }, { data: received }, { data: sent }] =
    await Promise.all([
      supabase
        .from("projects")
        .select("id, title, status, updated_at")
        .eq("owner_id", profile.id)
        .order("updated_at", { ascending: false }),

      // RLS policy `collab_select_project_side` is what scopes this to projects
      // this teacher may edit; the .neq keeps their own offers out of the inbox.
      supabase
        .from("collaboration_requests")
        .select(
          "id, message, status, created_at, projects(id, title), profiles(full_name, email)",
        )
        .neq("user_id", profile.id)
        .order("created_at", { ascending: false }),

      supabase
        .from("collaboration_requests")
        .select("id, status, projects(id, title)")
        .eq("user_id", profile.id)
        .order("created_at", { ascending: false }),
    ]);

  return ok({
    myProjects: (myProjects ?? []) as DashboardData["myProjects"],
    received: (received ?? []).map((r: any) => ({
      id: r.id,
      message: r.message,
      status: r.status,
      created_at: r.created_at,
      project: r.projects ?? null,
      requester: r.profiles ?? null,
    })),
    sent: (sent ?? []).map((r: any) => ({
      id: r.id,
      status: r.status,
      project: r.projects ?? null,
    })),
    emailNotifications: profile.email_notifications ?? true,
    error,
  });
}

export interface ConnectionsData {
  /** Subjects that appear on at least one matching project, with how many. */
  nodes: { slug: string; projectCount: number }[];
  /** Subject pairs that share a project, with how many they share. */
  edges: SubjectConnection[];
  /** Subjects nobody has tagged yet — the gaps worth noticing. */
  untaggedSlugs: string[];
  totalProjects: number;
  selectedGrades: Grade[];
}

export async function loadConnections(
  ctx: Ctx,
): Promise<LoadResult<ConnectionsData>> {
  const { supabase } = ctx.locals;

  // Grade lives in the URL, exactly as it does on the browse page, so a
  // filtered graph is a link you can send someone.
  const selectedGrades = ctx.url.searchParams
    .getAll("grade")
    .map(Number)
    .filter((g): g is Grade => g === 10 || g === 11 || g === 12);

  const gradeArg = selectedGrades.length > 0 ? selectedGrades : null;

  // Both RPCs are SECURITY INVOKER, so RLS still decides what this teacher
  // may see; the graph can never draw a project they cannot open.
  const [{ data: edges }, { data: usage }, { count }] = await Promise.all([
    supabase.rpc("subject_connections", { p_grades: gradeArg }),
    supabase.rpc("subject_usage", { p_grades: gradeArg }),
    supabase.from("projects").select("id", { count: "exact", head: true }),
  ]);

  const nodes = (
    (usage ?? []) as { subject_slug: string; project_count: number }[]
  )
    .map((row) => ({ slug: row.subject_slug, projectCount: row.project_count }))
    .sort((a, b) => b.projectCount - a.projectCount);

  const tagged = new Set(nodes.map((n) => n.slug));
  const untaggedSlugs = SUBJECTS.map((s) => s.slug).filter(
    (slug) => !tagged.has(slug),
  );

  return ok({
    nodes,
    edges: (edges ?? []) as SubjectConnection[],
    untaggedSlugs,
    totalProjects: count ?? 0,
    selectedGrades,
  });
}
