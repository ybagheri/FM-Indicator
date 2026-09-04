# NON-REPAINTING — closed-bar discipline + confirmation delays (normative)

> Companion to `SYSTEMATIC_SPECIFICATION.md` (§9), `ARCHITECTURE.md` (§5),
> `TESTING.md` (§Coverage 9–12). Testable contract. No profitability claims.

## 1. Rules

1. Only bars `shift >= 1` (closed) feed swings / legs / states / scores.
   Bar 0 (forming) feeds NOTHING except an optional intrabar POTENTIAL
   preview when `InpUseIntrabarPotential=true` (default false) — never
   DEVELOPING / CONFIRMED, never alerts twice, never writes buffers.
2. Swing at `s` does not exist until bar `s+k` closes (`last_closed >= s+k`,
   `InpSwingK` default 3). `Swings.mqh` never exposes unconfirmed swings;
   internal pending buffer of size k.
3. Closed-bar freeze: once bar `b` closes, its OHLC and any state reached on
   `b` never change when later bars arrive. Backfill carries the honest
   confirmation delay (recompute from frozen closes yields identical swings
   and states).
4. Max one FM state transition per closed bar (prevents same-bar
   POTENTIAL→CONFIRMED jumps that would hide history).
5. DATA buffers (`Target/Potential/Developing/Confirmed`) are written only
   at the issuing closed-bar shift (shift 1 at event time) and never
   rewritten afterwards. `PLOT_DRAW_BEGIN` skips warmup.
6. Retrospective labels (measuring vs exhaustion gap disambiguation) appear
   only in DEBUG logs, never as live states.

## 2. Where the delay lives (documented, not hidden)

- Swing confirmation: k bars. Leg/projection: at `B0+k` close. CONFIRMED
  with `RequireFollowThrough`: exactly one closed bar later (delayed path).
- History therefore shows signals later than the extreme bar — by design.
  The indicator never rewrites history to "look perfect".

## 3. Implementation hooks

`CMarketData` (closed mapping `i>=1`, `IsNewBar` on `time[1]` change),
`CSwingDetector::Update(rates,…,1)`, `CFMEngine::Update(…,1,…)`,
`OnCalculate` full recompute on `prev_calculated==0`, incremental on new
closed bar only, tick-without-new-close = preview stub.

## 4. Tests (must keep passing)

- `test_fm.py`: swing absent before k bars; freeze (extension identical);
  follow-through delay (no same-bar confirm); edge (flat/zero-ATR/tiny).
- Per-layer freeze/no-look-ahead suites: `test_bar/state/breakout/reversal/
  setup/general/decision/pullback` (§freeze_safety). Static delimiter scan
  over all MQL5 files (balanced braces/parens) in CI place of MetaEditor.
- Human acceptance: MetaEditor compile + Strategy Tester visual run shows
  DEBUG bar/state/BO/MTR/plan/decision lines and `FM_DECISION` updating per
  closed bar with no rewritten history.
