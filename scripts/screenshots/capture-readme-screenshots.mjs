import { fileURLToPath } from "node:url";
import { mkdir, readFile } from "node:fs/promises";
import { chromium } from "playwright";

const baseUrl = process.env.BOLOGNESA_URL ?? "http://127.0.0.1:4001";
const phase = process.env.BOLOGNESA_CAPTURE_PHASE ?? "all";
const librariesOnly = process.env.BOLOGNESA_CAPTURE_LIBRARIES_ONLY === "1";
const outputDirectory = process.env.BOLOGNESA_SCREENSHOT_OUTPUT_DIR
  ?? fileURLToPath(new URL("../../docs/screenshots/", import.meta.url));
await mkdir(outputDirectory, { recursive: true });
const screenshotPath = (name) => `${outputDirectory}/${name}`;

const browser = process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS
  ? await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, { exposeNetwork: "<loopback>" })
  : await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: 1,
    locale: "en-US"
  });
  page.setDefaultTimeout(15_000);
  // Use the same illustration across captures; encoded video frames vary between runs.
  const withStableVideoFrame = async (capture) => {
    await page.evaluate(async (artwork) => {
      window.screenshotVideoFrames = [];
      for (const video of document.querySelectorAll("video")) {
        // MediaRecorder omits a duration header. Normalize its known six-second
        // timeline for captures while keeping the real Video.js controls mounted.
        video.pause();
        const descriptors = Object.fromEntries(["duration", "seekable", "buffered", "currentTime", "paused", "ended", "seeking", "play"]
          .map(key => [key, Object.getOwnPropertyDescriptor(video, key)]));
        const ranges = {length: 1, start: () => 0, end: () => 6};
        Object.defineProperties(video, {
          duration: {configurable: true, get: () => 6},
          seekable: {configurable: true, get: () => ranges},
          buffered: {configurable: true, get: () => ranges},
          currentTime: {configurable: true, get: () => 2},
          paused: {configurable: true, get: () => true},
          ended: {configurable: true, get: () => false},
          seeking: {configurable: true, get: () => false},
          // A delayed metadata/autoplay callback must not restart a capture.
          play: {configurable: true, value: () => Promise.resolve()},
        });
        for (const event of ["durationchange", "progress", "timeupdate", "pause", "seeked"]) video.dispatchEvent(new Event(event));
        const image = new Image();
        image.src = `data:image/svg+xml,${encodeURIComponent(artwork)}`;
        image.width = video.getBoundingClientRect().width;
        image.height = video.getBoundingClientRect().height;
        image.style.cssText = "display:block;max-width:100%;border-radius:inherit;";
        await image.decode();
        const container = video.closest("video-skin")?.shadowRoot.querySelector("media-container");
        if (!container) throw new Error("Video.js controls did not mount.");
        image.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:cover;pointer-events:none;z-index:0;";
        container.append(image);
        // The synthetic artwork replaces decoded pixels for captures. Hide the
        // native video plane to avoid GPU/poster compositing changing its edges.
        const visibility = video.style.visibility;
        video.style.visibility = "hidden";
        window.screenshotVideoFrames.push({video, image, descriptors, visibility});
      }
    }, '<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="720" viewBox="0 0 1440 720"><rect width="1440" height="720" fill="#10191e"/><circle cx="1050" cy="260" r="220" fill="#e47755" opacity=".42"/><path d="m0 530 260-210 190 142 210-232 230 302 180-165 370 260v93H0Z" fill="#283239"/><path d="m0 620 350-190 220 168 260-210 260 170 190-132 160 112v182H0Z" fill="#171f24"/><text x="110" y="565" fill="#f4f1ed" font-family="Arial,sans-serif" font-size="55" font-weight="700">AFTER THE SIGNAL</text></svg>');
    try {
      // Settle metadata-availability fades before capturing the fixed timeline.
      await page.waitForFunction(() => Array.from(document.querySelectorAll("video-skin")).every(skin =>
        Array.from(skin.shadowRoot.querySelectorAll("media-time")).every(time => getComputedStyle(time).opacity === "1")
      ));
      await capture();
    } finally {
      await page.evaluate(() => {
        for (const {video, image, descriptors, visibility} of window.screenshotVideoFrames) {
          image.remove();
          video.style.visibility = visibility;
          for (const [key, descriptor] of Object.entries(descriptors)) {
            if (descriptor) Object.defineProperty(video, key, descriptor);
            else delete video[key];
          }
          video.dispatchEvent(new Event("durationchange"));
        }
        delete window.screenshotVideoFrames;
      });
    }
  };

  const stylesheetResponses = [];
  const stylesheetFailures = [];
  page.on("response", (response) => {
    if (response.url().includes("/assets/css/app.css")) {
      stylesheetResponses.push((async () => ({
        status: response.status(),
        contentType: response.headers()["content-type"],
        text: await response.text()
      }))().then((result) => ({
        ...result,
        hasCanvasToken: result.text.includes("--color-canvas"),
        hasOldStyles: result.text.includes("radial-gradient(circle at 50% -20%"),
        text: result.text.slice(0, 180)
      })));
    }
  });
  page.on("requestfailed", (request) => {
    if (request.url().includes("/assets/css/app.css")) {
      stylesheetFailures.push(request.failure()?.errorText ?? "unknown request failure");
    }
  });

  const waitForTheme = async () => {
    try {
      await page.waitForFunction(
        () => getComputedStyle(document.body).backgroundColor === "rgb(14, 17, 19)",
        null,
        { timeout: 4_000 }
      );
    } catch (error) {
      const style = await page.evaluate(() => ({
        backgroundColor: getComputedStyle(document.body).backgroundColor,
        textColor: getComputedStyle(document.body).color,
        canvasToken: getComputedStyle(document.documentElement).getPropertyValue("--color-canvas"),
        bodyClass: document.body.className,
        stylesheetLinks: Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map((link) => ({
          href: link.href,
          disabled: link.disabled,
          sheet: Boolean(link.sheet),
          rules: link.sheet?.cssRules.length
        }))
      }));
      throw new Error(
        `Theme did not load: ${JSON.stringify(style)}; stylesheet responses: ${JSON.stringify(await Promise.all(stylesheetResponses))}; failures: ${stylesheetFailures}`,
        { cause: error }
      );
    }
    const stylesheet = await stylesheetResponses.at(-1);
    if (stylesheet?.status !== 200) {
      throw new Error(`App stylesheet returned HTTP ${stylesheet?.status ?? "no response"}.`);
    }
  };

  const normalizeDemoDetails = async () => {
    await page.evaluate(() => {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        node.textContent = node.textContent.replace(/\b\d+(?:\.\d+)? MB\b/g, "0.4 MB");
      }
    });
  };

  const waitForStablePage = async () => {
    await page.waitForFunction(() => window.liveSocket?.isConnected());
    await page.waitForTimeout(400);
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate(() => {
      for (const image of document.images) image.loading = "eager";
    });
    await page.waitForFunction(() => Array.from(document.images).every((image) => image.complete));
    await page.evaluate(() =>
      Promise.all(Array.from(document.images, (image) => image.decode().catch(() => {})))
    );
    await page.waitForFunction(() => {
      const progress = Array.from(document.querySelectorAll("canvas"))
        .find((canvas) => canvas.style.zIndex === "100001");
      return !progress || progress.style.display === "none";
    });
  };

  await page.route("https://image.tmdb.org/**", async (route) => {
    const isPoster = route.request().url().includes("readme-demo-poster");
    const width = isPoster ? 600 : 1440;
    const height = isPoster ? 900 : 720;
    const artwork = isPoster
      ? `<rect width="600" height="900" fill="#11191e"/><circle cx="400" cy="295" r="190" fill="#e47755" opacity=".76"/><path d="M0 600 205 360l160 174 95-115 140 181v300H0Z" fill="#283239"/><text x="52" y="710" fill="#f4f1ed" font-family="Arial,sans-serif" font-size="42" font-weight="700">AFTER THE</text><text x="52" y="763" fill="#f4f1ed" font-family="Arial,sans-serif" font-size="42" font-weight="700">SIGNAL</text><text x="55" y="812" fill="#b5b8ba" font-family="Arial,sans-serif" font-size="17" letter-spacing="4">A SAMPLE FILM</text>`
      : `<rect width="1440" height="720" fill="#10191e"/><circle cx="1050" cy="260" r="220" fill="#e47755" opacity=".42"/><path d="m0 530 260-210 190 142 210-232 230 302 180-165 370 260v93H0Z" fill="#283239"/><path d="m0 620 350-190 220 168 260-210 260 170 190-132 160 112v182H0Z" fill="#171f24"/><text x="110" y="565" fill="#f4f1ed" font-family="Arial,sans-serif" font-size="55" font-weight="700">AFTER THE SIGNAL</text>`;

    await route.fulfill({
      status: 200,
      contentType: "image/svg+xml",
      body: `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${artwork}</svg>`
    });
  });

  if (phase === "all" || phase === "public") {
    await page.goto(`${baseUrl}/setup`);
    await page.getByRole("heading").first().waitFor();
    await waitForStablePage();
    await waitForTheme();
    await page.screenshot({ animations: "disabled", path: screenshotPath("setup.png"), fullPage: true });

  }

  if (phase === "all" || phase === "app") {
    const ids = JSON.parse(await readFile(process.env.BOLOGNESA_SCREENSHOT_IDS, "utf8"));
    await page.goto(`${baseUrl}/login`);
    await page.getByRole("heading").first().waitFor();
    await waitForStablePage();
    await waitForTheme();
    await page.screenshot({ animations: "disabled", path: screenshotPath("login.png"), fullPage: true });
    const csrfToken = await page.locator('input[name="_csrf_token"]').inputValue();
    const loginResponse = await page.request.post(`${baseUrl}/login`, {
      form: {
        _csrf_token: csrfToken,
        "login[email]": "demo@example.test",
        "login[password]": "demo-password-only-for-screenshots"
      }
    });
    if (!loginResponse.ok()) {
      throw new Error(`Demo login failed with HTTP ${loginResponse.status()}.`);
    }

    const capture = async (name, route, selector = "main h1", loadingSelector = null) => {
      await page.goto(`${baseUrl}${route}`);
      await page.locator(selector).first().waitFor();
      await waitForStablePage();
      if (loadingSelector) {
        await page.locator(loadingSelector).waitFor({ state: "detached" });
      }
      if (route === "/libraries") {
        await page.locator('[data-library-name="Series"]').waitFor();
        await page.addStyleTag({
          content: `
            [data-library-name="Movies"] > .library-path,
            [data-library-name="Series"] > .library-path,
            [data-library-name="Music"] > .library-path { font-size: 0; }
            [data-library-name="Movies"] > .library-path::after {
              content: "/media/movies";
              font-size: 14px;
            }
            [data-library-name="Music"] > .library-path::after {
              content: "/media/music";
              font-size: 14px;
            }
            [data-library-name="Series"] > .library-path::after {
              content: "/media/series";
              font-size: 14px;
            }
          `
        });
      }
      if (route === "/settings") {
        await page.addStyleTag({
          content: `
            select {
              appearance: none !important;
              background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='m4 6 4 4 4-4' fill='none' stroke='%23f4f1ed' stroke-linecap='round' stroke-linejoin='round' stroke-width='1.5'/%3E%3C/svg%3E") !important;
              background-position: right 1rem center !important;
              background-repeat: no-repeat !important;
              background-size: 1rem !important;
            }
          `
        });
      }
      await waitForTheme();
      await normalizeDemoDetails();
      await page.evaluate(() => document.activeElement?.blur());
      await page.mouse.move(1430, 990);
      await withStableVideoFrame(() => page.screenshot({ animations: "disabled", path: screenshotPath(name), fullPage: true }));
    };

    if (!librariesOnly) await capture("home.png", "/");
    await capture("libraries.png", "/libraries");
    await page.locator('#library-add').click();
    await page.waitForFunction(() => document.activeElement?.id === "library-name");
    await page.screenshot({ animations: "disabled", path: screenshotPath("library-create.png") });
    await page.locator('#library-create-cancel').click();
    await page.locator('#library-form').waitFor({state: "detached"});
    // Exercise the library screen with the same synthetic data at each requested width.
    for (const width of [375, 430, 768, 1280]) {
      await page.setViewportSize({width, height: 900});
      if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) {
        throw new Error(`Libraries overflow at ${width}px.`);
      }
      const row = page.locator(`[data-library-name="Movies"]`);
      const scan = row.locator('button[id^="library-scan-"]').filter({hasText: "Scan"});
      await scan.waitFor({state: "visible"});
      if (!await scan.isEnabled()) throw new Error("Initial scan action is unavailable.");
      await row.locator('summary').click();
      if (width === 375 || width === 1280) {
        await page.screenshot({ animations: "disabled", path: screenshotPath(width === 375 ? "library-scan-details-mobile.png" : "library-scan-details.png"), fullPage: true });
      }
      await row.locator('[id^="library-reinspect-"]').click();
      const confirmation = page.locator('[role="dialog"][id^="library-reinspect-confirm-"]');
      await confirmation.waitFor({state: "visible"});
      if (!(await confirmation.textContent()).includes("Movies")) throw new Error("Confirmation lost library context.");
      await page.keyboard.press("Escape");
      await confirmation.waitFor({state: "detached"});
      if (!await row.locator('details').evaluate(el => el.open)) throw new Error("LiveView patch closed scan details.");
      await row.locator('summary').click();
      await page.locator('#library-add').click();
      await page.locator('#library-name').waitFor({state: "visible"});
      // JS.focus retries across two frames; wait before editing another field.
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      await page.waitForFunction(() => document.activeElement?.id === "library-name");
      if (width === 375) {
        await page.screenshot({ animations: "disabled", path: screenshotPath("library-create-mobile.png") });
      }
      const draftName = `Draft library ${width}`;
      await page.locator('#library-name').fill(draftName);
      await page.waitForFunction(() => !document.querySelector('#library-form').classList.contains('phx-change-loading'));
      await page.locator('#library-path').fill("/missing-library-source");
      await page.waitForFunction(() => !document.querySelector('#library-form').classList.contains('phx-change-loading'));
      if (await page.locator('#library-name').inputValue() !== draftName) throw new Error(`Draft name changed before submission at ${width}px.`);
      await page.locator('#library-submit').click();
      await page.locator('#library-error').waitFor({state: "visible"});
      await page.waitForFunction(() => !document.querySelector('#library-form').classList.contains('phx-submit-loading'));
      if (await page.locator('#library-name').inputValue() !== draftName) throw new Error(`Invalid source erased form values at ${width}px.`);
      await page.locator('#library-submit').focus();
      await page.keyboard.press("Tab");
      if (!await page.locator('#library-create-panel').evaluate(el => el.contains(document.activeElement))) throw new Error("Focus escaped the add panel.");
      await page.locator('#library-create-cancel').click();
      await page.locator('#library-form').waitFor({state: "detached"});
      await page.waitForFunction(() => document.activeElement?.id === "library-add");
      if (width === 375) await page.screenshot({path: screenshotPath("libraries-mobile.png"), fullPage: true});
    }
    await page.setViewportSize({width: 1440, height: 1000});
    if (!librariesOnly) {
    await capture("library.png", `/movies?library_id=${ids.movie_library}`, "main h1", "#movies-loading");
    await capture("movie-review.png", "/movies/review");
    await capture("movie.png", `/movies/${ids.movie}?library_id=${ids.movie_library}`);
    await page.locator("#movie-playback-options > summary").click();
    await page.locator('[id^="movie-play-"]').first().click();
    const video = page.locator("video[id^='movie-video-']");
    try {
      await video.waitFor({ state: "attached" });
    } catch (error) {
      const message = await page.locator("body").innerText().catch(() => "No page text");
      throw new Error(`The player did not open: ${message}`, { cause: error });
    }
    await video.evaluate((element) => element.play());
    await page.waitForFunction(() => {
      const element = document.querySelector("video[id^='movie-video-']");
      return element && element.readyState >= 2 && !element.paused;
    });
    await video.evaluate(async (element) => {
      const seeked = new Promise((resolve) => element.addEventListener("seeked", resolve, { once: true }));
      element.currentTime = 2;
      await seeked;
      element.pause();
    });
    const playButton = page.locator("#movie-player media-play-button");
    await playButton.click();
    await page.waitForFunction(() => !document.querySelector("#movie-player video").paused);
    await playButton.click();
    await page.waitForFunction(() => document.querySelector("#movie-player video").paused);
    const timeline = page.locator("#movie-player media-time-slider");
    await timeline.focus();
    await page.keyboard.press("Home");
    await page.keyboard.press("ArrowRight");
    await page.waitForFunction(() => document.querySelector("#movie-player video").currentTime > 0);
    await video.evaluate(async element => {
      const seeked = new Promise(resolve => element.addEventListener("seeked", resolve, {once: true}));
      element.currentTime = 2;
      await seeked;
    });
    await page.waitForTimeout(500);
    await normalizeDemoDetails();
    await page.evaluate(() => document.activeElement?.blur());
    await page.mouse.move(1430, 990);
    await withStableVideoFrame(() => page.locator("#movie-player").screenshot({ animations: "disabled", path: screenshotPath("player.png") }));

    await capture("music.png", `/music?library_id=${ids.music_library}`, "main h1", "#music-loading");
    await page.locator(`#play-track-${ids.music_track}`).click();
    const audio = page.locator("audio#music-player");
    await audio.waitFor({ state: "attached" });
    const assertMusicSearchAligned = async () => {
      const aligned = await page.locator("#music-search").evaluate(form => {
        const field = form.querySelector("input").getBoundingClientRect();
        const button = form.querySelector("button[type=submit]").getBoundingClientRect();
        return Math.abs(field.top - button.top) <= 1 && Math.abs(field.bottom - button.bottom) <= 1;
      });
      if (!aligned) throw new Error("Music search field and submit button are not aligned.");
    };
    await assertMusicSearchAligned();
    const audioFrame = page.locator("#music-player-frame");
    const audioPlay = audioFrame.locator("media-play-button");
    await page.waitForFunction(() => document.querySelector("#music-player")?.paused === false);
    const rowButton = page.locator(`#play-track-${ids.music_track}`);
    await page.waitForFunction(id => document.querySelector(`#play-track-${id}`)?.closest("article")?.dataset.playback === "playing", ids.music_track);
    await rowButton.click();
    await page.waitForFunction(id => document.querySelector(`#play-track-${id}`)?.closest("article")?.dataset.playback === "paused", ids.music_track);
    await rowButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector("audio#music-player");
      return element && element.readyState >= 2 && !element.paused && element.currentTime > 0;
    });
    await audioPlay.click();
    await page.waitForFunction(() => document.querySelector("#music-player")?.paused);
    const audioSlider = audioFrame.locator("media-time-slider");
    await audioSlider.focus();
    await page.keyboard.press("ArrowRight");
    await page.waitForFunction(() => document.querySelector("#music-player")?.currentTime >= 4);
    await audio.evaluate(async (element) => {
      element.pause();
      const seeked = new Promise((resolve) => element.addEventListener("seeked", resolve, { once: true }));
      element.currentTime = 2;
      await seeked;
    });
    const audioMute = audioFrame.locator("media-mute-button");
    await audioMute.click();
    await page.waitForFunction(() => document.querySelector("#music-player")?.muted);
    await audioMute.click();
    await page.waitForFunction(() => !document.querySelector("#music-player")?.muted);
    await audioFrame.locator("media-i18n").evaluate(element => { element.lang = "es"; });
    await page.waitForFunction(() => document.querySelector("audio-skin").shadowRoot.querySelector("media-play-button").getAttribute("aria-label") === "Reproducir");
    await audioFrame.locator("media-i18n").evaluate(element => { element.lang = "en"; });
    await page.waitForFunction(() => document.querySelector("audio-skin").shadowRoot.querySelector("media-play-button").getAttribute("aria-label") === "Play");
    await page.locator("#refresh-music").click();
    await page.locator("#music-loading").waitFor({ state: "detached" });
    const audioState = await audio.evaluate((element) => ({paused: element.paused, position: element.currentTime, error: element.error?.code}));
    if (!audioState.paused || Math.abs(audioState.position - 2) > 0.1 || audioState.error) {
      throw new Error(`Music playback/refresh verification failed: ${JSON.stringify(audioState)}`);
    }
    // The native buffered-range bar must be complete before capturing it.
    await page.waitForFunction(() => {
      const audio = document.querySelector("#music-player");
      return audio && Number.isFinite(audio.duration) && audio.buffered.length === 1
        && audio.buffered.start(0) <= 0.01 && audio.buffered.end(0) >= audio.duration - 0.01;
    });
    await waitForStablePage();
    await page.evaluate(() => document.activeElement?.blur());
    await page.mouse.move(1430, 990);
    await page.screenshot({ animations: "disabled", path: screenshotPath("music-player.png"), fullPage: true });
    console.log(`Verified Video.js audio controls with synthetic PCM WAV: play, keyboard seek, pause, mute, English/Spanish labels and refresh in Chromium ${browser.version()}.`);

    // Keep the music player and every browse view usable on narrow screens.
    await page.setViewportSize({width: 390, height: 844});
    const assertMusicFits = async () => {
      await assertMusicSearchAligned();
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      if (overflow) throw new Error("Music layout overflows the mobile viewport.");
      const miniPlayer = page.locator('#music-playback [data-player-action="expand"]');
      if (!await miniPlayer.isVisible()) throw new Error("Compact music player is hidden on mobile.");
      await miniPlayer.click();
      if (!await audioFrame.isVisible()) throw new Error("Expanded music player is hidden on mobile.");
      const playback = page.locator("#music-playback");
      if (await playback.getAttribute("role") !== "dialog" || await playback.getAttribute("aria-modal") !== "true") {
        throw new Error("Expanded music player is not exposed as a modal dialog.");
      }
      if (!await page.locator(".music-header").evaluate(element => element.inert)) {
        throw new Error("Background music controls remain available while the player is expanded.");
      }
      await page.setViewportSize({width: 700, height: 844});
      const keepsFullscreen = await playback.evaluate(element => getComputedStyle(element).position === "fixed");
      if (!keepsFullscreen) throw new Error("Expanded player stopped covering the page after a mobile rotation.");
      await page.setViewportSize({width: 390, height: 844});
      await page.keyboard.press("Escape");
      if (await miniPlayer.getAttribute("aria-expanded") !== "false") throw new Error("Escape did not minimize the music player.");
      if (!await miniPlayer.evaluate(element => document.activeElement === element)) throw new Error("Focus was not restored to the compact player.");
      await miniPlayer.click();
      await page.locator('#music-playback [data-player-action="collapse"]').click();
      const trackButtons = page.locator("#music-tracks .music-track-play");
      if (await trackButtons.count()) {
        await trackButtons.last().evaluate(element => element.scrollIntoView({block: "center"}));
      }
      const overlapsTracks = await page.evaluate(() => {
        const tracks = document.querySelector("#music-tracks");
        const player = document.querySelector("#music-playback")?.getBoundingClientRect();
        if (!tracks || tracks.hidden || !player) return false;
        return [...tracks.querySelectorAll("button")].some(button => {
          const rect = button.getBoundingClientRect();
          return rect.width && rect.height && rect.bottom > 0 && rect.top < innerHeight
            && rect.bottom > player.top && rect.top < player.bottom;
        });
      });
      if (overlapsTracks) throw new Error("Music player covers track controls on mobile.");
    };
    await assertMusicFits();
    await waitForStablePage();
    await page.screenshot({animations: "disabled", path: screenshotPath("music-mobile.png"), fullPage: true});
    await page.locator("#music-artists-link").click();
    await page.locator(`#artist-${ids.music_artist}`).waitFor();
    await assertMusicFits();
    await page.locator(`#artist-${ids.music_artist}`).click();
    await page.locator(`#album-${ids.music_album}`).waitFor();
    await assertMusicFits();
    await page.locator(`#album-${ids.music_album}`).click();
    await page.locator("#play-album").waitFor();
    await assertMusicFits();
    await page.setViewportSize({width: 1440, height: 1000});
    await page.locator("#music-albums-link").click();
    await page.locator(`#album-${ids.music_album}`).waitFor();
    await waitForStablePage();
    await page.screenshot({animations: "disabled", path: screenshotPath("music-albums.png"), fullPage: true});

    // Exercise artist -> album navigation and native ended-driven playback.
    await page.locator("#music-artists-link").click();
    await page.locator(`#artist-${ids.music_artist}`).click();
    await page.locator(`#album-${ids.music_album}`).click();
    await page.locator("#play-album").click();
    await page.waitForFunction((id) => {
      const audio = document.querySelector("#music-player");
      return audio?.querySelector("source")?.src.includes(`/tracks/${id}/`) && !audio.paused && audio.currentTime > 0;
    }, ids.music_track);
    await audio.evaluate((element) => { window.albumPlayerUnderTest = element; element.currentTime = element.duration - 0.2; });
    await page.waitForFunction((id) => {
      const audio = document.querySelector("#music-player");
      return audio?.querySelector("source")?.src.includes(`/tracks/${id}/`) && !audio.paused && audio.currentTime > 0;
    }, ids.music_second_track);
    await page.locator("#music-artists-link").click();
    await page.locator(`#artist-${ids.music_artist}`).waitFor();
    if (!await audio.evaluate((element) => element === window.albumPlayerUnderTest && !element.paused)) {
      throw new Error("Album player did not survive music patch navigation.");
    }
    await page.locator("#music-songs-link").click();
    await page.waitForFunction(id => document.querySelector(`#play-track-${id}`)?.closest("article")?.dataset.playback === "playing", ids.music_second_track);
    await page.locator("#queue-previous").click();
    await page.waitForFunction((id) => document.querySelector("#music-player source")?.src.includes(`/tracks/${id}/`), ids.music_track);
    await page.locator("#queue-next").click();
    await page.waitForFunction((id) => {
      const audio = document.querySelector("#music-player");
      return audio?.querySelector("source")?.src.includes(`/tracks/${id}/`) && audio.readyState >= 2 && !audio.paused;
    }, ids.music_second_track);
    await audio.evaluate((element) => { element.currentTime = element.duration - 0.2; });
    await page.locator("#queue-finished").waitFor();
    if (!await audio.evaluate((element) => element.paused)) throw new Error("Album did not stop after the last track.");
    await page.locator("#queue-previous").click();
    await page.waitForFunction(() => {
      const audio = document.querySelector("#music-player");
      return audio && !audio.paused && audio.currentTime > 0;
    });
    await page.locator(`#nav-library-${ids.series_library}`).click();
    await page.locator("#series-screen").waitFor({state: "visible"});
    await page.locator("#series-loading").waitFor({state: "detached"});
    await page.waitForFunction(() => {
      const previousAudio = window.albumPlayerUnderTest;
      return !previousAudio.isConnected && previousAudio.paused;
    });
    console.log("Verified artist/album navigation, automatic album advance, previous/next, music navigation continuity, final stop and stop on leaving music with synthetic WAV audio.");

    await capture("series.png", `/series?library_id=${ids.series_library}`, "main h1", "#series-loading");
    await capture("series-review.png", "/series/review");
    await capture("series-detail.png", `/series/${ids.series}?library_id=${ids.series_library}`);
    await capture("season.png", `/series/seasons/${ids.season}?library_id=${ids.series_library}`);
    await capture("episode.png", `/episodes/${ids.episode}?library_id=${ids.series_library}`);

    // Exercise the series journey at a narrow viewport, using actual LiveView navigation.
    await page.setViewportSize({width: 390, height: 844});
    const assertSeriesFits = async () => {
      if (new URL(page.url()).searchParams.get("library_id") !== String(ids.series_library)) {
        throw new Error("Mobile series navigation lost its library context.");
      }
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
      if (overflow) throw new Error("Series layout overflows the mobile viewport.");
    };
    await capture("series-mobile.png", `/series?library_id=${ids.series_library}`, "#series-screen h1", "#series-loading");
    await assertSeriesFits();
    const menuToggle = page.locator("#app-menu-toggle");
    await menuToggle.click();
    await page.locator("#app-navigation[open]").waitFor();
    await page.locator(`#nav-library-${ids.series_library}`).waitFor({state: "visible"});
    await page.evaluate(() => {
      const group = document.querySelector(".app-nav-primary");
      const original = group.querySelector("a");
      for (let n = 0; n < 30; n++) {
        const item = original.cloneNode(true);
        item.removeAttribute("id");
        item.removeAttribute("aria-current");
        item.dataset.navigationProbe = "true";
        item.querySelector("span").textContent = `A library with a long descriptive name ${n}`;
        group.append(item);
      }
    });
    await page.locator("[data-navigation-probe]").last().scrollIntoViewIfNeeded();
    if (!await page.locator("#app-menu-close").evaluate(element => {
      const rect = element.getBoundingClientRect();
      return rect.top >= 0 && rect.bottom <= innerHeight;
    })) throw new Error("Many libraries pushed navigation close out of view.");
    if (await page.evaluate(() => document.querySelector("#app-navigation").scrollWidth > document.querySelector("#app-navigation").clientWidth)) {
      throw new Error("Long library names overflow the mobile navigation.");
    }
    await page.evaluate(() => {
      document.querySelectorAll("[data-navigation-probe]").forEach(element => element.remove());
      document.querySelector(".app-nav-primary").scrollTop = 0;
    });
    await page.keyboard.press("Escape");
    await page.locator("#app-navigation:not([open])").waitFor({state: "attached"});
    if (!await menuToggle.evaluate(element => element === document.activeElement)) {
      throw new Error("Closing mobile navigation did not return focus to its trigger.");
    }
    await menuToggle.click();
    await page.setViewportSize({width: 1440, height: 1000});
    await page.locator(`#nav-library-${ids.series_library}`).waitFor({state: "visible"});
    await page.setViewportSize({width: 390, height: 844});
    await page.locator("#app-navigation:not([open])").waitFor({state: "attached"});
    await page.locator("#series-list a").first().click();
    await page.locator("#series-title").waitFor();
    await waitForStablePage();
    await assertSeriesFits();
    await capture("series-detail-mobile.png", `/series/${ids.series}?library_id=${ids.series_library}`, "#series-title");
    await page.locator("#season-list a").first().click();
    await page.locator("#season-title").waitFor();
    await page.locator("#episodes-loading").waitFor({state: "detached"});
    await assertSeriesFits();
    await capture("season-mobile.png", `/series/seasons/${ids.season}?library_id=${ids.series_library}`, "#season-title", "#episodes-loading");
    await page.locator("#episode-list a").first().click();
    await page.locator("#episode-title").waitFor();
    await page.locator("#episode-loading").waitFor({state: "detached"});
    await assertSeriesFits();
    const episodeBreadcrumbFontSize = await page.locator("#episode-breadcrumb").evaluate(
      element => Number.parseFloat(getComputedStyle(element).fontSize)
    );
    if (episodeBreadcrumbFontSize < 16) throw new Error("Episode breadcrumb text is too small.");
    const playerFits = await page.locator("#episode-player").evaluate(element => {
      const rect = element.getBoundingClientRect();
      return rect.top >= 0 && rect.bottom <= innerHeight;
    });
    if (!playerFits) throw new Error("Episode player is outside the first mobile viewport.");
    const episodeVideo = await page.locator("#episode-video-frame video").elementHandle();
    await page.locator("#episode-description > summary").click();
    if (!await episodeVideo.evaluate(video => video.isConnected)) {
      throw new Error("Expanding the synopsis recreated the episode player.");
    }
    await page.locator("#episode-description > summary").click();
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({width, height: 1000});
      const fits = await page.evaluate(() => {
        const series = document.querySelector("#episode-series");
        const title = series.textContent;
        series.textContent = title.repeat(20);
        const season = document.querySelector("#episode-season").getBoundingClientRect();
        const frame = document.querySelector("#episode-video-frame").getBoundingClientRect();
        const result = document.documentElement.scrollWidth <= innerWidth &&
          season.right <= innerWidth && season.left >= 0 &&
          Math.abs(frame.width / frame.height - 16 / 9) < 0.03;
        series.textContent = title;
        return result;
      });
      if (!fits) throw new Error(`Episode layout or long breadcrumb does not fit at ${width}px.`);
    }
    await page.setViewportSize({width: 390, height: 844});
    await page.locator("#episode-playback-options > summary").click();
    await page.locator("#episode-versions").waitFor({state: "visible"});
    await page.locator("#episode-playback-options > summary").click();
    await page.locator("#episode-back").click();
    await page.locator("#season-title").waitFor();
    await assertSeriesFits();
    await page.locator("#season-back").click();
    await page.locator("#series-title").waitFor();
    await assertSeriesFits();
    await capture("episode-mobile.png", `/episodes/${ids.episode}?library_id=${ids.series_library}`, "#episode-title", "#episode-loading");
    console.log("Verified mobile series layouts and catalog/series/season/episode navigation with library context.");

    const assertMoviesFit = async () => {
      if (new URL(page.url()).searchParams.get("library_id") !== String(ids.movie_library)) {
        throw new Error("Mobile movie navigation lost its library context.");
      }
      if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) {
        throw new Error("Movie layout overflows the mobile viewport.");
      }
    };
    await capture("movies-mobile.png", `/movies?library_id=${ids.movie_library}`, "#movies-screen h1", "#movies-loading");
    await assertMoviesFit();
    await page.locator("#movies-list a").first().click();
    await page.locator("#movie-title").waitFor();
    await waitForStablePage();
    await assertMoviesFit();
    await capture("movie-mobile.png", `/movies/${ids.movie}?library_id=${ids.movie_library}`, "#movie-title", "#movie-loading");
    await assertMoviesFit();
    await page.locator("#movie-playback-options > summary").click();
    await page.locator('[id^="movie-play-"]').first().click();
    await page.locator("#movie-player video").waitFor({state: "attached"});
    await assertMoviesFit();
    await page.locator('[id^="movie-correct-"]').first().click();
    await page.locator("#movie-review").waitFor();
    await page.setViewportSize({width: 1440, height: 1000});
    console.log("Verified mobile movie layouts, library context, playback entry and manual-correction navigation.");

    await capture("settings.png", "/settings");
    await capture("about.png", "/about");
    }

    await page.goto(`${baseUrl}/libraries`);
    const libraryRow = page.locator('[data-library-name="Movies"]');
    const details = libraryRow.locator('details');
    await details.locator('summary').click();
    await libraryRow.locator('button[id^="library-reinspect-"]').click();
    await page.evaluate(() => {
      window.libraryFocusAudit = [];
      document.addEventListener("focusin", event => window.libraryFocusAudit.push({id: event.target.id, tag: event.target.tagName}));
    });
    await page.locator(`#library-reinspect-confirm-button-${ids.movie_library}`).click();
    await page.locator(`#library-scan-state-${ids.movie_library}[data-state="queued"]`).waitFor();
    if (await libraryRow.locator('button[id^="library-scan-"]').isEnabled()) throw new Error("Scan remained enabled while queued.");
    if (await libraryRow.locator('button[id^="library-reinspect-"]').isEnabled()) throw new Error("Reanalysis remained enabled while queued.");
    try {
    await page.waitForFunction(id => document.activeElement === document.querySelector(`#library-details-${id} > summary`), ids.movie_library);
    } catch (error) {
      console.log(await page.evaluate(id => ({active: {id: document.activeElement.id, tag: document.activeElement.tagName}, summary: document.querySelector(`#library-details-${id}`)?.outerHTML, audit: window.libraryFocusAudit}), ids.movie_library));
      throw error;
    }
    if (!await details.evaluate(el => el.open)) throw new Error("Status refresh closed scan details.");
    const musicRow = page.locator('[data-library-name="Music"]');
    await musicRow.locator('button[id^="library-scan-"]').click();
    await page.locator(`#library-scan-state-${ids.music_library}[data-state="queued"]`).waitFor();
    await page.reload();
    await page.locator(`#library-scan-state-${ids.movie_library}[data-state="queued"]`).waitFor();
    await page.locator(`#library-scan-state-${ids.music_library}[data-state="queued"]`).waitFor();
    console.log("Verified responsive libraries at 375/430/768/1280px, form validation and focus, contextual confirmation, disclosure preservation and durable concurrent scan requests.");
  }

  console.log(`Captured README screenshots (${phase}) into ${outputDirectory}.`);
} finally {
  await browser.close();
}
