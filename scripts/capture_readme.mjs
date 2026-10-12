import { fileURLToPath } from "node:url";
import { mkdir, readFile } from "node:fs/promises";
import { chromium } from "playwright";

const baseUrl = process.env.BOLOGNESA_URL ?? "http://127.0.0.1:4001";
const phase = process.env.BOLOGNESA_CAPTURE_PHASE ?? "all";
const outputDirectory = process.env.BOLOGNESA_SCREENSHOT_OUTPUT_DIR
  ?? fileURLToPath(new URL("../docs/screenshots/", import.meta.url));
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
    await page.screenshot({ path: screenshotPath("setup.png"), fullPage: true });

  }

  if (phase === "all" || phase === "app") {
    const ids = JSON.parse(await readFile(process.env.BOLOGNESA_SCREENSHOT_IDS, "utf8"));
    await page.goto(`${baseUrl}/login`);
    await page.getByRole("heading").first().waitFor();
    await waitForStablePage();
    await waitForTheme();
    await page.screenshot({ path: screenshotPath("login.png"), fullPage: true });
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
            [data-library-name="Movies"] > p:nth-of-type(2),
            [data-library-name="Series"] > p:nth-of-type(2) { font-size: 0; }
            [data-library-name="Movies"] > p:nth-of-type(2)::after {
              content: "/media/movies";
              font-size: 14px;
            }
            [data-library-name="Series"] > p:nth-of-type(2)::after {
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
      await page.screenshot({ path: screenshotPath(name), fullPage: true });
    };

    await capture("home.png", "/");
    await capture("libraries.png", "/libraries");
    await capture("library.png", `/movies?library_id=${ids.movie_library}`, "main h1", "#movies-loading");
    await capture("movie-review.png", "/movies/review");
    await capture("movie.png", `/movies/${ids.movie}?library_id=${ids.movie_library}`);
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
    await page.waitForTimeout(500);
    await video.evaluate((element) => {
      element.removeAttribute("controls");
    });
    await video.evaluate((element) => {
      const player = document.querySelector("#movie-player");
      const playerRect = player.getBoundingClientRect();
      const videoRect = element.getBoundingClientRect();
      const frame = document.createElement("div");
      frame.setAttribute("aria-hidden", "true");
      frame.style.cssText = `position:absolute;z-index:1;left:${videoRect.left - playerRect.left}px;top:${videoRect.top - playerRect.top}px;width:${videoRect.width}px;height:${videoRect.height}px;background:#10191e url("data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="720" viewBox="0 0 1440 720"><rect width="1440" height="720" fill="#10191e"/><circle cx="1050" cy="260" r="220" fill="#e47755" opacity=".42"/><path d="m0 530 260-210 190 142 210-232 230 302 180-165 370 260v93H0Z" fill="#283239"/><path d="m0 620 350-190 220 168 260-210 260 170 190-132 160 112v182H0Z" fill="#171f24"/><text x="110" y="565" fill="#f4f1ed" font-family="Arial,sans-serif" font-size="55" font-weight="700">AFTER THE SIGNAL</text></svg>')}" center / 100% 100% no-repeat;pointer-events:none;`;
      player.append(frame);
      element.style.visibility = "hidden";
    });
    await page.addStyleTag({
      content: `
        #movie-player { position: relative; }
        #movie-player video { display: block; }
        #movie-player::after {
          content: "▶   0:02 / 0:04                                      ◖   ⛶";
          position: absolute;
          left: 16px;
          right: 16px;
          bottom: 0;
          height: 44px;
          display: flex;
          align-items: flex-end;
          padding: 0 12px 12px;
          box-sizing: border-box;
          color: #fff;
          font: 13px Arial, sans-serif;
          white-space: pre;
          background:
            linear-gradient(#e47755, #e47755) 116px calc(100% - 12px) / 50% 3px no-repeat,
            linear-gradient(#aaa, #aaa) 116px calc(100% - 12px) / calc(100% - 180px) 3px no-repeat,
            linear-gradient(transparent, rgba(0, 0, 0, .9));
          pointer-events: none;
          z-index: 2;
        }
      `
    });
    await normalizeDemoDetails();
    await page.evaluate(() => document.activeElement?.blur());
    await page.mouse.move(1430, 990);
    await page.screenshot({ path: screenshotPath("player.png"), fullPage: true });

    await capture("series.png", `/series?library_id=${ids.series_library}`, "main h1", "#series-loading");
    await capture("series-review.png", "/series/review");
    await capture("series-detail.png", `/series/${ids.series}?library_id=${ids.series_library}`);
    await capture("season.png", `/series/seasons/${ids.season}?library_id=${ids.series_library}`);
    await capture("episode.png", `/episodes/${ids.episode}?library_id=${ids.series_library}`);
    await capture("settings.png", "/settings");
    await capture("about.png", "/about");
  }

  console.log(`Captured README screenshots (${phase}) into ${outputDirectory}.`);
} finally {
  await browser.close();
}
