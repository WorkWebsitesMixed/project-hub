/// <reference types="astro/client" />

import type { SupabaseClient, User } from '@supabase/supabase-js';
import type { Profile } from './lib/database.types';

declare global {
  interface ImportMetaEnv {
    readonly PUBLIC_SUPABASE_URL: string;
    readonly PUBLIC_SUPABASE_ANON_KEY: string;
    readonly PUBLIC_ALLOWED_EMAIL_DOMAIN: string;
    readonly PUBLIC_SITE_URL: string;
  }

  interface ImportMeta {
    readonly env: ImportMetaEnv;
  }

  namespace App {
    interface Locals {
      supabase: SupabaseClient;
      /** The verified Google account, or null when signed out. */
      user: User | null;
      /** The teacher's profile row. Null until the first sign-in completes. */
      profile: Profile | null;
    }
  }
}

export {};
