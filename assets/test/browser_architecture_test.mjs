import test from "node:test"
import assert from "node:assert/strict"
import {readdir} from "node:fs/promises"
import {join} from "node:path"
import {build} from "esbuild"

async function modules(directory) {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(entries.map(entry => entry.isDirectory()
    ? modules(join(directory, entry.name))
    : entry.name.endsWith(".mjs") ? [join(directory, entry.name)] : []))
  return nested.flat()
}

const player = "assets/js/music/player/"
for (const [layer, allowed] of [
  ["model", ["model"]],
  ["operations", ["operations", "model"]],
  ["adapters", ["adapters", "model"]],
  ["ui", ["ui", "model"]],
]) {
  test(`music ${layer} dependency graph stays inside its allowed layers`, async () => {
    const entryPoints = await modules(`${player}${layer}`)
    assert.ok(entryPoints.length > 0)
    const result = await build({entryPoints, bundle: true, write: false, metafile: true,
      outdir: "tmp/architecture-check", platform: "neutral", logLevel: "silent"})
    for (const dependency of Object.keys(result.metafile.inputs)) {
      assert.ok(allowed.some(folder => dependency.startsWith(`${player}${folder}/`)),
        `${layer} imports forbidden dependency ${dependency}; inject the effect or command instead`)
    }
  })
}
