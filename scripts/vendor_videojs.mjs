// Regenerate the checked-in browser dependency with `npm ci && npm run vendor-videojs`.
import {build} from "esbuild"
import {readFile, writeFile, rm} from "node:fs/promises"

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
import "@videojs/html/i18n/locales/es/register";`,
    resolveDir: process.cwd(),
  },
  bundle: true, minify: true, format: "esm", target: "es2022",
  // Preserve notices in the final Phoenix asset as well as the source distribution.
  banner: {js: `/*! Video.js 10.1.0 and bundled dependencies\n${license}\n*/`},
  legalComments: "inline", outfile: "assets/vendor/videojs.min.mjs",
})
await writeFile("assets/vendor/videojs.LICENSE", license)
await rm("assets/vendor/videojs.min.mjs.LEGAL.txt", {force: true})
