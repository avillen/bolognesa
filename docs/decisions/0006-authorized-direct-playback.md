# 0006. Authorized direct media delivery

Status: Accepted and deployed. Compatibility depends on the browser and media codecs; device coverage remains incomplete.

## Context

Playback must keep private libraries out of `Plug.Static`, support browser seeking, and reject requests after a session is closed or revoked.

## Decision

- Let the user select an available file explicitly. Use the native `<video>` or music `<audio>` element without autoplay. Durable playback progress is a separate feature.
- Video media URLs contain catalog and file IDs; music URLs contain track and file IDs. Both selectors recheck their own current associations. URLs contain IDs, never disk paths or credentials. Resolve the current session and reauthorize the relationship on every `GET` and `HEAD`. An unauthenticated request returns an empty `401` response.
- Validate the source, relative path, physical ancestors, regular file, size, modification time, and identity. Open the file and compare its descriptor with the validated state; stream bounded chunks from that descriptor instead of reopening the path.
- Support a full response and one byte range. Return `400` for invalid syntax, `416` for an unsatisfiable range, and no body for `HEAD`. Use separate closed video/audio MIME policies with shared descriptor and range delivery.
- A preflight check may report a missing file, but every content request validates and authorizes again.

The music extension uses `/music/tracks/:track_id/media/:file_id`, requires a current successful audio inspection and imported token, and remains direct-only. Browser audio errors are visible; music does not use the video HLS profile. Local identity and durable import ownership are recorded in [decision 0018](0018-local-music-catalog.md).

## Consequences

Each range request checks authorization and the file, adding database and filesystem work. Descriptor validation protects against path replacement before open, but the filesystem offers no atomic snapshot against a fast external swap-and-restore. Bolognesa mounts originals read-only; it cannot prevent outside writes.

Serving bytes does not guarantee that a browser can decode a container or codec. Real playback must be checked with representative files and devices. This decision does not include transcoding, saved progress, or TV pairing.
