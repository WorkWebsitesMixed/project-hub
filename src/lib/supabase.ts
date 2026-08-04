import { createServerClient, createBrowserClient, parseCookieHeader } from '@supabase/ssr';
import type { AstroCookies } from 'astro';

const SUPABASE_URL = import.meta.env.PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error(
    'Missing PUBLIC_SUPABASE_URL or PUBLIC_SUPABASE_ANON_KEY. Copy .env.example to .env.',
  );
}

/**
 * Request-scoped client. Reads the session from the request cookies and writes
 * refreshed tokens back through Astro's cookie API, so a token that expires
 * mid-request is renewed transparently.
 *
 * The anon key is safe here — it carries no privileges of its own. Every read
 * and write is still filtered by Row Level Security against the signed-in
 * user's JWT.
 */
export function createSupabaseServerClient(context: {
  cookies: AstroCookies;
  request: Request;
}) {
  return createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return parseCookieHeader(context.request.headers.get('Cookie') ?? '').map(
          (cookie) => ({ name: cookie.name, value: cookie.value ?? '' }),
        );
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          context.cookies.set(name, value, { ...options, path: '/' });
        }
      },
    },
  });
}

/** Browser-side client, for React islands that need to talk to Supabase directly. */
export function createSupabaseBrowserClient() {
  return createBrowserClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

export const ALLOWED_EMAIL_DOMAIN =
  import.meta.env.PUBLIC_ALLOWED_EMAIL_DOMAIN ?? 'marymount.edu.co';
