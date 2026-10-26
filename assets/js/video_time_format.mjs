// Older TV browsers support numeric formatting but reject style: "unit".
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

// Diagnose the boundary between constructing and using a formatter. Never emit
// formatted values, locale input beyond en/es, or exception messages/stacks.
export function probeTimeFormatting(locale, intl = globalThis.Intl) {
  locale = locale === "es" ? "es" : "en"
  const {NumberFormat, ListFormat} = intl || {}
  const result = {
    intl_unit_constructor: "not_run", intl_unit_format: "not_run",
    time_format_step: "ok", time_format_error: "none", time_format_locale: locale,
  }
  const errorKind = error => {
    switch (error?.name) {
      case "RangeError": return "range"
      case "TypeError": return "type"
      case "ReferenceError": return "reference"
      default: return "other"
    }
  }
  let native
  try {
    native = new NumberFormat(locale, {style: "unit", unit: "second"})
    result.intl_unit_constructor = "ok"
  } catch (error) { result.intl_unit_constructor = errorKind(error) }
  if (native) {
    try { native.format(1); result.intl_unit_format = "ok" }
    catch (error) { result.intl_unit_format = errorKind(error) }
  }
  const check = (step, run) => {
    try { run(); return true }
    catch (error) {
      result.time_format_step = step
      result.time_format_error = errorKind(error)
      return false
    }
  }
  for (const minimumIntegerDigits of [1, 2]) {
    if (!check("numeric", () => createTimeNumberFormat(locale, {useGrouping: false, minimumIntegerDigits}, NumberFormat).format(2))) return result
  }
  for (const unit of ["hour", "minute", "second"]) {
    for (const style of ["long", "short", "narrow"]) {
      if (!check(`${unit}_${style}`, () => createTimeNumberFormat(locale,
        {style: "unit", unit, unitDisplay: style}, NumberFormat).format(2))) return result
    }
  }
  // Video.js already joins phrases itself if ListFormat is absent.
  if (typeof ListFormat === "function") {
    for (const style of ["long", "short", "narrow"]) {
      if (!check(`list_${style}`, () => createTimeListFormat(locale,
        {type: "unit", style}, ListFormat).format(["1 h", "2 min"]))) return result
    }
  }
  return result
}
