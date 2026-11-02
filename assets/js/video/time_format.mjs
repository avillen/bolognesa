// Some embedded browsers construct unit formatters but fail when they are used.
// Keep this fallback scoped to Video.js time formatting, preserving the global Intl API.
export function createTimeNumberFormat(locale, options, NumberFormat = Intl.NumberFormat) {
  try {
    const formatter = new NumberFormat(locale, options)
    // Some embedded implementations accept the options and fail only when the
    // format accessor or function is used. Exercise it inside the same fallback.
    if (options?.style === "unit") formatter.format(0)
    return formatter
  } catch (error) {
    if (!(error instanceof RangeError || error instanceof TypeError) || options?.style !== "unit") throw error
    const suffix = {hour: "h", minute: "min", second: "s"}[options.unit]
    if (!suffix) throw error
    const number = new NumberFormat(locale, {useGrouping: false})
    return {format: value => `${number.format(value)} ${suffix}`}
  }
}
