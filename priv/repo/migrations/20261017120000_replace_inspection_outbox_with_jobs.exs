defmodule Bolognesa.Repo.Migrations.ReplaceInspectionOutboxWithJobs do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    DECLARE item record; cursor_id bigint := 0; last_id bigint; linked bigint;
    BEGIN
      LOOP
        last_id := cursor_id;
        FOR item IN
          SELECT e.*, i.id AS inspection_id, i.job_id, i.state AS inspection_state,
                 i.token AS current_token, i.observed_revision, f.revision, f.availability
          FROM media_inspection_events e
          LEFT JOIN media_inspections i ON i.media_file_id = e.media_file_id
          JOIN media_files f ON f.id = e.media_file_id
          WHERE e.id > cursor_id ORDER BY e.id LIMIT 100
        LOOP
          last_id := item.id;
          IF item.current_token IS DISTINCT FROM item.token OR item.observed_revision <> item.revision
             OR item.availability <> 'available' OR item.inspection_state NOT IN ('pending', 'running') THEN
            CONTINUE;
          END IF;
          IF item.job_id IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM oban_jobs WHERE id = item.job_id AND
              (worker <> 'Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker' OR
               args IS DISTINCT FROM jsonb_build_object('media_file_id', item.media_file_id, 'token', item.token::text))) THEN
              RAISE EXCEPTION 'Inspection request has a mismatched linked job';
            END IF;
            CONTINUE;
          END IF;
          SELECT id INTO linked FROM oban_jobs
          WHERE worker = 'Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker'
            AND args = jsonb_build_object('media_file_id', item.media_file_id, 'token', item.token::text)
          ORDER BY id DESC LIMIT 1;
          IF linked IS NULL AND item.delivered_at IS NULL THEN
            INSERT INTO oban_jobs (worker, queue, args, max_attempts)
            VALUES ('Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker', 'media_inspections',
              jsonb_build_object('media_file_id', item.media_file_id, 'token', item.token::text), 3)
            RETURNING id INTO linked;
          END IF;
          IF linked IS NULL THEN
            UPDATE media_inspections SET state = 'failed', failure_reason = 'unexpected_failure',
              finished_at = timezone('UTC', now()), updated_at = timezone('UTC', now())
            WHERE id = item.inspection_id;
          ELSE
            UPDATE media_inspections SET job_id = linked WHERE id = item.inspection_id;
          END IF;
        END LOOP;
        EXIT WHEN last_id = cursor_id;
        cursor_id := last_id;
      END LOOP;
      IF EXISTS (SELECT 1 FROM media_inspections i JOIN media_files f ON f.id = i.media_file_id
        WHERE i.state IN ('pending', 'running') AND i.job_id IS NULL
          AND f.availability = 'available' AND i.observed_revision = f.revision) THEN
        RAISE EXCEPTION 'Current inspection request has no legacy event or linked job';
      END IF;
      IF EXISTS (SELECT 1 FROM media_inspections i
        JOIN media_files f ON f.id=i.media_file_id JOIN oban_jobs j ON j.id=i.job_id
        WHERE i.state IN ('pending','running') AND f.availability='available'
          AND i.observed_revision=f.revision AND
          (j.worker <> 'Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker' OR
           j.args IS DISTINCT FROM jsonb_build_object('media_file_id',i.media_file_id,'token',i.token::text))) THEN
        RAISE EXCEPTION 'Current inspection request has a mismatched linked job';
      END IF;
    END $$;
    """

    drop table(:media_inspection_events)
  end

  def down do
    raise Ecto.MigrationError,
      message: "irreversible: restore the pre-migration database backup and matching release"
  end
end
