// Regenerate the checked-in browser dependency with `npm ci && npm run vendor-videojs`.
import {build} from "esbuild"
import {readFile, writeFile, rm} from "node:fs/promises"
import {fileURLToPath} from "node:url"
import {dirname} from "node:path"

const notices = await Promise.all([
  "node_modules/@videojs/html/LICENSE",
  "node_modules/signal-polyfill/LICENSE",
  "node_modules/@lit/context/LICENSE",
].map(path => readFile(path, "utf8")))
const license = notices.join("\n\n")
await build({
  stdin: {
    contents: `export {createPlayer, videoFeatures, timeFeature, bufferFeature} from "@videojs/html";
import "@videojs/html/video/skin";
import "@videojs/html/audio/player";
import "@videojs/html/audio/skin";
import "@videojs/html/i18n/locales/es/register";`,
    resolveDir: process.cwd(),
  },
  bundle: true, minify: true, format: "esm", target: "es2022",
  plugins: [{
    name: "compatible-time-formatting",
    setup(build) {
      build.onLoad({filter: /@videojs\/utils\/dist\/time\/format\.js$/}, async ({path}) => {
        const source = await readFile(path, "utf8")
        if (!source.includes("new Intl.NumberFormat(")) throw new Error("Review Video.js time formatting compatibility patch")
        const leadingZero = source.split("\n").find(line => line.includes("body = body.replace(new RegExp("))
        if (!leadingZero) throw new Error("Review Video.js leading time zero compatibility patch")
        const shim = fileURLToPath(new URL("../assets/js/video_time_format.mjs", import.meta.url))
        return {
          contents: `import {createTimeNumberFormat} from ${JSON.stringify(shim)};\n` +
            source.replaceAll("new Intl.NumberFormat(", "createTimeNumberFormat(")
              // This branch always has two-digit minutes below ten. Remove only the
              // locale's padded zero without requiring Unicode property escapes.
              .replace(leadingZero, "\t\tbody = body.startsWith(zero) ? body.slice(zero.length) : body;"),
          resolveDir: dirname(path),
          loader: "js",
        }
      })
    },
  }],
  // Preserve notices in the final Phoenix asset as well as the source distribution.
  banner: {js: `/*! Video.js 10.1.0 and bundled dependencies\n${license}\n*/`},
  legalComments: "inline", outfile: "assets/vendor/videojs.min.mjs",
})
await writeFile("assets/vendor/videojs.LICENSE", license)
await rm("assets/vendor/videojs.min.mjs.LEGAL.txt", {force: true})
