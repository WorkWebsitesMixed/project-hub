# Project Hub

Interdisciplinary project board for **Marymount School Medellín**, Grades 10–12.

Teachers post the projects they are running, tag them across subjects and
grades, and find colleagues whose work connects. The point is not a project
archive — it is the moment a Calculus teacher discovers the 11th-grade Physics
unit nobody told them about.

> **Picking this up after a break?** Read [`HANDOFF.md`](HANDOFF.md) first —
> current state, open items, and the exact steps to finish email notifications.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Frontend | Astro 7 (SSR) + React islands | Content-shaped pages, interactive tagging and filtering where it matters |
| Styling | Tailwind 4 | Brand tokens live in `src/styles/global.css` |
| Database | Supabase (Postgres) | Cross-disciplinary tagging is a relational many-to-many query; Firestore cannot join |
| Auth | Supabase + Google OAuth | Restricted to `marymount.edu.co`, then gated on approved-teacher status |
| Hosting | Vercel | GitHub Pages cannot serve SSR or protect a route |

## Access model

Students share the `marymount.edu.co` domain with staff, so domain matching
alone does **not** identify a teacher. Access has two gates:

1. **Google OAuth**, consent screen set to Internal — keeps everyone outside the
   school out entirely.
2. **Approval status** on the `profiles` row — a new sign-in lands as `pending`
   and can read nothing until an admin marks it `approved`. Row Level Security
   enforces this in the database, not in the UI.

## Email notifications

Collaboration offers and their answers can be emailed. The feature is **off
unless a transport is configured** — without one, every send returns quietly
and the hub works in-app only.

| Transport | Set | Notes |
| --- | --- | --- |
| Google Workspace mailbox | `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS` | Preferred. No DNS change needed. |
| Resend | `RESEND_API_KEY` | Used only when no `SMTP_*` values are set. Needs SPF, DKIM and DMARC records. |

`marymount.edu.co` already publishes SPF, DKIM and a DMARC policy of
`p=quarantine`, all configured for Google Workspace. Sending through a school
mailbox therefore inherits authentication that already works. Adding an outside
provider would mean editing the SPF record that the whole school's mail depends
on — the record currently authorises Google, GoDaddy, Mailchimp and Zoho, and
uses 5 of the 10 DNS lookups the standard allows.

`SMTP_PASS` is a 16-character **app password**, spaces removed — not the account
password. Generating one requires 2-Step Verification on that account, which is
precisely why app passwords exist: an automated program cannot type a code from
someone's phone. Note that an app password authenticates against the whole
mailbox, not just sending, which is the argument for a dedicated empty mailbox
rather than a personal account.

Test the credentials before deploying anything:

```bash
npm run email:test -- someone@marymount.edu.co
```

That runs from your machine, so the password never leaves it. It names the
three failures worth distinguishing: rejected credentials, an unreachable
relay, and a wrong sender address.

Sending is never fatal: the collaboration request is already committed by the
time mail is attempted, so an outage or a bounced address is logged and
swallowed behind a short timeout rather than turning a successful click into an
error page. Teachers can opt out from their dashboard.

Messages are written in the **project's** language rather than a stored
per-teacher preference: the owner wrote the project in that language, and the
volunteer chose to offer help on it.

## Languages

The interface ships in English, Spanish and French (`/`, `/es/`, `/fr/`).
Project text stays in whatever language its author wrote it in; each project
records its language so the UI can label and filter on it.

## Local setup

```bash
npm install
cp .env.example .env    # then fill in the Supabase keys
npm run dev
```

| Command | Does |
| --- | --- |
| `npm run dev` | Dev server on http://localhost:4321 |
| `npm run build` | Production build |
| `npm run check` | Astro + TypeScript diagnostics |
| `npm run db:test` | Apply migrations to a throwaway Postgres and run the schema tests |
| `npm run seed:generate` | Rebuild the subject seed SQL from `src/lib/subjects.ts` |
| `npm run email:test -- <addr>` | Send one real email through the configured SMTP account |

## Database

Migrations live in `supabase/migrations/` and are applied **in filename order**.
Paste each into the Supabase SQL Editor, or run them with the Supabase CLI.

Every file is **idempotent** — safe to re-run, and safe to run out of order
if nothing in it depends on an earlier file. `npm run db:test` applies the
whole set twice on purpose, so a migration that would fail on a second run
fails the test suite instead of failing in production.

| File | Contents |
| --- | --- |
| `0001_schema.sql` | Tables, enums, indexes, triggers |
| `0002_rls.sql` | Row Level Security policies and helper functions |
| `0003_seed_subjects.sql` | Generated — 22 subjects, 50 grade pairs |
| `0004_search_and_storage.sql` | `search_projects` RPC, connection graph, attachments bucket |
| `0005_upsert_project.sql` | Atomic project write across three tables |
| `0006_respond_to_collaboration.sql` | Accept/decline, granting or withdrawing membership |
| `0007_graph_grade_filter_and_email_prefs.sql` | Grade filtering for the graph, email opt-out column |
| `0008_confirmed_collaborations.sql` | Confirmed-collaboration graph and the joint-projects list |
| `0009_collaboration_is_not_moderation.sql` | Keeps admin rights out of collaboration offers |
| `0010_project_schedule.sql` | Academic year, term and week range on a project |

`npm run db:test` spins up a disposable Postgres (podman or docker), applies
every migration and runs `supabase/tests/`, which asserts the things that would
be expensive to get wrong: outside-domain sign-ins are rejected, new accounts
land as `pending` and can read nothing, a pending account cannot approve
itself, and a teacher cannot edit a colleague's project. Run it after any
schema change.

## Layout

```
src/
  lib/subjects.ts     Canonical subject catalog — source of truth for the SQL seed
  i18n/               UI strings (en/es/fr) and locale helpers
  layouts/            Page shell: header, language switcher, footer
  components/         Shared Astro + React components
  pages/              Routes; `es/` and `fr/` mirror the default-locale tree
  styles/global.css   Brand tokens, subject-family accents, contrast notes
supabase/migrations/  Schema and RLS policies
```

## When a project runs

A project records an **academic year, a term and a week range** — `T2 · weeks
3–6` — rather than free-text duration. Timing is the commonest reason two
well-matched projects never happen, and prose cannot be compared. The old free
text survives as an optional note for the nuance dropdowns cannot hold.

The calendar lives in `src/lib/terms.ts`: three terms, twelve weeks each, and a
year that begins in August so `2026` means *2026–2027*. Confirmed against how
the school actually runs. If a term length ever changes, change
`WEEKS_PER_TERM` — the form stops offering weeks that do not exist and no
migration is needed, because the database only enforces a flat 1–12 ceiling.

Term is optional, because "Idea" is a valid status and an idea has no dates.
Those projects read as *not scheduled yet*, and a term filter excludes them
deliberately — "what runs in T2" is a question about scheduled work.

## Subject catalog

Add or rename subjects in `src/lib/subjects.ts` only — the database seed is
generated from it. A subject tag is always a **(subject, grade) pair**, because
Spanish, English, Art and others are taught at all three grades and the hub
needs to distinguish 11th-grade Physics from 12th-grade Physics.
