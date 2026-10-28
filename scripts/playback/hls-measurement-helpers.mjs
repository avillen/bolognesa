// Pure helpers shared by the synthetic HTTP measurement and its accounting tests.
export function parseFixture(manifest) {
  if (!manifest.startsWith("#EXTM3U") || !manifest.includes("#EXT-X-ENDLIST")) {
    throw new Error("Use a completed, plain MPEG-TS media playlist fixture")
  }
  if (/#EXT-X-(KEY|MAP|BYTERANGE|STREAM-INF|DISCONTINUITY|GAP)/.test(manifest)) {
    throw new Error("Encrypted, variant, discontinuous and byte-range fixtures are unsupported")
  }
  const targetDuration = Number(manifest.match(/^#EXT-X-TARGETDURATION:(\d+)\s*$/m)?.[1])
  if (!Number.isInteger(targetDuration) || targetDuration <= 0) throw new Error("Invalid target duration")
  const segments = []
  let duration
  for (const line of manifest.split(/\r?\n/).map(line => line.trim())) {
    if (line.startsWith("#EXTINF:")) {
      if (duration !== undefined) throw new Error("Missing segment URI")
      duration = Number(line.slice(8).split(",")[0])
      if (!Number.isFinite(duration) || duration <= 0) throw new Error("Invalid segment duration")
    } else if (line && !line.startsWith("#")) {
      if (duration === undefined || !/^[a-zA-Z0-9_-]+\.ts$/.test(line)) throw new Error("Invalid segment URI")
      segments.push({duration, uri: line})
      duration = undefined
    }
  }
  if (!segments.length || duration !== undefined) throw new Error("Incomplete fixture")
  return {targetDuration, segments, duration: segments.reduce((sum, segment) => sum + segment.duration, 0)}
}

export function publishedSegments(fixture, availableSeconds) {
  const cycles = Math.floor(availableSeconds / fixture.duration)
  let count = cycles * fixture.segments.length
  let remaining = availableSeconds - cycles * fixture.duration
  for (const segment of fixture.segments) {
    if (remaining + 1e-8 < segment.duration) break
    remaining -= segment.duration
    count++
  }
  return count
}

export function renderPlaylist(fixture, {published, windowSize = 12, completed = false}) {
  const first = Math.max(0, published - windowSize)
  const lines = ["#EXTM3U", "#EXT-X-VERSION:3", `#EXT-X-TARGETDURATION:${fixture.targetDuration}`,
    `#EXT-X-MEDIA-SEQUENCE:${first}`, `#EXT-X-DISCONTINUITY-SEQUENCE:${Math.floor(first / fixture.segments.length)}`]
  for (let sequence = first; sequence < published; sequence++) {
    const index = sequence % fixture.segments.length
    if (sequence > first && index === 0) lines.push("#EXT-X-DISCONTINUITY")
    lines.push(`#EXTINF:${fixture.segments[index].duration},`, `seg-${String(sequence).padStart(6, "0")}.ts`)
  }
  if (completed) lines.push("#EXT-X-ENDLIST")
  return lines.join("\n") + "\n"
}

export function summarizePhase(requests, phase) {
  const resources = Object.fromEntries(["manifest", "segment"].map(resource => {
    const selected = requests.filter(request => request.phase === phase.name && request.resource === resource)
    const latencies = selected.map(request => request.latency_ms).filter(Number.isFinite).sort((a, b) => a - b)
    const comparable = selected.filter(request => typeof request.unchanged === "boolean")
    return [resource, {
      requests: selected.length,
      statuses: selected.reduce((counts, request) => {
        counts[request.status] = (counts[request.status] || 0) + 1
        return counts
      }, {}),
      bytes: selected.reduce((sum, request) => sum + request.bytes, 0),
      requests_per_minute: phase.duration_ms > 0 ? selected.length * 60000 / phase.duration_ms : null,
      intervals_ms: selected.slice(1).map((request, index) => request.at_ms - selected[index].at_ms),
      unchanged_fraction: comparable.length ? comparable.filter(request => request.unchanged).length / comparable.length : null,
      latency_mean_ms: latencies.length ? latencies.reduce((sum, value) => sum + value, 0) / latencies.length : null,
      latency_p95_ms: latencies.length ? latencies[Math.ceil(latencies.length * 0.95) - 1] : null,
    }]
  }))
  return {...phase, position_advanced_s: Number.isFinite(phase.position_end_s) && Number.isFinite(phase.position_start_s)
    ? phase.position_end_s - phase.position_start_s : null, resources}
}
