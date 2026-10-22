# 0022. Optional application log forwarding to Loki

Status: Implemented and activated on the opted-in Compose installation; Alloy sent log entries to Grafana Cloud with no retries or drops observed.

## Context

Docker's rotated application logs provide local diagnostics. An operator wants remote
log search in Grafana Cloud, while ordinary Bolognesa installations must remain
independent of Grafana, Loki, Alloy, and external credentials.

## Decision

- Add a separate `monitoring.loki.yaml` opt-in Compose override. Selecting it is the
  only way to add a log collector or require Loki credentials.
- Run a dedicated Alloy service for logs. It reads only the application container,
  selected by an explicit Compose label; it does not collect PostgreSQL, metrics Alloy,
  host logs, or media files.
- Give only this optional service a read-only bind mount of Docker's socket. A
  read-only socket mount still grants broad Docker daemon control, so operators must
  explicitly choose this integration on a trusted host.
- Send logs to a configured Loki push endpoint with a stack-scoped `logs:write` token.
  Apply only stable `service` and `instance` labels; keep event identifiers and other
  log fields in the log body.
- Persist Docker read positions in a dedicated volume. Do not enable Loki's experimental
  Alloy WAL; remote log delivery remains best effort. Retain local Docker log rotation
  and keep collector lifecycle separate from application releases.

## Consequences

Loki credentials and the Docker socket are unnecessary unless the override is selected.
Remote retention, network use, and account limits follow the selected Grafana Cloud
plan. Docker log rotation bounds how far back a new collector can read. The bounded
Alloy delivery is best effort and does not guarantee lossless delivery. See the
[operator guide](../../deploy/compose/monitoring.md#optional-application-logs-with-loki).
