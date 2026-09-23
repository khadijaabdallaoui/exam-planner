-- =====================================================================
-- Exam Planning & Room Booking : schema PostgreSQL (14+)
-- Objectif : empêcher les conflits AU NIVEAU DE LA BASE, pas seulement
-- dans le code applicatif.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;  -- nécessaire pour EXCLUDE avec = et &&

-- ---------- Types ----------
CREATE TYPE user_role    AS ENUM ('admin', 'scolarite', 'professeur', 'etudiant');
CREATE TYPE exam_status  AS ENUM ('planned', 'confirmed', 'cancelled');
CREATE TYPE session_type AS ENUM ('normale', 'rattrapage');

-- ---------- Référentiel ----------
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  full_name     text NOT NULL,
  role          user_role NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rooms (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL UNIQUE,             -- ex: "Amphi 1"
  building   text,
  capacity   integer NOT NULL CHECK (capacity > 0),
  equipment  text[] NOT NULL DEFAULT '{}',
  is_active  boolean NOT NULL DEFAULT true
);

CREATE TABLE filieres (
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name  text NOT NULL,
  level text NOT NULL,                          -- ex: "S3"
  UNIQUE (name, level)
);

CREATE TABLE groups (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  filiere_id    uuid NOT NULL REFERENCES filieres(id),
  name          text NOT NULL,                  -- ex: "Groupe A"
  student_count integer NOT NULL CHECK (student_count >= 0),
  UNIQUE (filiere_id, name)
);

CREATE TABLE student_groups (
  user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  group_id uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, group_id)
);

CREATE TABLE modules (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,
  name       text NOT NULL,
  filiere_id uuid NOT NULL REFERENCES filieres(id)
);

-- ---------- Examens ----------
CREATE TABLE exams (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_id    uuid NOT NULL REFERENCES modules(id),
  session_type session_type NOT NULL DEFAULT 'normale',
  room_id      uuid NOT NULL REFERENCES rooms(id),
  professor_id uuid NOT NULL REFERENCES users(id),
  starts_at    timestamptz NOT NULL,
  ends_at      timestamptz NOT NULL,
  status       exam_status NOT NULL DEFAULT 'planned',
  -- intervalle calculé automatiquement : [début, fin[ (la fin est exclue,
  -- donc un examen 08:00-10:00 et un autre 10:00-12:00 ne sont PAS en conflit)
  during       tstzrange GENERATED ALWAYS AS (tstzrange(starts_at, ends_at, '[)')) STORED,
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT exams_valid_time CHECK (ends_at > starts_at),

  -- Une salle ne peut pas avoir deux examens qui se chevauchent
  CONSTRAINT exams_no_room_overlap
    EXCLUDE USING gist (room_id WITH =, during WITH &&)
    WHERE (status <> 'cancelled'),

  -- Un professeur ne peut pas être responsable de deux examens simultanés
  CONSTRAINT exams_no_professor_overlap
    EXCLUDE USING gist (professor_id WITH =, during WITH &&)
    WHERE (status <> 'cancelled')
);

CREATE INDEX exams_starts_at_idx ON exams (starts_at);

-- Groupes concernés par un examen.
-- `during` et `active` sont des copies synchronisées par trigger : PostgreSQL
-- ne peut pas écrire une contrainte d'exclusion à travers une jointure.
CREATE TABLE exam_groups (
  exam_id  uuid NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
  group_id uuid NOT NULL REFERENCES groups(id),
  during   tstzrange NOT NULL,
  active   boolean NOT NULL DEFAULT true,
  PRIMARY KEY (exam_id, group_id),

  -- Un groupe ne peut pas avoir deux examens simultanés
  CONSTRAINT exam_groups_no_group_overlap
    EXCLUDE USING gist (group_id WITH =, during WITH &&)
    WHERE (active)
);

CREATE INDEX exam_groups_group_idx ON exam_groups (group_id);

CREATE FUNCTION exam_groups_fill() RETURNS trigger AS $$
BEGIN
  SELECT e.during, e.status <> 'cancelled'
    INTO NEW.during, NEW.active
    FROM exams e WHERE e.id = NEW.exam_id;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exam_groups_fill_trg
  BEFORE INSERT ON exam_groups
  FOR EACH ROW EXECUTE FUNCTION exam_groups_fill();

CREATE FUNCTION exams_sync_groups() RETURNS trigger AS $$
BEGIN
  UPDATE exam_groups
     SET during = NEW.during,
         active = (NEW.status <> 'cancelled')
   WHERE exam_id = NEW.id;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exams_sync_groups_trg
  AFTER UPDATE OF starts_at, ends_at, status ON exams
  FOR EACH ROW EXECUTE FUNCTION exams_sync_groups();

-- ---------- Historique (qui a changé quoi, et quand) ----------
CREATE TABLE exam_history (
  id          bigserial PRIMARY KEY,
  exam_id     uuid NOT NULL REFERENCES exams(id),
  actor_id    uuid REFERENCES users(id),
  action      text NOT NULL,                    -- INSERT | UPDATE
  before_data jsonb,
  after_data  jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX exam_history_exam_idx ON exam_history (exam_id, created_at DESC);

-- L'API doit exécuter, au début de chaque transaction :
--   SELECT set_config('app.user_id', '<uuid de l''utilisateur>', true);
CREATE FUNCTION exams_log_change() RETURNS trigger AS $$
BEGIN
  INSERT INTO exam_history (exam_id, actor_id, action, before_data, after_data)
  VALUES (
    NEW.id,
    NULLIF(current_setting('app.user_id', true), '')::uuid,
    TG_OP,
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END,
    to_jsonb(NEW)
  );
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exams_log_change_trg
  AFTER INSERT OR UPDATE ON exams
  FOR EACH ROW EXECUTE FUNCTION exams_log_change();

-- ---------- Notifications ----------
CREATE TABLE notifications (
  id         bigserial PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exam_id    uuid REFERENCES exams(id) ON DELETE SET NULL,
  message    text NOT NULL,
  channel    text NOT NULL DEFAULT 'in_app',    -- in_app | email | (whatsapp/telegram plus tard)
  sent_at    timestamptz,
  read_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);
