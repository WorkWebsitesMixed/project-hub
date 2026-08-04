import type { APIRoute } from 'astro';
import { ALLOWED_EMAIL_DOMAIN } from '../../lib/supabase';

export const prerender = false;

export const GET: APIRoute = async ({ locals, url, redirect }) => {
  const next = url.searchParams.get('next') ?? '/dashboard';

  const { data, error } = await locals.supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: `${url.origin}/auth/callback?next=${encodeURIComponent(next)}`,
      queryParams: {
        // Tells Google to show only school accounts in the picker. This is a
        // convenience, not a control — the real domain check is the database
        // trigger in 0001_schema.sql, which nothing client-side can bypass.
        hd: ALLOWED_EMAIL_DOMAIN,
        prompt: 'select_account',
      },
    },
  });

  if (error || !data?.url) {
    return redirect(`/auth/error?reason=oauth&detail=${encodeURIComponent(error?.message ?? 'unknown')}`);
  }

  return redirect(data.url);
};
