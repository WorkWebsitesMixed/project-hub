// @ts-check
import { defineConfig } from 'astro/config';

import react from '@astrojs/react';
import tailwindcss from '@tailwindcss/vite';
import vercel from '@astrojs/vercel';

// https://astro.build/config
export default defineConfig({
  // Almost every page sits behind the login gate, so server-render by default
  // and opt individual pages IN with `export const prerender = true`.
  output: 'server',

  adapter: vercel(),

  integrations: [react()],

  // Trilingual staff body: English, Spanish, French.
  // English is the default and serves from `/`; the others get a prefix
  // (`/es/...`, `/fr/...`). Flip `defaultLocale` if Spanish should lead.
  i18n: {
    locales: ['en', 'es', 'fr'],
    defaultLocale: 'en',
    routing: {
      prefixDefaultLocale: false,
      redirectToDefaultLocale: false,
    },
  },

  vite: {
    plugins: [tailwindcss()],
  },
});
