// Video.js sees file time, while the native video sees only the current FFmpeg session.
export const fileTimeFeature = native => ({
  ...native,
  state(context) {
    const state = native.state(context)
    return {...state, async seek(time) {
      const timeline = context.target().media.fileTimeline
      if (!timeline) return state.seek(time)
      if (!Number.isFinite(time) || !timeline.duration || timeline.pending) return 0
      const position = Math.max(0, Math.min(time, timeline.duration))
      context.set({currentTime: position, seeking: true})
      timeline.seek(position)
      return position
    }}
  },
  attach(context) {
    return native.attach({...context, set(value) {
      const timeline = context.target.media.fileTimeline
      if (!timeline) return context.set(value)
      if (timeline.pending) return
      const next = {...value}
      if ("currentTime" in next) next.currentTime = Math.min(timeline.duration || Infinity,
        timeline.offset + Math.max(0, next.currentTime || 0))
      if ("duration" in next) next.duration = timeline.duration
      context.set(next)
    }})
  },
})

export const fileBufferFeature = native => ({
  ...native,
  attach(context) {
    return native.attach({...context, set(value) {
      const timeline = context.target.media.fileTimeline
      if (!timeline) return context.set(value)
      context.set({
        buffered: value.buffered.map(([start, end]) => [
          start + timeline.offset, Math.min(timeline.duration || Infinity, end + timeline.offset),
        ]),
        seekable: timeline.duration ? [[0, timeline.duration]] : [],
      })
    }})
  },
})
