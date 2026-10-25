import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"
import {build} from "esbuild"

test("the player bundled with the application avoids Safari 16.2 syntax errors", async () => {
  const config = await readFile(new URL("../../config/config.exs", import.meta.url), "utf8")
  const target = config.match(/--target=([^\s]+)/)[1].split(",")
  const result = await build({
    entryPoints: [new URL("../js/hooks/video_player.js", import.meta.url).pathname],
    bundle: true, target, write: false, minify: true,
  })
  // Safari added class static initialization blocks in 16.4. A parse error in
  // this eagerly imported dependency also prevents LiveView catalog loading.
  assert.equal(/\bstatic\s*\{/.test(result.outputFiles[0].text), false,
    "the application target must lower class static blocks for Safari 16.2")
})
