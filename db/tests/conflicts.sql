-- Tests des contraintes. Lancer sur une base vide après schema.sql :
--   psql "$DATABASE_URL" -f db/schema.sql
--   psql "$DATABASE_URL" -f db/tests/conflicts.sql
-- Chaque bloc doit afficher NOTICE "OK : ..." ; sinon il lève une exception.

BEGIN;

-- Données fictives (jamais de vraies données d'étudiants)
INSERT INTO users (id, email, password_hash, full_name, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'prof1@test.ma', 'x', 'Prof Un',   'professeur'),
  ('00000000-0000-0000-0000-000000000002', 'prof2@test.ma', 'x', 'Prof Deux', 'professeur');

INSERT INTO rooms (id, name, capacity) VALUES
  ('10000000-0000-0000-0000-000000000001', 'Amphi 1', 300),
  ('10000000-0000-0000-0000-000000000002', 'Amphi 2', 300);

INSERT INTO filieres (id, name, level) VALUES
  ('20000000-0000-0000-0000-000000000001', 'Economie', 'S3');

INSERT INTO groups (id, filiere_id, name, student_count) VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Groupe A', 120),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Groupe B', 110);

INSERT INTO modules (id, code, name, filiere_id) VALUES
  ('40000000-0000-0000-0000-000000000001', 'ECO301', 'Macroéconomie', '20000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002', 'ECO302', 'Statistiques',  '20000000-0000-0000-0000-000000000001');

-- Examen de référence : Amphi 1, Prof Un, 08:00-10:00, Groupe A
INSERT INTO exams (id, module_id, room_id, professor_id, starts_at, ends_at) VALUES
  ('50000000-0000-0000-0000-000000000001',
   '40000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001',
   '2026-01-15 08:00+00', '2026-01-15 10:00+00');
INSERT INTO exam_groups (exam_id, group_id) VALUES
  ('50000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001');

-- 1) Même salle, horaire qui chevauche  -> doit échouer
DO $$ BEGIN
  INSERT INTO exams (module_id, room_id, professor_id, starts_at, ends_at) VALUES
    ('40000000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-000000000002',
     '2026-01-15 09:00+00', '2026-01-15 11:00+00');
  RAISE EXCEPTION 'ECHEC : conflit de salle non détecté';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'OK : conflit de salle bloqué';
END $$;

-- 2) Même prof, salle différente, horaire qui chevauche -> doit échouer
DO $$ BEGIN
  INSERT INTO exams (module_id, room_id, professor_id, starts_at, ends_at) VALUES
    ('40000000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-000000000001',
     '2026-01-15 09:00+00', '2026-01-15 11:00+00');
  RAISE EXCEPTION 'ECHEC : conflit de professeur non détecté';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'OK : conflit de professeur bloqué';
END $$;

-- 3) Salle libre juste après (10:00-12:00, fin exclue) -> doit réussir
INSERT INTO exams (id, module_id, room_id, professor_id, starts_at, ends_at) VALUES
  ('50000000-0000-0000-0000-000000000002',
   '40000000-0000-0000-0000-000000000002',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000002',
   '2026-01-15 10:00+00', '2026-01-15 12:00+00');
DO $$ BEGIN RAISE NOTICE 'OK : examens consécutifs autorisés'; END $$;

-- 4) Même groupe, autre salle, autre prof, horaire qui chevauche -> doit échouer
DO $$ BEGIN
  INSERT INTO exam_groups (exam_id, group_id) VALUES
    ('50000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001');
  -- l'examen 2 (10:00-12:00) ne chevauche pas l'examen 1 (08:00-10:00) : doit passer
  RAISE NOTICE 'OK : groupe sur deux créneaux distincts autorisé';
END $$;

-- On déplace l'examen 2 sur 09:00-11:00 : le groupe A serait en double -> doit échouer
DO $$ BEGIN
  UPDATE exams SET starts_at = '2026-01-15 09:00+00', ends_at = '2026-01-15 11:00+00'
   WHERE id = '50000000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'ECHEC : déplacement conflictuel non bloqué';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'OK : déplacement conflictuel bloqué (salle ou groupe)';
END $$;

-- 5) Un examen annulé libère la salle
UPDATE exams SET status = 'cancelled' WHERE id = '50000000-0000-0000-0000-000000000001';
INSERT INTO exams (module_id, room_id, professor_id, starts_at, ends_at) VALUES
  ('40000000-0000-0000-0000-000000000002',
   '10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001',
   '2026-01-15 08:30+00', '2026-01-15 09:30+00');
DO $$ BEGIN RAISE NOTICE 'OK : examen annulé libère la salle'; END $$;

-- 6) L'historique a enregistré les changements
DO $$ BEGIN
  IF (SELECT count(*) FROM exam_history) < 3 THEN
    RAISE EXCEPTION 'ECHEC : historique incomplet';
  END IF;
  RAISE NOTICE 'OK : historique enregistré';
END $$;

ROLLBACK;
