defmodule Bolognesa.Repo.Migrations.ReplaceMusicRefreshOutboxWithJobs do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    DECLARE item record; cursor_id bigint := 0; last_id bigint; linked bigint;
      previous_token uuid; job_state text; import_state text; failure text;
    BEGIN
      LOOP
        last_id := cursor_id;
        FOR item IN
          SELECT e.*, i.token AS current_token, i.observed_revision, i.state AS inspection_state,
                 i.tracks, f.revision AS current_revision, f.availability, l.content_type
          FROM music_refresh_events e JOIN media_files f ON f.id=e.media_file_id
          JOIN libraries l ON l.id=f.library_id
          LEFT JOIN media_inspections i ON i.media_file_id=f.id
          WHERE e.id > cursor_id ORDER BY e.id LIMIT 100
        LOOP
          last_id := item.id;
          IF item.content_type <> 'music' OR item.availability <> 'available'
            OR item.inspection_state IS DISTINCT FROM 'succeeded'
            OR item.current_token IS DISTINCT FROM item.inspection_token
            OR item.observed_revision <> item.current_revision OR item.revision <> item.current_revision
            OR NOT (item.tracks @> '{"items":[{"kind":"audio"}]}'::jsonb) THEN
            CONTINUE;
          END IF;
          SELECT inspection_token INTO previous_token FROM music_imports WHERE media_file_id=item.media_file_id;
          IF previous_token = item.inspection_token THEN CONTINUE; END IF;
          linked := item.job_id;
          IF linked IS NOT NULL AND EXISTS (SELECT 1 FROM oban_jobs WHERE id=linked AND
            (worker <> 'Bolognesa.Music.Infrastructure.Jobs.RefreshWorker' OR
             args IS DISTINCT FROM jsonb_build_object('file_id',item.media_file_id,'revision',item.revision))) THEN
            RAISE EXCEPTION 'Music request has a mismatched linked job';
          END IF;
          IF linked IS NULL AND item.delivered_at IS NULL THEN
            INSERT INTO oban_jobs(worker,queue,args,max_attempts)
            VALUES ('Bolognesa.Music.Infrastructure.Jobs.RefreshWorker','music_imports',
              jsonb_build_object('file_id',item.media_file_id,'revision',item.revision),3)
            RETURNING id INTO linked;
          END IF;
          SELECT state::text INTO job_state FROM oban_jobs WHERE id=linked;
          import_state := CASE WHEN job_state='executing' THEN 'running'
            WHEN job_state IN ('available','scheduled','retryable') THEN 'pending' ELSE 'failed' END;
          failure := CASE WHEN import_state <> 'failed' THEN NULL
            WHEN job_state='discarded' THEN 'attempts_exhausted' ELSE 'unexpected_failure' END;
          INSERT INTO music_imports(media_file_id,observed_revision,inspection_token,state,job_id,
            failure_reason,started_at,finished_at,inserted_at,updated_at)
          VALUES (item.media_file_id,item.revision,item.inspection_token,import_state,linked,failure,
            CASE WHEN import_state='running' THEN (SELECT attempted_at FROM oban_jobs WHERE id=linked) END,
            CASE WHEN import_state='failed' THEN timezone('UTC',now()) END,timezone('UTC',now()),timezone('UTC',now()))
          ON CONFLICT (media_file_id) DO UPDATE SET observed_revision=EXCLUDED.observed_revision,
            inspection_token=EXCLUDED.inspection_token,state=EXCLUDED.state,job_id=EXCLUDED.job_id,
            failure_reason=EXCLUDED.failure_reason,started_at=EXCLUDED.started_at,
            finished_at=EXCLUDED.finished_at,updated_at=EXCLUDED.updated_at;
        END LOOP;
        EXIT WHEN last_id=cursor_id;
        cursor_id := last_id;
      END LOOP;
    END $$;
    """

    drop table(:music_refresh_events)
  end

  def down do
    raise Ecto.MigrationError,
      message: "irreversible: restore the pre-migration database backup and matching release"
  end
end
