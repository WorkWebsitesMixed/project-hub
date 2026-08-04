/**
 * Regenerates supabase/migrations/0003_seed_subjects.sql from the canonical
 * catalog in src/lib/subjects.ts.
 *
 *   npm run seed:generate
 *
 * Never hand-edit the generated SQL — edit subjects.ts and re-run this, so the
 * TypeScript the UI reads and the rows the database holds cannot drift apart.
 */

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { SUBJECTS } from '../src/lib/subjects.ts';

const here = dirname(fileURLToPath(import.meta.url));
const outFile = resolve(here, '../supabase/migrations/0003_seed_subjects.sql');

const q = (value: string) => `'${value.replace(/'/g, "''")}'`;

const subjectRows = SUBJECTS.map((s, i) =>
  `  (${q(s.slug)}, ${q(s.name.en)}, ${q(s.name.es)}, ${q(s.name.fr)}, ${q(s.family)}, ${i})`,
).join(',\n');

const gradeRows = SUBJECTS.flatMap((s) =>
  s.grades.map((g) => `  (${q(s.slug)}, ${g})`),
).join(',\n');

const pairCount = SUBJECTS.reduce((n, s) => n + s.grades.length, 0);
const perGrade = [10, 11, 12]
  .map((g) => `${g}: ${SUBJECTS.filter((s) => s.grades.includes(g as 10)).length}`)
  .join(', ');

const sql = `-- Project Hub — subject catalog seed
--
-- GENERATED FILE. Do not edit by hand.
-- Source: src/lib/subjects.ts  ·  Regenerate: npm run seed:generate
--
-- ${SUBJECTS.length} subjects, ${pairCount} (subject, grade) pairs.
-- Subjects offered per grade — ${perGrade}.
--
-- Safe to re-run: subjects upsert, grade pairs are added but never removed.
-- Retiring a subject from a grade is a deliberate act, because project_subjects
-- references these rows with ON DELETE RESTRICT.

insert into public.subjects (slug, name_en, name_es, name_fr, family, sort_order) values
${subjectRows}
on conflict (slug) do update set
  name_en    = excluded.name_en,
  name_es    = excluded.name_es,
  name_fr    = excluded.name_fr,
  family     = excluded.family,
  sort_order = excluded.sort_order;

insert into public.grade_subjects (subject_slug, grade) values
${gradeRows}
on conflict (subject_slug, grade) do nothing;
`;

writeFileSync(outFile, sql);
console.log(
  `Wrote ${outFile}\n  ${SUBJECTS.length} subjects, ${pairCount} grade pairs (${perGrade})`,
);
