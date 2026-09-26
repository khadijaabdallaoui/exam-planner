-- Extension nécessaire pour les contraintes d'exclusion
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Intervalle de temps de chaque examen (colonne normale, remplie par un trigger)
ALTER TABLE exams ADD COLUMN during tstzrange;

CREATE OR REPLACE FUNCTION exams_fill_during() RETURNS trigger AS $$
BEGIN
  NEW.during := tstzrange(NEW."startsAt", NEW."endsAt", '[)');
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exams_fill_during_trg
  BEFORE INSERT OR UPDATE OF "startsAt", "endsAt" ON exams
  FOR EACH ROW EXECUTE FUNCTION exams_fill_during();

-- Une salle ne peut pas avoir deux examens qui se chevauchent
ALTER TABLE exams ADD CONSTRAINT exams_no_room_overlap
  EXCLUDE USING gist ("roomId" WITH =, during WITH &&)
  WHERE (status <> 'CANCELLED');

-- Un professeur ne peut pas être responsable de deux examens simultanés
ALTER TABLE exams ADD CONSTRAINT exams_no_professor_overlap
  EXCLUDE USING gist ("professorId" WITH =, during WITH &&)
  WHERE (status <> 'CANCELLED');

-- Colonnes synchronisées pour détecter les conflits de groupe
ALTER TABLE exam_groups ADD COLUMN during tstzrange;
ALTER TABLE exam_groups ADD COLUMN active boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION exam_groups_fill() RETURNS trigger AS $$
BEGIN
  SELECT e.during, e.status <> 'CANCELLED'
    INTO NEW.during, NEW.active
    FROM exams e WHERE e.id = NEW."examId";
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exam_groups_fill_trg
  BEFORE INSERT ON exam_groups
  FOR EACH ROW EXECUTE FUNCTION exam_groups_fill();

CREATE OR REPLACE FUNCTION exams_sync_groups() RETURNS trigger AS $$
BEGIN
  UPDATE exam_groups
     SET during = NEW.during,
         active = (NEW.status <> 'CANCELLED')
   WHERE "examId" = NEW.id;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER exams_sync_groups_trg
  AFTER UPDATE OF "startsAt", "endsAt", status ON exams
  FOR EACH ROW EXECUTE FUNCTION exams_sync_groups();

-- Un groupe ne peut pas avoir deux examens simultanés
ALTER TABLE exam_groups ADD CONSTRAINT exam_groups_no_group_overlap
  EXCLUDE USING gist ("groupId" WITH =, during WITH &&)
  WHERE (active);