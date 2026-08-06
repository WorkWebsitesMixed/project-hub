/**
 * The school calendar, as far as the hub needs to know it.
 *
 * Single source of truth for terms and weeks, the same way `subjects.ts` is for
 * the catalog. The database only enforces a flat 1–12 ceiling; the shape of the
 * real calendar lives here.
 */

import type { Locale } from '../i18n/ui';

export const TERMS = ['T1', 'T2', 'T3'] as const;
export type Term = (typeof TERMS)[number];

/**
 * How many teaching weeks each term has.
 *
 * ⚠ ASSUMPTION — 12 across the board, not yet checked against the published
 * school calendar. If T3 is shorter, change it here and the form stops offering
 * weeks that do not exist. Nothing else needs touching.
 */
export const WEEKS_PER_TERM: Record<Term, number> = {
  T1: 12,
  T2: 12,
  T3: 12,
};

export const TERM_LABELS: Record<Term, Record<Locale, string>> = {
  T1: { en: 'Term 1', es: 'Periodo 1', fr: 'Trimestre 1' },
  T2: { en: 'Term 2', es: 'Periodo 2', fr: 'Trimestre 2' },
  T3: { en: 'Term 3', es: 'Periodo 3', fr: 'Trimestre 3' },
};

/** Single letter used in the compact "T2 · S3–S6" form on cards. */
const WEEK_INITIAL: Record<Locale, string> = { en: 'W', es: 'S', fr: 'S' };

/**
 * The academic year runs August → June, so a date in, say, March 2027 belongs
 * to the year that started in August 2026. A year is stored as its starting
 * calendar year: 2026 means 2026–2027.
 */
export const ACADEMIC_YEAR_START_MONTH = 8;

export function currentAcademicYear(now: Date = new Date()): number {
  const month = now.getMonth() + 1;
  return month >= ACADEMIC_YEAR_START_MONTH ? now.getFullYear() : now.getFullYear() - 1;
}

export function academicYearLabel(year: number): string {
  return `${year}–${year + 1}`;
}

/**
 * Years offered in the form and the filter. Last year is included because a
 * project posted in July for the term that just ended still needs somewhere to
 * live; next year because teachers plan ahead over the holidays.
 */
export function academicYearOptions(now: Date = new Date()): number[] {
  const current = currentAcademicYear(now);
  return [current - 1, current, current + 1];
}

export function isTerm(value: unknown): value is Term {
  return typeof value === 'string' && (TERMS as readonly string[]).includes(value);
}

export function weekOptions(term: Term | null): number[] {
  const total = term ? WEEKS_PER_TERM[term] : Math.max(...Object.values(WEEKS_PER_TERM));
  return Array.from({ length: total }, (_, i) => i + 1);
}

export interface Schedule {
  academic_year: number | null;
  term: Term | null;
  week_start: number | null;
  week_end: number | null;
}

/**
 * "Periodo 2 · semanas 3–6". Returns null when there is nothing to say, so
 * callers can fall back to "sin programar" rather than rendering an empty row.
 */
export function formatSchedule(
  schedule: Schedule,
  locale: Locale,
  options: { withYear?: boolean } = {},
): string | null {
  if (!schedule.term) return null;

  const parts = [TERM_LABELS[schedule.term][locale]];

  if (schedule.week_start != null) {
    const { week_start: from, week_end: to } = schedule;
    const one = { en: 'week', es: 'semana', fr: 'semaine' }[locale];
    const many = { en: 'weeks', es: 'semanas', fr: 'semaines' }[locale];
    parts.push(
      to == null || to === from ? `${one} ${from}` : `${many} ${from}–${to}`,
    );
  }

  if (options.withYear && schedule.academic_year != null) {
    parts.push(academicYearLabel(schedule.academic_year));
  }

  return parts.join(' · ');
}

/** The compact form for a card chip: "T2 · S3–S6". */
export function formatScheduleShort(schedule: Schedule, locale: Locale): string | null {
  if (!schedule.term) return null;
  if (schedule.week_start == null) return schedule.term;

  const w = WEEK_INITIAL[locale];
  const { week_start: from, week_end: to } = schedule;
  return to == null || to === from
    ? `${schedule.term} · ${w}${from}`
    : `${schedule.term} · ${w}${from}–${w}${to}`;
}
