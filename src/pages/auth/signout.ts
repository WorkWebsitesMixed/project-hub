import type { APIRoute } from 'astro';

export const prerender = false;

const signOut: APIRoute = async ({ locals, redirect }) => {
  await locals.supabase.auth.signOut();
  return redirect('/');
};

// POST is the real one (it is a state change, and CSRF-safer). GET exists so a
// plain link works if JavaScript is unavailable.
export const POST = signOut;
export const GET = signOut;
