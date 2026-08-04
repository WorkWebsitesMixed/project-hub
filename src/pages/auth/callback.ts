import type { APIRoute } from 'astro';

export const prerender = false;

/**
 * Google sends the teacher back here with a one-time code. Exchanging it sets
 * the session cookies.
 *
 * A failure here is usually not a bug: the database trigger rejects any account
 * outside marymount.edu.co at insert time, so someone signing in with a
 * personal Google account lands in the error branch by design.
 */
export const GET: APIRoute = async ({ locals, url, redirect }) => {
  const code = url.searchParams.get('code');
  const next = url.searchParams.get('next') ?? '/dashboard';
  const oauthError = url.searchParams.get('error_description') ?? url.searchParams.get('error');

  if (oauthError) {
    return redirect(`/auth/error?reason=google&detail=${encodeURIComponent(oauthError)}`);
  }

  if (!code) {
    return redirect('/auth/error?reason=missing_code');
  }

  const { error } = await locals.supabase.auth.exchangeCodeForSession(code);

  if (error) {
    // The trigger raises on a non-school email; Supabase surfaces that as a
    // generic "Database error saving new user".
    const looksLikeDomainRejection = /database error|saving new user/i.test(error.message);
    return redirect(
      `/auth/error?reason=${looksLikeDomainRejection ? 'domain' : 'exchange'}` +
        `&detail=${encodeURIComponent(error.message)}`,
    );
  }

  // Where they go next is decided by the middleware: approved teachers reach
  // their destination, everyone else is redirected to the waiting screen.
  return redirect(next.startsWith('/') ? next : '/dashboard');
};
