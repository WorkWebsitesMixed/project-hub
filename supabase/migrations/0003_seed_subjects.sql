-- Project Hub — subject catalog seed
--
-- GENERATED FILE. Do not edit by hand.
-- Source: src/lib/subjects.ts  ·  Regenerate: npm run seed:generate
--
-- 22 subjects, 50 (subject, grade) pairs.
-- Subjects offered per grade — 10: 14, 11: 18, 12: 18.
--
-- Safe to re-run: subjects upsert, grade pairs are added but never removed.
-- Retiring a subject from a grade is a deliberate act, because project_subjects
-- references these rows with ON DELETE RESTRICT.

insert into public.subjects (slug, name_en, name_es, name_fr, family, sort_order) values
  ('mathematics', 'Mathematics', 'Matemáticas', 'Mathématiques', 'stem', 0),
  ('general-science', 'General Science', 'Ciencias Generales', 'Sciences générales', 'stem', 1),
  ('trigonometry', 'Trigonometry', 'Trigonometría', 'Trigonométrie', 'stem', 2),
  ('calculus', 'Calculus', 'Cálculo', 'Calcul', 'stem', 3),
  ('biology', 'Biology', 'Biología', 'Biologie', 'stem', 4),
  ('chemistry', 'Chemistry', 'Química', 'Chimie', 'stem', 5),
  ('physics', 'Physics', 'Física', 'Physique', 'stem', 6),
  ('research', 'Research', 'Investigación', 'Recherche', 'stem', 7),
  ('social-studies', 'Social Studies', 'Sociales', 'Sciences sociales', 'humanities', 8),
  ('economics', 'Economics', 'Economía', 'Économie', 'humanities', 9),
  ('philosophy', 'Philosophy', 'Filosofía', 'Philosophie', 'humanities', 10),
  ('global-perspectives', 'Global Perspectives', 'Perspectivas Globales', 'Perspectives mondiales', 'humanities', 11),
  ('spanish', 'Spanish', 'Español', 'Espagnol', 'languages', 12),
  ('english', 'English', 'Inglés', 'Anglais', 'languages', 13),
  ('french', 'French', 'Francés', 'Français', 'languages', 14),
  ('art', 'Art', 'Arte', 'Art', 'arts', 15),
  ('music', 'Music', 'Música', 'Musique', 'arts', 16),
  ('creative-movement', 'Creative Movement', 'Movimiento Creativo', 'Mouvement créatif', 'arts', 17),
  ('design-technology', 'Design & Technology', 'Diseño y Tecnología', 'Design et Technologie', 'applied', 18),
  ('physical-education', 'Physical Education', 'Educación Física', 'Éducation physique', 'applied', 19),
  ('ethics', 'Ethics', 'Ética', 'Éthique', 'values', 20),
  ('religion', 'Religion', 'Religión', 'Religion', 'values', 21)
on conflict (slug) do update set
  name_en    = excluded.name_en,
  name_es    = excluded.name_es,
  name_fr    = excluded.name_fr,
  family     = excluded.family,
  sort_order = excluded.sort_order;

insert into public.grade_subjects (subject_slug, grade) values
  ('mathematics', 10),
  ('general-science', 10),
  ('trigonometry', 11),
  ('calculus', 12),
  ('biology', 11),
  ('biology', 12),
  ('chemistry', 11),
  ('chemistry', 12),
  ('physics', 11),
  ('physics', 12),
  ('research', 12),
  ('social-studies', 10),
  ('social-studies', 11),
  ('social-studies', 12),
  ('economics', 11),
  ('economics', 12),
  ('philosophy', 11),
  ('philosophy', 12),
  ('global-perspectives', 10),
  ('global-perspectives', 11),
  ('spanish', 10),
  ('spanish', 11),
  ('spanish', 12),
  ('english', 10),
  ('english', 11),
  ('english', 12),
  ('french', 10),
  ('french', 11),
  ('french', 12),
  ('art', 10),
  ('art', 11),
  ('art', 12),
  ('music', 10),
  ('music', 11),
  ('music', 12),
  ('creative-movement', 10),
  ('creative-movement', 11),
  ('creative-movement', 12),
  ('design-technology', 10),
  ('design-technology', 11),
  ('design-technology', 12),
  ('physical-education', 10),
  ('physical-education', 11),
  ('physical-education', 12),
  ('ethics', 10),
  ('ethics', 11),
  ('ethics', 12),
  ('religion', 10),
  ('religion', 11),
  ('religion', 12)
on conflict (subject_slug, grade) do nothing;
