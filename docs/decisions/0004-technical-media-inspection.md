# 0004. Durable technical inspection by file revision

Status: Accepted; implemented. Recovery behavior and playback compatibility are separate verification concerns.

## Context

Scanning discovers files without inspecting their media streams. Inspection must extract technical metadata without changing originals, recover after interruption, and reject stale results. File revisions use size and modification time, so some content changes may be invisible.

## Decision

Request inspection for new, changed, restored, or explicitly reanalyzed files. A normal scan reuses inspection for unchanged files. Persist each inventory batch, inspection state, and outbox event in one transaction. A recoverable dispatcher creates Oban jobs after commit.

Give every inspection request a fresh token. Save a result only when token, revision, and availability are still current. Initially limit inspection concurrency to one per instance and measure before increasing it.

The `ffprobe` adapter revalidates the physical path, reads only allowed technical metadata, and does not persist its full output or private data. Run it outside database transactions with time and output limits. A single-file failure must not stop the rest of the scan.

## Consequences

The outbox adds a table and dispatcher but keeps durable work atomic with the inventory update. Reinspecting every file would catch more changes but repeatedly read the entire library; full-content hashing would add I/O and complexity. Revisit these trade-offs if real needs arise.

File-system changes are not atomic snapshots. This decision alone does not verify recovery on a deployment or establish playback compatibility.
