import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";

// Mutate only the disposable database created by the screenshot runner.
export async function verifySeriesUI(page, {baseUrl, ids, waitForStablePage}) {
  const container = process.env.BOLOGNESA_SCREENSHOT_DB_CONTAINER;
  if (!container) throw new Error("Series UI verification requires the disposable screenshot database.");
  assert(Number.isSafeInteger(ids.series));
  assert(Number.isSafeInteger(ids.episode));
  const query = sql => execFileSync("docker", ["exec", "-i", container, "psql", "-U", "postgres",
    "-d", "bolognesa_screenshots", "-At", "-v", "ON_ERROR_STOP=1"], {input: sql, encoding: "utf8"}).trim();
  const original = JSON.parse(query(`SELECT json_build_object('title', title, 'overview', overview) FROM series WHERE id = ${ids.series};`));
  const originalEpisode = JSON.parse(query(`SELECT json_build_object('title', title, 'overview', overview) FROM episodes WHERE id = ${ids.episode};`));
  const literal = value => value == null ? "NULL" : `'${value.replaceAll("'", "''")}'`;
  const update = (title, overview) => query(`UPDATE series SET title = ${literal(title)}, overview = ${literal(overview)} WHERE id = ${ids.series};`);
  const updateEpisode = (title, overview) => query(`UPDATE episodes SET title = ${literal(title)}, overview = ${literal(overview)} WHERE id = ${ids.episode};`);
  const routes = [
    `/series?library_id=${ids.series_library}`,
    `/series/${ids.series}?library_id=${ids.series_library}`,
    `/series/seasons/${ids.season}?library_id=${ids.series_library}`,
    `/episodes/${ids.episode}?library_id=${ids.series_library}`,
    "/series/review",
  ];
  const longTitle = "The Late Night Radio Show and the Neighbours Who Keep Listening";
  const longText = "The neighbours share stories, music and memories over the late night radio. ".repeat(30);
  try {
    update(longTitle, longText);
    updateEpisode(`The First Call and the Story That Continues Until Morning`, longText);
    const catalogWidths = new Map();
    for (const width of [320, 390, 639, 640, 768, 1023, 1024, 1440]) {
      await page.setViewportSize({width, height: 1000});
      let catalogLeft;
      for (const [index, route] of routes.entries()) {
        await page.goto(`${baseUrl}${route}`);
        await page.locator("main h1").first().waitFor();
        await waitForStablePage();
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false,
          `Series route ${route} overflows at ${width}px`);
        if (index === 0) {
          const cardWidth = await page.locator(".series-catalog-card").first().evaluate(el => el.getBoundingClientRect().width);
          assert(cardWidth >= 130 && cardWidth < 280, `Unexpected poster width ${cardWidth} at ${width}px`);
          catalogWidths.set(width, cardWidth);
          catalogLeft = await page.locator("main h1").first().evaluate(el => el.getBoundingClientRect().left);
        }
        if (route === "/series/review") {
          const reviewLeft = await page.locator("main h1").first().evaluate(el => el.getBoundingClientRect().left);
          assert(Math.abs(reviewLeft - catalogLeft) < 1, `Review heading is misaligned at ${width}px`);
        }
      }
    }
    assert(Math.abs(catalogWidths.get(1024) - catalogWidths.get(1023)) < 40, "Sidebar causes an abrupt poster size change");

    await page.setViewportSize({width: 390, height: 844});
    await page.goto(`${baseUrl}${routes[0]}`);
    await waitForStablePage();
    const options = page.locator("#series-library-options > summary");
    await page.mouse.move(0, 0);
    const optionsBackground = await options.evaluate(el => getComputedStyle(el).backgroundColor);
    await options.hover();
    assert.notEqual(await options.evaluate(el => getComputedStyle(el).backgroundColor), optionsBackground, "Library options lack hover feedback");
    await options.focus();
    await page.keyboard.press("Tab");
    await page.keyboard.press("Shift+Tab");
    assert(await options.evaluate(el => el === document.activeElement && getComputedStyle(el).outlineStyle !== "none"), "Library options lack keyboard focus");
    await page.keyboard.press("Enter");
    await page.locator("#series-library-options[open] #series-review-link").waitFor({state: "visible"});
    await page.keyboard.press("Enter");
    await page.locator("#series-library-options:not([open])").waitFor({state: "attached"});

    await page.goto(`${baseUrl}${routes[2]}`);
    await waitForStablePage();
    const play = page.locator(".series-episode-play").first();
    await page.mouse.move(0, 0);
    const playBackground = await play.evaluate(el => getComputedStyle(el).backgroundColor);
    await play.hover();
    assert.notEqual(await play.evaluate(el => getComputedStyle(el).backgroundColor), playBackground, "Episode play lacks hover feedback");

    await page.goto(`${baseUrl}${routes[1]}`);
    await waitForStablePage();
    const synopsis = page.locator("#series-synopsis");
    const summary = synopsis.locator("summary");
    await page.locator('#series-synopsis[data-expandable="true"]').waitFor();
    await summary.focus();
    // Tab away and back establishes keyboard focus, including :focus-visible.
    await page.keyboard.press("Tab");
    await page.keyboard.press("Shift+Tab");
    assert(await summary.evaluate(el => el === document.activeElement && getComputedStyle(el).outlineStyle !== "none"), "Synopsis keyboard focus is invisible");
    await page.keyboard.press("Enter");
    await page.waitForFunction(() => document.querySelector("#series-synopsis").open);
    await page.setViewportSize({width: 1440, height: 1000});
    await page.waitForFunction(() => {
      const el = document.querySelector("#series-synopsis");
      return el.open && el.dataset.expandable === "true";
    });
    await page.setViewportSize({width: 320, height: 844});
    assert(await synopsis.evaluate(el => el.open), "Resizing collapsed the expanded synopsis");

    // The real retry event patches this mounted LiveView with changed fixture data.
    await synopsis.evaluate(el => { window.seriesSynopsisUnderTest = el; });
    const refresh = async title => {
      await page.evaluate(() => {
        const button = document.createElement("button");
        button.id = "series-ui-refresh-probe";
        button.setAttribute("phx-click", "retry");
        button.textContent = "Refresh fixture";
        document.querySelector(".series-screen").append(button);
      });
      await page.locator("#series-ui-refresh-probe").click();
      await page.waitForFunction(title => document.querySelector("#series-title")?.textContent.trim() === title, title);
      await page.locator("#series-loading").waitFor({state: "detached"});
      assert(await synopsis.evaluate(el => el === window.seriesSynopsisUnderTest), "LiveView replaced the synopsis instead of patching it");
      await page.evaluate(() => document.querySelector("#series-ui-refresh-probe")?.remove());
    };
    update("Updated long synopsis", `${longText} Another story reaches the radio.`);
    await refresh("Updated long synopsis");
    assert(await synopsis.evaluate(el => el.open && el.dataset.expandable === "true"), "LiveView patch lost expanded state");
    await summary.focus();
    await page.keyboard.press("Enter");
    await page.waitForFunction(() => !document.querySelector("#series-synopsis").open);
    await summary.click();
    await page.waitForFunction(() => document.querySelector("#series-synopsis").open);

    update("Updated short synopsis", "A short story.");
    await refresh("Updated short synopsis");
    await page.locator('#series-synopsis[data-expandable="false"]').waitFor();
    assert.equal(await synopsis.evaluate(el => el.open), false);
    assert.equal(await summary.getAttribute("tabindex"), "-1");
    assert.equal(await synopsis.locator(".media-read-more").isVisible(), false);
    await summary.click();
    assert.equal(await synopsis.evaluate(el => el.open), false, "Short synopsis still toggles");
    console.log("Verified Series layouts at 320/390/639/640/768/1023/1024/1440px with long content, hover/menu feedback, keyboard disclosure/focus, expanded resizing and real LiveView content patches.");
  } finally {
    update(original.title, original.overview);
    updateEpisode(originalEpisode.title, originalEpisode.overview);
    await page.setViewportSize({width: 1440, height: 1000});
  }
}
