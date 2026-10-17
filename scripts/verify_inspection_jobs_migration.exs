# MIX_ENV=test mix run --no-start scripts/verify_inspection_jobs_migration.exs
Code.require_file("direct_jobs_migration_check.exs", __DIR__)
Bolognesa.DirectJobsMigrationCheck.run(:inspection)
