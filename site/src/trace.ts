import { scaleLinear } from "d3-scale";
import { line } from "d3-shape";
import type { Run } from "./data";

const W = 1000, H = 200, MID = 100, PAD = 28;

// Deterministic noise: the same data always draws the same trace.
function rng(seed: string) {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) { h = Math.imul(h ^ seed.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
  return () => { h = Math.imul(h ^ (h >>> 16), 2246822507); h = Math.imul(h ^ (h >>> 13), 3266489909); h ^= h >>> 16; return (h >>> 0) / 4294967296; };
}

const niceStep = (span: number) => [5, 10, 30, 60, 120, 300, 600, 1200].find((s) => span / s <= 8) ?? 1800;
const fmtT = (s: number) => (s === 0 ? "T0" : `${s > 0 ? "+" : "-"}${Math.abs(s) >= 120 ? `${Math.round(Math.abs(s) / 60)}m` : `${Math.abs(s)}s`}`);

export function traceSvg(r: Run): string {
  const rto = Math.max(r.rto_seconds, 1);
  const pre = Math.max(rto * 0.3, 20), post = Math.max(rto * 0.22, 15);
  const x = scaleLinear().domain([-pre, rto + post]).range([PAD, W - PAD]);
  const rand = rng(r.drill + r.started_at);
  const noise = (amp: number) => MID + (rand() - 0.5) * 2 * amp;
  const ln = line<[number, number]>().x((p) => p[0]).y((p) => p[1]);
  const walk = (a: number, b: number, amp: number): [number, number][] => {
    const pts: [number, number][] = [];
    for (let px = x(a); px <= x(b); px += 5) pts.push([px, noise(amp)]);
    pts.push([x(b), MID]);
    return pts;
  };
  const x0 = x(0), x1 = x(rto);
  const pre_ = walk(-pre, 0, 7);
  // The fault: a violent excursion that decays into the flatline.
  const spike: [number, number][] = [[x0, MID]];
  for (let i = 1; i <= 9; i++) spike.push([x0 + i * 4, MID + (i % 2 ? -1 : 1) * (80 / i) * (0.6 + rand() * 0.4)]);
  spike.push([x0 + 40, MID]);
  const flat: [number, number][] = [[x0 + 40, MID], [x1, MID]];
  const post_ = walk(rto, rto + post, 7).map((p, i) => (i === 0 ? [x1, MID] : p) as [number, number]);

  const step = niceStep(rto + pre + post);
  let grid = "";
  for (let t = Math.ceil(-pre / step) * step; t <= rto + post; t += step) {
    grid += `<line x1="${x(t)}" x2="${x(t)}" y1="14" y2="${H - 24}" class="g"/><text x="${x(t)}" y="${H - 8}" class="tk" text-anchor="middle">${fmtT(t)}</text>`;
  }
  const label = `${r.drill}: fault at T0, recovered ${r.rto_seconds} seconds later${r.mode === "simulated" ? " (simulated)" : ""}.`;
  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${label}" class="trace" preserveAspectRatio="none">
  <g>${grid}</g>
  <line x1="${x0}" x2="${x0}" y1="6" y2="${H - 24}" class="fault-line"/>
  <path d="${ln(pre_)}" class="ln amber" data-ph="pre"/>
  <path d="${ln(spike)}" class="ln red" data-ph="spike"/>
  <path d="${ln(flat)}" class="ln red flat" data-ph="flat"/>
  <path d="${ln(post_)}" class="ln amber" data-ph="post"/>
  <g class="mk" data-ph="fault"><text x="${x0 + 6}" y="18" class="lab red-t">FAULT</text></g>
  <g class="mk" data-ph="rec"><line x1="${x1}" x2="${x1}" y1="6" y2="${H - 24}" class="rec-line"/><path d="M${x1 - 6} 10 L${x1} 2 L${x1 + 6} 10 Z" class="rec-mark"/><text x="${x1 - 6}" y="18" class="lab green-t" text-anchor="end">RECOVERED</text></g>
  <text x="${(x0 + 40 + x1) / 2}" y="${MID - 12}" class="lab red-t mk" data-ph="flat" text-anchor="middle">${x1 - x0 > 160 ? "fault active" : ""}</text>
</svg>`;
}

// Canary sequence as ticks. Rows that existed before the fault but are not in the restored database are a hole.
export function stripSvg(r: Run): string {
  const lost = Math.max(0, r.last_seq_before - r.first_seq_after);
  const pad = Math.max(Math.round(lost * 0.5), 40);
  const span = lost + 2 * pad, cells = 200, cw = W / cells;
  const holeFrom = pad / span * cells, holeTo = (pad + lost) / span * cells;
  let ticks = "";
  for (let i = 0; i < cells; i++) {
    if (lost > 0 && i >= Math.floor(holeFrom) && i < Math.ceil(holeTo)) continue;
    ticks += `<rect x="${(i * cw + 0.8).toFixed(1)}" y="8" width="${(cw - 2).toFixed(1)}" height="22"/>`;
  }
  const hole = lost > 0
    ? `<rect x="${holeFrom * cw}" y="4" width="${(holeTo - holeFrom) * cw}" height="30" class="hole"/><text x="${(holeFrom + holeTo) / 2 * cw}" y="52" text-anchor="middle" class="lab red-t">${lost.toLocaleString("en")} rows lost</text>`
    : `<text x="${W / 2}" y="52" text-anchor="middle" class="lab green-t">0 rows lost: the canary kept writing</text>`;
  const alt = lost > 0 ? `${lost} canary rows lost, about ${r.rpo_seconds} seconds of writes` : "no canary rows lost";
  return `<svg viewBox="0 0 ${W} 60" role="img" aria-label="Canary sequence strip: ${alt}" class="strip" preserveAspectRatio="none"><g class="ticks">${ticks}</g>${hole}</svg>`;
}
