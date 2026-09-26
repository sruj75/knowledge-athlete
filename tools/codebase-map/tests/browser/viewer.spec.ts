import { expect, test } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";

const areaCards = (page: Page) => page.locator('[data-testid^="area-card-AREA_"]');
const areaRegions = (page: Page) => page.locator('[data-testid^="area-region-AREA_"]');
const areaDiagram = (page: Page, id: string) => page.locator(`[data-testid="area-diagram"][data-area-id="${id}"]`);
const areaSvg = (page: Page, id = "AREA_01") => areaDiagram(page, id).locator("svg");
const content = (page: Page) => page.getByTestId("diagram-content");
const canvas = (page: Page) => page.getByTestId("diagram-viewport");

async function scrollPosition(page: Page) {
  return canvas(page).evaluate(element => ({ x: element.scrollLeft, y: element.scrollTop }));
}

async function nextFrames(page: Page) {
  await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
}

async function overview(page: Page) {
  await page.goto("/");
  await expect(areaCards(page)).toHaveCount(23);
  await expect(page.getByTestId("diagram-loading")).toBeHidden();
  await expect(content(page)).toHaveAttribute("data-active-area", "");
}

async function focusArea(page: Page, id: string) {
  await page.getByLabel("Jump to area", { exact: true }).selectOption(id);
  await expect(content(page)).toHaveAttribute("data-active-area", id);
  await expect(page.getByLabel("Jump to area", { exact: true })).toHaveValue(id);
  await expect(page.locator(".current-area")).toContainText(id.slice(-2));
  await expect(areaSvg(page, id)).toBeVisible();
}

async function regionPositions(page: Page) {
  return areaRegions(page).evaluateAll(regions => regions.map(region => ({
    id: region.getAttribute("data-area-id")!,
    x: Number(region.getAttribute("data-world-x")),
    y: Number(region.getAttribute("data-world-y")),
    width: Number(region.getAttribute("data-world-width")),
    height: Number(region.getAttribute("data-world-height")),
  })));
}

async function wheelOver(locator: Locator, dx: number, dy: number) {
  const box = await locator.boundingBox();
  if (!box) throw new Error("Scroll target has no bounds");
  await locator.page().mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await locator.page().mouse.wheel(dx, dy);
}

async function touchSwipe(page: Page, locator: Locator) {
  const box = await locator.boundingBox();
  if (!box) throw new Error("Scroll target has no touch bounds");
  const x = Math.round(box.x + box.width / 2), y = Math.round(box.y + box.height - 24);
  const distance = Math.min(220, box.height - 48);
  const session = await page.context().newCDPSession(page);
  await session.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 });
  await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y, id: 1 }] });
  for (let step = 1; step <= 8; step += 1) {
    await session.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x, y: y - distance * step / 8, id: 1 }] });
    await nextFrames(page);
  }
  await session.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await session.detach();
}

async function largestConnectionGroup(page: Page) {
  return page.locator(".map-connection-group").evaluateAll(groups => groups.map(group => ({
    id: group.getAttribute("data-connection-group")!,
    ids: JSON.parse(group.getAttribute("data-edge-ids")!) as string[],
  })).sort((a, b) => b.ids.length - a.ids.length)[0]);
}

for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
  test(`overview keeps 23 readable spatial regions without zoom or miniature nodes at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await overview(page);
    await expect(content(page)).toHaveAttribute("data-area-count", "23");
    await expect(content(page)).toHaveAttribute("data-node-count", "210");
    await expect(content(page)).toHaveAttribute("data-edge-count", "422");
    await expect(page.getByTestId("area-diagram")).toHaveCount(0);
    await expect(page.getByRole("button", { name: /^(Zoom in|Zoom out|Fit diagram)$/ })).toHaveCount(0);
    await expect(page.getByTestId("area-card-AREA_01")).toHaveAccessibleName(/Start, sign in, permissions and owner changes/);
    await expect(page.getByTestId("area-card-AREA_23")).toHaveAccessibleName(/Codebase map publishing/);
    await expect(page.getByTestId("area-card-AREA_22")).toContainText("Runtime updates, feedback and privacy");
    const fontSizes = await page.locator(".area-card-title").evaluateAll(titles => titles.map(title => {
      let scale = 1;
      for (let ancestor: Element | null = title; ancestor; ancestor = ancestor.parentElement) {
        const matrix = new DOMMatrixReadOnly(getComputedStyle(ancestor).transform);
        scale *= Math.hypot(matrix.a, matrix.b);
      }
      return Number.parseFloat(getComputedStyle(title).fontSize) * scale;
    }));
    expect(fontSizes).toHaveLength(23);
    expect(Math.min(...fontSizes)).toBeGreaterThanOrEqual(13.99);
    const overflow = await page.locator(".area-card-title, .region-meta").evaluateAll(labels => labels.flatMap(label => {
      const region = label.closest(".map-region")!;
      const bounds = region.getBoundingClientRect();
      const text = label.getBoundingClientRect();
      return text.left < bounds.left || text.right > bounds.right || text.top < bounds.top || text.bottom > bounds.bottom
        ? [{ area: region.getAttribute("data-area-id"), label: label.textContent }] : [];
    }));
    expect(overflow, "Overview labels escape their subsystem regions").toEqual([]);
    const positions = await regionPositions(page);
    expect(new Set(positions.map(region => region.x)).size).toBeGreaterThan(5);
    expect(new Set(positions.map(region => region.y)).size).toBeGreaterThan(5);
    const order = (id: string) => positions.find(region => region.id === id)!;
    expect(order("AREA_13").y).toBeLessThan(order("AREA_01").y);
    expect(order("AREA_01").y).toBeLessThan(order("AREA_11").y);
    expect(order("AREA_11").y).toBeLessThan(order("AREA_07").y);
    expect(order("AREA_02").x).toBeLessThan(order("AREA_16").x);
    expect(order("AREA_08").y).toBeLessThan(order("AREA_10").y);
    const groupedEdges = await page.locator(".map-connection-group").evaluateAll(groups => groups.flatMap(group => JSON.parse(group.getAttribute("data-edge-ids")!) as string[]));
    expect(groupedEdges).toHaveLength(261);
    expect(new Set(groupedEdges).size).toBe(261);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(viewport.width);
    const extent = await canvas(page).evaluate(element => {
      const content = element.querySelector('[data-testid="diagram-content"]')!.getBoundingClientRect();
      return { width: element.scrollWidth, height: element.scrollHeight, contentWidth: content.width, contentHeight: content.height };
    });
    expect(extent.width, "Overview has blank overflow beyond its actual map").toBeLessThanOrEqual(extent.contentWidth + 1);
    expect(extent.height, "Overview has blank overflow below its actual map").toBeLessThanOrEqual(extent.contentHeight + 1);
  });

  test(`subsystem inflow and outflow remain below its title and navigate at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await overview(page);
    await focusArea(page, "AREA_01");
    const flows = page.getByRole("region", { name: "Subsystem inflow and outflow" });
    const incoming = flows.getByRole("list", { name: "Inflow", exact: true });
    const outgoing = flows.getByRole("list", { name: "Outflow", exact: true });
    await expect(incoming).toContainText("Provider credentials / Firebase custom token");
    await expect(outgoing).toContainText("Close old pool and retarget owner directory");
    await expect(incoming).not.toContainText("Restore credentials");
    const titleBox = (await page.locator(".current-area").boundingBox())!;
    const flowsBox = (await flows.boundingBox())!;
    expect(flowsBox.y).toBeGreaterThanOrEqual(titleBox.y + titleBox.height);
    expect(flowsBox.y + flowsBox.height).toBeLessThanOrEqual((await canvas(page).boundingBox())!.y);
    await page.screenshot({ path: test.info().outputPath(`subsystem-${viewport.width}.png`) });
    const beforeScroll = await scrollPosition(page);
    await wheelOver(outgoing, 0, 500);
    await expect.poll(() => outgoing.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
    expect(await scrollPosition(page)).toEqual(beforeScroll);
    await outgoing.focus();
    await page.keyboard.press("Home");
    await expect.poll(() => outgoing.evaluate(element => element.scrollTop)).toBe(0);
    const destination = outgoing.getByRole("button", { name: "To 07 · Local archive authorities", exact: true });
    await destination.focus();
    await page.keyboard.press("Enter");
    await expect(content(page)).toHaveAttribute("data-active-area", "AREA_07");
    await expect(flows).toHaveAttribute("data-area-id", "AREA_07");
    expect(await incoming.evaluate(element => element.scrollTop)).toBe(0);
    expect(await outgoing.evaluate(element => element.scrollTop)).toBe(0);
    await expect(page.locator(".current-area")).toBeFocused();
    await page.keyboard.press("Escape");
    await expect(content(page)).toHaveAttribute("data-active-area", "");
    await expect(page.getByRole("button", { name: "Overview", exact: true })).toBeFocused();
    await focusArea(page, "AREA_23");
    await expect(incoming).toContainText("No incoming flows recorded in the map.");
    await expect(outgoing).toContainText("No outgoing flows recorded in the map.");
    await incoming.focus();
    await page.keyboard.press("Escape");
    await expect(content(page)).toHaveAttribute("data-active-area", "");
  });
}

test("connection inspection preserves the map and its destinations open on explicit activation", async ({ page }) => {
  await overview(page);
  const group = await largestConnectionGroup(page);
  await page.locator(`[data-connection-group="${group.id}"]`).focus();
  await page.keyboard.press("Enter");
  const inspector = page.getByRole("complementary", { name: "Connection details" });
  await expect(inspector).toBeVisible();
  expect(await inspector.locator("[data-edge-id]").evaluateAll(items => items.map(item => item.getAttribute("data-edge-id")))).toEqual(group.ids);
  const list = inspector.getByRole("list", { name: "Individual connections" });
  const before = await scrollPosition(page);
  await wheelOver(list, 0, 300);
  await expect.poll(() => list.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  expect(await scrollPosition(page)).toEqual(before);
  await list.focus();
  await page.keyboard.press("Home");
  await expect.poll(() => list.evaluate(element => element.scrollTop)).toBe(0);
  await page.keyboard.press("Escape");
  await expect(inspector).toBeHidden();
  expect(await scrollPosition(page)).toEqual(before);
  await page.locator(`[data-connection-group="${group.id}"]`).focus();
  await page.keyboard.press("Enter");
  await page.mouse.move(5, 5);
  await nextFrames(page);
  await expect(inspector).toBeVisible();
  const inspectorBox = (await inspector.boundingBox())!;
  const canvasBox = (await canvas(page).boundingBox())!;
  expect(inspectorBox.x).toBeGreaterThanOrEqual(canvasBox.x);
  expect(inspectorBox.x + inspectorBox.width).toBeLessThanOrEqual(canvasBox.x + canvasBox.width + 1);
  expect(inspectorBox.y + inspectorBox.height).toBeLessThanOrEqual(canvasBox.y + canvasBox.height + 1);
  const target = group.id.slice(0, 7);
  await inspector.locator(".connection-endpoints button").first().click();
  await expect(inspector).toBeHidden();
  await expect(content(page)).toHaveAttribute("data-active-area", target);
  await expect(areaSvg(page, target)).toBeVisible();
  await expect(canvas(page)).toBeFocused();
});

test("native mobile touch scrolling moves the map and independently scrolls connection details", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await overview(page);
  const before = await scrollPosition(page);
  await touchSwipe(page, canvas(page));
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(before.y + 20);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
  await expect(page.getByTestId("area-diagram")).toHaveCount(0);
  const group = await largestConnectionGroup(page);
  await page.locator(`[data-connection-group="${group.id}"]`).focus();
  await page.keyboard.press("Enter");
  const list = page.getByRole("list", { name: "Individual connections" });
  const mapPosition = await scrollPosition(page);
  await touchSwipe(page, list);
  await expect.poll(() => list.evaluate(element => element.scrollTop)).toBeGreaterThan(20);
  expect(await scrollPosition(page)).toEqual(mapPosition);
});

test("detail views inspect and navigate connected subsystems without replacing the current diagram", async ({ page }) => {
  await overview(page);
  for (const id of ["AREA_07", "AREA_15"]) {
    await focusArea(page, id);
    const initial = await scrollPosition(page);
    const svgId = await areaSvg(page, id).getAttribute("id");
    const connections = page.getByRole("navigation", { name: "Connected subsystems", exact: true });
    const toggle = connections.getByRole("button", { name: /connected subsystems/ });
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(await scrollPosition(page)).toEqual(initial);
    await connections.getByRole("button", { name: /^Inspect connections with/ }).first().click();
    const inspector = page.getByRole("complementary", { name: "Connection details" });
    await expect(inspector).toBeVisible();
    expect(await scrollPosition(page)).toEqual(initial);
    expect(await areaSvg(page, id).getAttribute("id")).toBe(svgId);
    await inspector.getByRole("button", { name: "Close connection details" }).click();
    await expect(toggle).toBeFocused();
    await toggle.click();
    const destination = connections.locator(".connected-list > div > button:first-child").first();
    const target = `AREA_${await destination.locator("span").first().innerText()}`;
    await destination.click();
    await expect(content(page)).toHaveAttribute("data-active-area", target);
    await expect(areaSvg(page, target)).toBeVisible();
    await expect(page.getByTestId("area-diagram")).toHaveCount(1);
  }
});

test("all 23 cached views preserve 210 nodes and 422 connections including areas without internal edges", async ({ page }) => {
  test.setTimeout(120_000);
  await overview(page);
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  const positions = await regionPositions(page);
  const externalEdges = await page.locator(".map-connection-group").evaluateAll(groups => groups.flatMap(group => JSON.parse(group.getAttribute("data-edge-ids")!) as string[]));
  const areaIds = await page.getByLabel("Jump to area", { exact: true }).locator("option").evaluateAll(options => options.map(option => (option as HTMLOptionElement).value).filter(Boolean));
  expect(areaIds).toHaveLength(23);
  const nodes = new Set<string>();
  const internalEdges = new Set<string>();
  const inflows: string[] = [], outflows: string[] = [];
  const svgIds = new Map<string, string>();
  for (const id of areaIds) {
    await focusArea(page, id);
    await expect(page.getByTestId("area-diagram")).toHaveCount(1);
    for (const [name, entries] of [["Inflow", inflows], ["Outflow", outflows]] as const) {
      entries.push(...await page.getByRole("list", { name, exact: true }).locator("[data-flow-edge-id]").evaluateAll(items => items.map(item => item.getAttribute("data-flow-edge-id")!)));
    }
    const diagram = areaDiagram(page, id);
    expect(await diagram.locator("[data-node-id]").evaluateAll(items => {
      const viewport = document.querySelector('[data-testid="diagram-viewport"]')!.getBoundingClientRect();
      return items.some(item => {
        const box = item.getBoundingClientRect();
        return Math.min(box.right, viewport.right) - Math.max(box.left, viewport.left) > 12
          && Math.min(box.bottom, viewport.bottom) - Math.max(box.top, viewport.top) > 12;
      });
    }), `${id} opened without a visible node`).toBe(true);
    for (const node of await diagram.locator("[data-node-id]").evaluateAll(items => items.map(item => item.getAttribute("data-node-id")!))) nodes.add(node);
    for (const edge of await diagram.locator('[data-edge-id][data-edge-kind="internal"]').evaluateAll(items => items.map(item => item.getAttribute("data-edge-id")!))) internalEdges.add(edge);
    if (["AREA_20", "AREA_21"].includes(id)) await expect(diagram.locator("[data-edge-id]")).toHaveCount(0);
    expect(await diagram.innerText()).not.toMatch(/<br\s*\/?\s*>/i);
    svgIds.set(id, (await areaSvg(page, id).getAttribute("id"))!);
  }
  expect(nodes.size).toBe(210);
  expect(internalEdges.size).toBe(161);
  expect(externalEdges).toHaveLength(261);
  expect(inflows.sort()).toEqual([...externalEdges].sort());
  expect(outflows.sort()).toEqual([...externalEdges].sort());
  expect(new Set([...internalEdges, ...externalEdges]).size).toBe(422);
  for (const id of ["AREA_01", "AREA_07", "AREA_15", "AREA_20", "AREA_21"]) {
    await focusArea(page, id);
    expect(await areaSvg(page, id).getAttribute("id")).toBe(svgIds.get(id));
  }
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  expect(await regionPositions(page)).toEqual(positions);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
  expect(errors).toEqual([]);
});

test("wheel scrolling never opens an overview area or changes the size of an open diagram", async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 700 });
  await overview(page);
  const positions = await regionPositions(page);
  const before = await scrollPosition(page);
  await wheelOver(canvas(page), 180, 220);
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(before.y);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
  await expect(page.getByTestId("area-diagram")).toHaveCount(0);
  expect(await regionPositions(page)).toEqual(positions);
  await focusArea(page, "AREA_01");
  const svg = areaSvg(page);
  const initial = (await svg.boundingBox())!;
  const start = await scrollPosition(page);
  await wheelOver(canvas(page), 0, 220);
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(start.y);
  const after = (await svg.boundingBox())!;
  expect(after.width).toBe(initial.width);
  expect(after.height).toBe(initial.height);
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await canvas(page).focus();
  for (const key of ["+", "-", "="]) await page.keyboard.press(key);
  expect((await svg.boundingBox())!.width).toBe(initial.width);
  expect((await svg.boundingBox())!.height).toBe(initial.height);
});

test("click and keyboard activation open one complete readable subsystem without a zoom transition", async ({ page }) => {
  await overview(page);
  await page.getByTestId("area-card-AREA_01").click();
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await expect(page.getByTestId("area-diagram")).toHaveCount(1);
  const diagram = areaDiagram(page, "AREA_01");
  await expect(diagram.locator(".node-details").first()).toBeVisible();
  await expect(diagram).toContainText("OmiApp.swift:279");
  const label = diagram.locator(".nodeLabel").first();
  const fontSize = await label.evaluate(element => Number.parseFloat(getComputedStyle(element).fontSize));
  expect(fontSize).toBeGreaterThanOrEqual(14);
  const geometry = await areaSvg(page).evaluate(element => {
    const svg = element as SVGSVGElement;
    return { naturalWidth: svg.viewBox.baseVal.width, width: svg.getBoundingClientRect().width, scale: svg.getScreenCTM()!.a };
  });
  // Fractional SVG widths are rounded to CSS layout subpixels, never app-scaled.
  expect(Math.abs(geometry.width - geometry.naturalWidth)).toBeLessThan(1);
  expect(fontSize * geometry.scale).toBeGreaterThanOrEqual(13.99);
  const size = (await areaSvg(page).boundingBox())!;
  await nextFrames(page);
  expect((await areaSvg(page).boundingBox())!.width).toBe(size.width);
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await expect(page.getByTestId("area-diagram")).toHaveCount(0);
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.getByTestId("area-card-AREA_21").focus();
  await page.keyboard.press("Enter");
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_21");
  await expect(areaSvg(page, "AREA_21")).toBeVisible();
  await canvas(page).focus();
  await page.keyboard.press("Escape");
  await expect(areaCards(page)).toHaveCount(23);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
});

test("mouse dragging, native keyboard scrolling and fullscreen preserve explicit navigation", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 700 });
  await overview(page);
  await focusArea(page, "AREA_01");
  const box = (await canvas(page).boundingBox())!;
  const before = await scrollPosition(page);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 - 100, box.y + box.height / 2 - 80, { steps: 5 });
  await page.mouse.up();
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(before.y + 50);
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await canvas(page).focus();
  const beforeKey = await scrollPosition(page);
  await page.keyboard.press("ArrowDown");
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(beforeKey.y);
  await focusArea(page, "AREA_01");
  await page.getByRole("button", { name: "Enter fullscreen", exact: true }).click();
  await expect(page.getByRole("button", { name: "Exit fullscreen", exact: true })).toBeVisible();
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await page.getByRole("button", { name: "Exit fullscreen", exact: true }).click();
  await canvas(page).focus();
  await page.keyboard.press("Escape");
  await expect(content(page)).toHaveAttribute("data-active-area", "");
});

test("each area remembers its scroll position and resizing preserves its readable diagram", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 700 });
  await overview(page);
  await wheelOver(canvas(page), 140, 120);
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(0);
  const overviewPosition = await scrollPosition(page);
  await focusArea(page, "AREA_01");
  await wheelOver(canvas(page), 0, 280);
  await expect.poll(async () => (await scrollPosition(page)).y).toBeGreaterThan(100);
  const saved = await scrollPosition(page);
  const svgId = await areaSvg(page).getAttribute("id");
  const originalSize = (await areaSvg(page).boundingBox())!;
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await scrollPosition(page)).toEqual(saved);
  expect((await areaSvg(page).boundingBox())!.width).toBe(originalSize.width);
  expect((await areaSvg(page).boundingBox())!.height).toBe(originalSize.height);
  await focusArea(page, "AREA_15");
  await focusArea(page, "AREA_01");
  await expect.poll(() => scrollPosition(page)).toEqual(saved);
  expect(await areaSvg(page).getAttribute("id")).toBe(svgId);
  await page.setViewportSize({ width: 900, height: 700 });
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await expect.poll(() => scrollPosition(page)).toEqual(overviewPosition);
});

test("a failed area render exposes retry and allows returning to the overview", async ({ page }) => {
  await page.addInitScript(() => {
    const original = SVGGraphicsElement.prototype.getBBox;
    let failed = false;
    SVGGraphicsElement.prototype.getBBox = function (...args) {
      if (!failed && this.ownerSVGElement?.id.startsWith("intentive_area_") && this.getAttribute("data-node-id") === "APP") {
        failed = true;
        document.documentElement.setAttribute("data-area-measurement-failed", "true");
        throw new Error("Injected one-shot local SVG measurement failure");
      }
      return original.apply(this, args);
    };
  });
  await overview(page);
  await page.getByLabel("Jump to area", { exact: true }).selectOption("AREA_01");
  const notice = page.getByRole("alert").filter({ hasText: "This subsystem couldn’t be drawn" });
  await expect(notice).toBeVisible();
  await expect(notice).toBeInViewport();
  await expect(page.locator("html")).toHaveAttribute("data-area-measurement-failed", "true");
  await expect(page.getByTestId("diagram-error")).toBeHidden();
  await expect(page.getByLabel("Jump to area", { exact: true })).toBeEnabled();
  await page.getByLabel("Jump to area", { exact: true }).selectOption("AREA_01");
  await expect(notice, "Reselecting the failed area must not discard its retry control").toBeVisible();
  await notice.getByRole("button", { name: "Retry this area", exact: true }).click();
  await expect(areaSvg(page)).toBeVisible();
  await expect(notice).toBeHidden();
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await expect(areaDiagram(page, "AREA_01").locator("[data-node-id]")).toHaveCount(8);
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await expect(areaCards(page)).toHaveCount(23);
});

test("a failed initial Mermaid load shows a global error and retry recovers the complete map", async ({ page, request }) => {
  const html = await (await request.get("/")).text();
  // Keep the page's declared bootstrap scripts available, then fail the lazy
  // renderer import. This exercises the real load failure without chunk names.
  const bootstrapScripts = new Set([...html.matchAll(/<script\b[^>]*\bsrc="([^"]+)"/g)]
    .map(match => new URL(match[1], "http://127.0.0.1:4173").pathname));
  expect(bootstrapScripts.size).toBeGreaterThan(0);
  let failedScripts = 0;
  let rejectLazyScript = true;
  await page.route("**/*.js", async route => {
    if (rejectLazyScript && !bootstrapScripts.has(new URL(route.request().url()).pathname)) {
      failedScripts += 1;
      await route.abort("failed");
    } else {
      await route.continue();
    }
  });
  await page.goto("/");
  await expect(page.getByTestId("diagram-error")).toBeVisible();
  expect(failedScripts).toBeGreaterThan(0);
  await expect(page.getByTestId("diagram-loading")).toBeHidden();
  rejectLazyScript = false;
  await page.getByRole("button", { name: "Try again", exact: true }).click();
  await expect(areaCards(page)).toHaveCount(23);
  await expect(page.getByTestId("diagram-error")).toBeHidden();
  await focusArea(page, "AREA_01");
  await expect(areaSvg(page)).toBeVisible();
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
