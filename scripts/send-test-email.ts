/**
 * Sends one real email through whatever SMTP account is configured in `.env`.
 *
 *   npm run email:test -- destinatario@marymount.edu.co
 *
 * Run this from your own machine before wiring anything into Vercel. It proves
 * the credentials work without the password ever leaving your laptop.
 */

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import nodemailer from 'nodemailer';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** Minimal .env reader — not worth a dependency for four values. */
function loadEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  try {
    for (const line of readFileSync(resolve(root, '.env'), 'utf8').split('\n')) {
      const match = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/i);
      if (!match) continue;
      env[match[1]] = match[2].trim().replace(/^["']|["']$/g, '');
    }
  } catch {
    console.error('No .env file found. Copy .env.example to .env first.');
    process.exit(1);
  }
  return env;
}

const env = loadEnv();
const to = process.argv[2];

if (!to) {
  console.error('Usage: npm run email:test -- someone@marymount.edu.co');
  process.exit(1);
}

const host = env.SMTP_HOST ?? 'smtp.gmail.com';
const port = Number(env.SMTP_PORT ?? 587);
const user = env.SMTP_USER;
const pass = env.SMTP_PASS;

if (!user || !pass) {
  console.error(
    'Set SMTP_USER and SMTP_PASS in .env.\n' +
      'SMTP_PASS is the 16-character app password, spaces removed.',
  );
  process.exit(1);
}

console.log(`Connecting to ${host}:${port} as ${user}…`);

const transporter = nodemailer.createTransport({
  host,
  port,
  secure: port === 465,
  auth: { user, pass },
  connectionTimeout: 10000,
});

try {
  await transporter.verify();
  console.log('✓ Credentials accepted.');

  const info = await transporter.sendMail({
    from: env.EMAIL_FROM ?? user,
    to,
    subject: 'Project Hub — prueba de envío',
    text:
      'Si estás leyendo esto, el envío por SMTP funciona.\n\n' +
      'Este es un mensaje de prueba de la plataforma Project Hub.',
    html:
      '<div style="font-family:-apple-system,Segoe UI,sans-serif;color:#051937;">' +
      '<p>Si estás leyendo esto, el envío por SMTP funciona.</p>' +
      '<p style="color:#4a5a72;font-size:14px;">Mensaje de prueba de la plataforma Project Hub.</p>' +
      '</div>',
  });

  console.log(`✓ Sent. Message id: ${info.messageId}`);
  console.log('\nCheck the inbox (and the spam folder) of', to);
} catch (error) {
  const err = error as { code?: string; responseCode?: number; message?: string };
  console.error('\n✗ Failed:', err.message ?? error);

  // The three failures worth naming, because each has a different fix.
  if (err.responseCode === 535 || err.code === 'EAUTH') {
    console.error(
      '\nThe server rejected the credentials. Usually one of:\n' +
        '  · the app password was copied with its spaces — remove them\n' +
        '  · SMTP_USER is not the full address (needs @marymount.edu.co)\n' +
        '  · the app password was revoked, or belongs to a different account',
    );
  } else if (err.code === 'ETIMEDOUT' || err.code === 'ESOCKET') {
    console.error(
      `\nCould not reach ${host}:${port}. The school network may block outbound\n` +
        'SMTP. Try from another connection before concluding the account is wrong.',
    );
  }
  process.exit(1);
}
