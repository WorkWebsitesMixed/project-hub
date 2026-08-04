import { ui, LOCALES, type Locale, type UIKey } from './ui';

export const DEFAULT_LOCALE: Locale = 'en';

/** Pull the locale out of a URL like `/es/projects/42`, falling back to English. */
export function getLocaleFromUrl(url: URL): Locale {
  const [, maybeLocale] = url.pathname.split('/');
  return LOCALES.includes(maybeLocale as Locale)
    ? (maybeLocale as Locale)
    : DEFAULT_LOCALE;
}

/**
 * Translator for a locale. Falls back to the English string rather than
 * rendering a raw key, so a missing translation degrades quietly.
 */
export function useTranslations(locale: Locale) {
  return function t(key: UIKey): string {
    return ui[locale][key] ?? ui[DEFAULT_LOCALE][key];
  };
}

/** Prefix a path with the locale, leaving the default locale unprefixed. */
export function localizePath(path: string, locale: Locale): string {
  const clean = path.startsWith('/') ? path : `/${path}`;
  return locale === DEFAULT_LOCALE ? clean : `/${locale}${clean}`;
}

/** Pick the right field from a `{ en, es, fr }` record. */
export function localized<T extends Record<Locale, string>>(
  record: T,
  locale: Locale,
): string {
  return record[locale] ?? record[DEFAULT_LOCALE];
}

export { LOCALES, type Locale };
