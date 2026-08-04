import { useMemo, useState, type ReactNode } from 'react';
import SubjectPicker from './SubjectPicker';
import { createSupabaseBrowserClient } from '../lib/supabase';
import {
  GRADES,
  PROJECT_STATUSES,
  STATUS_LABELS,
  subjectsForGrade,
  type Grade,
  type ProjectStatus,
} from '../lib/subjects';
import { LOCALES, type Locale } from '../i18n/ui';

export interface ProjectFormValues {
  id?: string;
  title: string;
  description: string;
  grades: Grade[];
  primarySubject: string | null;
  crossSubjects: string[];
  status: ProjectStatus;
  duration: string;
  resources: string;
  language: Locale;
}

interface Props {
  locale: Locale;
  initial?: Partial<ProjectFormValues>;
  labels: Record<string, string>;
  pickerLabels: {
    search: string;
    allGrades: string;
    allFamilies: string;
    clear: string;
    noMatches: string;
  };
}

const EMPTY: ProjectFormValues = {
  title: '',
  description: '',
  grades: [],
  primarySubject: null,
  crossSubjects: [],
  status: 'idea',
  duration: '',
  resources: '',
  language: 'en',
};

export default function ProjectForm({ locale, initial, labels, pickerLabels }: Props) {
  const [values, setValues] = useState<ProjectFormValues>({
    ...EMPTY,
    language: locale,
    ...initial,
  });
  const [files, setFiles] = useState<File[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const gradeLabel = (g: Grade) => `${labels.grade} ${g}`;

  /**
   * The primary subject is scoped to the grades the project actually targets —
   * an 11th-grade project should not offer Calculus. Cross-disciplinary
   * subjects are deliberately unrestricted, since reaching into another grade
   * is the entire point of the hub.
   */
  const primaryOptions = useMemo(() => {
    const grades = values.grades.length > 0 ? values.grades : [...GRADES];
    return grades.flatMap((grade) =>
      subjectsForGrade(grade).map((subject) => ({
        tag: `${subject.slug}@${grade}`,
        label: `${subject.name[locale]} · ${gradeLabel(grade)}`,
      })),
    );
  }, [values.grades, locale]);

  function toggleGrade(grade: Grade) {
    setValues((v) => {
      const grades = v.grades.includes(grade)
        ? v.grades.filter((g) => g !== grade)
        : [...v.grades, grade].sort();
      // A primary subject that is no longer offered at any targeted grade has
      // to go, or we would submit a tag the database will reject.
      const stillValid =
        v.primarySubject &&
        grades.some((g) => v.primarySubject!.endsWith(`@${g}`));
      return { ...v, grades, primarySubject: stillValid ? v.primarySubject : null };
    });
  }

  // Typed structurally: React 19 deprecates the FormEvent alias, and
  // preventDefault is all this handler needs from the event.
  async function handleSubmit(event: { preventDefault: () => void }) {
    event.preventDefault();
    setError(null);

    if (!values.title.trim()) return setError(labels.errorTitle);
    if (values.grades.length === 0) return setError(labels.errorGrades);
    if (!values.primarySubject) return setError(labels.errorPrimary);

    setSaving(true);
    const supabase = createSupabaseBrowserClient();

    // One RPC writes the project and all its tags in a single transaction, so
    // a dropped connection cannot leave a half-tagged project behind.
    const { data: projectId, error: rpcError } = await supabase.rpc('upsert_project', {
      p_title: values.title.trim(),
      p_description: values.description.trim(),
      p_status: values.status,
      p_duration: values.duration.trim(),
      p_resources: values.resources.trim(),
      p_language: values.language,
      p_grades: values.grades,
      p_primary_subject: values.primarySubject,
      p_cross_subjects: values.crossSubjects,
      p_id: values.id ?? null,
    });

    if (rpcError || !projectId) {
      setSaving(false);
      return setError(rpcError?.message ?? labels.errorGeneric);
    }

    // Attachments are best-effort: the project is already saved, so a failed
    // upload should not lose the teacher's writing.
    for (const file of files) {
      const path = `${projectId}/${crypto.randomUUID()}-${file.name}`;
      const { error: uploadError } = await supabase.storage
        .from('project-files')
        .upload(path, file);
      if (!uploadError) {
        await supabase.from('project_attachments').insert({
          project_id: projectId,
          storage_path: path,
          file_name: file.name,
          mime_type: file.type,
          size_bytes: file.size,
        });
      }
    }

    const prefix = locale === 'en' ? '' : `/${locale}`;
    window.location.href = `${prefix}/projects/${projectId}`;
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-8">
      {error && (
        <p
          role="alert"
          className="rounded-lg border border-magenta bg-magenta-tint px-4 py-3 text-sm text-navy"
        >
          {error}
        </p>
      )}

      <Field label={labels.title} required>
        <input
          type="text"
          required
          maxLength={200}
          value={values.title}
          onChange={(e) => setValues((v) => ({ ...v, title: e.target.value }))}
          className="w-full rounded-lg border border-line px-3 py-2 text-navy"
        />
      </Field>

      <Field label={labels.description} hint={labels.descriptionHint}>
        <textarea
          rows={6}
          value={values.description}
          onChange={(e) => setValues((v) => ({ ...v, description: e.target.value }))}
          className="w-full rounded-lg border border-line px-3 py-2 leading-relaxed text-navy"
        />
      </Field>

      <Field label={labels.grades} required>
        <div className="flex flex-wrap gap-2">
          {GRADES.map((grade) => {
            const active = values.grades.includes(grade);
            return (
              <button
                key={grade}
                type="button"
                onClick={() => toggleGrade(grade)}
                aria-pressed={active}
                className={[
                  'rounded-lg px-4 py-2 text-sm transition',
                  active
                    ? 'bg-navy font-semibold text-white'
                    : 'border border-line text-ink-muted hover:bg-surface-sunken hover:text-navy',
                ].join(' ')}
              >
                {gradeLabel(grade)}
              </button>
            );
          })}
        </div>
      </Field>

      <Field label={labels.primary} hint={labels.primaryHint} required>
        <select
          required
          value={values.primarySubject ?? ''}
          onChange={(e) =>
            setValues((v) => ({ ...v, primarySubject: e.target.value || null }))
          }
          className="w-full rounded-lg border border-line px-3 py-2 text-navy"
        >
          <option value="">—</option>
          {primaryOptions.map((option) => (
            <option key={option.tag} value={option.tag}>
              {option.label}
            </option>
          ))}
        </select>
      </Field>

      <Field label={labels.cross} hint={labels.crossHint}>
        <SubjectPicker
          locale={locale}
          selected={values.crossSubjects}
          primaryTag={values.primarySubject}
          onChange={(crossSubjects) => setValues((v) => ({ ...v, crossSubjects }))}
          labels={{
            ...pickerLabels,
            selectedCount: (n) =>
              n === 0 ? labels.noneSelected : `${n} ${labels.selectedSuffix}`,
            grade: gradeLabel,
          }}
        />
      </Field>

      <div className="grid gap-6 sm:grid-cols-2">
        <Field label={labels.status}>
          <select
            value={values.status}
            onChange={(e) =>
              setValues((v) => ({ ...v, status: e.target.value as ProjectStatus }))
            }
            className="w-full rounded-lg border border-line px-3 py-2 text-navy"
          >
            {PROJECT_STATUSES.map((status) => (
              <option key={status} value={status}>
                {STATUS_LABELS[status][locale]}
              </option>
            ))}
          </select>
        </Field>

        <Field label={labels.language} hint={labels.languageHint}>
          <select
            value={values.language}
            onChange={(e) =>
              setValues((v) => ({ ...v, language: e.target.value as Locale }))
            }
            className="w-full rounded-lg border border-line px-3 py-2 text-navy"
          >
            {LOCALES.map((code) => (
              <option key={code} value={code}>
                {code.toUpperCase()}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <Field label={labels.duration} hint={labels.durationHint}>
        <input
          type="text"
          value={values.duration}
          onChange={(e) => setValues((v) => ({ ...v, duration: e.target.value }))}
          placeholder={labels.durationPlaceholder}
          className="w-full rounded-lg border border-line px-3 py-2 text-navy"
        />
      </Field>

      <Field label={labels.resources} hint={labels.resourcesHint}>
        <textarea
          rows={3}
          value={values.resources}
          onChange={(e) => setValues((v) => ({ ...v, resources: e.target.value }))}
          className="w-full rounded-lg border border-line px-3 py-2 leading-relaxed text-navy"
        />
      </Field>

      <Field label={labels.files} hint={labels.filesHint}>
        <input
          type="file"
          multiple
          accept="image/png,image/jpeg,image/webp,image/gif,application/pdf"
          onChange={(e) => setFiles(Array.from(e.target.files ?? []))}
          className="block w-full text-sm text-ink-muted file:mr-3 file:rounded-lg file:border-0 file:bg-surface-sunken file:px-4 file:py-2 file:text-sm file:font-medium file:text-navy"
        />
      </Field>

      <div className="flex items-center gap-3 border-t border-line pt-6">
        <button
          type="submit"
          disabled={saving}
          className="rounded-lg bg-navy px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-navy-soft disabled:opacity-60"
        >
          {saving ? labels.saving : labels.submit}
        </button>
        <a
          href={locale === 'en' ? '/dashboard' : `/${locale}/dashboard`}
          className="text-sm text-ink-muted transition hover:text-navy"
        >
          {labels.cancel}
        </a>
      </div>
    </form>
  );
}

function Field({
  label,
  hint,
  required,
  children,
}: {
  label: string;
  hint?: string;
  required?: boolean;
  children: ReactNode;
}) {
  return (
    <label className="block">
      <span className="text-sm font-semibold text-navy">
        {label}
        {required && <span className="ml-1 text-magenta">*</span>}
      </span>
      {hint && <span className="mt-0.5 block text-xs text-ink-muted">{hint}</span>}
      <div className="mt-2">{children}</div>
    </label>
  );
}
