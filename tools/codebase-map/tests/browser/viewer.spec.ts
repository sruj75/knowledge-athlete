import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

const areaCards = (page: Page) => page.locator('[data-testid^="area-card-AREA_"]');
const areaSvg = (page: Page) => page.locator('[data-testid="area-diagram"] svg, svg[data-testid="area-diagram"]');

async function camera(page: Page) {
  return page.getByTestId("diagram-content").evaluate(element => ({
    x: Number(element.getAttribute("data-x")),
    y: Number(element.getAttribute("data-y")),
    scale: Number(element.getAttribute("data-scale")),
  }));
}

async function overview(page: Page) {
  await page.goto("/");
  await expect(areaCards(page)).toHaveCount(23);
  await expect(page.getByTestId("diagram-loading")).toBeHidden();
  await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", "");
}

async function focusArea(page: Page, id: string) {
  await page.getByLabel("Jump to area", { exact: true }).selectOption(id);
  await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", id);
  await expect(page.getByLabel("Jump to area", { exact: true })).toHaveValue(id);
  await expect(page.locator(".current-area")).toContainText(id.slice(-2));
  await expect(areaSvg(page)).toBeVisible();
  await expect(page.getByTestId("area-loading")).toBeHidden();
  await expect(page.getByTestId("area-diagram")).toHaveCount(1);
}

async function cardPositions(page: Page) {
  return areaCards(page).evaluateAll(cards => cards.map(card => ({
    id: card.getAttribute("data-area-id"),
    x: card.getAttribute("data-world-x"),
    y: card.getAttribute("data-world-y"),
  })));
}

async function tabWithoutMovingMap(page: Page, steps: number) {
  const initial = await camera(page);
  for (let step = 0; step < steps; step += 1) {
    await page.keyboard.press("Tab");
    const state = await page.evaluate(() => {
      const viewport = document.querySelector('[data-testid="diagram-viewport"]')!;
      const main = document.querySelector(".map-main")!;
      const active = document.activeElement!;
      const visible = viewport.getBoundingClientRect();
      const focused = active.getBoundingClientRect();
      return {
        scroll: [viewport.scrollLeft, viewport.scrollTop, main.scrollLeft, main.scrollTop],
        focus: active.getAttribute("aria-label") || active.getAttribute("data-testid") || active.tagName,
        reachable: !viewport.contains(active) || active === viewport || (
          Math.min(focused.right, visible.right) > Math.max(focused.left, visible.left)
          && Math.min(focused.bottom, visible.bottom) > Math.max(focused.top, visible.top)
        ),
      };
    });
    expect(state.scroll, `Tab ${step + 1}: ${state.focus}`).toEqual([0, 0, 0, 0]);
    expect(state.reachable, `Tab ${step + 1} focused an offscreen control: ${state.focus}`).toBe(true);
    expect(await camera(page), `Tab ${step + 1} changed the camera`).toEqual(initial);
  }
}

for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
  test(`overview has 23 readable areas without a miniature node graph at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await overview(page);
    const content = page.getByTestId("diagram-content");
    await expect(content).toHaveAttribute("data-area-count", "23");
    await expect(content).toHaveAttribute("data-node-count", "210");
    await expect(content).toHaveAttribute("data-edge-count", "422");
    await expect(content.locator("[data-node-id], [data-edge-id]")).toHaveCount(0);
    await expect(page.getByTestId("area-card-AREA_01")).toHaveAccessibleName(/Start, sign in, permissions and owner changes/);
    await expect(page.getByTestId("area-card-AREA_23")).toHaveAccessibleName(/Codebase map publishing/);
    await expect(page.getByTestId("area-card-AREA_22")).toContainText("Runtime updates, feedback and privacy");
    const fontSizes = await page.locator(".area-card-title").evaluateAll(titles => titles.map(title => {
      const content = title.closest('[data-testid="diagram-content"]');
      return Number.parseFloat(getComputedStyle(title).fontSize) * Number(content?.getAttribute("data-scale"));
    }));
    expect(fontSizes).toHaveLength(23);
    expect(Math.min(...fontSizes)).toBeGreaterThanOrEqual(13.99);
    expect(await content.innerText()).not.toContain("OmiApp.swift:279");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(viewport.width);
  });

  test(`Tab navigation keeps overview and detail controls reachable without native scrolling at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await overview(page);
    await page.getByTestId("diagram-viewport").focus();
    await tabWithoutMovingMap(page, 28);
    await page.getByTestId("area-card-AREA_01").click();
    await expect(areaSvg(page)).toBeVisible();
    await expect(page.getByTestId("area-card-AREA_01")).toHaveAttribute("tabindex", "-1");
    // Start where a real card click left focus. Tab must not scroll the clipped
    // canvas to a neighboring card whose world position is now offscreen.
    await tabWithoutMovingMap(page, 50);
    await expect(page.getByLabel("Jump to area", { exact: true }).locator("option")).toHaveCount(24);
  });

  test(`dense-area destination controls stay outside the canvas with reduced motion at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await overview(page);
    expect(await page.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches)).toBe(true);
    for (const area of ["AREA_07", "AREA_15"]) {
      await focusArea(page, area);
      const destinations = page.locator("button[data-destination-area]");
      expect(await destinations.count()).toBeGreaterThan(0);
      const overlapping = await destinations.evaluateAll(buttons => {
        const canvas = document.querySelector('[data-testid="diagram-viewport"]')!.getBoundingClientRect();
        return buttons.filter(button => {
          const box = button.getBoundingClientRect();
          return Math.min(box.right, canvas.right) > Math.max(box.left, canvas.left)
            && Math.min(box.bottom, canvas.bottom) > Math.max(box.top, canvas.top);
        }).map(button => button.getAttribute("data-destination-area"));
      });
      expect(overlapping, `${area} destination controls cover canvas content`).toEqual([]);
      const initial = await camera(page);
      await page.getByRole("button", { name: "Zoom in", exact: true }).click();
      expect((await camera(page)).scale).toBeGreaterThan(initial.scale);
      await destinations.first().focus();
      const beforeKeyboardZoom = await camera(page);
      await page.keyboard.press("+");
      await expect.poll(async () => (await camera(page)).scale / beforeKeyboardZoom.scale).toBeCloseTo(1.3, 3);
      expect(await page.evaluate(() => document.getAnimations().filter(animation => animation.playState === "running").length)).toBe(0);
      const destination = destinations.last();
      const nextArea = await destination.getAttribute("data-destination-area");
      await destination.click();
      await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", nextArea!);
      await expect(areaSvg(page)).toBeVisible();
    }
    await page.getByRole("button", { name: "Overview", exact: true }).click();
    await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", "");
    await expect(page.locator("button[data-destination-area]")).toHaveCount(0);
  });
}

test("area focus reveals readable nodes, source detail, and cached layouts without moving the board", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await overview(page);
  const content = page.getByTestId("diagram-content");
  const positions = await cardPositions(page);
  await page.getByTestId("area-card-AREA_01").click();
  await expect(content).toHaveAttribute("data-active-area", "AREA_01");
  await expect(areaSvg(page)).toBeVisible();
  const svgId = await areaSvg(page).getAttribute("id");
  expect(svgId).toBeTruthy();
  const firstNode = page.getByTestId("area-diagram").locator('[data-node-id="APP"]');
  await expect(firstNode).toBeInViewport();
  const primaryFont = await firstNode.evaluate(node => {
    const label = node.querySelector(".nodeLabel p");
    const matrix = (node as SVGGraphicsElement).getScreenCTM();
    if (!label || !matrix) throw new Error("Node label has no screen geometry");
    return Number.parseFloat(getComputedStyle(label).fontSize) * Math.hypot(matrix.a, matrix.b);
  });
  expect(primaryFont).toBeGreaterThanOrEqual(11.9);
  await expect(page.getByTestId("area-diagram").locator("[data-node-id]")).toHaveCount(8);
  await expect(page.getByTestId("area-diagram").locator(".node-details").first()).toBeHidden();

  for (let step = 0; step < 4; step += 1) {
    await page.getByRole("button", { name: "Zoom in", exact: true }).click();
  }
  await expect(page.getByTestId("area-diagram").locator(".node-details").first()).toBeVisible();
  await expect(page.getByTestId("area-diagram")).toContainText("OmiApp.swift:279");
  expect(await page.getByTestId("area-diagram").innerText()).not.toContain("<br/>");
  expect(await areaSvg(page).getAttribute("id")).toBe(svgId);

  const before = await camera(page);
  const viewport = page.getByTestId("diagram-viewport");
  const oldBounds = await viewport.boundingBox();
  if (!oldBounds) throw new Error("Diagram viewport has no bounds");
  await page.setViewportSize({ width: 1100, height: 800 });
  const newBounds = await viewport.boundingBox();
  if (!newBounds) throw new Error("Resized diagram viewport has no bounds");
  await expect.poll(async () => {
    const after = await camera(page);
    return {
      scale: after.scale,
      centerX: Math.round((newBounds.width / 2 - after.x) / after.scale),
      centerY: Math.round((newBounds.height / 2 - after.y) / after.scale),
    };
  }).toEqual({
    scale: before.scale,
    centerX: Math.round((oldBounds.width / 2 - before.x) / before.scale),
    centerY: Math.round((oldBounds.height / 2 - before.y) / before.scale),
  });
  expect(await areaSvg(page).getAttribute("id")).toBe(svgId);
  expect(await cardPositions(page)).toEqual(positions);

  await focusArea(page, "AREA_02");
  await focusArea(page, "AREA_01");
  expect(await areaSvg(page).getAttribute("id")).toBe(svgId);
  await page.getByRole("button", { name: "Fit diagram", exact: true }).click();
  await expect(content).toHaveAttribute("data-active-area", "");
  await expect(page.getByTestId("area-diagram")).toHaveCount(0);
  expect(await cardPositions(page)).toEqual(positions);
  expect(errors).toEqual([]);
});

test("wheel zoom enters and leaves an area; pointer, keyboard and fullscreen retain navigation", async ({ page }) => {
  await overview(page);
  const content = page.getByTestId("diagram-content");
  const initial = await camera(page);
  const card = await page.getByTestId("area-card-AREA_01").boundingBox();
  if (!card) throw new Error("Area card has no bounds");
  await page.mouse.move(card.x + card.width / 2, card.y + card.height / 2);
  await page.mouse.wheel(0, -650);
  await expect(content).toHaveAttribute("data-active-area", "AREA_01");
  await expect(areaSvg(page)).toBeVisible();
  expect((await camera(page)).scale).toBeGreaterThanOrEqual(initial.scale * 2);
  await page.mouse.wheel(0, 1300);
  await expect(content).toHaveAttribute("data-active-area", "");
  await expect(page.getByTestId("area-diagram")).toHaveCount(0);

  const viewport = page.getByTestId("diagram-viewport");
  const bounds = await viewport.boundingBox();
  if (!bounds) throw new Error("Diagram viewport has no bounds");
  const beforeDrag = await camera(page);
  await page.mouse.move(bounds.x + bounds.width - 20, bounds.y + bounds.height - 20);
  await page.mouse.down();
  await page.mouse.move(bounds.x + bounds.width - 130, bounds.y + bounds.height - 100, { steps: 6 });
  await page.mouse.up();
  expect((await camera(page)).x).not.toBe(beforeDrag.x);
  await viewport.focus();
  const beforeKey = await camera(page);
  await page.keyboard.press("ArrowRight");
  expect((await camera(page)).x).not.toBe(beforeKey.x);
  await page.keyboard.press("+");
  expect((await camera(page)).scale).toBeGreaterThan(beforeKey.scale);
  await page.getByRole("button", { name: "Enter fullscreen", exact: true }).click();
  await expect(page.getByRole("button", { name: "Exit fullscreen", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Exit fullscreen", exact: true }).click();
});

test("separate zoom thresholds keep the current area stable and enter it at readable scale", async ({ page }) => {
  await overview(page);
  await focusArea(page, "AREA_01");
  const content = page.getByTestId("diagram-content");
  const baseline = Number(await content.getAttribute("data-overview-scale"));
  const svgId = await areaSvg(page).getAttribute("id");
  const viewport = await page.getByTestId("diagram-viewport").boundingBox();
  if (!viewport) throw new Error("Diagram viewport has no bounds");
  await page.mouse.move(viewport.x + viewport.width / 2, viewport.y + viewport.height / 2);
  for (const step of [
    { relative: 1.8, active: "AREA_01" },
    { relative: 1.4, active: "" },
    { relative: 1.8, active: "" },
    { relative: 2.1, active: "AREA_01" },
  ]) {
    const target = baseline * step.relative;
    const current = await camera(page);
    await page.mouse.wheel(0, -Math.log(target / current.scale) / .002);
    await expect(content).toHaveAttribute("data-active-area", step.active);
    if (step.relative !== 2.1) {
      await expect.poll(async () => Math.abs((await camera(page)).scale - target)).toBeLessThan(.005);
    }
  }
  await expect(areaSvg(page)).toBeVisible();
  expect(await areaSvg(page).getAttribute("id")).toBe(svgId);
  await expect.poll(async () => page.getByTestId("area-diagram").locator('[data-node-id="APP"]').evaluate(node => {
    const label = node.querySelector(".nodeLabel p")!;
    const matrix = (node as SVGGraphicsElement).getScreenCTM()!;
    return Number.parseFloat(getComputedStyle(label).fontSize) * Math.hypot(matrix.a, matrix.b);
  })).toBeGreaterThanOrEqual(11.9);
});

test("continued forward wheel gestures retain readable focus while an area layout is loading", async ({ page }) => {
  await overview(page);
  let releaseLoading!: () => void;
  const loadingGate = new Promise<void>(resolve => { releaseLoading = resolve; });
  let heldScripts = 0;
  await page.route("**/*.js", async route => {
    heldScripts += 1;
    await loadingGate;
    await route.continue();
  });
  const card = await page.getByTestId("area-card-AREA_01").boundingBox();
  if (!card) throw new Error("Area card has no bounds");
  await page.mouse.move(card.x + card.width / 2, card.y + card.height / 2);
  await page.mouse.wheel(0, -400);
  await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", "AREA_01");
  await expect(page.getByTestId("area-loading")).toBeVisible();
  await expect.poll(() => heldScripts).toBeGreaterThan(0);
  const entry = await camera(page);
  await page.mouse.wheel(0, -80);
  await page.mouse.wheel(0, -80);
  await expect.poll(async () => (await camera(page)).scale).toBeGreaterThan(entry.scale);
  releaseLoading();
  await expect(areaSvg(page)).toBeVisible();
  await expect.poll(async () => page.getByTestId("area-diagram").locator('[data-node-id="APP"]').evaluate(node => {
    const label = node.querySelector(".nodeLabel p")!;
    const matrix = (node as SVGGraphicsElement).getScreenCTM()!;
    return Number.parseFloat(getComputedStyle(label).fontSize) * Math.hypot(matrix.a, matrix.b);
  })).toBeGreaterThanOrEqual(11.9);
});

test("two-finger pinch changes scale and reveals the area under the gesture", async ({ page }) => {
  await overview(page);
  const initial = await camera(page);
  const card = await page.getByTestId("area-card-AREA_01").boundingBox();
  if (!card) throw new Error("Area card has no bounds");
  const x = card.x + card.width / 2;
  const y = card.y + card.height / 2;
  const session = await page.context().newCDPSession(page);
  await session.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 });
  await session.send("Input.dispatchTouchEvent", {
    type: "touchStart", touchPoints: [{ x: x - 20, y, id: 1 }, { x: x + 20, y, id: 2 }],
  });
  for (const distance of [45, 65, 85]) {
    await session.send("Input.dispatchTouchEvent", {
      type: "touchMove", touchPoints: [{ x: x - distance, y, id: 1 }, { x: x + distance, y, id: 2 }],
    });
  }
  await session.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await expect.poll(async () => (await camera(page)).scale).toBeGreaterThan(initial.scale * 4);
  await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", "AREA_01");
  await expect(areaSvg(page)).toBeVisible();
  await session.detach();
});

for (const area of [
  { id: "AREA_07", nodes: 7, internal: 5, cross: 67 },
  { id: "AREA_15", nodes: 14, internal: 18, cross: 57 },
  { id: "AREA_20", nodes: 12, internal: 0, cross: 27 },
  { id: "AREA_21", nodes: 5, internal: 0, cross: 10 },
]) {
  test(`${area.id} preserves every local node and incident cross-area connection`, async ({ page }) => {
    await overview(page);
    await focusArea(page, area.id);
    const diagram = page.getByTestId("area-diagram");
    await expect(diagram.locator("[data-node-id]")).toHaveCount(area.nodes);
    await expect(diagram.locator('[data-edge-id][data-edge-kind="internal"]')).toHaveCount(area.internal);
    const connections = page.locator(".map-connection[data-edge-id]");
    await expect(connections).toHaveCount(area.cross);
    const ids = await connections.evaluateAll(edges => edges.map(edge => edge.getAttribute("data-edge-id")));
    expect(new Set(ids).size).toBe(area.cross);
    const connectionLabel = await connections.first().locator("title").textContent();
    expect(connectionLabel).toBeTruthy();
    await connections.first().focus();
    await expect(page.getByRole("tooltip")).toHaveText(connectionLabel!);
    const destinations = page.locator("button[data-destination-area]");
    expect(await destinations.count()).toBeGreaterThan(0);
    const destination = destinations.first();
    const nextArea = await destination.getAttribute("data-destination-area");
    expect(nextArea).toMatch(/^AREA_\d{2}$/);
    await destination.click();
    await expect(page.getByTestId("diagram-content")).toHaveAttribute("data-active-area", nextArea!);
    await expect(areaSvg(page)).toBeVisible();
    await expect(page.getByTestId("area-diagram")).toHaveCount(1);
  });
}

test("every source area renders all 210 nodes and all 422 source connections", async ({ page }) => {
  test.setTimeout(120_000);
  await overview(page);
  const areaIds = await page.getByLabel("Jump to area", { exact: true }).locator("option").evaluateAll(options =>
    options.map(option => (option as HTMLOptionElement).value).filter(Boolean));
  expect(areaIds).toHaveLength(23);
  const nodes = new Set<string>();
  const edges = new Set<string>();
  for (const id of areaIds) {
    await focusArea(page, id);
    const diagram = page.getByTestId("area-diagram");
    await expect.poll(async () => diagram.locator("[data-node-id]").evaluateAll(items => {
      const viewport = document.querySelector('[data-testid="diagram-viewport"]')!.getBoundingClientRect();
      return items.some(item => {
        const node = item.getBoundingClientRect();
        const visibleWidth = Math.max(0, Math.min(node.right, viewport.right) - Math.max(node.left, viewport.left));
        const visibleHeight = Math.max(0, Math.min(node.bottom, viewport.bottom) - Math.max(node.top, viewport.top));
        return visibleWidth >= Math.min(node.width, viewport.width) * .5 && visibleHeight >= Math.min(node.height, viewport.height) * .5;
      });
    })).toBe(true);
    for (const node of await diagram.locator("[data-node-id]").evaluateAll(items =>
      items.map(item => item.getAttribute("data-node-id")!))) nodes.add(node);
    for (const edge of await page.locator("[data-edge-id]").evaluateAll(items =>
      items.map(item => item.getAttribute("data-edge-id")!))) edges.add(edge);
    expect(await diagram.innerText()).not.toMatch(/<br\s*\/?\s*>/i);
  }
  expect(nodes.size).toBe(210);
  expect(edges.size).toBe(422);
});

test("failed area layout keeps the overview usable and retries the lazy renderer", async ({ page }) => {
  await overview(page);
  let failedScripts = 0;
  let rejectLazyScript = true;
  await page.route("**/*.js", async route => {
    if (rejectLazyScript) {
      failedScripts += 1;
      await route.abort("failed");
    } else {
      await route.continue();
    }
  });
  await page.getByTestId("area-card-AREA_01").click();
  await expect(page.getByTestId("area-error")).toBeVisible();
  expect(failedScripts).toBeGreaterThan(0);
  await expect(areaCards(page)).toHaveCount(23);
  await expect(page.getByTestId("area-loading")).toBeHidden();
  await expect(page.getByLabel("Jump to area", { exact: true })).toBeEnabled();
  rejectLazyScript = false;
  await page.getByRole("button", { name: "Retry area", exact: true }).click();
  await expect(areaSvg(page)).toBeVisible();
  await expect(page.getByTestId("area-error")).toBeHidden();
});

test("invalid Mermaid has an explicit global error and a corrected response recovers", async ({ page }) => {
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
  await page.getByRole("button", { name: "Try again", exact: true }).click();
  await expect(page.getByTestId("diagram-error")).toBeVisible();
  await page.unroute("http://127.0.0.1:4173/");
  await page.reload();
  await expect(areaCards(page)).toHaveCount(23);
});

test("the published source link names the exact build commit", async ({ page }) => {
  await page.goto("/");
  const commit = process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA;
  const link = page.getByTestId("commit-link");
  if (commit) {
    await expect(link).toHaveAttribute("href", `https://github.com/sruj75/knowledge-athlete/blob/${commit}/docs/architecture/intentive-codeflow.mmd`);
    await expect(link).toContainText(commit.slice(0, 7));
  } else if (await link.count()) {
    expect(await link.getAttribute("href")).toMatch(/\/blob\/[a-f0-9]{40}\/docs\/architecture\/intentive-codeflow\.mmd$/);
  } else {
    await expect(page.getByText("Local build · commit unavailable")).toBeVisible();
  }
});
