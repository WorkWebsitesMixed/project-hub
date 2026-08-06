# Handoff — Project Hub

**As of 6 August 2026.** Everything in the original roadmap is built, deployed
and in use, including email notifications. One thing remains unproven: that a
notification actually leaves Vercel's runtime. See below.

---

## Where things live

| | |
| --- | --- |
| **Live site** | https://project-hub-hazel.vercel.app |
| **Repo** | https://github.com/WorkWebsitesMixed/project-hub (public) |
| **Hosting** | Vercel, project `project-hub` under scope `class-tracker1` |
| **Database** | Supabase, project ref `gmbmfejhbgdrmtbyefic` |
| **Google OAuth** | Client `369705473552-vauso4diu5dnlvlnbeph4di2in7g6l6r.apps.googleusercontent.com` |
| **Admin** | `andres.forero@marymount.edu.co` |

Deployment is manual — `npx vercel deploy --prod --yes`. The Vercel GitHub App
is not connected to the `WorkWebsitesMixed` org, so pushes do **not** auto-deploy.
Connecting it is a small win nobody has needed yet.

---

## State of the database

All nine migrations are applied. They are **idempotent** — safe to re-run in
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
| `0010_project_schedule.sql` | Academic year, term and week range on a project |

**40 checks passing** (`npm run db:test`, needs podman or docker). They cover
the things that would be expensive to get wrong: outside-domain sign-ins are
rejected, a pending account reads nothing, self-approval is blocked, a teacher
cannot edit a colleague's project, and one acceptance draws exactly one line on
the confirmed graph rather than six.

---

## Email

**Configured and deployed on 6 August 2026.** IT created
`projecthub@marymount.edu.co`; an app password was generated on it and the five
`SMTP_*` / `EMAIL_FROM` variables are set on Vercel across production, preview
and development. `npm run email:test` sends successfully from a laptop.

The app password lives **only** in `.env` (gitignored) and in Vercel's encrypted
environment store, marked sensitive. It is not in the repository and must never
be. If it leaks, revoke it at `myaccount.google.com/apppasswords` on the
projecthub account — that invalidates it everywhere without touching the mailbox
password.

### Still unverified: outbound SMTP from Vercel

Sending works from a laptop. Whether it works from Vercel's Node runtime has not
been observed, because the only two triggers are a real collaboration offer and
a real answer to one — there is no test endpoint. The next offer made in
production is the test.

If nothing arrives, check `npx vercel logs <deployment-url>` for `[email] Could
not send:`. The fallback is Resend, already implemented and selected
automatically when no `SMTP_*` values are set — but it needs SPF and DKIM
records added to a shared school DNS record, which is why it is plan B.

Note that a failure here is quiet by design: the collaboration request commits
before mail is attempted, so an SMTP problem never turns a successful click into
an error page. That is correct behaviour and also why it must be checked
deliberately rather than assumed.

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

### If the app password ever has to be regenerated

```bash
# 1. put the new 16 characters, spaces removed, in .env
npm run email:test -- andres.forero@marymount.edu.co

# 2. push it to all three environments
for e in production preview development; do
  printf '%s' 'newpassword' | npx vercel env add SMTP_PASS "$e" --force
done
npx vercel deploy --prod --yes
```

The script names the three failures worth distinguishing: rejected credentials,
an unreachable relay, and a bad sender address. The most common by far is
pasting the app password with its spaces still in.

Two traps found the first time round. A duplicate `SMTP_PASS` line lower in
`.env` silently wins — the loader takes the last assignment. And the app
password page returns "esta opción no está disponible para tu cuenta" when
2-Step Verification is not yet on for that account, which reads like a policy
block but is not.

### Still to tell the staff

The announcement sent on 5 August says notifications do not exist yet and asks
teachers to check *Mi espacio*. Once a real notification has been seen arriving
in production, that needs a short follow-up.

---

## Open items, in rough priority order

**Term lengths are assumed, not verified.** `WEEKS_PER_TERM` in
`src/lib/terms.ts` says twelve weeks for all three terms. Nobody checked that
against the school calendar. If T3 is shorter, the form currently offers weeks
that do not exist. One constant, one line to fix.

**Projects posted before 6 August have no term.** The backfill gave them an
academic year derived from when they were posted, but deliberately left the term
null rather than guessing — a wrong term on the board is worse than an honest
"sin programar". Their owners can set it by editing the project.

**One collaboration has no subject recorded.** David Felipe Hincapié Calle
offered on the LaTeX project before migration 0008 added that field, so his
offer has `offered_grade_subject_id = NULL`. The joint-projects list shows the
collaboration; the graph correctly refuses to draw a line for it. He can fix it
himself from the project page — the offer section now shows an amber prompt and
a "Cambiar mi aporte" control. He is the only person affected; every offer since
requires the subject at the form.

**Iván Darío Arango has an unanswered offer** from Verónica Correa on his
JUSTICIA SOCIAL project. It was made before email was switched on, so no
notification was ever sent and he has no way of knowing. Nothing will resend it
— write to him. The same applies to any offer made before 6 August.

**Admin rights used to leak into collaboration** (fixed in `0009`). `can_edit_project()`
says yes to admins on everything, which is right for moderation but wrong for
offers — it made the admin the recipient of every teacher's collaboration
requests. Collaboration now uses `leads_project()`, which has no admin
override, and the dashboard scopes its inbox explicitly rather than trusting
RLS. If you add another feature around collaboration_requests, use
`leads_project()`, not `can_edit_project()`.

**A handful of teachers have accounts.** The announcement went out on 5 August
and projects are arriving. The confirmed-collaborations view is still nearly
empty — honest, but not yet useful to a learning director.

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

**A project runs in exactly one term.** Confirmed with the staff: nothing spans
a term boundary. If that ever changes it needs an `end_term` column, *not* a
reinterpretation of `week_end` — a week range that silently wraps into the next
term would be unqueryable.

**The free-text duration was kept as a note, not replaced.** Teachers wrote real
constraints in it ("depende de cuándo esté libre el laboratorio") that dropdowns
cannot hold. The structured fields are for comparing; the note is for reading.

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
| `npm run db:test` | Applies every migration twice to a disposable Postgres, runs 40 checks |
| `npm run seed:generate` | Rebuilds the subject seed from `src/lib/subjects.ts` |
| `npm run email:test -- <addr>` | Sends one real email through the configured SMTP account |

Add or rename subjects in `src/lib/subjects.ts` **only**, then regenerate the
seed. That file is the single source of truth for the catalog, the UI and the
database.
