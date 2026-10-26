import test from "node:test"
import assert from "node:assert/strict"
import {createTimeNumberFormat, createTimeListFormat, probeTimeFormatting} from "../js/video_time_format.mjs"

class LegacyNumberFormat extends Intl.NumberFormat {
  constructor(locale, options) {
    if (options?.style === "unit") throw new RangeError("Unsupported unit style")
    super(locale, options)
  }
}

test("time units fall back to readable abbreviations on older browsers", () => {
  for (const locale of ["en", "es"]) {
    for (const [unit, suffix] of [["hour", "h"], ["minute", "min"], ["second", "s"]]) {
      const formatter = createTimeNumberFormat(locale, {style: "unit", unit, unitDisplay: "long"}, LegacyNumberFormat)
      assert.equal(formatter.format(2), `2 ${suffix}`)
    }
    assert.equal(createTimeNumberFormat(locale, {minimumIntegerDigits: 2}, LegacyNumberFormat).format(3), "03")
  }
})

test("unit number formatting falls back when an older implementation throws TypeError", () => {
  class LegacyTypeErrorNumberFormat extends Intl.NumberFormat {
    constructor(locale, options) {
      if (options?.style === "unit") throw new TypeError("Unsupported unit style")
      super(locale, options)
    }
  }
  for (const locale of ["en", "es"]) {
    const formatter = createTimeNumberFormat(locale, {style: "unit", unit: "second", unitDisplay: "long"}, LegacyTypeErrorNumberFormat)
    assert.equal(formatter.format(2), `2 s`)
  }
})

test("unit formatting recovers when construction succeeds but accessing or using format fails", () => {
  class DelayedUnitNumberFormat {
    constructor(locale, options) {
      this.unit = options?.style === "unit"
      this.number = new Intl.NumberFormat(locale, this.unit ? {} : options)
    }
    get format() {
      if (this.unit) throw new TypeError("Unit format accessor is unavailable")
      return this.number.format
    }
  }
  for (const locale of ["en", "es"]) {
    for (const [unit, suffix] of [["hour", "h"], ["minute", "min"], ["second", "s"]]) {
      const formatter = createTimeNumberFormat(locale, {style: "unit", unit, unitDisplay: "long"}, DelayedUnitNumberFormat)
      assert.equal(formatter.format(2), `2 ${suffix}`)
    }
  }
})

test("supported formatting retains native localized output", () => {
  for (const locale of ["en", "es"]) {
    const options = {style: "unit", unit: "minute", unitDisplay: "long"}
    assert.equal(createTimeNumberFormat(locale, options).format(2), new Intl.NumberFormat(locale, options).format(2))
  }
})

test("unrelated formatting errors are preserved", () => {
  assert.throws(() => createTimeNumberFormat("en", {style: "invalid"}), RangeError)
  assert.throws(() => createTimeNumberFormat("en", {style: "unit", unit: "invalid"}, LegacyNumberFormat), RangeError)
  class BrokenNumberFormat { constructor() { throw new TypeError("Broken formatter") } }
  assert.throws(() => createTimeNumberFormat("en", {style: "unit", unit: "second"}, BrokenNumberFormat), TypeError)
})


test("time phrases survive a ListFormat implementation that rejects unit lists", () => {
  class LegacyListFormat extends Intl.ListFormat {
    constructor(locale, options) {
      if (options?.type === "unit") throw new RangeError("Unsupported list type")
      super(locale, options)
    }
  }
  for (const locale of ["en", "es"]) {
    for (const style of ["long", "short", "narrow"]) {
      const expected = style === "narrow" ? "1 h 2 min" : "1 h, 2 min"
      assert.equal(createTimeListFormat(locale, {type: "unit", style}, LegacyListFormat).format(["1 h", "2 min"]), expected)
    }
    const options = {type: "unit", style: "long"}
    assert.equal(createTimeListFormat(locale, options).format(["1 h", "2 min"]), new Intl.ListFormat(locale, options).format(["1 h", "2 min"]))
  }
  class BrokenListFormat { constructor() { throw new TypeError("Broken formatter") } }
  assert.throws(() => createTimeListFormat("en", {type: "unit"}, BrokenListFormat), TypeError)
  assert.throws(() => createTimeListFormat("en", {type: "invalid"}), RangeError)
})


test("formatter probes distinguish constructor failures from delayed format failures without error text", () => {
  const recovered = probeTimeFormatting("es", {NumberFormat: LegacyNumberFormat, ListFormat: Intl.ListFormat})
  assert.equal(recovered.intl_unit_constructor, "range")
  assert.equal(recovered.intl_unit_format, "not_run")
  assert.equal(recovered.time_format_step, "ok")
  assert.equal(recovered.time_format_error, "none")
  class DelayedNumberFormat {
    constructor(locale, options) {
      this.native = new Intl.NumberFormat(locale, options?.style === "unit" ? {} : options)
      this.unit = options?.style === "unit"
    }
    format(value) {
      if (this.unit) throw new RangeError("private error text")
      return this.native.format(value)
    }
  }
  const delayed = probeTimeFormatting("es", {NumberFormat: DelayedNumberFormat, ListFormat: Intl.ListFormat})
  assert.equal(delayed.intl_unit_constructor, "ok")
  assert.equal(delayed.intl_unit_format, "range")
  assert.equal(delayed.time_format_step, "ok")
  assert.equal(delayed.time_format_error, "none")
  assert.equal(JSON.stringify(delayed).includes("private"), false)
})
