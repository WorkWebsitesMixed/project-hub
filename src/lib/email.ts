/**
 * Transactional email for collaboration offers, sent through Resend.
 *
 * Three deliberate properties:
 *
 * 1. **Optional.** With no RESEND_API_KEY set, every function here returns
 *    quietly. The hub works exactly as before — in-app only — so the feature
 *    can ship before the school's sending domain is sorted out.
 *
 * 2. **Never fatal.** The collaboration request is already committed by the
 *    time we get here. A Resend outage, a bounced address or a slow response
 *    must not turn a successful action into an error page, so failures are
 *    logged and swallowed, behind a short timeout.
 *
 * 3. **Written in the project's language.** We do not store a per-teacher
 *    language preference, and guessing from a browser header is worse than
 *    using something we actually know: the project owner wrote the project in
 *    that language, and the volunteer chose to offer help on it.
 */

import type { Locale } from '../i18n/ui';

const RESEND_API_KEY = import.meta.env.RESEND_API_KEY;
const EMAIL_FROM = import.meta.env.EMAIL_FROM ?? 'Project Hub <onboarding@resend.dev>';

export const emailEnabled = Boolean(RESEND_API_KEY);

interface SendArgs {
  to: string;
  subject: string;
  heading: string;
  body: string[];
  quote?: string;
  ctaLabel: string;
  ctaUrl: string;
  footer: string;
}

async function send({
  to,
  subject,
  heading,
  body,
  quote,
  ctaLabel,
  ctaUrl,
  footer,
}: SendArgs): Promise<void> {
  if (!RESEND_API_KEY) return;

  const esc = (s: string) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  // Inline styles only — email clients strip <style> blocks unpredictably.
  const html = `
<div style="margin:0;padding:24px;background:#f6f8fb;font-family:-apple-system,Segoe UI,sans-serif;">
  <div style="max-width:520px;margin:0 auto;background:#ffffff;border:1px solid #dde3ec;border-radius:12px;padding:28px;">
    <p style="margin:0 0 4px;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#4a5a72;">
      Marymount School Medell&iacute;n &middot; Project Hub
    </p>
    <h1 style="margin:0 0 16px;font-size:20px;line-height:1.3;color:#051937;">${esc(heading)}</h1>
    ${body.map((p) => `<p style="margin:0 0 12px;font-size:15px;line-height:1.6;color:#051937;">${esc(p)}</p>`).join('')}
    ${
      quote
        ? `<blockquote style="margin:16px 0;padding:8px 0 8px 14px;border-left:3px solid #1eaade;font-size:15px;line-height:1.6;color:#4a5a72;">${esc(quote)}</blockquote>`
        : ''
    }
    <p style="margin:24px 0 0;">
      <a href="${ctaUrl}" style="display:inline-block;background:#051937;color:#ffffff;text-decoration:none;font-size:14px;font-weight:600;padding:11px 20px;border-radius:8px;">${esc(ctaLabel)}</a>
    </p>
    <p style="margin:24px 0 0;padding-top:16px;border-top:1px solid #dde3ec;font-size:12px;line-height:1.5;color:#4a5a72;">${esc(footer)}</p>
  </div>
</div>`.trim();

  const text = [heading, '', ...body, quote ? `\n"${quote}"\n` : '', ctaUrl, '', footer]
    .filter(Boolean)
    .join('\n');

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html, text }),
      // A slow provider must not hold up the page. The action already succeeded.
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) {
      console.error('[email] Resend rejected the message:', response.status, await response.text());
    }
  } catch (error) {
    console.error('[email] Could not send:', error);
  }
}

const copy = {
  offer: {
    en: (p: { requester: string; project: string }) => ({
      subject: `${p.requester} wants to collaborate on "${p.project}"`,
      heading: `${p.requester} wants to collaborate`,
      body: [
        `${p.requester} has offered to help with your project "${p.project}".`,
        'Accepting gives them edit access so you can build it together.',
      ],
      cta: 'Open my hub',
      footer:
        'You are receiving this because you own a project on the Project Hub. You can turn these emails off in the hub.',
    }),
    es: (p: { requester: string; project: string }) => ({
      subject: `${p.requester} quiere colaborar en «${p.project}»`,
      heading: `${p.requester} quiere colaborar`,
      body: [
        `${p.requester} se ofreció a ayudar con tu proyecto «${p.project}».`,
        'Al aceptar, le das acceso de edición para que puedan construirlo juntos.',
      ],
      cta: 'Abrir mi espacio',
      footer:
        'Recibes este correo porque tienes un proyecto en el Project Hub. Puedes desactivar estos correos en el sitio.',
    }),
    fr: (p: { requester: string; project: string }) => ({
      subject: `${p.requester} souhaite collaborer sur « ${p.project} »`,
      heading: `${p.requester} souhaite collaborer`,
      body: [
        `${p.requester} propose de vous aider sur votre projet « ${p.project} ».`,
        'En acceptant, vous lui donnez un accès en modification pour construire à deux.',
      ],
      cta: 'Ouvrir mon espace',
      footer:
        'Vous recevez ce message car vous avez un projet sur le Project Hub. Vous pouvez désactiver ces courriels sur le site.',
    }),
  },
  answer: {
    en: (p: { owner: string; project: string; accepted: boolean }) => ({
      subject: p.accepted
        ? `You are on the team for "${p.project}"`
        : `About your offer on "${p.project}"`,
      heading: p.accepted ? 'You are on the team' : 'Your offer was not taken up',
      body: p.accepted
        ? [
            `${p.owner} accepted your offer to collaborate on "${p.project}".`,
            'You can now edit the project alongside them.',
          ]
        : [
            `${p.owner} has declined your offer on "${p.project}" for now.`,
            'The project is still on the board if you want to follow it.',
          ],
      cta: 'Open the project',
      footer: 'You are receiving this because you offered to collaborate on the Project Hub.',
    }),
    es: (p: { owner: string; project: string; accepted: boolean }) => ({
      subject: p.accepted
        ? `Ya haces parte del equipo de «${p.project}»`
        : `Sobre tu propuesta en «${p.project}»`,
      heading: p.accepted ? 'Ya haces parte del equipo' : 'Tu propuesta no fue aceptada',
      body: p.accepted
        ? [
            `${p.owner} aceptó tu propuesta de colaborar en «${p.project}».`,
            'Ya puedes editar el proyecto junto a esa persona.',
          ]
        : [
            `${p.owner} rechazó tu propuesta en «${p.project}» por ahora.`,
            'El proyecto sigue publicado si quieres seguirlo.',
          ],
      cta: 'Abrir el proyecto',
      footer: 'Recibes este correo porque te ofreciste a colaborar en el Project Hub.',
    }),
    fr: (p: { owner: string; project: string; accepted: boolean }) => ({
      subject: p.accepted
        ? `Vous faites partie de l’équipe de « ${p.project} »`
        : `À propos de votre proposition sur « ${p.project} »`,
      heading: p.accepted ? 'Vous faites partie de l’équipe' : 'Votre proposition n’a pas été retenue',
      body: p.accepted
        ? [
            `${p.owner} a accepté votre proposition de collaborer sur « ${p.project} ».`,
            'Vous pouvez maintenant modifier le projet avec cette personne.',
          ]
        : [
            `${p.owner} a décliné votre proposition sur « ${p.project} » pour le moment.`,
            'Le projet reste publié si vous souhaitez le suivre.',
          ],
      cta: 'Ouvrir le projet',
      footer: 'Vous recevez ce message car vous avez proposé de collaborer sur le Project Hub.',
    }),
  },
};

/** Tell a project owner that a colleague has offered to help. */
export async function notifyCollaborationOffer(args: {
  to: string;
  requesterName: string;
  projectTitle: string;
  projectId: string;
  message: string;
  language: Locale;
  origin: string;
}): Promise<void> {
  const c = copy.offer[args.language]({
    requester: args.requesterName,
    project: args.projectTitle,
  });
  await send({
    to: args.to,
    subject: c.subject,
    heading: c.heading,
    body: c.body,
    quote: args.message || undefined,
    ctaLabel: c.cta,
    ctaUrl: `${args.origin}/dashboard`,
    footer: c.footer,
  });
}

/** Tell a volunteer whether their offer was taken up. */
export async function notifyCollaborationAnswer(args: {
  to: string;
  ownerName: string;
  projectTitle: string;
  projectId: string;
  accepted: boolean;
  language: Locale;
  origin: string;
}): Promise<void> {
  const c = copy.answer[args.language]({
    owner: args.ownerName,
    project: args.projectTitle,
    accepted: args.accepted,
  });
  await send({
    to: args.to,
    subject: c.subject,
    heading: c.heading,
    body: c.body,
    ctaLabel: c.cta,
    ctaUrl: `${args.origin}/projects/${args.projectId}`,
    footer: c.footer,
  });
}
