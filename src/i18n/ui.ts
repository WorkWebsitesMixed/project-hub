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
    'auth.signedInAs': 'Signed in as',
    'auth.errorTitle': 'Sign-in did not work',
    'auth.errorDomain':
      'That account is not a marymount.edu.co address. Please sign in with your school Google account.',
    'auth.errorGeneric': 'Something went wrong on the way back from Google. Please try again.',
    'auth.backHome': 'Back to the start',
    'auth.tryAgain': 'Try again',
    'dash.title': 'My hub',
    'dash.myProjects': 'My projects',
    'dash.noProjects': 'You have not posted a project yet.',
    'dash.interest': 'Interest in my projects',
    'dash.noInterest': 'No one has asked to collaborate yet.',
    'dash.myInterest': 'Projects I offered to join',
    'admin.title': 'Teacher approvals',
    'admin.intro':
      'Students share the school email domain, so every new account waits here until you confirm they teach.',
    'admin.pending': 'Waiting',
    'admin.approved': 'Approved teachers',
    'admin.none': 'Nobody is waiting for approval.',
    'admin.approve': 'Approve',
    'admin.reject': 'Reject',
    'admin.makeAdmin': 'Make admin',
    'admin.revoke': 'Revoke access',
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
    'auth.signedInAs': 'Sesión iniciada como',
    'auth.errorTitle': 'No se pudo iniciar sesión',
    'auth.errorDomain':
      'Esa cuenta no es una dirección marymount.edu.co. Ingresa con tu cuenta de Google del colegio.',
    'auth.errorGeneric': 'Algo falló al volver de Google. Inténtalo de nuevo.',
    'auth.backHome': 'Volver al inicio',
    'auth.tryAgain': 'Intentar de nuevo',
    'dash.title': 'Mi espacio',
    'dash.myProjects': 'Mis proyectos',
    'dash.noProjects': 'Aún no has publicado ningún proyecto.',
    'dash.interest': 'Interés en mis proyectos',
    'dash.noInterest': 'Todavía nadie ha pedido colaborar.',
    'dash.myInterest': 'Proyectos a los que me ofrecí',
    'admin.title': 'Aprobación de docentes',
    'admin.intro':
      'Las estudiantes comparten el dominio del colegio, así que cada cuenta nueva espera aquí hasta que confirmes que es docente.',
    'admin.pending': 'En espera',
    'admin.approved': 'Docentes aprobadas',
    'admin.none': 'Nadie está esperando aprobación.',
    'admin.approve': 'Aprobar',
    'admin.reject': 'Rechazar',
    'admin.makeAdmin': 'Hacer admin',
    'admin.revoke': 'Revocar acceso',
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
    'auth.signedInAs': 'Connecté en tant que',
    'auth.errorTitle': 'La connexion a échoué',
    'auth.errorDomain':
      'Ce compte n’est pas une adresse marymount.edu.co. Connectez-vous avec votre compte Google de l’école.',
    'auth.errorGeneric': 'Un problème est survenu au retour de Google. Veuillez réessayer.',
    'auth.backHome': 'Retour à l’accueil',
    'auth.tryAgain': 'Réessayer',
    'dash.title': 'Mon espace',
    'dash.myProjects': 'Mes projets',
    'dash.noProjects': 'Vous n’avez pas encore publié de projet.',
    'dash.interest': 'Intérêt pour mes projets',
    'dash.noInterest': 'Personne n’a encore demandé à collaborer.',
    'dash.myInterest': 'Projets que j’ai proposé de rejoindre',
    'admin.title': 'Approbation des enseignants',
    'admin.intro':
      'Les élèves partagent le domaine de l’école, donc chaque nouveau compte attend ici jusqu’à ce que vous confirmiez qu’il enseigne.',
    'admin.pending': 'En attente',
    'admin.approved': 'Enseignants approuvés',
    'admin.none': 'Personne n’attend d’approbation.',
    'admin.approve': 'Approuver',
    'admin.reject': 'Refuser',
    'admin.makeAdmin': 'Nommer admin',
    'admin.revoke': 'Révoquer l’accès',
  },
} as const;

export type UIKey = keyof (typeof ui)['en'];
