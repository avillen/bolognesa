import test from "node:test"
import assert from "node:assert/strict"
import {createTimeNumberFormat} from "../js/video_time_format.mjs"

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
