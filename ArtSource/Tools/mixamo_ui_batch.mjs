import fs from "node:fs/promises";

const catalogPath = "/Users/exrector/Documents/PROJECTS/DerClou/ArtSource/Animations/mixamo-motion-catalog.json";
const outputDirectory = "/Users/exrector/Downloads/actions/MixamoFull";
const statePath = `${outputDirectory}/_bulk-ui-state.json`;

function safeFilename(value) {
  return String(value || "mixamo-motion")
    .replace(/[^A-Za-z0-9._ -]+/g, "_")
    .replace(/^[ .]+|[ .]+$/g, "") || "mixamo-motion";
}

async function saveState(state) {
  const temporary = `${statePath}.partial`;
  await fs.writeFile(temporary, `${JSON.stringify(state, null, 2)}\n`);
  await fs.rename(temporary, statePath);
}

async function archiveOne(item, chrome) {
  const destination = `${outputDirectory}/${safeFilename(item.name)}__${item.id}.fbx`;
  try {
    await fs.access(destination);
    return { status: "exists", id: item.id };
  } catch {}

  const tab = await chrome.tabs.new();
  try {
    const url = `https://www.mixamo.com/#/?page=1&type=Motion&query=${encodeURIComponent(item.name)}`;
    await tab.goto(url).catch(() => {});
    await tab.playwright.waitForTimeout(900);

    const animatedThumbnail = String(item.thumbnail).replace("/static.png", "/animated.gif");
    const image = tab.playwright.locator(`img[src="${animatedThumbnail}"]`);
    await image.waitFor({ state: "attached", timeoutMs: 15_000 });
    await image.click({ timeoutMs: 10_000 });
    await tab.playwright.waitForTimeout(1_100);

    await tab.playwright
      .getByRole("button", { name: /^(Download|Скачать)$/ })
      .last()
      .click({ timeoutMs: 10_000 });
    await tab.playwright.waitForTimeout(250);

    const dialog = tab.playwright.getByRole("dialog").last();
    const selects = dialog.getByRole("combobox");
    await selects.nth(1).selectOption({ value: "false" });
    await selects.nth(2).selectOption({ value: "30" });
    await selects.nth(3).selectOption({ value: "0" });
    await dialog
      .getByRole("button", { name: /^(Download|Скачать)$/ })
      .click({ timeoutMs: 10_000 });

    let signedURL = "";
    for (let index = 0; index < 60; index += 1) {
      await tab.playwright.waitForTimeout(500);
      signedURL = await tab.url();
      if (signedURL.startsWith("https://mixamo-storage-prod.s3-us-west-2.amazonaws.com/")) break;
    }
    if (!signedURL.startsWith("https://mixamo-storage-prod.s3-us-west-2.amazonaws.com/")) {
      throw new Error("Mixamo did not provide a signed export URL");
    }

    const response = await fetch(signedURL);
    if (!response.ok) throw new Error(`Mixamo export download HTTP ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    await fs.writeFile(`${destination}.partial`, bytes);
    await fs.rename(`${destination}.partial`, destination);
    await fs.writeFile(`${destination}.source.json`, `${JSON.stringify({
      provider: "Adobe Mixamo",
      motionID: item.id,
      motionName: item.name,
      motionDescription: item.description || "",
      exportCharacter: "Y Bot",
      format: "FBX Binary, without skin, 30 fps, no key reduction",
      acquisition: "authenticated Mixamo UI through Chrome; temporary signed export URL",
      rawRedistributionAllowed: false,
    }, null, 2)}\n`);
    return { status: "downloaded", id: item.id, bytes: bytes.length };
  } finally {
    await tab.close().catch(() => {});
  }
}

export async function runMixamoUIBatch(chrome, batchSize = 10) {
  await chrome.nameSession("🎞️ Архив Mixamo DerClou");
  await fs.mkdir(outputDirectory, { recursive: true });
  const catalog = JSON.parse(await fs.readFile(catalogPath, "utf8")).items;
  let state;
  try {
    state = JSON.parse(await fs.readFile(statePath, "utf8"));
  } catch {
    state = { schemaVersion: 3, catalogCount: catalog.length, character: "Y Bot", completed: [], failed: {} };
  }
  const completed = new Set(state.completed || []);
  const failed = state.failed || {};
  const queue = catalog
    .filter((item) => !completed.has(item.id))
    .sort((left, right) => (failed[left.id]?.totalAttempts || 0) - (failed[right.id]?.totalAttempts || 0))
    .slice(0, batchSize);

  for (const item of queue) {
    let succeeded = false;
    let lastError = "";
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const result = await archiveOne(item, chrome);
        completed.add(item.id);
        delete failed[item.id];
        state.last = { id: item.id, name: item.name, status: result.status, at: new Date().toISOString() };
        succeeded = true;
        break;
      } catch (error) {
        lastError = String(error?.message || error);
        const totalAttempts = (failed[item.id]?.totalAttempts || 0) + 1;
        failed[item.id] = { name: item.name, error: lastError, totalAttempts, at: new Date().toISOString() };
        state.last = { id: item.id, name: item.name, status: "retry", error: lastError, at: new Date().toISOString() };
        await new Promise((resolve) => setTimeout(resolve, attempt * 1_000));
      } finally {
        state.completed = [...completed];
        state.failed = failed;
        await saveState(state);
      }
    }
    if (!succeeded) {
      state.last = { id: item.id, name: item.name, status: "deferred", error: lastError, at: new Date().toISOString() };
      await saveState(state);
    }
  }

  return {
    completed: completed.size,
    total: catalog.length,
    failed: Object.keys(failed).length,
    batch: queue.length,
    last: state.last,
  };
}
