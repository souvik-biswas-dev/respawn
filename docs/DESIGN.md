# Design: Respawn Console

The console is a static site that shows drill results. It must feel like a **flight recorder / black box**, not a SaaS template.

## Concept
After a crash, investigators read the black box. Respawn's console is that readout: a dark instrument panel where each drill is a recorded trace of a failure and recovery. The story is the timeline: normal, fault, outage, recovery.

## Banned (this is what makes sites look AI-generated)
- Purple/blue gradient backgrounds, glassmorphism, glowing orbs
- Three-column feature card grids with emoji icons
- Inter/Roboto as the only font, centered hero with two buttons
- Generic "Get started" CTAs, lorem ipsum, stock illustrations
- Rounded-everything with soft drop shadows

## Visual system
| Token | Value |
|---|---|
| Background | `#0B0C0A` (warm near-black) |
| Surface | `#12140F`, 1px hairline borders `#2A2D24` |
| Primary ink | `#E9E6D8` (bone) |
| Signal amber | `#FFB000` (phosphor; used for traces and the one accent) |
| Fault red | `#FF3B2F` (only for the fault/outage segment) |
| Recovered green | `#7CFFB2` (only for the recovered state) |
| Radius | 0-2px. Sharp. |
| Texture | subtle scanlines + film grain via CSS, very low opacity |

Typography (self-host via Fontsource, no Google CDN):
- Display: **Instrument Serif** (large numbers and headings, italic for emphasis)
- Data/UI: **JetBrains Mono** or **IBM Plex Mono**
- Never more than these two families.

## Libraries (pick these, keep the bundle small)
- **D3** (d3-scale, d3-shape, d3-axis only) for the traces
- **GSAP** (core + ScrollTrigger) for the scroll-driven replay
- **Vite** + vanilla TS, no UI framework needed
- Optional: **Lenis** for smooth scroll if it does not hurt accessibility

## Signature elements
1. **The Trace.** Each drill is a horizontal seismograph-style line: flat amber (healthy), spike and drop in red (fault), a flatline gap (outage) with the RTO as a large serif number above it, then amber resumes. Scrolling replays the trace being drawn.
2. **The RPO gap.** Canary sequence numbers shown as a dense tick strip; the missing ticks after recovery are rendered as a visible hole with the lost count labelled.
3. **Recorder header.** A fake-but-honest "REC" indicator with the date of the latest run and its `mode`. If any data is simulated, a persistent amber banner reads `SIMULATED DATA`, always visible.
4. **Rebuild ledger.** The delete-server drill steps (terraform apply, ansible, argocd sync, restore) as a timestamped log with durations, like a flight data log.
5. **Alert strip.** Which alerts fired during each drill, as small monospace tags.

## Layout
Single page, vertical story:
1. Header strip (REC, latest run time, mode)
2. Headline: big serif RTO of the headline drill, one sentence of context
3. The three traces, stacked, scroll-replayed
4. Rebuild ledger
5. How to reproduce (3 commands, copyable)
6. Footer with repo link

## Data
Reads `drills/results/summary.json` and per-run JSON, copied into `site/public/data/` at build time. If none exist, show the committed **sample** data and the SIMULATED banner. Never present sample data as measured.

## Accessibility and performance
- Contrast AA on all text; red/green never the only signal (add labels and shapes)
- `prefers-reduced-motion`: skip the replay and show final traces
- Works at 360px wide; traces become scrollable horizontally with a visible hint
- Lighthouse performance 90+, total JS under 150 KB gzip
- Keyboard focusable, visible focus ring in amber

## Quality check before done
Open it and ask: would someone guess an AI made this in 10 seconds? If the answer is yes, revise typography, spacing and the trace before finishing.
