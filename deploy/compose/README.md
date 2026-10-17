# Linux deployment with Docker Compose

This deployment runs Bolognesa and PostgreSQL on a Linux server, with private HTTP access over LAN/Tailscale. The same commands work locally on the server or remotely from another machine over SSH. Do not open the port on your router or use public Internet access for this profile.

## Requirements

- Docker Engine and Docker Compose **2.24.4 or later** on the server. Overrides use [Compose file merge rules](https://docs.docker.com/reference/compose-file/merge/).
- `curl`, a POSIX shell, and `openssl` on the server; Bash and Make on the operator machine.
- For SSH: configured SSH keys and Docker group/access for the remote user. Neither Python nor jq is required on the server.
- For `deploy-release`: Git and authenticated `gh` on the operator machine, and GHCR pull access on the server.
- Existing multimedia directories readable by the container, which runs the application as `nobody`.

The port binds to loopback by default. To allow access from other devices, specify the private LAN or Tailscale IP in `BOLOGNESA_BIND_IP`. To listen on all interfaces via `0.0.0.0`, configure appropriate firewall filtering: Docker published ports can bypass regular UFW/firewalld rules ([Docker documentation](https://docs.docker.com/engine/install/ubuntu/#firewall-limitations)). HTTP does not encrypt credentials or application cookies; Tailscale protects traffic within its tunnel.

## Configuration and initial installation

From the repository root:

```sh
cp deploy/compose/deploy.env.example .env.deploy
chmod 600 .env.deploy
```

`.env.deploy` is operator Make configuration, not a shell script or the runtime `.env`. Use `VARIABLE=value` assignments without enclosing quotes. You can switch installations with `DEPLOY_CONFIG=/path/to/config`; Make command-line values take precedence.

Set `DEPLOY_TRANSPORT=local` to operate locally on the server, or `ssh` for a remote host. Over SSH, configure `DEPLOY_HOST=user@server.local`, `DEPLOY_DIR`, `DOCKER_BIN`, and `DEPLOY_HEALTH_URL`. The health URL must be reachable **from the server** and respond successfully after the app starts. Paths with spaces are supported. `DOCKER_BIN` must be an executable binary, not a command with arguments.

```sh
make deploy-init
```

This command distributes the selected recipes and scripts, prepares the directory, and generates secrets if `.env` does not already exist. It does not overwrite secrets on an existing installation. Edit `.env` **on the target server** before installing: `PHX_HOST`, `BOLOGNESA_BIND_IP`, `MEDIA_PATH`, image, and port. Secrets must remain private; generate them manually with `openssl rand -hex 64` for Phoenix and `openssl rand -hex 32` for PostgreSQL. The hexadecimal format avoids reserved characters in `DATABASE_URL`.

Preflight verifies storage budgets for images and backups: `DEPLOY_MIN_FREE_KIB` sets the minimum free space budget (default `262144`, 256 MiB). Adjust that budget to your actual database size; it does not guarantee every backup will fit. The PostgreSQL data directory can remain private and owned by PostgreSQL: the SSH operator user does not need to read it.

Keep `PUBLIC_PORT` and `BOLOGNESA_PORT` matching for direct HTTP. `PHX_HOST` is the hostname or IP accessed in the browser. If multiple private hostnames are used, `PHX_CHECK_ORIGIN=conn` permits those origins while preserving WebSocket validation; an empty value validates strictly against `PHX_HOST`.

```sh
make deploy-preflight
make deploy-install
```

Install requires that the PostgreSQL service for that project does not already exist. It pulls the image, waits for a healthy database, creates an initial backup, runs migrations, starts the application, and verifies HTTP health. Open `http://<PHX_HOST>:<PUBLIC_PORT>/setup` to create the initial administrator account. The TMDb token `TMDB_READ_TOKEN` is optional at boot and required for automatic work identification.

## Networking, persistence, and libraries

The base `compose.yaml` recipe uses a bridge network and a Docker volume. `DEPLOY_COMPOSE_FILES` allows appending override files **in order**, separated by `:`. Relative file paths are resolved relative to `deploy/compose/`; `DEPLOY_SOURCE_DIR` allows changing that base directory. Selected files are uploaded to the destination using their basenames, which must be unique. Do not use `:` inside filenames.

| Option | Files/configuration |
| --- | --- |
| Bridge + Docker volume | `DEPLOY_COMPOSE_FILES=compose.yaml`. The database does not publish ports. |
| Host networking | Append `network.host.yaml`. Configure `DB_PORT` and the Phoenix bind/port. PostgreSQL listens strictly on loopback. No `ports` mappings are used. |
| PostgreSQL host directory | Append `storage.bind.yaml` and set `POSTGRES_DATA_PATH` in `.env`. Create and verify that directory explicitly; it is not created automatically on mount. |
| Multiple media directories | Copy `media.example.yaml` to `media.local.yaml`, edit the mounts, and append that file. Keep all sources read-only and configure authorized internal roots. |

Operational example with host networking, directory database storage, and multiple media sources:

```make
DEPLOY_COMPOSE_FILES=compose.yaml:network.host.yaml:storage.bind.yaml:media.local.yaml
```

The media example mounts `/media/movies`, `/media/series`, and `/media/music`; set `MOVIES_PATH`, `SERIES_PATH`, and `MUSIC_PATH` in the server's `.env`. Add more sources or remove unused mounts and update the authorized roots accordingly. Register the **internal** paths in Libraries. `BOLOGNESA_LIBRARY_ROOTS` must match those mount targets, separated with `:`. Preserve existing library paths when adopting this setup; changing them can make their files inaccessible.

`COMPOSE_PROJECT_NAME` identifies containers and Docker volumes. Do not change its value when updating an existing installation: a different project name corresponds to a different project and separate data.

## Images and releases

`.github/workflows/container-image.yml` publishes to the repository's GHCR namespace in lowercase (`ghcr.io/avillen/bolognesa`). It is configured to publish a private multi-architecture HTTP image (`linux/amd64` and `linux/arm64`) with `latest-lan` and `sha-<commit>-lan` tags. The two builds run in parallel on native runners and assemble into a verified manifest; Docker selects the server's native architecture. Older HTTPS tags (`latest` / `sha-<commit>`) are no longer updated and retain their meaning.

Multi-architecture image publishing and private server deployment are verified. Anonymous queries to GHCR return HTTP 401: pulling this package currently requires authenticating Docker on the target host with package read permission (`read:packages`) or using an image from your own registry/local build. The maintainer can configure public package visibility to allow anonymous pulls. You can pin `BOLOGNESA_IMAGE` to an immutable digest or tag.

To deploy a release, ensure local checks pass (`mix precommit` and `make check-screenshots`) and the commit is pushed to `main` (`git push origin main`):

```sh
make deploy-release
# Or select the full SHA of a published commit on main:
make deploy-release COMMIT_SHA=<40-hex-characters>
```

Release monitors the `container-image.yml` GitHub Actions run for the requested commit on `main`, validates the run SHA, branch, and success conclusion, downloads the `server-image-ref` artifact, and deploys its verified HTTP digest. If repeated CI runs exist, select `DEPLOY_RUN_ID` explicitly; SHA and branch validation remains active. Workflow artifacts expire after 30 days. To deploy an already verified digest directly:

```sh
make deploy-update IMAGE_REF=ghcr.io/avillen/bolognesa@sha256:<digest>
```

For forks or alternative registries, set `IMAGE_REPOSITORY`; deploying with an explicit digest accepts the operator's chosen reference. `DEPLOY_WORKFLOW` and `DEPLOY_ARTIFACT` are configurable.

## Backup, update, and recovery

```sh
make deploy-backup
make deploy-update
make deploy-restore BACKUP_FILE=/path/on/server/backups/file.dump
```

Backups are saved in `<DEPLOY_DIR>/backups` unless `DEPLOY_BACKUP_DIR` is set. Store copies outside the server as well. Dumps are verified to be non-empty and readable by PostgreSQL before being saved with private file permissions.

Update requires an existing database. It pulls the image before stopping the app, waits for healthy database status, stops the app, creates a backup and records the previous image reference, applies migrations, recreates the app container, and verifies HTTP health. Only then does it persist the new image in the server's `.env`.

During HTTP verification, Phoenix may take several seconds to boot and bind the port. You may see transient connection errors on the console:
```text
curl: (7) Failed to connect to <host> port <port> after 0 ms: Couldn't connect to server
```
This is expected behavior. The verification script polls `DEPLOY_HEALTH_URL` up to `DEPLOY_HTTP_RETRIES` times (default `20`) with a `DEPLOY_WAIT_INTERVAL` delay (default `2` seconds) until the endpoint responds successfully or the 3-minute deadline expires.

If update fails before migrations begin, it attempts to restore the previous image. If it fails once migrations have started, it leaves the app stopped: inspect the database schema and backup before recovering. Rolling back to an older image does not revert applied migrations.

The PostgreSQL configuration is tracked in `.database-config`. Changes to that configuration, or updating an older installation without that file, block the update. After comparing the resolved Compose definition with actual storage, adopt the change explicitly:

```sh
make deploy-update ALLOW_DATABASE_CONFIG_CHANGE=yes EXPECTED_DATABASE_SOURCE=/path/to/postgres
```

For a Docker volume, `EXPECTED_DATABASE_SOURCE` is the existing volume name. This permission also covers intentional database resource/network changes; do not leave it enabled permanently. It does not replace verifying that the new recipe points to the same underlying data.

Restore verifies the dump, prompts the operator to type `RESTORE`, and replaces the database. The app remains stopped; select an image compatible with the restored schema before starting it. The direct script accepts `--yes` for automated workflows. Never use `down -v` to update or recover a live installation.

## One-time content-context rebuild

The release implementing [decision 0019](../../docs/decisions/0019-content-context-boundaries.md) requires a whole-database reset, including Oban jobs. The destructive migration does not preserve existing identities and refuses reversal. Do not activate it through an ordinary in-place update of a populated installation.

First verify the new release and image, record the current image, and prepare a validated backup with `make deploy-backup`. Keep that backup: the later update also creates a backup of the empty database, which cannot replace it. Stop the application and workers while keeping PostgreSQL running. Use the installation's existing project name, environment, complete Compose file set, data mount, and internal media paths throughout; never remove volumes or source directories.

From the deployment directory on the server, with `docker compose` configured for that installation, rebuild only its configured application database:

```sh
docker compose stop app
docker compose exec -T db sh -ec '
  dropdb --username "$POSTGRES_USER" --maintenance-db postgres --force "$POSTGRES_DB"
  createdb --username "$POSTGRES_USER" --owner "$POSTGRES_USER" "$POSTGRES_DB"
'
```

These commands discard accounts, sessions, library configuration, corrections, imported catalog data, and jobs. Source media is not changed. After the reset, run `make deploy-release COMMIT_SHA=<verified-main-sha>` from the operator checkout. Its normal backup, migration, startup, and health checks still apply. Verify `/setup`, create a new administrator, register sources using their existing internal paths, then scan and identify again.

If activation fails, leave the application stopped. Restore the pre-reset backup using the documented restore workflow and select the recorded old image; do not run the old image against the rebuilt schema.

## Local build and daily operation

```sh
make deploy-build DEPLOY_BUILD_PLATFORM=linux/arm64 DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-upload DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-update IMAGE_REF=bolognesa:lan
```

`deploy-upload` also loads the tar into Docker when `DEPLOY_IMAGE_TAR` is set. `DEPLOY_IMAGE_NAME` selects the exported tag, and `BUILD_DOCKER_BIN` sets the local Docker build binary (default `docker`). Image building occurs on the operator machine; Buildx and the capability to build the target platform are required. Do not pin the platform for the published multi-architecture image unless you intentionally want to force it.

```sh
make deploy-status
make deploy-logs
make deploy-console
make deploy-psql
make deploy-stop
```

The console connects to the running release container. `deploy-stop` preserves containers and data. To execute scripts directly on the server, configure `DEPLOY_DIR`, `DOCKER_BIN`, `COMPOSE_FILE`, and `DEPLOY_HEALTH_URL`, and run `scripts/operate.sh` with the desired operation.

## Configurable budgets

| Runtime variable | Default | Description |
| --- | --- | --- |
| `APP_MEMORY_LIMIT` / `APP_CPUS` | `1024m` / `2.0` | Application container resource limits. |
| `DB_MEMORY_LIMIT` / `DB_CPUS` | `256m` / `1.0` | Database container resource limits. |
| `TRANSCODE_TMPFS_SIZE` | `512m` | Tmpfs storage for FFmpeg transcoding. |
| `POOL_SIZE` | `10` | Database connection pool size. |
| `ERL_FLAGS` | Empty | Optional Erlang VM flags, e.g. `+S 2:2`. |
| `LOG_MAX_SIZE` / `LOG_MAX_FILES` | `10m` / `3` | Container log rotation size and count. |
| `DEPLOY_HTTP_RETRIES` | `20` | Number of HTTP health check retry attempts. |
| `DEPLOY_WAIT_INTERVAL` | `2` | Interval in seconds between health check retries. |

These are configurable initial budgets, not strict minimum requirements or benchmarked capacity. Container memory includes Phoenix, FFmpeg, and tmpfs; monitor usage and container restarts during real-world operation.

## Direct job migrations

The direct-job releases replace inspection, Music import, and video identification outboxes incrementally. Before applying each migration, stop all old application instances and workers and validate a pre-migration database backup with its matching image reference. Do not run old and new workers concurrently. Use the normal release process; no database reset or source rescan is required.

Migrations preserve current requests and linked jobs, backfill undelivered work in bounded batches, and then drop the corresponding event tables. Rehearse large backlogs to estimate the maintenance window: batches still run inside the overall migration transaction. Reversal is refused; restore the pre-migration backup with the matching old release to return to the prior schema. After startup, verify authenticated scanning, inspection and the content owner affected by that release.
