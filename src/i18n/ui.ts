/**
 * UI strings, keyed by locale.
 *
 * Scope note: this translates the *interface*. Project titles and descriptions
 * are teacher-written and stay in whatever language the teacher used — each
 * project carries a `language` field so the UI can label it ("Written in
 * Spanish") and filter on it. Machine-translating colleagues' words would be a
 * different, much larger decision.
 */

export const LOCALES = ['en', 'es', 'fr'] as const;
export type Locale = (typeof LOCALES)[number];

export const LOCALE_NAMES: Record<Locale, string> = {
  en: 'English',
  es: 'Español',
  fr: 'Français',
};

export const ui = {
  en: {
    'site.title': 'Project Hub',
    'site.tagline': 'Marymount School Medellín · Grades 10–12',
    'site.description':
      'Share your class projects, find the connections across departments, and build something together.',
    'nav.browse': 'Browse projects',
    'nav.new': 'Post a project',
    'nav.dashboard': 'My hub',
    'nav.signIn': 'Sign in with Google',
    'nav.signOut': 'Sign out',
    'home.heroTitle': 'Find the teacher your project is missing.',
    'home.heroBody':
      'Every project here is tagged across subjects and grades, so a Physics unit can surface for the Calculus teacher who never would have heard about it.',
    'home.cta': 'Browse projects',
    'home.ctaSecondary': 'Post yours',
    'auth.pendingTitle': 'Waiting for approval',
    'auth.pendingBody':
      'Your account has been created. An administrator needs to confirm you are a teacher before you can post or collaborate.',
    'filter.grade': 'Grade',
    'filter.subject': 'Subject',
    'filter.status': 'Status',
    'filter.clear': 'Clear filters',
    'project.primary': 'Primary subject',
    'project.cross': 'Connects with',
    'project.duration': 'Estimated duration',
    'project.resources': 'Resources needed',
    'project.collaborate': 'I want to collaborate',
    'project.collaborateSent': 'Interest sent',
  },
  es: {
    'site.title': 'Project Hub',
    'site.tagline': 'Marymount School Medellín · Grados 10–12',
    'site.description':
      'Comparte tus proyectos de clase, encuentra conexiones entre departamentos y construyan algo juntos.',
    'nav.browse': 'Ver proyectos',
    'nav.new': 'Publicar proyecto',
    'nav.dashboard': 'Mi espacio',
    'nav.signIn': 'Entrar con Google',
    'nav.signOut': 'Salir',
    'home.heroTitle': 'Encuentra al docente que le falta a tu proyecto.',
    'home.heroBody':
      'Cada proyecto se etiqueta por materias y grados, para que una unidad de Física llegue al profesor de Cálculo que nunca se habría enterado.',
    'home.cta': 'Ver proyectos',
    'home.ctaSecondary': 'Publicar el tuyo',
    'auth.pendingTitle': 'Esperando aprobación',
    'auth.pendingBody':
      'Tu cuenta fue creada. Un administrador debe confirmar que eres docente antes de que puedas publicar o colaborar.',
    'filter.grade': 'Grado',
    'filter.subject': 'Materia',
    'filter.status': 'Estado',
    'filter.clear': 'Limpiar filtros',
    'project.primary': 'Materia principal',
    'project.cross': 'Conecta con',
    'project.duration': 'Duración estimada',
    'project.resources': 'Recursos necesarios',
    'project.collaborate': 'Quiero colaborar',
    'project.collaborateSent': 'Interés enviado',
  },
  fr: {
    'site.title': 'Project Hub',
    'site.tagline': 'Marymount School Medellín · Niveaux 10–12',
    'site.description':
      'Partagez vos projets de classe, repérez les liens entre les départements et créez ensemble.',
    'nav.browse': 'Voir les projets',
    'nav.new': 'Publier un projet',
    'nav.dashboard': 'Mon espace',
    'nav.signIn': 'Se connecter avec Google',
    'nav.signOut': 'Se déconnecter',
    'home.heroTitle': 'Trouvez l’enseignant qui manque à votre projet.',
    'home.heroBody':
      'Chaque projet est étiqueté par matière et par niveau, pour qu’une séquence de Physique parvienne au professeur de Calcul qui n’en aurait jamais entendu parler.',
    'home.cta': 'Voir les projets',
    'home.ctaSecondary': 'Publier le vôtre',
    'auth.pendingTitle': 'En attente d’approbation',
    'auth.pendingBody':
      'Votre compte a été créé. Un administrateur doit confirmer que vous êtes enseignant avant que vous puissiez publier ou collaborer.',
    'filter.grade': 'Niveau',
    'filter.subject': 'Matière',
    'filter.status': 'Statut',
    'filter.clear': 'Réinitialiser',
    'project.primary': 'Matière principale',
    'project.cross': 'En lien avec',
    'project.duration': 'Durée estimée',
    'project.resources': 'Ressources nécessaires',
    'project.collaborate': 'Je veux collaborer',
    'project.collaborateSent': 'Intérêt envoyé',
  },
} as const;

export type UIKey = keyof (typeof ui)['en'];
