// Copies drill results into public/data and writes index.json. Real results win; with none at all
// the committed sample-*.json (always SIMULATED) are used and index.json says source "sample".
import fs from "node:fs";
import path from "node:path";

const here = import.meta.dirname;
const results = path.resolve(here, "../../drills/results");
const out = path.resolve(here, "../public/data");
const DRILLS = ["kill-node", "fill-disk", "delete-server"];
const files = fs.existsSync(results) ? fs.readdirSync(results).filter((f) => f.endsWith(".json")) : [];
const read = (f) => JSON.parse(fs.readFileSync(path.join(results, f), "utf8"));

let pick = {};
let source = "results";
if (files.includes("summary.json")) {
  for (const [d, e] of Object.entries(read("summary.json").drills ?? {})) pick[d] = e.file;
} else {
  const best = {};
  for (const f of files.filter((f) => !f.startsWith("sample-"))) {
    const r = read(f);
    const rank = (r.mode === "real" ? "1" : "0") + r.started_at;
    if (!best[r.drill] || rank > best[r.drill].rank) best[r.drill] = { rank, f };
  }
  for (const [d, b] of Object.entries(best)) pick[d] = b.f;
}
if (Object.keys(pick).length === 0) {
  source = "sample";
  for (const d of DRILLS) if (files.includes(`sample-${d}.json`)) pick[d] = `sample-${d}.json`;
}
if (Object.keys(pick).length === 0) {
  console.error("no drill results and no samples in drills/results");
  process.exit(1);
}
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
for (const f of Object.values(pick)) fs.copyFileSync(path.join(results, f), path.join(out, f));
fs.writeFileSync(path.join(out, "index.json"), JSON.stringify({ source, generated_at: new Date().toISOString(), files: pick }, null, 2));
console.log(`data: ${source}, ${Object.keys(pick).length} run(s)`);
