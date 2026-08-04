import { useMemo, useState } from 'react';
import { GRADES, FAMILIES, allTags, type Family, type Grade } from '../lib/subjects';
import type { Locale } from '../i18n/ui';

/**
 * Cross-disciplinary subject picker.
 *
 * Shows all 50 (subject, grade) pairs at once, because teachers already know
 * their own curriculum and stepping them through grade -> subject would just
 * add clicks. The filters above narrow the list without ever hiding it behind
 * a wizard: type a few letters, or tap a grade or a subject family.
 */

interface Props {
  locale: Locale;
  selected: string[];
  onChange: (next: string[]) => void;
  /** The primary subject, shown as already-implied rather than selectable. */
  primaryTag?: string | null;
  labels: {
    search: string;
    allGrades: string;
    allFamilies: string;
    selectedCount: (n: number) => string;
    clear: string;
    noMatches: string;
    grade: (g: Grade) => string;
  };
}

/** Strip accents so "fisica" finds "Física". */
function fold(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

export default function SubjectPicker({
  locale,
  selected,
  onChange,
  primaryTag,
  labels,
}: Props) {
  const [query, setQuery] = useState('');
  const [gradeFilter, setGradeFilter] = useState<Grade | 'all'>('all');
  const [familyFilter, setFamilyFilter] = useState<Family | 'all'>('all');

  const tags = useMemo(() => allTags(), []);
  const selectedSet = useMemo(() => new Set(selected), [selected]);

  const visible = useMemo(() => {
    const needle = fold(query.trim());
    return tags.filter((tag) => {
      if (gradeFilter !== 'all' && tag.grade !== gradeFilter) return false;
      if (familyFilter !== 'all' && tag.subject.family !== familyFilter) return false;
      if (!needle) return true;
      // Search across all three languages, so a French teacher typing
      // "physique" finds Physics on an English-language page.
      return Object.values(tag.subject.name).some((name) => fold(name).includes(needle));
    });
  }, [tags, query, gradeFilter, familyFilter]);

  const byGrade = useMemo(() => {
    return GRADES.map((grade) => ({
      grade,
      items: visible.filter((tag) => tag.grade === grade),
    })).filter((group) => group.items.length > 0);
  }, [visible]);

  function toggle(slug: string) {
    if (slug === primaryTag) return;
    onChange(
      selectedSet.has(slug)
        ? selected.filter((s) => s !== slug)
        : [...selected, slug],
    );
  }

  const filtersActive =
    query.trim() !== '' || gradeFilter !== 'all' || familyFilter !== 'all';

  return (
    <div className="rounded-card border border-line">
      {/* Filters */}
      <div className="space-y-3 border-b border-line p-4">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={labels.search}
          className="w-full rounded-lg border border-line px-3 py-2 text-sm text-navy placeholder:text-ink-muted"
        />

        <div className="flex flex-wrap items-center gap-1.5">
          <FilterChip
            active={gradeFilter === 'all'}
            onClick={() => setGradeFilter('all')}
            label={labels.allGrades}
          />
          {GRADES.map((grade) => (
            <FilterChip
              key={grade}
              active={gradeFilter === grade}
              onClick={() => setGradeFilter(grade)}
              label={labels.grade(grade)}
            />
          ))}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          <FilterChip
            active={familyFilter === 'all'}
            onClick={() => setFamilyFilter('all')}
            label={labels.allFamilies}
          />
          {(Object.keys(FAMILIES) as Family[]).map((family) => (
            <FilterChip
              key={family}
              active={familyFilter === family}
              onClick={() => setFamilyFilter(family)}
              label={FAMILIES[family].label[locale]}
              family={family}
            />
          ))}
        </div>
      </div>

      {/* Selection summary */}
      <div className="flex flex-wrap items-center gap-2 border-b border-line bg-surface-sunken px-4 py-2.5 text-xs">
        <span className="text-ink-muted">{labels.selectedCount(selected.length)}</span>
        {selected.length > 0 && (
          <button
            type="button"
            onClick={() => onChange([])}
            className="ml-auto rounded px-2 py-0.5 font-medium text-ink-muted transition hover:bg-white hover:text-navy"
          >
            {labels.clear}
          </button>
        )}
      </div>

      {/* The list */}
      <div className="max-h-96 space-y-5 overflow-y-auto p-4">
        {byGrade.length === 0 && (
          <p className="py-8 text-center text-sm text-ink-muted">{labels.noMatches}</p>
        )}

        {byGrade.map(({ grade, items }) => (
          <div key={grade}>
            <h4 className="text-xs font-semibold uppercase tracking-widest text-ink-muted">
              {labels.grade(grade)}
            </h4>
            <div className="mt-2 flex flex-wrap gap-1.5">
              {items.map((tag) => {
                const isPrimary = tag.slug === primaryTag;
                const isSelected = selectedSet.has(tag.slug);
                return (
                  <button
                    key={tag.slug}
                    type="button"
                    onClick={() => toggle(tag.slug)}
                    disabled={isPrimary}
                    aria-pressed={isSelected || isPrimary}
                    title={isPrimary ? 'Already the primary subject' : undefined}
                    className={[
                      'chip transition',
                      `family-${tag.subject.family}`,
                      isPrimary
                        ? 'chip-primary cursor-not-allowed opacity-70'
                        : isSelected
                          ? 'chip-primary'
                          : 'hover:brightness-95',
                    ].join(' ')}
                  >
                    {isSelected && !isPrimary && <span aria-hidden="true">✓</span>}
                    {tag.subject.name[locale]}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {filtersActive && (
        <div className="border-t border-line px-4 py-2 text-right">
          <button
            type="button"
            onClick={() => {
              setQuery('');
              setGradeFilter('all');
              setFamilyFilter('all');
            }}
            className="text-xs font-medium text-ink-muted transition hover:text-navy"
          >
            Reset filters
          </button>
        </div>
      )}
    </div>
  );
}

function FilterChip({
  active,
  onClick,
  label,
  family,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  family?: Family;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={[
        'rounded-full px-2.5 py-1 text-xs transition',
        family ? `family-${family}` : '',
        active
          ? 'bg-navy font-semibold text-white'
          : 'border border-line text-ink-muted hover:bg-surface-sunken hover:text-navy',
      ].join(' ')}
    >
      {label}
    </button>
  );
}
