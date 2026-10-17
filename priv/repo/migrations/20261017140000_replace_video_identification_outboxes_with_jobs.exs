defmodule Bolognesa.Repo.Migrations.ReplaceVideoIdentificationOutboxesWithJobs do
  use Ecto.Migration

  def up do
    convert("movie", "Movies")
    convert("series", "Series")
    drop table(:movie_identification_events)
    drop table(:series_identification_events)
  end

  defp convert(type, owner) do
    execute """
    DO $$
    DECLARE item record; cursor_id bigint := 0; last_id bigint; linked bigint;
    BEGIN
      LOOP
        last_id := cursor_id;
        FOR item IN
          SELECT e.*, d.id AS decision_id, d.job_id, d.state AS decision_state,
            d.token AS current_token, d.observed_revision, d.origin,
            f.revision, f.availability, l.content_type
          FROM #{type}_identification_events e
          JOIN media_files f ON f.id=e.media_file_id JOIN libraries l ON l.id=f.library_id
          LEFT JOIN #{type}_identifications d ON d.media_file_id=e.media_file_id
          WHERE e.id > cursor_id ORDER BY e.id LIMIT 100
        LOOP
          last_id := item.id;
          IF item.content_type <> '#{type}' OR item.availability <> 'available'
            OR item.current_token IS DISTINCT FROM item.token OR item.observed_revision <> item.revision
            OR item.decision_state IS DISTINCT FROM 'pending' OR item.origin='manual' THEN
            CONTINUE;
          END IF;
          IF item.job_id IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM oban_jobs WHERE id=item.job_id AND
              (worker <> 'Bolognesa.#{owner}.Infrastructure.Jobs.IdentificationWorker' OR
               args IS DISTINCT FROM jsonb_build_object('file_id',item.media_file_id,'token',item.token::text))) THEN
              RAISE EXCEPTION 'Identification request has a mismatched linked job';
            END IF;
            CONTINUE;
          END IF;
          SELECT id INTO linked FROM oban_jobs
          WHERE worker='Bolognesa.#{owner}.Infrastructure.Jobs.IdentificationWorker'
            AND args=jsonb_build_object('file_id',item.media_file_id,'token',item.token::text)
          ORDER BY id DESC LIMIT 1;
          IF linked IS NULL AND item.delivered_at IS NULL THEN
            INSERT INTO oban_jobs(worker,queue,args,max_attempts)
            VALUES ('Bolognesa.#{owner}.Infrastructure.Jobs.IdentificationWorker','identifications',
              jsonb_build_object('file_id',item.media_file_id,'token',item.token::text),3)
            RETURNING id INTO linked;
          END IF;
          IF linked IS NULL THEN
            UPDATE #{type}_identifications SET state='failed', failure_reason='unexpected_failure',
              finished_at=timezone('UTC',now()),updated_at=timezone('UTC',now()) WHERE id=item.decision_id;
          ELSE
            UPDATE #{type}_identifications SET job_id=linked WHERE id=item.decision_id;
          END IF;
        END LOOP;
        EXIT WHEN last_id=cursor_id;
        cursor_id := last_id;
      END LOOP;
      IF EXISTS (SELECT 1 FROM #{type}_identifications d JOIN media_files f ON f.id=d.media_file_id
        JOIN libraries l ON l.id=f.library_id WHERE l.content_type='#{type}'
        AND d.state='pending' AND d.job_id IS NULL AND f.availability='available'
        AND d.observed_revision=f.revision) THEN
        RAISE EXCEPTION 'Current identification request has no legacy event or linked job';
      END IF;
      IF EXISTS (SELECT 1 FROM #{type}_identifications d
        JOIN media_files f ON f.id=d.media_file_id JOIN libraries l ON l.id=f.library_id
        JOIN oban_jobs j ON j.id=d.job_id
        WHERE l.content_type='#{type}' AND d.state='pending'
          AND f.availability='available' AND d.observed_revision=f.revision AND
          (j.worker <> 'Bolognesa.#{owner}.Infrastructure.Jobs.IdentificationWorker' OR
           j.args IS DISTINCT FROM jsonb_build_object('file_id',d.media_file_id,'token',d.token::text))) THEN
        RAISE EXCEPTION 'Current identification request has a mismatched linked job';
      END IF;
    END $$;
    """
  end

  def down do
    raise Ecto.MigrationError,
      message: "irreversible: restore the pre-migration database backup and matching release"
  end
end
