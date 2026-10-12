# 0006. Authorized direct media delivery

Status: Accepted and deployed. Compatibility depends on the browser and media codecs; device coverage remains incomplete.

## Context

Playback must keep private libraries out of `Plug.Static`, support browser seeking, and reject requests after a session is closed or revoked.

## Decision

- Let the user select an available file explicitly. Use the native `<video>` element without autoplay. Durable playback progress is a separate feature.
- Media URLs contain catalog and file IDs, never disk paths or credentials. Resolve the current session and reauthorize the relationship on every `GET` and `HEAD`. An unauthenticated request returns an empty `401` response.
- Validate the source, relative path, physical ancestors, regular file, size, modification time, and identity. Open the file and compare its descriptor with the validated state; stream bounded chunks from that descriptor instead of reopening the path.
- Support a full response and one byte range. Return `400` for invalid syntax, `416` for an unsatisfiable range, and no body for `HEAD`. Use a closed list of video MIME types.
- A preflight check may report a missing file, but every content request validates and authorizes again.

## Consequences

Each range request checks authorization and the file, adding database and filesystem work. Descriptor validation protects against path replacement before open, but the filesystem offers no atomic snapshot against a fast external swap-and-restore. Bolognesa mounts originals read-only; it cannot prevent outside writes.

Serving bytes does not guarantee that a browser can decode a container or codec. Real playback must be checked with representative files and devices. This decision does not include transcoding, saved progress, or TV pairing.
