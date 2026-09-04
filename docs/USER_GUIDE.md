# USER GUIDE — install, read the chart, alerts, presets, EA use

> Practical companion to `CONFIGURATION.md`, `NON_REPAINTING.md`,
> `LIMITATIONS.md`. No profitability claims.

## 1. Install (MT5, Windows)

1. Copy `MQL5/Indicators/FM_Indicator.mq5` → terminal data folder
   `MQL5/Indicators/` (Find it: MT5 → File → Open Data Folder).
2. Copy `MQL5/Include/FM/*.mqh` (20 files) → `MQL5/Include/FM/`.
3. MetaEditor → open `FM_Indicator.mq5` → Compile (F7). Expect
   `0 errors, 0 warnings`.
4. Attach to a chart. No DLLs, no dependencies beyond the standard library.
5. Optional: load a preset (`Presets/*.set`) via indicator Inputs → Load.

## 2. Reading the chart

- Gray trend = Leg1 (A0→A1), silver = pullback (A1→B0), dashed H-line = target.
- Blue POTENTIAL (approaching) → orange DEVELOPING (touch + exhaustion) →
  lime CONFIRMED (reversal bar). Label: `[FAM] STATE SIDE #id T=target S=score`.
  - `FAM`: none = regular, `INV`/`RNG`/`CH`/`GAP`.
  - `SIDE`: `SELL` = fade a bull MM (short), `BUY` = fade a bear MM (long).
  - Arrows (red/green) mark DEVELOPING/CONFIRMED signal bars.
- `FM_DECISION` label: Phase-8 read-only verdict
  (`BUY/SELL/WAIT/NO_TRADE` + machine reason) — interpretation, never an order.
- Toggles: `InpShowLegs/Pullbacks/Targets/Zones`. Objects `FM_<id>_*`
  auto-delete on invalidation/expiry/symbol-timeframe change.
- Per-bar tags (B1/B2/PB/BO/FT/…) live in the Experts log at DEBUG level
  (`InpLogLevel=DEBUG`), not as chart clutter — by design (readability).

## 3. Alerts

Per-state enables (`InpAlertPotential/Developing/Confirmed`) + popup / sound /
push / email, once per `(setup id, state)`, 60s throttle (CONFIRMED exempt).
No per-tick repeats. Set `InpLogLevel=DEBUG` to also see bar/state/BO/MTR/
plan/decision lines in the Experts log.

## 4. Presets (see `CONFIGURATION.md` §2)

Balanced (default) → Conservative (stricter) / Aggressive (looser) /
M1-Scalp (noisy M1) / Line-Chart (close-only) / Families (research).

## 5. EA / research use (execution-free indicator)

- Buffers `Target/Potential/Developing/Confirmed` (frozen after close), or
  `#include <FM/FMEngine.mqh>` → `CFMEngine::ActiveSnapshots()`.
- v2: `InpExportCSV` writes one row per CONFIRMED for walk-forward review
  (`backtest_run` + MAE/MFE in `tests/fm_engine.py`).
- The indicator never trades. A future EA lives in a separate repo.

## 6. FAQ

- Repaint? No — see `NON_REPAINTING.md`. History shows honest confirmation delay.
- Why no BUY/SELL arrows everywhere? A direction needs context + location +
  setup + signal + RR + invalidation (Phase 8). Otherwise WAIT/NO_TRADE
  with a reason — that IS the answer.
- Live use? Not before `VALIDATION.md` §2 (tester run + walk-forward review).
