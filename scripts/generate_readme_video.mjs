import { writeFile } from "node:fs/promises";
import { chromium } from "playwright";

const outputPath = process.argv[2];
if (!outputPath) throw new Error("Pass the output path for the synthetic video.");

const browser = process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS
  ? await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, { exposeNetwork: "<loopback>" })
  : await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  const video = await page.evaluate(async () => {
    const canvas = document.createElement("canvas");
    canvas.width = 1280;
    canvas.height = 720;
    const context = canvas.getContext("2d");
    const gradient = context.createLinearGradient(0, 0, 1280, 720);
    gradient.addColorStop(0, "#11191e");
    gradient.addColorStop(1, "#39454a");
    context.fillStyle = gradient;
    context.fillRect(0, 0, 1280, 720);
    context.fillStyle = "rgba(228, 119, 85, .72)";
    context.beginPath();
    context.arc(920, 250, 190, 0, Math.PI * 2);
    context.fill();
    context.fillStyle = "#202b30";
    context.beginPath();
    context.moveTo(0, 570);
    context.lineTo(260, 350);
    context.lineTo(430, 510);
    context.lineTo(680, 290);
    context.lineTo(960, 570);
    context.lineTo(1120, 420);
    context.lineTo(1280, 540);
    context.lineTo(1280, 720);
    context.lineTo(0, 720);
    context.fill();
    context.fillStyle = "#f4f1ed";
    context.font = "700 56px Arial, sans-serif";
    context.fillText("AFTER THE SIGNAL", 72, 620);

    const stream = canvas.captureStream(24);
    const recorder = new MediaRecorder(stream, { mimeType: "video/webm;codecs=vp8" });
    const chunks = [];
    const finished = new Promise((resolve, reject) => {
      recorder.addEventListener("dataavailable", (event) => {
        if (event.data.size > 0) chunks.push(event.data);
      });
      recorder.addEventListener("stop", () => resolve(new Blob(chunks, { type: recorder.mimeType })));
      recorder.addEventListener("error", (event) => reject(event.error));
    });
    recorder.start(250);
    await new Promise((resolve) => {
      const stopAt = performance.now() + 6000;
      const renderFrame = (now) => {
        context.fillStyle = "#e47755";
        context.fillRect(72, 646, 190, 5);

        if (now >= stopAt) {
          recorder.stop();
          resolve();
        } else {
          requestAnimationFrame(renderFrame);
        }
      };

      requestAnimationFrame(renderFrame);
    });
    const blob = await finished;
    const preview = document.createElement("video");
    preview.muted = true;
    preview.src = URL.createObjectURL(blob);
    await new Promise((resolve, reject) => {
      preview.addEventListener("loadedmetadata", resolve, { once: true });
      preview.addEventListener("error", () => reject(preview.error), { once: true });
    });
    if (preview.duration < 1) throw new Error(`Synthetic video is too short: ${preview.duration}s`);
    await preview.play();
    if (preview.paused) throw new Error("Synthetic video did not start playing.");
    preview.pause();
    return Array.from(new Uint8Array(await blob.arrayBuffer()));
  });

  await writeFile(outputPath, Buffer.from(video));
} finally {
  await browser.close();
}
