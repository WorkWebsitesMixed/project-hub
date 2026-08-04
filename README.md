# Project Hub

Interdisciplinary project board for **Marymount School Medellín**, Grades 10–12.

Teachers post the projects they are running, tag them across subjects and
grades, and find colleagues whose work connects. The point is not a project
archive — it is the moment a Calculus teacher discovers the 11th-grade Physics
unit nobody told them about.

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

## Subject catalog

Add or rename subjects in `src/lib/subjects.ts` only — the database seed is
generated from it. A subject tag is always a **(subject, grade) pair**, because
Spanish, English, Art and others are taught at all three grades and the hub
needs to distinguish 11th-grade Physics from 12th-grade Physics.
