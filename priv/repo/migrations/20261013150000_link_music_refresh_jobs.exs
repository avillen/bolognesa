defmodule Bolognesa.Repo.Migrations.LinkMusicRefreshJobs do
  use Ecto.Migration

  def up do
    alter table(:music_refresh_events), do: add(:job_id, :bigint)
  end

  def down do
    execute "DO $$ BEGIN IF EXISTS (SELECT 1 FROM libraries WHERE content_type = 'music') THEN RAISE EXCEPTION 'Remove music libraries explicitly before rollback'; END IF; END $$"
    alter table(:music_refresh_events), do: remove(:job_id)
  end
end
