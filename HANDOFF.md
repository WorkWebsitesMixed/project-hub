# Handoff — Project Hub

**As of 5 August 2026.** Everything in the original roadmap is built, deployed
and in use. Work is paused on one item only: email notifications, which are
waiting on IT to create a mailbox.

---

## Where things live

| | |
| --- | --- |
| **Live site** | https://project-hub-hazel.vercel.app |
| **Repo** | https://github.com/WorkWebsitesMixed/project-hub (public, 13 commits) |
| **Hosting** | Vercel, project `project-hub` under scope `class-tracker1` |
| **Database** | Supabase, project ref `gmbmfejhbgdrmtbyefic` |
| **Google OAuth** | Client `369705473552-vauso4diu5dnlvlnbeph4di2in7g6l6r.apps.googleusercontent.com` |
| **Admin** | `andres.forero@marymount.edu.co` |

Deployment is manual — `npx vercel deploy --prod --yes`. The Vercel GitHub App
is not connected to the `WorkWebsitesMixed` org, so pushes do **not** auto-deploy.
Connecting it is a small win nobody has needed yet.

---

## State of the database

All eight migrations are applied. They are **idempotent** — safe to re-run in
any order, and `npm run db:test` applies the whole set twice to prove it, so a
migration that would fail on a second run fails the suite instead of failing in
someone's SQL editor.

| Migration | Contents |
| --- | --- |
| `0001_schema.sql` | Tables, enums, indexes, triggers |
| `0002_rls.sql` | Row Level Security and helper functions |
| `0003_seed_subjects.sql` | Generated — 22 subjects, 50 grade pairs |
| `0004_search_and_storage.sql` | `search_projects`, attachments bucket |
| `0005_upsert_project.sql` | Atomic project write across three tables |
| `0006_respond_to_collaboration.sql` | Accept/decline, granting or withdrawing membership |
| `0007_graph_grade_filter_and_email_prefs.sql` | Grade filter for the graph, email opt-out |
| `0008_confirmed_collaborations.sql` | Confirmed-collaboration graph and the director's list |
| `0009_collaboration_is_not_moderation.sql` | Stops admin rights leaking into collaboration offers |

**40 checks passing** (`npm run db:test`, needs podman or docker). They cover
the things that would be expensive to get wrong: outside-domain sign-ins are
rejected, a pending account reads nothing, self-approval is blocked, a teacher
cannot edit a colleague's project, and one acceptance draws exactly one line on
the confirmed graph rather than six.

---

## The one blocked item: email

Everything is written and deployed. It is **inert** because no transport is
configured, which is deliberate — with nothing set, every send returns quietly
and the hub works in-app only.

### What is waiting

IT needs to create a dedicated mailbox, `projecthub@marymount.edu.co`, with
2-Step Verification enabled so an app password can be generated. The request
email is drafted (see the conversation; it also asks, separately and optionally,
for a `proyectos.marymount.edu.co` subdomain).

**App passwords are confirmed to work on this Workspace** — tested on the admin's
own account on 4 August.

### Why a school mailbox rather than an outside provider

`marymount.edu.co` already publishes SPF, DKIM and DMARC (`p=quarantine`, with
reports going to `soporte@marymount.edu.co`), all configured for Google
Workspace. A school mailbox inherits authentication that already works and needs
**no DNS change at all**.

Resend would need SPF and DKIM records added. The SPF record uses 5 of the 10
lookups the standard allows, so it is not full — but it is *shared*: it currently
authorises Google, GoDaddy, Mailchimp and Zoho. An error editing it does not
break the hub, it breaks the whole school's mail. That is the argument, not a
technical limit.

### Steps to finish, once the mailbox exists

1. Generate a 16-character app password on `projecthub@marymount.edu.co`.
2. Prove it locally first — the password never leaves the machine:
   ```bash
   # in .env
   SMTP_HOST="smtp.gmail.com"
   SMTP_PORT="587"
   SMTP_USER="projecthub@marymount.edu.co"
   SMTP_PASS="sixteencharsnospaces"
   EMAIL_FROM="Project Hub <projecthub@marymount.edu.co>"

   npm run email:test -- andres.forero@marymount.edu.co
   ```
   The script names the three failures that matter: rejected credentials, an
   unreachable relay, and a bad sender address. The most common is pasting the
   app password with its spaces still in.
3. Add the same five variables to Vercel (production, preview, development) and
   redeploy.
4. **Verify in production.** This is the one genuine unknown: whether Vercel's
   runtime permits outbound SMTP. It should — the Vercel adapter uses the Node
   runtime, not Edge — but it has not been tested, and it should not be assumed.
   If it fails, the fallback is Resend, which is already implemented and selected
   automatically when no `SMTP_*` values are set.
5. Announce it. The teacher email currently says notifications do not exist yet;
   that paragraph needs updating.

---

## Open items, in rough priority order

**One collaboration has no subject recorded.** David Felipe Hincapié Calle
offered on the LaTeX project before migration 0008 added that field, so his
offer has `offered_grade_subject_id = NULL`. The joint-projects list shows the
collaboration; the graph correctly refuses to draw a line for it. He can fix it
himself from the project page — the offer section now shows an amber prompt and
a "Cambiar mi aporte" control. He is the only person affected; every offer since
requires the subject at the form.

**The teacher announcement has not been sent.** A draft exists with corrections
applied: it needs to say that offers arrive in *Mi espacio* rather than by email,
and describe the two views of the connections map. Sending it after the subdomain
question resolves avoids a follow-up correcting the link.

**Admin rights used to leak into collaboration** (fixed in `0009`). `can_edit_project()`
says yes to admins on everything, which is right for moderation but wrong for
offers — it made the admin the recipient of every teacher's collaboration
requests. Collaboration now uses `leads_project()`, which has no admin
override, and the dashboard scopes its inbox explicitly rather than trusting
RLS. If you add another feature around collaboration_requests, use
`leads_project()`, not `can_edit_project()`.

**A handful of teachers have accounts.** The announcement went out on 5 August. The confirmed-collaborations view is nearly empty, which is
honest but not yet useful to a learning director.

**Vercel ↔ GitHub is not connected.** Deploys are manual. `vercel git connect`
fails because the Vercel GitHub App is not authorised on the org.

**The logo is a JPEG with a white background**, despite its original `.png` name.
Fine on white headers; it will show a white box on any dark surface. A transparent
PNG or SVG from whoever holds the brand assets would help.

---

## Decisions worth not re-litigating

These were argued through and settled. Changing them is fine — but know what
they were protecting.

**A subject tag is a (subject, grade) pair, never a bare name.** Spanish, English
and Art are taught at all three grades; the whole point is to distinguish
11th-grade Physics from 12th-grade Physics so the two can be linked.

**Students share `marymount.edu.co`.** The email domain cannot identify a
teacher. Two gates: OAuth keeps outsiders out, then an approval status on the
profile separates teachers from students. RLS enforces the second one in the
database, not the UI.

**The connections graph has two views because there are two questions.** A
teacher asks "who might I work with?" and needs the tagged view. A director asks
"what joint work is actually happening?" and needs the confirmed one. Replacing
one with the other would cost the hub its discovery function.

**A confirmed edge comes from two stated facts** — the project's primary subject,
and the subject the partner declared when offering. Deriving it from tags instead
would turn one acceptance into six connections nobody agreed to.

**The partner's subject is recorded on the offer, not the profile.** A teacher
who takes both Chemistry and Physics knows which applies to *this* project, and a
profile field would go stale the next time a timetable changed.

**Accepted collaborations are visible to all approved teachers; pending and
declined ones are not.** The director must be able to see joint work. A declined
offer is nobody else's business.

**Redirects only work when returned from a page, never from a component.** This
caused a blank white screen once. Loading and form handling live in
`src/lib/pageLoaders.ts`, which returns `{ kind: 'redirect' }` or `{ kind: 'ok' }`;
thin page wrappers act on it, and the page components are pure renderers that
cannot swallow a response.

**`projects` embeds `profiles` via an explicit constraint name.** There are two
relationships between those tables — the `owner_id` foreign key and a
many-to-many through `project_members` — and PostgREST returns HTTP 300 rather
than guessing.

**Brand accents are fills, not type.** Measured against WCAG: only navy (17.5:1)
and purple (8.0:1) clear AA as text on white. Cyan, green, amber and orange land
between 1.9 and 3.5. The ratios are recorded in `src/styles/global.css`.

---

## Running it

```bash
npm install
cp .env.example .env      # fill in the Supabase values
npm run dev               # http://localhost:4321
```

| Command | Does |
| --- | --- |
| `npm run check` | Astro + TypeScript diagnostics — currently 0 errors |
| `npm run db:test` | Applies every migration twice to a disposable Postgres, runs 36 checks |
| `npm run seed:generate` | Rebuilds the subject seed from `src/lib/subjects.ts` |
| `npm run email:test -- <addr>` | Sends one real email through the configured SMTP account |

Add or rename subjects in `src/lib/subjects.ts` **only**, then regenerate the
seed. That file is the single source of truth for the catalog, the UI and the
database.
