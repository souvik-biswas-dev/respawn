export interface Step { name: string; seconds: number }
export interface Run {
  drill: string; mode: "real" | "simulated"; label?: string;
  started_at: string; fault_injected_at: string; recovered_at: string;
  rto_seconds: number; last_seq_before: number; first_seq_after: number; rpo_seconds: number;
  alerts_fired: string[]; steps: Step[]; notes: string; environment: Record<string, string>;
}
export interface Index { source: "results" | "sample"; generated_at: string; files: Record<string, string> }
export interface Data { index: Index; runs: Run[]; simulated: boolean }

export const ORDER = ["kill-node", "fill-disk", "delete-server"];

export async function load(): Promise<Data> {
  const index: Index = await (await fetch("data/index.json")).json();
  const runs = await Promise.all(Object.values(index.files).map(async (f) => (await fetch(`data/${f}`)).json() as Promise<Run>));
  runs.sort((a, b) => ORDER.indexOf(a.drill) - ORDER.indexOf(b.drill));
  // Samples are never measurements, whatever a file claims.
  const simulated = index.source === "sample" || runs.some((r) => r.mode === "simulated");
  return { index, runs, simulated };
}
