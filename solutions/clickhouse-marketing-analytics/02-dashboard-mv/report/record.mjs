/* Record the staged reveal as video: opens the report page, waits until every
 * panel has revealed, keeps rolling a beat, saves a .webm into recordings/.
 *
 *   node record.mjs [url] [out-dir]
 *
 * Needs playwright (npx playwright install chromium). The page must be served
 * by server.py (it holds the ClickHouse credentials).
 * Convert for the article:  ffmpeg -i reveal.webm -vf fps=12,scale=1160:-1 reveal.gif
 */
import { chromium } from "playwright";

const url = process.argv[2] ?? "http://localhost:8088/";
const dir = process.argv[3] ?? "recordings";

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: 1280, height: 1450 },
  recordVideo: { dir, size: { width: 1280, height: 1450 } },
});
const page = await ctx.newPage();
page.on("console", (m) => m.type() === "error" && console.error("[page]", m.text()));

await page.goto(url, { waitUntil: "domcontentloaded" });
await page.waitForFunction(
  () => document.querySelectorAll(".panel").length > 0 &&
        document.querySelectorAll(".panel:not(.revealed)").length === 0,
  { timeout: 600_000 });
await page.waitForTimeout(2500);                 // hold the finished report

const video = page.video();
await ctx.close();
const path = await video.path();
await browser.close();
console.log(`recorded: ${path}`);
