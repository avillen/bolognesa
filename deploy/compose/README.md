# Linux deployment with Docker Compose

Run Bolognesa and PostgreSQL 17 on a private Linux server. **This LAN/HTTP profile must not be exposed directly to the public Internet.** Do not forward its port on your router. HTTP does not encrypt credentials or cookies; Tailscale protects traffic inside its tunnel.

For your own development machine, use the [local quick start](../../README.md#try-it-with-docker). It uses development credentials; this server profile generates secrets and provides backup/update safeguards.

## Requirements

- Docker Engine and Compose 2.24.4+ on the server.
- `curl`, `openssl`, and a POSIX shell on the server; Bash and Make on the operator machine.
- Media folders readable by the app container's `nobody` user.
- For remote operation: SSH keys and Docker access for the remote user.
- For published releases: Git and authenticated `gh` on the operator machine, plus image pull access on the server.

## First installation

Run from the repository root of the version you intend to install.

### 1. Choose the server

```sh
make help
cp deploy/compose/deploy.env.example .env.deploy
chmod 600 .env.deploy
```

Edit `.env.deploy`: use `DEPLOY_TRANSPORT=local` to operate on this machine, or `ssh` with `DEPLOY_HOST=user@server.local` for a remote server. Set `DEPLOY_DIR` to the installation directory and `DEPLOY_HEALTH_URL` to a URL reachable from the server.

This file configures Make, not the application. Use unquoted `VARIABLE=value` assignments. `DEPLOY_CONFIG=/path/to/config` selects another installation; command-line values take precedence. `DOCKER_BIN` must name an executable, not a command with arguments.

### 2. Prepare configuration

```sh
make deploy-init
```

This copies the recipe and scripts and creates private runtime `.env` secrets on the target server. Existing secrets are preserved. Edit that server's `.env`:

| Setting | What to enter |
| --- | --- |
| `PHX_HOST` | Private hostname/IP used in the browser. |
| `BOLOGNESA_BIND_IP` | Keep `127.0.0.1`, or choose the private LAN/Tailscale interface. |
| `BOLOGNESA_PORT`, `PUBLIC_PORT` | The same web port, normally `4000`. |
| `MEDIA_PATH` | An existing, readable host media folder. |
| `BOLOGNESA_IMAGE` | The image/tag/digest to install. |
| `TMDB_READ_TOKEN` | Needed for movie/series identification; optional for startup and music. |

Keep configuration private. If generating secrets yourself, use `openssl rand -hex 64` for `SECRET_KEY_BASE` and `openssl rand -hex 32` for `POSTGRES_PASSWORD`.

Avoid binding to `0.0.0.0` unless you have appropriate firewall filtering: [Docker published ports can bypass UFW/firewalld rules](https://docs.docker.com/engine/install/ubuntu/#firewall-limitations). Set `PHX_CHECK_ORIGIN=conn` only when intentionally using multiple private hostnames; otherwise leave it empty.

### 3. Make the image available

The default `ghcr.io/avillen/bolognesa:latest-lan` currently requires authentication. On the server, authenticate Docker to GHCR with package read permission (`read:packages`), or use the [local build path](#local-build-and-daily-operation). Prefer a commit tag or digest for controlled updates.

### 4. Install and open the app

```sh
make deploy-preflight
make deploy-install
```

Install expects a new project without an existing PostgreSQL service. It obtains the image, waits for the database, makes an initial backup, migrates, starts the app, and checks HTTP health.

Open `http://<PHX_HOST>:<PUBLIC_PORT>/setup`, create the administrator, then add a library and scan it. Use **container paths**: the default mount is `/media`. For problems, run `make deploy-status` and `make deploy-logs`.

Preflight checks a configurable free-space budget (`DEPLOY_MIN_FREE_KIB`, default 256 MiB); increase it for your database and images. It is not a guarantee that every backup will fit.

## Backup, update, and recovery

**0.x releases do not guarantee database/application compatibility.** Read the target release's migration notes before updating. PostgreSQL 17 is used by Compose and CI; other major versions are unverified. These scripts do not upgrade PostgreSQL major versions. Never reuse an existing data directory with a different major-version image.

```sh
make deploy-backup
make deploy-update IMAGE_REF=ghcr.io/avillen/bolognesa@sha256:<digest>
make deploy-restore BACKUP_FILE=/path/on/server/backups/file.dump
```

Keep backups outside the server, with the matching application image and private configuration. Dumps include accounts, libraries, corrections, metadata, and jobs. They exclude media and configuration; back those up separately. Backups default to `<DEPLOY_DIR>/backups` (`DEPLOY_BACKUP_DIR` overrides it), use private permissions, and are checked with `pg_restore --list`. Rehearse a full restore on a disposable installation.

Update obtains the image, stops the app, backs up the database and records the old image, migrates, starts the app, and checks HTTP before saving the new image reference. Transient connection errors are normal while Phoenix starts.

If failure occurs before migrations, update attempts to restore the old image. Once migrations start, failure leaves the app stopped. An older image does not undo migrations: inspect the schema and backup before recovery.

Restore asks you to type `RESTORE`, replaces the database, and leaves the app stopped. Select a schema-compatible image before restarting. The direct restore script accepts `--yes` for automation. Never use `down -v` to update or recover a live installation.

Preserve `COMPOSE_PROJECT_NAME`, database storage, and internal library paths. Changed database configuration blocks updates through `.database-config`. After verifying the resolved recipe points to the intended data, explicitly adopt a change:

```sh
make deploy-update ALLOW_DATABASE_CONFIG_CHANGE=yes EXPECTED_DATABASE_SOURCE=/path/to/postgres
```

For Docker volumes, use the existing volume name instead of a path. Do not leave this override enabled.

## Images and releases

The image workflow publishes HTTP images for `linux/amd64` and `linux/arm64`, tagged `latest-lan` and `sha-<commit>-lan`. Docker selects the native architecture. Older HTTPS tags are no longer updated.

For a published commit on `main`, after local checks and CI:

```sh
make deploy-release
# Or select a published main commit:
make deploy-release COMMIT_SHA=<40-hex-characters>
```

This verifies the image workflow's commit, branch, success, and digest artifact before deployment. Artifacts expire after 30 days; an already verified digest can be used with `deploy-update`. Select `DEPLOY_RUN_ID` if repeated workflow runs need disambiguation. Forks can set `IMAGE_REPOSITORY`, `DEPLOY_WORKFLOW`, and `DEPLOY_ARTIFACT`.

## Local build and daily operation

To avoid the private GHCR package, build an HTTP image on the operator machine and load it on the server. Select the server's architecture; cross-building may need emulation. For ARM64:

```sh
make deploy-build DEPLOY_BUILD_PLATFORM=linux/arm64 DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-upload DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-install IMAGE_REF=bolognesa:lan
# For an existing installation, use deploy-update instead of deploy-install.
```

`DEPLOY_IMAGE_NAME` changes the exported tag; `BUILD_DOCKER_BIN` selects the build binary. Use this build command: HTTP must be enabled at compile time, not just by setting a runtime variable on an arbitrary image.

```sh
make deploy-status
make deploy-logs
make deploy-console
make deploy-psql
make deploy-stop
```

Stop preserves data. Direct server operations use `scripts/operate.sh` with the installation's `DEPLOY_DIR`, `DOCKER_BIN`, `COMPOSE_FILE`, and `DEPLOY_HEALTH_URL`.

## Networking, persistence, and libraries

The default recipe uses bridge networking and a Docker database volume, without publishing PostgreSQL. Append overrides to `DEPLOY_COMPOSE_FILES`, separated by `:`, in order:

| Need | Override/configuration |
| --- | --- |
| Host networking | `network.host.yaml`; set `DB_PORT` and the app port. PostgreSQL stays on loopback. |
| Database host directory | `storage.bind.yaml`; set `POSTGRES_DATA_PATH` and create it first. |
| Separate movie/series/music folders | Copy `media.example.yaml` to `media.local.yaml`, edit mounts, and set `MOVIES_PATH`, `SERIES_PATH`, `MUSIC_PATH`. |

For example:

```make
DEPLOY_COMPOSE_FILES=compose.yaml:network.host.yaml:storage.bind.yaml:media.local.yaml
```

Keep media read-only. `BOLOGNESA_LIBRARY_ROOTS` must list authorized internal mount paths separated by `:`; register those same paths in Libraries. Preserve existing paths during updates.

File paths are relative to `deploy/compose/` unless `DEPLOY_SOURCE_DIR` changes that base. Uploaded files must have distinct basenames; do not use `:` in filenames. Paths with spaces are supported.

## Optional services and budgets

[Monitoring](monitoring.md) and [Sonarr/Radarr/Prowlarr](media-automation.md) are opt-in, with their own setup instructions. The base installation needs neither. Media automation uses separate commands and does not change Bolognesa's manual rescan behavior.

Runtime budgets are configurable in the server `.env`: app `1024m`/2 CPUs, database `256m`/1 CPU, transcode tmpfs `512m`, and connection pool `10`. These are defaults, not measured minimum requirements. Watch memory, restarts, and actual workload. `ERL_FLAGS` can constrain the VM; `LOG_MAX_SIZE`/`LOG_MAX_FILES` default to `10m`/3. HTTP health checks default to 20 retries at two-second intervals (`DEPLOY_HTTP_RETRIES`, `DEPLOY_WAIT_INTERVAL`), with a three-minute deadline.

## Direct job migrations

These replace inspection, music import, and video identification outboxes. Stop all old app instances/workers and validate a backup with its matching image before migrating; never mix old and new workers. No reset or rescan is required.

Migrations preserve requests/jobs, backfill pending work, and drop obsolete tables. Batches still share one transaction; large-backlog maintenance time is unmeasured. Reversal is refused: returning to the old schema requires the pre-migration backup and old image. After startup, check scanning, inspection, and the affected catalog.
