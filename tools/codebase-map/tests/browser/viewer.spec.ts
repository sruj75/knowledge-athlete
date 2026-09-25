import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

const areaCards = (page: Page) => page.locator('[data-testid^="area-card-AREA_"]');
const areaRegions = (page: Page) => page.locator('[data-testid^="area-region-AREA_"]');
const areaDiagram = (page: Page, id: string) => page.locator(`[data-testid="area-diagram"][data-area-id="${id}"]`);
const areaSvg = (page: Page, id = "AREA_01") => areaDiagram(page, id).locator("svg");
const content = (page: Page) => page.getByTestId("diagram-content");

async function camera(page: Page) {
  return content(page).evaluate(element => ({
    x: Number(element.getAttribute("data-x")),
    y: Number(element.getAttribute("data-y")),
    scale: Number(element.getAttribute("data-scale")),
  }));
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
  await expect(areaDiagram(page, id)).toHaveAttribute("data-readable", "true");
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

async function viewBox(page: Page) {
  const box = await page.getByTestId("diagram-viewport").boundingBox();
  if (!box) throw new Error("Map viewport has no bounds");
  return box;
}

async function wheelTo(page: Page, scale: number, point?: { x: number; y: number }) {
  const before = await camera(page);
  const box = await viewBox(page);
  const requested = point ?? { x: box.width / 2, y: box.height / 2 };
  // Browser wheel events use integer screen coordinates; measure the same anchor.
  const anchor = { x: Math.round(box.x + requested.x) - box.x, y: Math.round(box.y + requested.y) - box.y };
  await page.mouse.move(box.x + anchor.x, box.y + anchor.y);
  await page.mouse.wheel(0, -Math.log(scale / before.scale) / .002);
  await expect.poll(async () => (await camera(page)).scale).toBeCloseTo(scale, 5);
  return { before, anchor };
}

function worldAt(transform: { x: number; y: number; scale: number }, point: { x: number; y: number }) {
  return { x: (point.x - transform.x) / transform.scale, y: (point.y - transform.y) / transform.scale };
}

async function panBy(page: Page, dx: number, dy: number) {
  const box = await viewBox(page);
  const steps = Math.ceil(Math.max(Math.abs(dx) / (box.width * .35), Math.abs(dy) / (box.height * .35)));
  const start = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  for (let step = 0; step < steps; step += 1) {
    await page.mouse.move(start.x, start.y);
    await page.mouse.down();
    await page.mouse.move(start.x + dx / steps, start.y + dy / steps, { steps: 3 });
    await page.mouse.up();
  }
}

for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
  test(`overview has 23 readable subsystem regions without miniature nodes at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await overview(page);
    await expect(content(page)).toHaveAttribute("data-area-count", "23");
    await expect(content(page)).toHaveAttribute("data-node-count", "210");
    await expect(content(page)).toHaveAttribute("data-edge-count", "422");
    await expect(content(page).locator("[data-node-id]:visible, [data-edge-id]:visible")).toHaveCount(0);
    await expect(page.getByTestId("area-card-AREA_01")).toHaveAccessibleName(/Start, sign in, permissions and owner changes/);
    await expect(page.getByTestId("area-card-AREA_23")).toHaveAccessibleName(/Codebase map publishing/);
    await expect(page.getByTestId("area-card-AREA_22")).toContainText("Runtime updates, feedback and privacy");
    const scale = (await camera(page)).scale;
    const fontSizes = await page.locator(".area-card-title").evaluateAll(titles => titles.map(title => Number.parseFloat(getComputedStyle(title).fontSize)));
    expect(fontSizes).toHaveLength(23);
    expect(Math.min(...fontSizes) * scale).toBeGreaterThanOrEqual(13.99);
    const overflow = await page.locator(".area-card-title, .region-meta").evaluateAll(labels => labels.flatMap(label => {
      const region = label.closest(".map-region")!;
      const bounds = region.getBoundingClientRect();
      const text = label.getBoundingClientRect();
      const padding = { left: text.left - bounds.left, right: bounds.right - text.right, top: text.top - bounds.top, bottom: bounds.bottom - text.bottom };
      return Object.values(padding).some(value => value < 3.5)
        ? [{ area: region.getAttribute("data-area-id"), label: label.textContent, padding }] : [];
    }));
    expect(overflow, "Overview titles or metadata escape their subsystem regions").toEqual([]);
    if (viewport.width >= 700) {
      const clipped = await areaRegions(page).evaluateAll(regions => {
        const viewport = document.querySelector('[data-testid="diagram-viewport"]')!.getBoundingClientRect();
        return regions.filter(region => {
          const box = region.getBoundingClientRect();
          return box.left < viewport.left - 1 || box.top < viewport.top - 1 || box.right > viewport.right + 1 || box.bottom > viewport.bottom + 1;
        }).map(region => region.getAttribute("data-area-id"));
      });
      expect(clipped, "Desktop overview clips entire subsystem regions").toEqual([]);
    }
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
  });

  test(`reduced-motion focus and persistent connection inspector work at ${viewport.width}px`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await overview(page);
    const group = await page.locator(".map-connection-group").evaluateAll(groups => groups.map(group => ({
      id: group.getAttribute("data-connection-group")!,
      ids: JSON.parse(group.getAttribute("data-edge-ids")!) as string[],
    })).sort((a, b) => b.ids.length - a.ids.length)[0]);
    await page.locator(`[data-connection-group="${group.id}"]`).focus();
    await page.keyboard.press("Enter");
    const inspector = page.getByRole("complementary", { name: "Connection details" });
    await expect(inspector).toBeVisible();
    expect(await inspector.locator("[data-edge-id]").evaluateAll(items => items.map(item => item.getAttribute("data-edge-id")))).toEqual(group.ids);
    const list = inspector.getByRole("list", { name: "Individual connections" });
    const listBox = await list.boundingBox();
    if (!listBox) throw new Error("Connection inspector list has no bounds");
    const initial = await camera(page);
    await page.mouse.move(listBox.x + listBox.width / 2, listBox.y + listBox.height / 2);
    await page.mouse.wheel(0, 300);
    await expect.poll(async () => list.evaluate(element => element.scrollTop)).toBeGreaterThan(0);
    expect(await camera(page), "Scrolling the inspector zoomed the map").toEqual(initial);
    await list.focus();
    await page.keyboard.press("Home");
    await expect.poll(async () => list.evaluate(element => element.scrollTop)).toBe(0);
    expect(await camera(page), "Keyboard scrolling the inspector moved the map").toEqual(initial);
    await page.keyboard.press("Escape");
    await expect(inspector).toBeHidden();
    expect(await camera(page), "Closing the inspector reset the map").toEqual(initial);
    await page.locator(`[data-connection-group="${group.id}"]`).focus();
    await page.keyboard.press("Enter");
    await page.mouse.move(5, 5);
    await nextFrames(page);
    await expect(inspector).toBeVisible();
    const inspectorBox = await inspector.boundingBox();
    const canvasBox = await viewBox(page);
    expect(inspectorBox!.x).toBeGreaterThanOrEqual(canvasBox.x);
    expect(inspectorBox!.x + inspectorBox!.width).toBeLessThanOrEqual(canvasBox.x + canvasBox.width + 1);
    expect(inspectorBox!.y + inspectorBox!.height).toBeLessThanOrEqual(canvasBox.y + canvasBox.height + 1);
    const target = group.id.slice(0, 7);
    await inspector.locator(".connection-endpoints button").first().click();
    await expect(inspector).toBeHidden();
    await expect(content(page)).toHaveAttribute("data-active-area", target);
    await expect(areaDiagram(page, target)).toHaveAttribute("data-readable", "true");
    const after = await camera(page);
    await nextFrames(page);
    expect(await camera(page), "Reduced-motion focus still animated").toEqual(after);
    await page.getByRole("button", { name: "Overview", exact: true }).click();
    await expect(content(page)).toHaveAttribute("data-active-area", "");
  });
}

test("a native mobile touch swipe scrolls connection details without moving the map", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await overview(page);
  const id = await page.locator(".map-connection-group").evaluateAll(groups => groups.sort((a, b) =>
    JSON.parse(b.getAttribute("data-edge-ids")!).length - JSON.parse(a.getAttribute("data-edge-ids")!).length)[0].getAttribute("data-connection-group"));
  await page.locator(`[data-connection-group="${id}"]`).focus();
  await page.keyboard.press("Enter");
  const list = page.getByRole("list", { name: "Individual connections" });
  const box = await list.boundingBox();
  if (!box) throw new Error("Connection list has no touch target");
  const initial = await camera(page);
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
  await expect.poll(async () => list.evaluate(element => element.scrollTop), { timeout: 5000 }).toBeGreaterThan(20);
  expect(await camera(page)).toEqual(initial);
  await session.detach();
});

test("close views can inspect and navigate connected subsystems without replacing their node view", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  for (const id of ["AREA_07", "AREA_15"]) {
    await focusArea(page, id);
    const initial = await camera(page);
    const svgId = await areaSvg(page, id).getAttribute("id");
    const connections = page.getByRole("navigation", { name: "Connected subsystems", exact: true });
    const toggle = connections.getByRole("button", { name: /connected subsystems/ });
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(await camera(page)).toEqual(initial);
    expect(await areaSvg(page, id).getAttribute("id")).toBe(svgId);
    await connections.getByRole("button", { name: /^Inspect connections with/ }).first().click();
    const inspector = page.getByRole("complementary", { name: "Connection details" });
    await expect(inspector).toBeVisible();
    expect(await camera(page)).toEqual(initial);
    expect(await areaSvg(page, id).getAttribute("id")).toBe(svgId);
    await inspector.getByRole("button", { name: "Close connection details" }).click();
    await toggle.click();
    const destination = connections.locator(".connected-list > div > button:first-child").first();
    const target = `AREA_${await destination.locator("span").first().innerText()}`;
    await destination.click();
    await expect(content(page)).toHaveAttribute("data-active-area", target);
    await expect(areaDiagram(page, target)).toHaveAttribute("data-readable", "true");
    expect(await areaSvg(page, id).getAttribute("id")).toBe(svgId);
  }
});

test("all 23 cached views preserve 210 nodes and 422 connections including areas without internal edges", async ({ page }) => {
  test.setTimeout(120_000);
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  const positions = await regionPositions(page);
  const areaIds = await page.getByLabel("Jump to area", { exact: true }).locator("option").evaluateAll(options => options.map(option => (option as HTMLOptionElement).value).filter(Boolean));
  expect(areaIds).toHaveLength(23);
  const nodes = new Set<string>();
  const internalEdges = new Set<string>();
  const svgIds = new Map<string, string>();
  for (const id of areaIds) {
    await focusArea(page, id);
    const diagram = areaDiagram(page, id);
    expect(await diagram.locator("[data-node-id]").evaluateAll(items => {
      const viewport = document.querySelector('[data-testid="diagram-viewport"]')!.getBoundingClientRect();
      return items.some(item => {
        const box = item.getBoundingClientRect();
        return Math.min(box.right, viewport.right) - Math.max(box.left, viewport.left) > 12
          && Math.min(box.bottom, viewport.bottom) - Math.max(box.top, viewport.top) > 12;
      });
    }), `${id} focused into empty space without a visible node`).toBe(true);
    for (const node of await diagram.locator("[data-node-id]").evaluateAll(items => items.map(item => item.getAttribute("data-node-id")!))) nodes.add(node);
    for (const edge of await diagram.locator('[data-edge-id][data-edge-kind="internal"]').evaluateAll(items => items.map(item => item.getAttribute("data-edge-id")!))) internalEdges.add(edge);
    if (["AREA_20", "AREA_21"].includes(id)) await expect(diagram.locator("[data-edge-id]")).toHaveCount(0);
    expect(await diagram.innerText()).not.toMatch(/<br\s*\/?\s*>/i);
    svgIds.set(id, (await areaSvg(page, id).getAttribute("id"))!);
    expect(await regionPositions(page)).toEqual(positions);
  }
  expect(nodes.size).toBe(210);
  expect(internalEdges.size).toBe(161);
  const externalEdges = await page.locator(".map-connection-group").evaluateAll(groups => groups.flatMap(group => JSON.parse(group.getAttribute("data-edge-ids")!) as string[]));
  expect(externalEdges).toHaveLength(261);
  expect(new Set([...internalEdges, ...externalEdges]).size).toBe(422);
  for (const id of ["AREA_01", "AREA_07", "AREA_15", "AREA_20", "AREA_21"]) {
    await focusArea(page, id);
    expect(await areaSvg(page, id).getAttribute("id")).toBe(svgIds.get(id));
  }
  await page.getByRole("button", { name: "Fit diagram", exact: true }).click();
  expect(await regionPositions(page)).toEqual(positions);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
  expect(errors).toEqual([]);
});

test("wheel zoom retains its world anchor through detail loading and reverse zoom", async ({ page }) => {
  await overview(page);
  const positions = await regionPositions(page);
  const region = positions.find(area => area.id === "AREA_01")!;
  const initial = await camera(page);
  const requested = { x: initial.x + (region.x + region.width / 2) * initial.scale, y: initial.y + (region.y + region.height / 2) * initial.scale };
  const viewportBefore = await viewBox(page);
  const { anchor } = await wheelTo(page, 24, requested);
  const original = worldAt(initial, anchor);
  await expect(areaDiagram(page, "AREA_01")).toHaveAttribute("data-readable", "true");
  await nextFrames(page);
  const after = await camera(page);
  expect(after.scale).toBeCloseTo(24, 5);
  expect(worldAt(after, anchor).x).toBeCloseTo(original.x, 5);
  expect(worldAt(after, anchor).y).toBeCloseTo(original.y, 5);
  expect(await viewBox(page)).toEqual(viewportBefore);
  await nextFrames(page);
  expect(await camera(page), "Detail rendering moved the camera after wheel zoom").toEqual(after);
  await wheelTo(page, initial.scale, anchor);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
  await expect(areaDiagram(page, "AREA_01")).toHaveAttribute("data-readable", "false");
  expect(worldAt(await camera(page), anchor).x).toBeCloseTo(original.x, 5);
  expect(worldAt(await camera(page), anchor).y).toBeCloseTo(original.y, 5);
  expect(await regionPositions(page)).toEqual(positions);
});

test("panning at close zoom reveals a second region without clicking or changing selection", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  await focusArea(page, "AREA_01");
  const before = await camera(page);
  const region = (await regionPositions(page)).find(area => area.id === "AREA_17")!;
  const box = await viewBox(page);
  await panBy(page, box.width / 2 - (region.x + region.width / 2) * before.scale - before.x,
    box.height / 2 - (region.y + region.height / 2) * before.scale - before.y);
  await expect(areaDiagram(page, "AREA_17")).toHaveAttribute("data-readable", "true");
  await expect(areaDiagram(page, "AREA_17")).toBeInViewport();
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  expect((await camera(page)).scale).toBe(before.scale);
});

test("click focus animates and wheel input cancels that animation without a delayed jump", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  await focusArea(page, "AREA_01");
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.clock.install();
  const initial = await camera(page);
  await page.getByTestId("area-card-AREA_01").click();
  await page.clock.runFor(100);
  const intermediate = await camera(page);
  expect(intermediate.scale).toBeGreaterThan(initial.scale);
  await page.clock.runFor(500);
  const focused = await camera(page);
  expect(focused.scale).toBeGreaterThan(intermediate.scale);
  await expect(areaDiagram(page, "AREA_01")).toHaveAttribute("data-readable", "true");
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await page.clock.runFor(100);
  const box = await viewBox(page);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, -80);
  await page.clock.runFor(32);
  const interrupted = await camera(page);
  await page.clock.runFor(500);
  expect(await camera(page)).toEqual(interrupted);
});

test("labels reveal reserved source lines without moving nodes and resize preserves the camera", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  await focusArea(page, "AREA_01");
  const diagram = areaDiagram(page, "AREA_01");
  const nodePositions = await diagram.locator("[data-node-id]").evaluateAll(nodes => nodes.map(node => ({ id: node.getAttribute("data-node-id"), transform: node.getAttribute("transform") })));
  const svgId = await areaSvg(page).getAttribute("id");
  await expect(diagram.locator(".node-details").first()).toBeHidden();
  await page.getByRole("button", { name: "Zoom in", exact: true }).click();
  await page.getByRole("button", { name: "Zoom in", exact: true }).click();
  await expect(diagram.locator(".node-details").first()).toBeVisible();
  await expect(diagram).toContainText("OmiApp.swift:279");
  expect(await diagram.locator("[data-node-id]").evaluateAll(nodes => nodes.map(node => ({ id: node.getAttribute("data-node-id"), transform: node.getAttribute("transform") })))).toEqual(nodePositions);
  const before = await camera(page);
  const oldBox = await viewBox(page);
  await page.setViewportSize({ width: 1100, height: 800 });
  const newBox = await viewBox(page);
  const originalCenter = worldAt(before, { x: oldBox.width / 2, y: oldBox.height / 2 });
  await expect.poll(async () => worldAt(await camera(page), { x: newBox.width / 2, y: newBox.height / 2 }).x).toBeCloseTo(originalCenter.x, 4);
  expect(worldAt(await camera(page), { x: newBox.width / 2, y: newBox.height / 2 }).y).toBeCloseTo(originalCenter.y, 4);
  expect((await camera(page)).scale).toBe(before.scale);
  expect(await areaSvg(page).getAttribute("id")).toBe(svgId);
});

test("zoom-out never increases a preserved desktop scale after resizing to mobile", async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 700 });
  await overview(page);
  await page.getByTestId("diagram-viewport").focus();
  await page.keyboard.press("ArrowRight");
  const before = await camera(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect.poll(async () => Number(await content(page).getAttribute("data-overview-scale"))).toBeGreaterThan(before.scale);
  expect((await camera(page)).scale).toBe(before.scale);
  await page.getByRole("button", { name: "Zoom out", exact: true }).click();
  expect((await camera(page)).scale).toBeLessThanOrEqual(before.scale);
  await wheelTo(page, before.scale * 1.05);
});

test("pointer, keyboard, fullscreen and overview controls retain navigation", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  const initial = await camera(page);
  await panBy(page, 90, 60);
  expect((await camera(page)).x).toBeCloseTo(initial.x + 90, 1);
  const viewport = page.getByTestId("diagram-viewport");
  await viewport.focus();
  const beforeKey = await camera(page);
  await page.keyboard.press("ArrowRight");
  expect((await camera(page)).x).toBe(beforeKey.x - 64);
  await page.keyboard.press("+");
  expect((await camera(page)).scale).toBeCloseTo(beforeKey.scale * 1.3, 4);
  await page.getByRole("button", { name: "Enter fullscreen", exact: true }).click();
  await expect(page.getByRole("button", { name: "Exit fullscreen", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Exit fullscreen", exact: true }).click();
  for (const key of ["Home", "Escape", "f"]) {
    await focusArea(page, "AREA_01");
    await viewport.focus();
    await page.keyboard.press(key);
    await expect(content(page)).toHaveAttribute("data-active-area", "");
    expect((await camera(page)).scale).toBeCloseTo(Number(await content(page).getAttribute("data-overview-scale")), 5);
  }
});

test("two-finger pinch preserves the gesture anchor while revealing the region under it", async ({ page }) => {
  await overview(page);
  const initial = await camera(page);
  const card = await page.getByTestId("area-card-AREA_01").boundingBox();
  if (!card) throw new Error("Area card has no bounds");
  const box = await viewBox(page);
  const x = Math.round(card.x + card.width / 2), y = Math.round(card.y + card.height / 2);
  const anchor = { x: x - box.x, y: y - box.y };
  const initialWorld = worldAt(initial, anchor);
  const session = await page.context().newCDPSession(page);
  await session.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 });
  await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: x - 10, y, id: 1 }, { x: x + 10, y, id: 2 }] });
  for (const distance of [30, 60, 100, 140]) {
    await session.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: x - distance, y, id: 1 }, { x: x + distance, y, id: 2 }] });
  }
  await session.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await expect.poll(async () => (await camera(page)).scale).toBeGreaterThan(initial.scale * 10);
  await expect(areaDiagram(page, "AREA_01")).toHaveAttribute("data-readable", "true");
  await nextFrames(page);
  const after = await camera(page);
  expect(worldAt(after, anchor).x).toBeCloseTo(initialWorld.x, 3);
  expect(worldAt(after, anchor).y).toBeCloseTo(initialWorld.y, 3);
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await session.detach();
});
test("a failed local render keeps the overview usable and Retry restores the focused area", async ({ page }) => {
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
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  const initial = await camera(page);
  await page.getByLabel("Jump to area", { exact: true }).selectOption("AREA_01");
  const region = page.getByTestId("area-region-AREA_01");
  await expect(region.getByRole("alert")).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("data-area-measurement-failed", "true");
  await expect(page.getByTestId("diagram-error")).toBeHidden();
  await expect(areaCards(page)).toHaveCount(23);
  await expect(page.getByLabel("Jump to area", { exact: true })).toBeEnabled();
  expect(await camera(page)).toEqual(initial);
  await page.getByTestId("diagram-viewport").focus();
  await page.keyboard.press("ArrowRight");
  expect((await camera(page)).x).toBe(initial.x - 64);
  await region.getByRole("button", { name: "Retry this area" }).click();
  await expect(areaDiagram(page, "AREA_01")).toHaveAttribute("data-readable", "true");
  await expect(region.getByRole("alert")).toBeHidden();
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await expect(areaDiagram(page, "AREA_01").locator("[data-node-id]")).toHaveCount(8);
});

test("an offscreen destination failure exposes a visible retry that restores navigation", async ({ page }) => {
  await page.addInitScript(() => {
    const original = SVGGraphicsElement.prototype.getBBox;
    let failed = false;
    SVGGraphicsElement.prototype.getBBox = function (...args) {
      if (!failed && document.documentElement.hasAttribute("data-arm-offscreen-failure")
        && this.ownerSVGElement?.id.startsWith("intentive_area_") && this.getAttribute("data-node-id") === "APP") {
        failed = true;
        throw new Error("Injected offscreen destination measurement failure");
      }
      return original.apply(this, args);
    };
  });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await overview(page);
  await focusArea(page, "AREA_15");
  const before = await camera(page);
  await page.locator("html").evaluate(element => element.setAttribute("data-arm-offscreen-failure", "true"));
  await page.getByLabel("Jump to area", { exact: true }).selectOption("AREA_01");
  const notice = page.locator(".focus-error[role=alert]");
  await expect(notice).toBeVisible();
  await expect(notice).toBeInViewport();
  await expect(notice).toContainText("Start, sign in");
  expect(await camera(page)).toEqual(before);
  await notice.getByRole("button", { name: "Retry opening area", exact: true }).click();
  await expect(areaDiagram(page, "AREA_01")).toHaveAttribute("data-readable", "true");
  await expect(notice).toBeHidden();
  await expect(content(page)).toHaveAttribute("data-active-area", "AREA_01");
  await expect(areaDiagram(page, "AREA_01").locator("[data-node-id]")).toHaveCount(8);
});

test("wheel input during a pending local render cancels its later focus movement", async ({ page }) => {
  await page.addInitScript(() => {
    const original = SVGGraphicsElement.prototype.getBBox;
    let interrupted = false;
    SVGGraphicsElement.prototype.getBBox = function (...args) {
      if (!interrupted && this.ownerSVGElement?.id.startsWith("intentive_area_") && this.getAttribute("data-node-id") === "APP") {
        interrupted = true;
        const viewport = document.querySelector('[data-testid="diagram-viewport"]')!;
        const box = viewport.getBoundingClientRect();
        const x = Math.round(box.left + box.width / 2), y = Math.round(box.top + box.height / 2);
        viewport.dispatchEvent(new WheelEvent("wheel", { deltaY: -100, clientX: x, clientY: y, bubbles: true, cancelable: true }));
        document.documentElement.setAttribute("data-render-wheel-anchor", JSON.stringify({ x: x - box.left, y: y - box.top }));
      }
      return original.apply(this, args);
    };
  });
  await overview(page);
  const initial = await camera(page);
  await page.getByLabel("Jump to area", { exact: true }).selectOption("AREA_01");
  await expect(page.locator("html")).toHaveAttribute("data-render-wheel-anchor");
  await expect(page.locator('body > div[aria-hidden="true"] svg[id^="intentive_area_"]')).toHaveCount(0);
  await nextFrames(page);
  const anchor = JSON.parse((await page.locator("html").getAttribute("data-render-wheel-anchor"))!) as { x: number; y: number };
  const after = await camera(page);
  expect(after.scale).toBeCloseTo(initial.scale * Math.exp(.2), 5);
  expect(worldAt(after, anchor).x).toBeCloseTo(worldAt(initial, anchor).x, 5);
  expect(worldAt(after, anchor).y).toBeCloseTo(worldAt(initial, anchor).y, 5);
  await expect(content(page)).toHaveAttribute("data-active-area", "");
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
