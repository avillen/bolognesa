# Product

Bolognesa is a self-hosted media center built with Elixir and Phoenix. It began as a way to learn Elixir by building something useful at home, and it is developed in public so others can try it and learn from it too. The product aims to make a personal media library easy to scan, identify, browse, and play.

## Audience and scope

Bolognesa is an early, personal project. The target first complete journey is to create an administrator account, add a media folder, scan and identify files, correct matches, play a browser-compatible file, and eventually resume playback later. Original media files are read-only: Bolognesa does not move, rename, or delete them.

Movies, series, and local music are supported. Music uses embedded tags with a filename fallback, artist/album browsing, and authenticated direct audio delivery. Albums play in order with automatic advance and previous/next controls; listening survives browsing within the music screen. Queue editing, playback across other screens, independent accounts, general remote access, and dedicated clients remain future work. The generic Compose deployment is intended for trusted private networks; it must not be exposed directly to the public Internet.

## Community and growth

The project is maintained around one real home use case. People are invited to run it, report bugs, share environment and playback results, improve documentation and tests, and contribute focused fixes when code contributions are open. Larger features should start with a discussion about the problem and the smallest useful change. The maintainer chooses priorities and cannot promise support or a merge for every proposal.

Growth should follow evidence from use: first make setup, scanning, identification, correction, and playback more reliable across real environments. Consider broader media types, more accounts, remote access, and dedicated clients when there is a concrete need and capacity to maintain them. These are possibilities, not commitments.

## Product principles

- Keep the application understandable and practical to run at home.
- Prefer simple designs that remain responsive on modest hardware.
- Make background work recoverable and explain failures to users.
- Treat user corrections and future persisted progress as durable data.
- Record what has been verified separately from expected behavior.

The [roadmap](roadmap.md) describes current milestones. Architecture rules live in [conventions](conventions/), and accepted trade-offs are in [decisions](decisions/).
