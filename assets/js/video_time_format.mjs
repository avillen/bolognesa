// Older TV browsers support numeric formatting but reject style: "unit".
// Keep this fallback scoped to Video.js time formatting, preserving the global Intl API.
export function createTimeNumberFormat(locale, options, NumberFormat = Intl.NumberFormat) {
  try {
    return new NumberFormat(locale, options)
  } catch (error) {
    if (!(error instanceof RangeError || error instanceof TypeError) || options?.style !== "unit") throw error
    const suffix = {hour: "h", minute: "min", second: "s"}[options.unit]
    if (!suffix) throw error
    const number = new NumberFormat(locale, {useGrouping: false})
    return {format: value => `${number.format(value)} ${suffix}`}
  }
}

// Some embedded browsers expose ListFormat but reject type: "unit".
export function createTimeListFormat(locale, options, ListFormat = Intl.ListFormat) {
  try {
    return new ListFormat(locale, options)
  } catch (error) {
    if (!(error instanceof RangeError) || options?.type !== "unit" ||
        !["long", "short", "narrow"].includes(options.style ?? "long")) throw error
    return {format: parts => [...parts].join(options.style === "narrow" ? " " : ", ")}
  }
}
