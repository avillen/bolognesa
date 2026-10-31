# Linux deployment with Docker Compose

Run Bolognesa and PostgreSQL 17 on a private Linux server. **This LAN/HTTP profile must not be exposed directly to the public Internet.** Do not forward its port on your router. HTTP does not encrypt credentials or cookies; Tailscale protects traffic inside its tunnel.

For your own development machine, use the [local quick start](../../README.md#try-it-with-docker). It uses development credentials; this server profile generates secrets and provides backup/update safeguards.

## Requirements

- Docker Engine and Compose 2.24.4+ on the server.
- `curl`, `openssl`, and a POSIX shell on the server; Bash and Make on the operator machine.
- Media folders readable by the app container's `nobody` user.
- For remote operation: SSH keys and Docker access for the remote user.
- Git on the operator machine. The maintainer's `deploy-release` command also needs authenticated `gh`; installing a public image by digest does not.

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

The published `ghcr.io/avillen/bolognesa` images can be pulled anonymously. No GitHub login or maintainer credentials are needed. The default `latest-lan` tag follows published `main` builds; prefer a commit tag or immutable digest for controlled installations. The [source-build path](#build-from-release-source) is an alternative to downloading the application image.

For the first experimental preview, set `BOLOGNESA_IMAGE=ghcr.io/avillen/bolognesa:v0.1.0` in the server's `.env`. For an immutable installation, use the `ghcr.io/avillen/bolognesa@sha256:<digest>` reference recorded in the [release notes](https://github.com/avillen/bolognesa/releases/tag/v0.1.0). The image and source tag `v0.1.0` identify the same commit; distribution evidence is recorded in [#13](https://github.com/avillen/bolognesa/issues/13).

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

The scripts retain the **three most recent managed backups** by modification time.
Set `DEPLOY_BACKUP_KEEP` to a positive integer in the operator's `.env.deploy` to
change this limit. Standalone backups prune only after the new dump passes validation;
updates prune after successful migration and HTTP verification. Failed updates retain
their backups. The backup created by the current operation is always kept.

Installing these scripts applies this policy to existing backups on the next successful
backup or update. Pruning removes only generated `pre-migration-*.dump` files with the
expected timestamp name (with or without the process ID used by newer scripts) and
their matching `.image-ref` files. Other files,
temporary dumps, and symbolic links are left alone. To preview a cleanup on the server:

```sh
DEPLOY_BACKUP_KEEP=3 sh /srv/bolognesa/scripts/prune-backups.sh --dry-run /srv/bolognesa/backups
```

Use the installation's actual script and backup directories. Review the preview and
the retained recovery copies before running the same command without `--dry-run`.

Backup, update and cleanup share a lock in the backup directory. An overlapping
operation fails before changing backups; retry when the first operation finishes.
If an interrupted process leaves `.bolognesa-backup.lock` behind, verify that no backup
or update is still running before removing that lock directory and its `owner` file.

Update obtains the image, stops the app, backs up the database and records the old image, migrates, starts the app, and checks HTTP before saving the new image reference. Transient connection errors are normal while Phoenix starts.

If failure occurs before migrations, update attempts to restore the old image. Once migrations start, failure leaves the app stopped. An older image does not undo migrations: inspect the schema and backup before recovery.

Restore asks you to type `RESTORE`, replaces the database, and leaves the app stopped. Select a schema-compatible image before restarting. The direct restore script accepts `--yes` for automation. Never use `down -v` to update or recover a live installation.

Preserve `COMPOSE_PROJECT_NAME`, database storage, and internal library paths. Changed database configuration blocks updates through `.database-config`. After verifying the resolved recipe points to the intended data, explicitly adopt a change:

```sh
make deploy-update ALLOW_DATABASE_CONFIG_CHANGE=yes EXPECTED_DATABASE_SOURCE=/path/to/postgres
```

For Docker volumes, use the existing volume name instead of a path. Do not leave this override enabled.

## Images and releases

The image workflow publishes HTTP images for `linux/amd64` and `linux/arm64`, tagged `latest-lan` and `sha-<commit>-lan`. Docker selects the native architecture. Historical HTTPS tags (`latest` and `sha-<commit>`) were removed during preparation for public distribution; do not reuse them for these HTTP builds.

### Versioned public distribution

The first release pairs source tag `v0.1.0` with image tag `ghcr.io/avillen/bolognesa:v0.1.0`. Both select the same source commit. This versioned image uses the private LAN/HTTP build, despite having no `-lan` suffix. Existing `latest-lan` and `sha-<commit>-lan` tags keep their LAN/HTTP meaning; historical `latest` and `sha-<commit>` tags retain their HTTPS meaning. A release tag must not be reassigned to a different image. Install by the recorded digest to avoid mutable-tag ambiguity.

The existing workflow can supply the release image without workflow changes. After the final release commit is selected in #14, the maintainer must:

1. Verify a successful `container-image.yml` run on `main` for that exact commit, including both native build jobs and the publish job. Download its `server-image-ref` artifact before its 30-day expiry; check `variant=lan`, the full commit SHA, and the repository/digest. Preserve this evidence in #13 and the release notes.
2. Inspect that digest with `docker buildx imagetools inspect --raw ghcr.io/avillen/bolognesa@sha256:<digest>`. Require exactly `linux/amd64` and `linux/arm64` in the manifest. Native build and manifest evidence does not establish runtime or playback compatibility on both architectures; state the environments actually tested separately.
3. After explicit image-publication approval, add `v0.1.0` to that verified manifest using `docker buildx imagetools create -t ghcr.io/avillen/bolognesa:v0.1.0 ghcr.io/avillen/bolognesa@sha256:<digest>`. Verify that the version tag resolves to the same digest and platforms. This leaves the existing rolling and commit tags in place.
4. For a package that is still private, inspect the retained images for private files and embedded credentials before changing visibility. Either review every existing package version or, with explicit deletion approval, remove obsolete versions first. Preserve the selected multi-architecture manifest and both referenced platform manifests, including those without tags. Keep a private recovery copy of any image needed by an existing installation before deleting its registry version. Removing a tag alone does not remove a version. Obtain separate approval for the visibility change, then apply it through GitHub's package settings. GitHub does not allow a public package to become private again. The upstream package has completed this visibility preparation; inspect any new release image before promoting it.
5. Verify anonymous access on a disposable Docker daemon with an empty credential configuration, as below. Record the command results, tag, immutable digest, source commit, and workflow URL in #13. Publish the corresponding source tag and release only under #14's separate authorization.

For the anonymous check, replace the digest with the release manifest digest. Run on a disposable daemon because these commands download both platform images. The temporary client configuration prevents use of saved registry credentials:

```sh
image=ghcr.io/avillen/bolognesa
digest='sha256:<digest>'
anonymous_config=$(mktemp -d)
trap 'rm -rf "$anonymous_config"' EXIT
printf '%s\n' '{"auths":{"ghcr.io":{}},"credHelpers":{}}' > "$anonymous_config/config.json"
DOCKER_CONFIG="$anonymous_config" docker manifest inspect "$image:v0.1.0"
DOCKER_CONFIG="$anonymous_config" docker manifest inspect "$image@$digest"
DOCKER_CONFIG="$anonymous_config" docker pull --platform linux/amd64 "$image@$digest"
DOCKER_CONFIG="$anonymous_config" docker pull --platform linux/arm64 "$image@$digest"
```

These pulls verify anonymous distribution, not execution on the target hardware. External testers install with the recorded digest through the first-installation steps above; no GitHub login or maintainer token is needed once this check passes.

### Deploy a verified main image

For a published commit on `main`, after local checks and CI:

```sh
make deploy-release
# Or select a published main commit:
make deploy-release COMMIT_SHA=<40-hex-characters>
```

This verifies the image workflow's commit, branch, success, and digest artifact before deployment. Artifacts expire after 30 days; an already verified digest can be used with `deploy-update`. Select `DEPLOY_RUN_ID` if repeated workflow runs need disambiguation. Forks can set `IMAGE_REPOSITORY`, `DEPLOY_WORKFLOW`, and `DEPLOY_ARTIFACT`.

## Local build and daily operation

Build an HTTP image on the operator machine and load it on the server. Select the server's architecture; cross-building may need emulation. For ARM64:

```sh
make deploy-build DEPLOY_BUILD_PLATFORM=linux/arm64 DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-upload DEPLOY_IMAGE_TAR=/tmp/bolognesa-image.tar
make deploy-install IMAGE_REF=bolognesa:lan
# For an existing installation, use deploy-update instead of deploy-install.
```

`DEPLOY_IMAGE_NAME` changes the exported tag; `BUILD_DOCKER_BIN` selects the build binary. Use this build command: HTTP must be enabled at compile time, not just by setting a runtime variable on an arbitrary image.

### Build from release source

Start with a fresh checkout of source tag `v0.1.0` and confirm its commit matches the release notes:

```sh
git clone --branch v0.1.0 --depth 1 https://github.com/avillen/bolognesa.git bolognesa-v0.1.0
cd bolognesa-v0.1.0
git rev-parse HEAD
```

Follow first-installation steps 1 and 2, then build and install for your server's architecture. This example uses AMD64; use `linux/arm64` for ARM64:

```sh
make deploy-build DEPLOY_BUILD_PLATFORM=linux/amd64 DEPLOY_IMAGE_NAME=bolognesa:v0.1.0 DEPLOY_IMAGE_TAR=/tmp/bolognesa-v0.1.0.tar
make deploy-upload DEPLOY_IMAGE_TAR=/tmp/bolognesa-v0.1.0.tar
make deploy-install IMAGE_REF=bolognesa:v0.1.0
```

The source build does not require GHCR credentials; it downloads public base images, operating-system packages, and application dependencies. It reproduces the build procedure from the release source, not a guaranteed byte-identical image: base tags and package repositories can change. The published digest identifies the exact distributed image.

### Daily operation

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
