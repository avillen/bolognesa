# Optional media automation

Add Sonarr (series), Radarr (movies) and Prowlarr (indexers) to an existing
[Bolognesa deployment](README.md). A download client runs separately; the examples
below use Transmission. Setup in each application's web interface is manual.
Bolognesa does not depend on these services or trigger rescans after their imports.

## Configure

1. Append `:media-automation.yaml` to `DEPLOY_COMPOSE_FILES` in the operator's
   `.env.deploy`. Keep the existing files and project name. For a base installation:

   ```make
   DEPLOY_COMPOSE_FILES=compose.yaml:media-automation.yaml
   ```

2. Add the following to the **server's private `.env`**. Replace the image version
   placeholders with published tags, or use immutable `@sha256:…` references.
   Choose images supporting your server architecture; see the LinuxServer
   [Sonarr](https://docs.linuxserver.io/images/docker-sonarr/),
   [Radarr](https://docs.linuxserver.io/images/docker-radarr/) and
   [Prowlarr](https://docs.linuxserver.io/images/docker-prowlarr/) image documentation.

   ```dotenv
   SONARR_IMAGE=lscr.io/linuxserver/sonarr:<version-tag>
   RADARR_IMAGE=lscr.io/linuxserver/radarr:<version-tag>
   PROWLARR_IMAGE=lscr.io/linuxserver/prowlarr:<version-tag>
   MEDIA_AUTOMATION_DATA_PATH=/srv/media-data
   MEDIA_AUTOMATION_CONFIG_PATH=/srv/bolognesa/media-config
   MEDIA_AUTOMATION_PUID=1000
   MEDIA_AUTOMATION_PGID=1000
   ```

   These paths and IDs are examples. Use a non-root media user and a group with
   access to downloads and final libraries. Coordinate permissions with the download
   client; the three services use umask `002`. Avoid recursive ownership changes
   to existing media.

3. Pre-create `sonarr`, `radarr` and `prowlarr` directories under
   `MEDIA_AUTOMATION_CONFIG_PATH`, writable by that UID/GID. Keep this directory
   private and outside the media tree: it stores databases, API keys and credentials.
   Docker rejects missing bind sources instead of creating directories automatically.

4. Set `MEDIA_AUTOMATION_DATA_PATH` to the existing common parent of downloads and
   final libraries. Sonarr and Radarr each mount it once at `/data`, for example:

   ```text
   /srv/media-data/       -> /data
     downloads/          -> /data/downloads
     movies/             -> /data/movies
     series/             -> /data/series
   ```

   Use your existing directory names. One common filesystem/mount allows hardlinks
   and avoids duplicating downloaded data; different shares or datasets may still
   prevent linking. Choose the narrowest usable parent. Bolognesa retains its existing
   read-only mounts and internal library paths; its final folders must refer to the
   same host directories. See [Servarr's storage guide](https://wiki.servarr.com/en/sonarr/installation/docker).

## Start and connect

```sh
make deploy-media-up
make deploy-media-status
```

`deploy-media-up` uploads the selected recipe, runs deployment preflight, pulls the
three images and starts only these services. It does not restart or migrate
Bolognesa/PostgreSQL. Container status alone does not verify setup or importing.

The panels bind to `127.0.0.1` by default: Sonarr on 8989, Radarr on 7878 and Prowlarr
on 9696. For an SSH deployment, forward them from the operator machine:

```sh
ssh -N -L 8989:127.0.0.1:8989 -L 7878:127.0.0.1:7878 -L 9696:127.0.0.1:9696 user@server.local
```

Open `http://localhost:8989`, `http://localhost:7878` and `http://localhost:9696`.
Alternatively, set `MEDIA_AUTOMATION_BIND_IP` to a private LAN/Tailscale interface.
Complete authentication setup in each panel; keep access within a trusted private
network. All three services use bridge networking even if Bolognesa uses host mode.

1. In Sonarr and Radarr, add and test the download client. Use an address reachable
   from their containers: `localhost` refers to the container itself. For a
   containerized client publishing RPC only on host loopback, attach Sonarr/Radarr
   to its existing Docker network through a private `*.local.yaml` override, keeping their `default` network
   for Prowlarr. Use a stable client alias accepted by its access rules.
2. If the client reports a different download path, configure **Remote Path Mapping**
   in both applications. For example, map its `/downloads/` to `/data/downloads/`.
   The host must match the download-client configuration. This translates paths;
   it does not mount or move files.
3. Set final roots to the existing `/data/series` and `/data/movies` equivalents.
   Use distinct download categories, enable hardlink imports, and leave completed
   download removal disabled while verifying continued seeding.
4. In Prowlarr, add your indexers and connect Sonarr at `http://sonarr:8989` and
   Radarr at `http://radarr:7878`, using their API keys. The Prowlarr URL visible to
   those apps is `http://prowlarr:9696`. Internal ports stay the same when published
   ports change. Prowlarr syncs indexers; download clients are configured separately.

Verify a controlled download, import, continued seeding and Bolognesa playback after
an explicit library scan. Compare device/inode numbers to confirm actual hardlinks.
Test the download-client connection again after changing upstream images.

## Operate and back up

```sh
make deploy-media-logs
make deploy-media-stop
```

These commands affect only the three optional services and preserve their data.
Ordinary Bolognesa releases do not update them; `deploy-stop` stops only Bolognesa
and PostgreSQL. Stop the optional services before removing their Compose override.

Before changing their images, stop them and privately back up all three configuration
directories, image references and private overrides. Keep a copy off the server.
Then use `deploy-media-up` to start/update them. For recovery, stop the services and
restore matching configurations and images: older images may not read upgraded
databases. Bolognesa's PostgreSQL backups do not include these service configurations.

Optional runtime settings: `MEDIA_AUTOMATION_TZ` (default `Etc/UTC`),
`SONARR_PORT`/`RADARR_PORT`/`PROWLARR_PORT`, and per-service `*_MEMORY_LIMIT`/`*_CPUS`
(default 512 MiB and one CPU each). Existing `LOG_MAX_SIZE`/`LOG_MAX_FILES` apply.
Resource defaults are initial budgets, not measured hardware requirements.
