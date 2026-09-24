import { expect, test } from "@playwright/test";

test("the complete product map renders and can be explored without relayout", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto("/");
  const content = page.getByTestId("diagram-content");
  await expect(content.locator("svg")).toBeVisible();
  await expect(page.getByTestId("diagram-loading")).toBeHidden();
  await expect(content).toContainText("Start, sign in, permissions and owner changes");
  await expect(content).toContainText("Runtime updates, feedback and privacy");
  await expect(content).toContainText("AppDelegate.applicationDidFinishLaunching");
  expect(await content.locator(".node").count()).toBeGreaterThan(200);
  expect(await content.locator(".edgePath, .flowchart-link").count()).toBeGreaterThan(400);
  // HTML line breaks must be rendered as lines rather than literal markup.
  expect(await content.innerText()).not.toContain("<br/>");
  const svgId = await content.locator("svg").getAttribute("id");
  const initialScale = Number(await content.getAttribute("data-scale"));
  await page.getByRole("button", { name: "Zoom in", exact: true }).click();
  expect(Number(await content.getAttribute("data-scale"))).toBeGreaterThan(initialScale);
  await page.getByRole("button", { name: "Zoom out", exact: true }).click();
  const initialX = Number(await content.getAttribute("data-x"));
  const box = await page.getByTestId("diagram-viewport").boundingBox();
  if (!box) throw new Error("Diagram viewport has no bounds");
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 120, box.y + box.height / 2 + 80, { steps: 6 });
  await page.mouse.up();
  expect(Number(await content.getAttribute("data-x"))).not.toBe(initialX);
  await page.getByRole("button", { name: "Fit diagram", exact: true }).click();
  await page.setViewportSize({ width: 900, height: 700 });
  await expect(content.locator("svg")).toBeVisible();
  expect(await content.locator("svg").getAttribute("id")).toBe(svgId);
  await page.getByTestId("diagram-viewport").focus();
  await page.keyboard.press("+");
  await page.getByRole("button", { name: "Enter fullscreen", exact: true }).click();
  await expect(page.getByRole("button", { name: "Exit fullscreen", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Exit fullscreen", exact: true }).click();
  expect(errors).toEqual([]);
});

test("invalid Mermaid has an explicit error and retry, and a corrected response recovers", async ({ page }) => {
  await page.route("http://127.0.0.1:4173/", async route => {
    const response = await route.fetch();
    const html = await response.text();
    expect(html).toContain("flowchart TD");
    // RSC text records are byte-length framed; preserve the input length so
    // this exercises Mermaid failure, not a broken React hydration payload.
    await route.fulfill({ response, body: html.replaceAll("flowchart TD", "NOT_A_GRAPH!") });
  });
  await page.goto("/");
  await expect(page.getByTestId("diagram-error")).toBeVisible();
  await expect(page.getByTestId("diagram-loading")).toBeHidden();
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(page.getByTestId("diagram-error")).toBeVisible();
  await page.unroute("http://127.0.0.1:4173/");
  await page.reload();
  await expect(page.getByTestId("diagram-content").locator("svg")).toBeVisible();
});

test("the published source link names the exact build commit", async ({ page }) => {
  await page.goto("/");
  const commit = process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA;
  const link = page.getByTestId("commit-link");
  if (commit) {
    await expect(link).toHaveAttribute("href", `https://github.com/sruj75/knowledge-athlete/blob/${commit}/docs/architecture/intentive-codeflow.mmd`);
    await expect(link).toContainText(commit.slice(0, 7));
  } else {
    // Local edited trees intentionally do not claim to match a committed map.
    if (await link.count()) {
      expect(await link.getAttribute("href")).toMatch(/\/blob\/[a-f0-9]{40}\/docs\/architecture\/intentive-codeflow\.mmd$/);
    } else {
      await expect(page.getByText("Local build · commit unavailable")).toBeVisible();
    }
  }
});
