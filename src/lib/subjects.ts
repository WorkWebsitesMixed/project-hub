/**
 * Canonical subject catalog for Marymount School Medellín, Grades 10-12.
 *
 * A subject tag is always a (subject, grade) PAIR, never a bare name — several
 * subjects (Spanish, English, Art...) are taught at all three grades, and the
 * whole point of the hub is to say "11th Physics connects to 12th Calculus".
 *
 * This file is the single source of truth. The SQL seed for `subjects` and
 * `grade_subjects` is generated from it (see scripts/generate-seed.ts), so add
 * a subject here and the database follows.
 */

export const GRADES = [10, 11, 12] as const;
export type Grade = (typeof GRADES)[number];

/**
 * Subject families drive the accent colour of every tag, chip and graph node.
 * Six families, six brand accents — see `global.css`.
 */
export const FAMILIES = {
  stem: { label: { en: 'STEM', es: 'STEM', fr: 'STEM' }, accent: 'cyan' },
  humanities: {
    label: { en: 'Humanities', es: 'Humanidades', fr: 'Sciences humaines' },
    accent: 'purple',
  },
  languages: {
    label: { en: 'Languages', es: 'Lenguas', fr: 'Langues' },
    accent: 'magenta',
  },
  arts: { label: { en: 'Arts', es: 'Artes', fr: 'Arts' }, accent: 'orange' },
  applied: {
    label: { en: 'Applied', es: 'Aplicadas', fr: 'Appliquées' },
    accent: 'green',
  },
  values: {
    label: { en: 'Values', es: 'Valores', fr: 'Valeurs' },
    accent: 'amber',
  },
} as const;

export type Family = keyof typeof FAMILIES;

export interface Subject {
  /** Stable identifier. Never change one — it is the database key. */
  slug: string;
  name: { en: string; es: string; fr: string };
  family: Family;
  /** Grades at which this subject is offered. */
  grades: Grade[];
}

export const SUBJECTS: Subject[] = [
  // — STEM ————————————————————————————————————————————————————
  {
    slug: 'mathematics',
    name: { en: 'Mathematics', es: 'Matemáticas', fr: 'Mathématiques' },
    family: 'stem',
    grades: [10],
  },
  {
    slug: 'general-science',
    name: {
      en: 'General Science',
      es: 'Ciencias Generales',
      fr: 'Sciences générales',
    },
    family: 'stem',
    grades: [10],
  },
  {
    slug: 'trigonometry',
    name: { en: 'Trigonometry', es: 'Trigonometría', fr: 'Trigonométrie' },
    family: 'stem',
    grades: [11],
  },
  {
    slug: 'calculus',
    name: { en: 'Calculus', es: 'Cálculo', fr: 'Calcul' },
    family: 'stem',
    grades: [12],
  },
  {
    slug: 'biology',
    name: { en: 'Biology', es: 'Biología', fr: 'Biologie' },
    family: 'stem',
    grades: [11, 12],
  },
  {
    slug: 'chemistry',
    name: { en: 'Chemistry', es: 'Química', fr: 'Chimie' },
    family: 'stem',
    grades: [11, 12],
  },
  {
    slug: 'physics',
    name: { en: 'Physics', es: 'Física', fr: 'Physique' },
    family: 'stem',
    grades: [11, 12],
  },
  {
    slug: 'research',
    name: { en: 'Research', es: 'Investigación', fr: 'Recherche' },
    family: 'stem',
    grades: [12],
  },

  // — Humanities ——————————————————————————————————————————————
  {
    slug: 'social-studies',
    name: { en: 'Social Studies', es: 'Sociales', fr: 'Sciences sociales' },
    family: 'humanities',
    grades: [10, 11, 12],
  },
  {
    slug: 'economics',
    name: { en: 'Economics', es: 'Economía', fr: 'Économie' },
    family: 'humanities',
    grades: [11, 12],
  },
  {
    slug: 'philosophy',
    name: { en: 'Philosophy', es: 'Filosofía', fr: 'Philosophie' },
    family: 'humanities',
    grades: [11, 12],
  },
  {
    slug: 'global-perspectives',
    name: {
      en: 'Global Perspectives',
      es: 'Perspectivas Globales',
      fr: 'Perspectives mondiales',
    },
    family: 'humanities',
    // Deliberately not offered in 12th grade.
    grades: [10, 11],
  },

  // — Languages ———————————————————————————————————————————————
  {
    slug: 'spanish',
    name: { en: 'Spanish', es: 'Español', fr: 'Espagnol' },
    family: 'languages',
    grades: [10, 11, 12],
  },
  {
    slug: 'english',
    name: { en: 'English', es: 'Inglés', fr: 'Anglais' },
    family: 'languages',
    grades: [10, 11, 12],
  },
  {
    slug: 'french',
    name: { en: 'French', es: 'Francés', fr: 'Français' },
    family: 'languages',
    grades: [10, 11, 12],
  },

  // — Arts ————————————————————————————————————————————————————
  {
    slug: 'art',
    name: { en: 'Art', es: 'Arte', fr: 'Art' },
    family: 'arts',
    grades: [10, 11, 12],
  },
  {
    slug: 'music',
    name: { en: 'Music', es: 'Música', fr: 'Musique' },
    family: 'arts',
    grades: [10, 11, 12],
  },
  {
    slug: 'creative-movement',
    name: {
      en: 'Creative Movement',
      es: 'Movimiento Creativo',
      fr: 'Mouvement créatif',
    },
    family: 'arts',
    grades: [10, 11, 12],
  },

  // — Applied —————————————————————————————————————————————————
  {
    slug: 'design-technology',
    name: {
      en: 'Design & Technology',
      es: 'Diseño y Tecnología',
      fr: 'Design et Technologie',
    },
    family: 'applied',
    grades: [10, 11, 12],
  },
  {
    slug: 'physical-education',
    name: {
      en: 'Physical Education',
      es: 'Educación Física',
      fr: 'Éducation physique',
    },
    family: 'applied',
    grades: [10, 11, 12],
  },

  // — Values ——————————————————————————————————————————————————
  {
    slug: 'ethics',
    name: { en: 'Ethics', es: 'Ética', fr: 'Éthique' },
    family: 'values',
    grades: [10, 11, 12],
  },
  {
    slug: 'religion',
    name: { en: 'Religion', es: 'Religión', fr: 'Religion' },
    family: 'values',
    grades: [10, 11, 12],
  },
];

/** Subjects offered at a given grade, in catalog order. */
export function subjectsForGrade(grade: Grade): Subject[] {
  return SUBJECTS.filter((s) => s.grades.includes(grade));
}

export function subjectBySlug(slug: string): Subject | undefined {
  return SUBJECTS.find((s) => s.slug === slug);
}

/** Every valid (subject, grade) tag, e.g. `physics@11`. */
export function allTags(): { slug: string; grade: Grade; subject: Subject }[] {
  return SUBJECTS.flatMap((subject) =>
    subject.grades.map((grade) => ({
      slug: `${subject.slug}@${grade}`,
      grade,
      subject,
    })),
  );
}

export const PROJECT_STATUSES = ['idea', 'in_progress', 'completed'] as const;
export type ProjectStatus = (typeof PROJECT_STATUSES)[number];

export const STATUS_LABELS: Record<
  ProjectStatus,
  { en: string; es: string; fr: string }
> = {
  idea: { en: 'Idea', es: 'Idea', fr: 'Idée' },
  in_progress: { en: 'In Progress', es: 'En Curso', fr: 'En cours' },
  completed: { en: 'Completed', es: 'Completado', fr: 'Terminé' },
};
