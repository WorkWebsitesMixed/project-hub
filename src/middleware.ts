import { defineMiddleware } from 'astro:middleware';
import { createSupabaseServerClient } from './lib/supabase';
import type { Profile } from './lib/database.types';
import { LOCALES } from './i18n/ui';
import { getLocaleFromUrl, localizePath } from './i18n/utils';

/**
 * Routes reachable while signed out. Everything else requires an approved
 * teacher — this is the second gate, mirroring the RLS policies in the
 * database. The database is what actually protects the data; this exists so
 * people get a sensible redirect instead of an empty page.
 */
const PUBLIC_PATHS = ['/', '/auth/signin', '/auth/callback', '/auth/signout', '/auth/error'];

/** Reachable while signed in but not yet approved. */
const PENDING_PATHS = ['/pending', '/auth/signout'];

/** Strip a locale prefix so route matching is language-agnostic. */
function normalizePath(pathname: string): string {
  const stripped = pathname.replace(
    new RegExp(`^/(${LOCALES.join('|')})(?=/|$)`),
    '',
  );
  const path = stripped === '' ? '/' : stripped;
  // Trailing slashes should not change whether a route is public.
  return path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;
}

export const onRequest = defineMiddleware(async (context, next) => {
  const supabase = createSupabaseServerClient(context);
  context.locals.supabase = supabase;

  // getUser() revalidates the JWT with Supabase. getSession() would just trust
  // the cookie, which is exactly the thing not to trust on the server.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  context.locals.user = user ?? null;
  context.locals.profile = null;

  if (user) {
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .maybeSingle();
    context.locals.profile = (data as Profile | null) ?? null;
  }

  const path = normalizePath(context.url.pathname);
  const locale = getLocaleFromUrl(context.url);
  const { profile } = context.locals;

  // Static assets and API-ish routes are handled by their own logic.
  if (path.startsWith('/auth/')) return next();

  if (!user) {
    if (PUBLIC_PATHS.includes(path)) return next();
    return context.redirect(
      `${localizePath('/', locale)}?signin=required&next=${encodeURIComponent(context.url.pathname)}`,
    );
  }

  // Signed in, but an admin has not confirmed they are a teacher. Students
  // share the school's email domain, so this is the check that matters.
  if (!profile || profile.status !== 'approved') {
    if (PENDING_PATHS.includes(path)) return next();
    return context.redirect(localizePath('/pending', locale));
  }

  // Approved users have no reason to sit on the waiting screen.
  if (path === '/pending') {
    return context.redirect(localizePath('/dashboard', locale));
  }

  if (path.startsWith('/admin') && profile.role !== 'admin') {
    return context.redirect(localizePath('/dashboard', locale));
  }

  return next();
});
