import { chromium } from "playwright";

const browser = await chromium.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
});

const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const consoleErrors = [];
page.on("console", (message) => {
  if (message.type() === "error") consoleErrors.push(message.text());
});

try {
  await page.goto("http://localhost:3000", { waitUntil: "networkidle" });

  const heading = page.getByRole("heading", { name: "가위바위보 아레나" });
  await heading.waitFor();

  const totalText = await page.locator("header").getByText(/총 \d+판/).textContent();
  const totalBefore = Number(totalText?.match(/\d+/)?.[0] ?? -1);
  if (totalBefore < 0) throw new Error("Initial total was not rendered.");

  await page.getByRole("button", { name: "바위 선택" }).click();
  await page.getByText("방금 결과").waitFor();
  await page.getByText(`총 ${totalBefore + 1}판`).waitFor();

  const overlay = await page.locator("[data-nextjs-dialog]").count();
  if (overlay > 0) throw new Error("Next.js error overlay is visible.");
  if (consoleErrors.length > 0) {
    throw new Error(`Console errors: ${consoleErrors.join(" | ")}`);
  }

  await page.screenshot({ path: "/tmp/rps-arena-verified.png", fullPage: true });
  console.log(JSON.stringify({
    status: "passed",
    title: await page.title(),
    totalBefore,
    totalAfter: totalBefore + 1,
    screenshot: "/tmp/rps-arena-verified.png",
  }));
} finally {
  await browser.close();
}
