<p align="center"><img src="priv/static/images/bolognesa-cat.svg" alt="Boloñesa cat icon" width="88"></p>

<h1 align="center">Boloñesa</h1>

Boloñesa is a self-hosted media center for movies, TV series, and local music, built with Elixir and Phoenix. It is named after my cat and started as a way to learn Elixir while building something useful at home.

**This is an experimental project.** Expect bugs, limited browser compatibility, and breaking changes. See the [changelog](CHANGELOG.md) for release notes.

## What you can do

- Add media folders, scan their files, and browse each library. Original files stay untouched.
- Identify movies and series with TMDb, review matches, and correct mistakes.
- Play movies and episodes, choose file versions, and continue to the next episode or numbered part.
- Browse local tracks, artists, and albums. Play individual songs or an album in order.

## Screenshots

[![Movie library](docs/screenshots/library.png)](docs/screenshots/library.png)

<details>
  <summary>Explore screenshots of every screen</summary>

  **Getting started**

  | First-run setup | Sign in | Home |
  | --- | --- | --- |
  | [<img src="docs/screenshots/setup.png" alt="First-run administrator setup screen" width="260">](docs/screenshots/setup.png) | [<img src="docs/screenshots/login.png" alt="Sign-in screen" width="260">](docs/screenshots/login.png) | [<img src="docs/screenshots/home.png" alt="Home screen" width="260">](docs/screenshots/home.png) |

  **Libraries and movies**

  | Libraries | Movie library | Movie review | Movie details | Player |
  | --- | --- | --- | --- | --- |
  | [<img src="docs/screenshots/libraries.png" alt="Libraries screen" width="190">](docs/screenshots/libraries.png) | [<img src="docs/screenshots/library.png" alt="Movie library" width="190">](docs/screenshots/library.png) | [<img src="docs/screenshots/movie-review.png" alt="Movie identification review screen" width="190">](docs/screenshots/movie-review.png) | [<img src="docs/screenshots/movie.png" alt="Movie details screen" width="190">](docs/screenshots/movie.png) | [<img src="docs/screenshots/player.png" alt="Video player screen" width="190">](docs/screenshots/player.png) |

  **Series**

  | Series library | Series review | Series details | Season | Episode |
  | --- | --- | --- | --- | --- |
  | [<img src="docs/screenshots/series.png" alt="Series library screen" width="190">](docs/screenshots/series.png) | [<img src="docs/screenshots/series-review.png" alt="Series identification review screen" width="190">](docs/screenshots/series-review.png) | [<img src="docs/screenshots/series-detail.png" alt="Series details screen" width="190">](docs/screenshots/series-detail.png) | [<img src="docs/screenshots/season.png" alt="Season screen" width="190">](docs/screenshots/season.png) | [<img src="docs/screenshots/episode.png" alt="Episode details screen" width="190">](docs/screenshots/episode.png) |

  | Mobile catalog | Mobile series | Mobile season | Mobile episode |
  | --- | --- | --- | --- |
  | [<img src="docs/screenshots/series-mobile.png" alt="Mobile series catalog" width="160">](docs/screenshots/series-mobile.png) | [<img src="docs/screenshots/series-detail-mobile.png" alt="Mobile series details" width="160">](docs/screenshots/series-detail-mobile.png) | [<img src="docs/screenshots/season-mobile.png" alt="Mobile episode list" width="160">](docs/screenshots/season-mobile.png) | [<img src="docs/screenshots/episode-mobile.png" alt="Mobile episode player" width="160">](docs/screenshots/episode-mobile.png) |

  **Music**

  | Music library | Music player |
  | --- | --- |
  | [<img src="docs/screenshots/music.png" alt="Local music library" width="260">](docs/screenshots/music.png) | [<img src="docs/screenshots/music-player.png" alt="Audio player" width="260">](docs/screenshots/music-player.png) |

  **Account**

  | Settings | About |
  | --- | --- |
  | [<img src="docs/screenshots/settings.png" alt="Settings screen" width="260">](docs/screenshots/settings.png) | [<img src="docs/screenshots/about.png" alt="About screen" width="260">](docs/screenshots/about.png) |
</details>

These captures use synthetic media. A screenshot does not establish playback support on a device.

## Try it with Docker

You need Git and Docker with the Compose plugin. For a new checkout:

```sh
git clone https://github.com/avillen/bolognesa.git
cd bolognesa
mkdir -p media
cp .env.example .env
# Put some media in ./media before starting.
docker compose up --build
```

Already have a checkout? Skip cloning and keep your existing `.env`. The first build may take several minutes. Elixir, PostgreSQL, and media tools are included in the containers.

1. Open [http://localhost:4000](http://localhost:4000), create the administrator account, and sign in.
2. Open **Libraries**, add a movie library at `/media`, and start a scan.
3. Wait for inspection and identification, then open a movie. Review any unmatched items.

Movie and series identification needs a [TMDb API Read Access Token](https://developer.themoviedb.org/docs/authentication-application). Set `TMDB_READ_TOKEN` in `.env` before starting. The app can start without it, and local music does not need it.

For separate libraries, use folders such as `media/movies`, `media/series`, and `media/music`, then register the matching **container paths**: `/media/movies`, `/media/series`, and `/media/music`. The container reads media as `nobody`; folders and files must be readable by that user.

Set `MEDIA_PATH` in `.env` to use another host folder, or `BOLOGNESA_PORT` to change the web port. `docker compose down` stops the services and keeps the database. `make local-up`, `make local-down`, and `make local-logs` are shortcuts.

If startup fails, check `docker compose logs --tail 100 app db`. On a slow first boot, the app may report `db:5432` connection refused before PostgreSQL finishes initializing. Wait for `PostgreSQL init process complete` and the final ready message, then retry with `docker compose up -d`; keep the database volume.

This quick start uses development credentials and binds to your own machine. For a private server, follow the [Linux deployment guide](deploy/compose/README.md). **The LAN/HTTP profile must not be exposed directly to the public Internet.**

## Playback limits

Playback depends on browser codec support and server hardware. Limited FFmpeg/HLS conversion supports one shared conversion session. Files containing several episodes play in full.

Video position and pause state can recover in the same tab for up to 12 hours, on a best-effort basis; progress is not saved across tabs or devices. Music plays without conversion and stops when leaving the music screen or reloading.

The video player stays mounted when changing episodes or parts and when retrying playback errors, preserving element fullscreen in supported browsers. A full page reload or browser crash exits fullscreen; entering it again requires a user action. Native mobile fullscreen behavior needs separate device verification.

## Before updating

Compatibility between releases is not guaranteed during early development. Read the [changelog](CHANGELOG.md) before updating, and keep a validated database backup, its matching application image, and private configuration. Back up original media separately. Restarting with an older image does not undo migrations.

The [deployment guide](deploy/compose/README.md#backup-update-and-recovery) explains backup and restore. The local quick start applies migrations automatically and has no managed backup workflow. Never use `docker compose down -v` to update data you want to keep.

## Contribute

Bug reports, setup feedback, documentation, and focused fixes are welcome. Discuss larger features first. See [CONTRIBUTING](CONTRIBUTING.md) for native development and checks.

- [Changelog](CHANGELOG.md)
- [Issues](https://github.com/avillen/bolognesa/issues) and [milestones](https://github.com/avillen/bolognesa/milestones)
- [Documentation and architecture](docs/README.md)
- [Linux deployment](deploy/compose/README.md)

Licensed under [MIT](LICENSE). Third-party components and media keep their own licenses. No demo media is bundled; use files you have the right to play and share.
