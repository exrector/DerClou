import fs from "node:fs/promises";

const baseURL = "https://www.mixamo.com/api/v1";
const catalogPath = "/Users/exrector/Documents/PROJECTS/DerClou/ArtSource/Animations/mixamo-motion-catalog.json";
const outputDirectory = "/Users/exrector/Downloads/actions/MixamoFull";
const statePath = `${outputDirectory}/_bulk-ui-state.json`;
let stateWriteChain = Promise.resolve();

function safeFilename(value) {
  return String(value || "mixamo-motion")
    .replace(/[^A-Za-z0-9._ -]+/g, "_")
    .replace(/^[ .]+|[ .]+$/g, "") || "mixamo-motion";
}

async function saveState(state) {
  const snapshot = `${JSON.stringify(state, null, 2)}\n`;
  stateWriteChain = stateWriteChain.then(async () => {
    const temporary = `${statePath}.partial`;
    await fs.writeFile(temporary, snapshot);
    await fs.rename(temporary, statePath);
  });
  return stateWriteChain;
}

function requestHeaders(authorization, json = false) {
  return {
    Accept: "application/json, text/javascript, */*; q=0.01",
    Authorization: authorization,
    Referer: "https://www.mixamo.com/",
    "X-Api-Key": "mixamo2",
    "X-Requested-With": "XMLHttpRequest",
    ...(json ? { "Content-Type": "application/json; charset=UTF-8" } : {}),
  };
}

async function requestJSON(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  let value;
  try { value = JSON.parse(text); } catch { value = { raw: text.slice(0, 800) }; }
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${JSON.stringify(value).slice(0, 800)}`);
  return value;
}

function normalizeDescriptor(product) {
  const descriptor = structuredClone(product?.details?.gms_hash || {});
  if (!descriptor["model-id"]) throw new Error("Mixamo product has no model-id");
  if (Array.isArray(descriptor.params)) {
    descriptor.params = descriptor.params.map((value) => value[value.length - 1]).join(",");
  }
  if (Array.isArray(descriptor.trim)) descriptor.trim = descriptor.trim.map(Number);
  descriptor.overdrive = 0;
  return descriptor;
}

async function prepareProduct(item, characterID, authorization) {
  const product = await requestJSON(
    `${baseURL}/products/${encodeURIComponent(item.id)}?similar=0&character_id=${encodeURIComponent(characterID)}`,
    { headers: requestHeaders(authorization) },
  );
  return { item, product, descriptor: normalizeDescriptor(product) };
}

async function requestExport(prepared, characterID, authorization) {
  await requestJSON(`${baseURL}/animations/export`, {
    method: "POST",
    headers: requestHeaders(authorization, true),
    body: JSON.stringify({
      gms_hash: [prepared.descriptor],
      preferences: { format: "fbx7_2019", skin: "false", fps: "30", reducekf: "0" },
      character_id: characterID,
      type: prepared.product.type || "Motion",
      product_name: prepared.product.description || prepared.product.name || prepared.item.name,
    }),
  });

  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    const monitor = await requestJSON(`${baseURL}/characters/${encodeURIComponent(characterID)}/monitor`, {
      headers: requestHeaders(authorization),
    });
    if (monitor.status === "completed" && typeof monitor.job_result === "string") return monitor.job_result;
    if (monitor.status === "failed") throw new Error(`Mixamo export failed: ${JSON.stringify(monitor.job_result)}`);
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Mixamo export monitor timed out");
}

async function saveDownload(prepared, signedURL) {
  const item = prepared.item;
  const destination = `${outputDirectory}/${safeFilename(item.name)}__${item.id}.fbx`;
  let bytes;
  let lastError;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      const response = await fetch(signedURL);
      if (!response.ok) throw new Error(`S3 download HTTP ${response.status}`);
      bytes = new Uint8Array(await response.arrayBuffer());
      break;
    } catch (error) {
      lastError = error;
      if (attempt < 4) await new Promise((resolve) => setTimeout(resolve, attempt * 300));
    }
  }
  if (!bytes) throw lastError || new Error("S3 download failed");
  await fs.writeFile(`${destination}.partial`, bytes);
  await fs.rename(`${destination}.partial`, destination);
  await fs.writeFile(`${destination}.source.json`, `${JSON.stringify({
    provider: "Adobe Mixamo",
    motionID: item.id,
    motionName: item.name,
    motionDescription: item.description || prepared.product.description || "",
    exportCharacter: "Y Bot",
    format: "FBX Binary, without skin, 30 fps, no key reduction",
    acquisition: "authenticated Mixamo API used by the official web application",
    rawRedistributionAllowed: false,
  }, null, 2)}\n`);
  return bytes.length;
}

export async function runMixamoFastBatch({ authorization, characterID, batchSize = 25, prefetch = 8 }) {
  if (!authorization?.startsWith("Bearer ")) throw new Error("Missing Mixamo bearer authorization");
  await fs.mkdir(outputDirectory, { recursive: true });
  const catalog = JSON.parse(await fs.readFile(catalogPath, "utf8")).items;
  let state;
  try { state = JSON.parse(await fs.readFile(statePath, "utf8")); }
  catch { state = { schemaVersion: 4, catalogCount: catalog.length, character: "Y Bot", completed: [], failed: {} }; }
  const completed = new Set(state.completed || []);
  const failed = state.failed || {};
  const queue = catalog.filter((item) => !completed.has(item.id)).slice(0, batchSize);
  const prepared = new Map();
  let nextPrepare = 0;

  const fillPrefetch = () => {
    while (nextPrepare < queue.length && prepared.size < prefetch) {
      const index = nextPrepare++;
      prepared.set(index, prepareProduct(queue[index], characterID, authorization));
    }
  };
  fillPrefetch();

  const pendingDownloads = new Set();
  for (let index = 0; index < queue.length; index += 1) {
    const item = queue[index];
    let success = false;
    let lastError = "";
    for (let attempt = 1; attempt <= 3 && !success; attempt += 1) {
      try {
        const current = await prepared.get(index);
        prepared.delete(index);
        fillPrefetch();
        const signedURL = await requestExport(current, characterID, authorization);
        const download = saveDownload(current, signedURL)
          .then(async (bytes) => {
            completed.add(item.id);
            delete failed[item.id];
            state.completed = [...completed];
            state.failed = failed;
            state.last = { id: item.id, name: item.name, status: "downloaded", bytes, at: new Date().toISOString() };
            await saveState(state);
          })
          .catch(async (error) => {
            const message = String(error?.message || error);
            failed[item.id] = {
              name: item.name,
              error: message,
              totalAttempts: (failed[item.id]?.totalAttempts || 0) + 1,
              at: new Date().toISOString(),
            };
            state.failed = failed;
            state.last = { id: item.id, name: item.name, status: "download-failed", error: message, at: new Date().toISOString() };
            await saveState(state);
          })
          .finally(() => pendingDownloads.delete(download));
        pendingDownloads.add(download);
        if (pendingDownloads.size >= 8) await Promise.race(pendingDownloads);
        success = true;
      } catch (error) {
        lastError = String(error?.message || error);
        failed[item.id] = {
          name: item.name,
          error: lastError,
          totalAttempts: (failed[item.id]?.totalAttempts || 0) + 1,
          at: new Date().toISOString(),
        };
        state.failed = failed;
        state.last = { id: item.id, name: item.name, status: "retry", error: lastError, at: new Date().toISOString() };
        await saveState(state);
        if (attempt < 3) {
          prepared.set(index, prepareProduct(item, characterID, authorization));
          await new Promise((resolve) => setTimeout(resolve, attempt * 500));
        }
      }
    }
    if (!success) state.last = { id: item.id, name: item.name, status: "deferred", error: lastError, at: new Date().toISOString() };
  }
  await Promise.all(pendingDownloads);
  return { completed: completed.size, total: catalog.length, failed: Object.keys(failed).length, batch: queue.length, last: state.last };
}
