/** Probe only server-issued configurations. No media URL is needed or attached here. */
export async function probePlaybackCapabilities({generation, candidates, preference = "auto"}, {
  video, mediaCapabilities = globalThis.navigator?.mediaCapabilities,
  MediaSource = globalThis.MediaSource, Hls, deadlineMs = 3000,
}) {
  const unknown = candidate => ({candidate_id: candidate.id, transport: candidate.transports[0], support: "unknown", smooth: "unknown", power_efficient: "unknown"})
  const results = candidates.slice(0, 6).map(unknown)
  let finished = false, timer
  const probes = candidates.slice(0, 6).map(async (candidate, index) => {
    const observation = await probeCandidate(candidate, {video, mediaCapabilities, MediaSource, Hls})
    if (!finished) results[index] = observation
  })
  await Promise.race([
    Promise.all(probes),
    new Promise(resolve => { timer = setTimeout(resolve, deadlineMs) }),
  ])
  finished = true
  clearTimeout(timer)
  return {version: 1, generation, preference, results}
}

const MP3 = "mp4a.40.34"
const mimeWithCodecs = (mime, configuration) => `${mime}; codecs="${[configuration.video.codec_string, configuration.audio?.codec_string].filter(Boolean).join(", ")}"`
// HLS.js feeds MPEG-TS MP3 to its own "audio/mpeg" SourceBuffer, or remuxes it as MP3-in-MP4.
const hlsJsMp3SourceBuffer = MediaSource => ["audio/mpeg", 'audio/mp4; codecs="mp3"'].find(type => MediaSource.isTypeSupported(type))
function hlsJsStreamsSupported(MediaSource, config) {
  if (config.audio?.codec_string !== MP3) return MediaSource.isTypeSupported(mimeWithCodecs("video/mp4", config))
  return MediaSource.isTypeSupported(mimeWithCodecs("video/mp4", {...config, audio: null})) && Boolean(hlsJsMp3SourceBuffer(MediaSource))
}
const support = value => value === "probably" ? "supported" : value === "" ? "unsupported" : "unknown"
const performance = value => value === true ? "yes" : value === false ? "no" : "unknown"
function safely(effect, fallback) { try { return effect() } catch { return fallback } }

async function probeCandidate(candidate, {video, mediaCapabilities, MediaSource, Hls}) {
  const config = candidate.configuration
  const mime = mimeWithCodecs(config.mime, config)
  let transport = candidate.transports[0]
  let supported = "unknown"
  if (candidate.transports.includes("file")) {
    supported = support(safely(() => video.canPlayType(mime), "maybe"))
  } else {
    const mse = safely(() => Hls?.isSupported() && hlsJsStreamsSupported(MediaSource, config), false)
    // A generic playlist MIME has no codec detail. WebKit can recognize it as "maybe";
    // exact elementary-stream support below must still be "probably".
    const playlist = safely(() => video.canPlayType("application/vnd.apple.mpegurl"), null)
    const native = playlist === "maybe" ? "supported" : support(playlist)
    const streams = support(safely(() => video.canPlayType(mimeWithCodecs("video/mp4", config)), "maybe"))
    if (candidate.transports.includes("hls_js") && mse) {
      transport = "hls_js"
      supported = "supported"
    } else if (candidate.transports.includes("native_hls")) {
      transport = "native_hls"
      supported = native === "unsupported" || streams === "unsupported" ? "unsupported" :
        native === "supported" && streams === "supported" ? "supported" : "unknown"
    } else if (mse === false) supported = "unsupported"
  }
  const observation = {candidate_id: candidate.id, transport, support: supported, smooth: "unknown", power_efficient: "unknown"}
  const decoding = decodingConfiguration(config, transport, MediaSource)
  if (!decoding || !mediaCapabilities?.decodingInfo) return observation
  try {
    const result = await mediaCapabilities.decodingInfo(decoding)
    if (result.supported === false) observation.support = "unsupported"
    observation.smooth = performance(result.smooth)
    observation.power_efficient = performance(result.powerEfficient)
  } catch { /* An absent or rejecting API adds no evidence. */ }
  return observation
}

function decodingConfiguration(config, transport, MediaSource) {
  const v = config.video, a = config.audio
  if (![v.width, v.height, v.frame_rate, v.bit_rate].every(value => Number.isFinite(value) && value > 0)) return null
  if (a && ![a.sample_rate, a.channels, a.bit_rate].every(value => Number.isFinite(value) && value > 0)) return null
  const mime = transport === "file" ? config.mime : "video/mp4"
  const decoding = {type: transport === "hls_js" ? "media-source" : "file",
    video: {contentType: `${mime}; codecs="${v.codec_string}"`, width: v.width, height: v.height, bitrate: v.bit_rate, framerate: v.frame_rate}}
  const audioType = a && transport === "hls_js" && a.codec_string === MP3 ?
    safely(() => hlsJsMp3SourceBuffer(MediaSource), undefined) :
    a && `audio/${mime.split("/")[1]}; codecs="${a.codec_string}"`
  if (a && audioType) decoding.audio = {contentType: audioType, channels: String(a.channels), bitrate: a.bit_rate, samplerate: a.sample_rate}
  return decoding
}
