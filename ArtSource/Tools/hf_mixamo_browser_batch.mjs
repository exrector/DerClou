import fs from "node:fs/promises";

const repository = "jasongzy/Mixamo";
const libraryRoot = "/Users/exrector/Documents/PROJECTS/DerClou/ArtSource/Animations/Library";
const outputDirectory = `${libraryRoot}/Sources/HashArchive`;
const statePath = `${libraryRoot}/Work/_browser-download-state.json`;
const datasetPage = `https://huggingface.co/datasets/${repository}`;
let stateWriteChain = Promise.resolve();

async function exists(path) {
  try { await fs.access(path); return true; } catch { return false; }
}

async function saveState(state, destinationPath = statePath) {
  const snapshot = `${JSON.stringify(state, null, 2)}\n`;
  stateWriteChain = stateWriteChain.then(async () => {
    const temporary = `${destinationPath}.partial`;
    await fs.writeFile(temporary, snapshot);
    await fs.rename(temporary, destinationPath);
  });
  return stateWriteChain;
}

async function animationFiles() {
  const response = await fetch(`https://huggingface.co/api/datasets/${repository}?expand[]=siblings`);
  if (!response.ok) throw new Error(`Hugging Face metadata HTTP ${response.status}`);
  const metadata = await response.json();
  return metadata.siblings
    .map((item) => item.rfilename)
    .filter((name) => /^animation\/[0-9a-f]{32}\.fbx$/.test(name))
    .sort();
}

async function signedDownloadURL(browser, relativePath) {
  const tab = await browser.tabs.new();
  try {
    await tab.goto(datasetPage).catch(() => {});
    const cdp = await tab.capabilities.get("cdp");
    await cdp.send("Network.enable", {});
    let cursor = (await cdp.readEvents({ methods: ["Network.requestWillBeSent"], limit: 1 })).cursor;
    tab.playwright.waitForEvent("download", { timeoutMs: 15_000 }).catch(() => null);
    const resolveURL = `https://huggingface.co/datasets/${repository}/resolve/main/${relativePath}?download=true`;
    await tab.goto(resolveURL).catch(() => {});
    for (let attempt = 0; attempt < 12; attempt += 1) {
      const page = await cdp.readEvents({
        afterSequence: cursor,
        methods: ["Network.requestWillBeSent"],
        limit: 1000,
        timeoutMs: 500,
      });
      cursor = page.cursor;
      const signed = page.events
        .map((event) => event.params?.request?.url)
        .find((url) => url?.includes("xet-bridge-us"));
      if (signed) return signed;
    }
    throw new Error("Chrome did not expose the signed Xet URL");
  } finally {
    await tab.close().catch(() => {});
  }
}

async function downloadOne(browser, relativePath) {
  const filename = relativePath.slice("animation/".length);
  const destination = `${outputDirectory}/${filename}`;
  if (await exists(destination)) return { filename, status: "exists" };

  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      const signedURL = await signedDownloadURL(browser, relativePath);
      const response = await fetch(signedURL);
      if (!response.ok) throw new Error(`Xet download HTTP ${response.status}`);
      const bytes = new Uint8Array(await response.arrayBuffer());
      await fs.writeFile(`${destination}.partial`, bytes);
      await fs.rename(`${destination}.partial`, destination);
      return { filename, status: "downloaded" };
    } catch (error) {
      if (attempt === 4) throw error;
      await new Promise((resolve) => setTimeout(resolve, attempt * 500));
    }
  }
}

export async function runHFMixamoBrowserBatch(browser, {
  batchSize = 200,
  workers = 10,
  partitionIndex = 0,
  partitionCount = 1,
} = {}) {
  if (!Number.isInteger(partitionCount) || partitionCount < 1) {
    throw new Error("partitionCount must be a positive integer");
  }
  if (!Number.isInteger(partitionIndex) || partitionIndex < 0 || partitionIndex >= partitionCount) {
    throw new Error("partitionIndex must be an integer within partitionCount");
  }
  await fs.mkdir(outputDirectory, { recursive: true });
  const files = await animationFiles();
  const missing = [];
  let startingCompleted = 0;
  for (const [fileIndex, relativePath] of files.entries()) {
    if (await exists(`${outputDirectory}/${relativePath.slice("animation/".length)}`)) {
      startingCompleted += 1;
    } else if (fileIndex % partitionCount === partitionIndex && missing.length < batchSize) {
      missing.push(relativePath);
    }
  }

  const partitionStatePath = partitionCount === 1
    ? statePath
    : statePath.replace(/\.json$/, `.p${partitionIndex}-of-${partitionCount}.json`);
  let state;
  try { state = JSON.parse(await fs.readFile(partitionStatePath, "utf8")); }
  catch { state = { schemaVersion: 1, repository, total: files.length, completed: 0, failed: {} }; }
  const failed = state.failed || {};
  let nextIndex = 0;
  let batchCompleted = 0;

  const worker = async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= missing.length) break;
      const relativePath = missing[index];
      try {
        const result = await downloadOne(browser, relativePath);
        batchCompleted += 1;
        delete failed[relativePath];
        state.last = { path: relativePath, status: result.status, at: new Date().toISOString() };
      } catch (error) {
        failed[relativePath] = { error: String(error?.message || error), at: new Date().toISOString() };
        state.last = { path: relativePath, status: "failed", error: failed[relativePath].error, at: new Date().toISOString() };
      }
      state.failed = failed;
      state.completed = startingCompleted + batchCompleted;
      await saveState(state, partitionStatePath);
    }
  };

  await Promise.all(Array.from({ length: Math.min(workers, missing.length) }, worker));
  let totalCompleted = 0;
  for (const relativePath of files) {
    if (await exists(`${outputDirectory}/${relativePath.slice("animation/".length)}`)) totalCompleted += 1;
  }
  state.completed = totalCompleted;
  state.failed = failed;
  await saveState(state, partitionStatePath);
  return {
    completed: totalCompleted,
    total: files.length,
    failed: Object.keys(failed).length,
    batch: missing.length,
    partitionIndex,
    partitionCount,
  };
}
