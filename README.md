# FM-Indicator — Fading Measured Moves (Al Brooks Price Action) for MT5

Systematic, configurable, testable MQL5 indicator + Expert Advisor sharing one
decision engine. The indicator (`MQL5/Indicators/FM_Indicator.mq5`) is a
non-trading visualization and decision mirror of the EA
(`MQL5/Experts/FM_EA.mq5`): same analysis, same strategy registry
(FM_FADE, PULLBACK, BREAKOUT, REVERSAL_MTR, DOUBLE, FAILED_BO), same
SINGLE/MULTI/AUTO selection, same structural veto, same risk/intent gating —
see `docs/INDICATOR_EA_PARITY_AUDIT.md` and `docs/INDICATOR_REFERENCE.md`.
The indicator core projects
**Leg1=Leg2 (AB=CD)** measured moves plus three v1.2 families — **range-height
breakout**, **shallow-pullback channel**, **measuring gap** — plus optional
**failed-breakout inverse-MM**, and detects **Fading Measured Move** setups as
an explicit state machine:

`PROJECTED → POTENTIAL → DEVELOPING → CONFIRMED → COMPLETED`, with
`→ INVALIDATED` from any state. No profitability claims.

## Theory in 30 seconds

- **Measured move (Brooks glossary):** a leg "about equal in size to something
  earlier in the trend". We operationalize as `Target = B0 ± |A1−A0|`.
- **Fade (Brooks glossary):** trading opposite the trend (e.g. selling a bull
  breakout you expect to fail). We fade only the *target zone*, never the trend.
- **Touch ≠ fade:** tests "overshoot or undershoot" (Brooks). Touch alone gives
  DEVELOPING at most; CONFIRMED needs an objective reversal bar (+ optional
  follow-through). The 2nd-leg trap (Brooks 2016 webinar) is why exhaustion is
  required before DEVELOPING.
- Everything discretionary is an `Inp*` input; see `docs/RESEARCH.md` (what
  Brooks says vs. our proxies) and `docs/SYSTEMATIC_SPECIFICATION.md` (exact math).

## Install

1. Copy `MQL5/Indicators/FM_Indicator.mq5` → terminal `MQL5/Indicators/`.
2. Copy `MQL5/Include/FM/*.mqh` → terminal `MQL5/Include/FM/`.
3. For the EA: copy `MQL5/Experts/FM_EA.mq5` → terminal `MQL5/Experts/`
   (same `Include/FM/` tree; needs no other files).
4. Open MetaEditor, compile `FM_Indicator.mq5` and `FM_EA.mq5` (F7).
5. No DLLs, no dependencies beyond the standard library.
6. Presets in `Presets/` bind inputs by name and load in both programs
   (EA-only names are ignored by older indicator builds; new parity inputs
   fall back to EA-identical defaults when absent from a `.set` file).

## Parameters (Balanced defaults; see SPEC §1)

Detection: `InpSwingK=3`, `InpMinLegATRMult=1.0`, `InpMinLegBars=3`,
`InpMaxLegBars=100`, pullback `0.15–0.90` / `50` bars. FM: approach `1.0×ATR`,
tolerance `0.25×ATR`, overshoot `0.50×ATR`. Signal bar: close in extreme 50%,
body ≥30%, adverse wick ≤60%, engulf/follow-through optional
(follow-through = 1-bar delayed confirm). Exhaustion v1.2: `InpMinPushes=3` +
wedge toggle. Score v1.2: display-only `S=0..100` in labels.
Phase-1 bar engine (read-only): per-closed-bar features
(doji/big/small/strong-close/inside/outside/ii/gap/overlap/runs/pressure/barbwire)
logged at DEBUG, never gating signals — see `docs/BAR_BY_BAR_ENGINE.md`.
Phase-2 pullback layer (read-only): EMA-gated H1/H2/L1/L2 + swing/micro
doubles logged at DEBUG, never gating signals — see `docs/PULLBACK_PATTERNS.md`.
Phase-3 market-state engine (read-only): TREND/CHANNEL/RANGE/BREAKOUT_MODE
scores (unit weights, pcts sum 100) logged at DEBUG, never gating signals —
see `docs/MARKET_STATE.md`.
Phase-4 breakout engine (read-only): N-bar/swing BO events with
PENDING→FOLLOW/FAILED lifecycle + second-leg trap flag, DEBUG-logged when
found, never gating signals — see `docs/BREAKOUT_ENGINE.md`.
Phase-5 reversal engine (read-only): per-bar exhaustion breadth
(climax/stall/pushes/wedge/overshoot) + pullback leg counting + EMA-cross
MTR proxy (MINOR/MAJOR, unit weights), DEBUG-logged when found, never
gating signals — see `docs/REVERSAL_ENGINE.md`.
Phase-6 setup plans (read-only): per DEVELOPING/CONFIRMED setup entry /
stop / objective / R + invalidation price, DEBUG-logged when valid, never
gating signals — see `docs/SETUP_ENGINE.md`.
Phase-7 general setups (read-only): pullback (H2 firm / H1 provisional) +
swing/micro doubles + breakout FOLLOW/PENDING + MTR MAJOR/MINOR catalog with
entry/stop/objective/R/score + best-candidate contest (FM included),
DEBUG-logged when valid, never gating signals — see `docs/GENERAL_SETUPS.md`.
Phase-8 decision engine (read-only): BUY/SELL/WAIT/NO_TRADE with
machine-checkable reasons (barbwire / mid-range / conflict / no-edge /
low-score / low-RR / late / trap-repeat), DEBUG-logged + single
`FM_DECISION` chart label, never gating signals — see
`docs/DECISION_ENGINE.md`.
**Price mode** `InpPriceMode`: `High/Low` (candles, default) or `Close`
(line chart — swings/legs/targets/distances on closes, like mobile
line-chart MM analysis). Families v1.2 (default OFF): `InpEnableRangeMM` /
`RangeLookback=50`, `InpEnableChannelMM` (depth 0.02–0.15 only),
`InpEnableGapMM` / `MinGapATRMult=1.0`. v2 research: `InpMTFTrendTFMinutes`
(read-only bias, 0=off), `InpLTFMinutes` (read-only LTF confirm, 0=off),
`InpExportCSV`/`InpCSVFile`. Presets:
**Conservative**, **Balanced**, **Aggressive**, **M1-Scalp**, **Line-Chart**,
**Families** (all MM families ON). Full table in SPEC §1.

## Chart reading

- Gray trend = Leg1 (A0→A1), silver = pullback (A1→B0), dashed H-line = target.
- Blue = POTENTIAL (approaching), orange = DEVELOPING (touch + exhaustion),
  lime = CONFIRMED (reversal bar). Label shows `#id + target`.
- Labels now carry explicit fade direction: `SELL` = fade a bull MM (short),
  `BUY` = fade a bear MM (long); DEVELOPING/CONFIRMED also draw a red/green
  arrow at the signal bar. Close targets stagger vertically so they stay readable.
  Family prefix: `INV`/`RNG`/`CH`/`GAP` (regular = none); `S=0..100` score when
  `InpShowScore` (display only, never trades).
- Presets in `Presets/`: Balanced, Conservative, Aggressive, **M1-Scalp**
  (for noisy M1 like EURUSD), **Families** (v1.2 all-families research).
  Load via indicator Inputs → Load.
- Toggles: `InpShowLegs/Pullbacks/Targets/Zones`. Objects named `FM_<id>_*`,
  auto-deleted on invalidation/expiry/symbol-timeframe change.
- EA use: DATA buffers `Target/Potential/Developing/Confirmed` (frozen after
  close) or `#include <FM/FMEngine.mqh>` → `CFMEngine::ActiveSnapshots()`.
  v2 research: CSV export per CONFIRMED + Python `backtest_run`/MAE/MFE.

## Real-time / repaint contract

- Closed bars (`shift≥1`) only. Swing `s` exists only after `s+k` closes.
- Max one state transition per closed bar; history never rewritten
  (backfill shows the honest confirmation delay).
- Bar 0 can only raise an intrabar POTENTIAL preview when
  `InpUseIntrabarPotential=true` (default false); never DEVELOPING/CONFIRMED.
- Retrospective measuring/exhaustion-gap labels exist only in DEBUG logs.

## Alerts

Per-state enables + popup/sound/push/email, once per `(setup id, state)`,
throttled (60 s cooldown except CONFIRMED). No per-tick repeats.

## Limitations

- All engines (v1 core, v1.1 fixes, v1.2 families, v2 tooling, bar-by-bar
  Phases 1–8, LTF confirm) are implemented and mirror-tested (97 Python
  tests, all pass), but live statistical validation is still pending — see
  roadmap before any live use.
- Context (Trend/Range/Transition) defaults to LOG_ONLY — it annotates, never
  vetoes, faithful to Brooks "context, not trigger". MTF/LTF overlays and the
  Phase-8 decision engine are likewise read-only: BUY/SELL are interpretation
  labels, never orders; nothing here gates the FM state machine.
- Compile in MetaEditor on Windows; this Linux env validates logic via the
  Python mirror (`tests/`), not `metaeditor.exe`.

## Status / next steps

EA/Indicator parity build (Phases 0–8, see `docs/CHANGELOG.md`): one shared
analysis + registry + veto/intent pipeline consumed by both programs; the
indicator's `FM_DECISION` label shows the EA-mirror final signal
(`BUY`/`SELL` = the EA logs `WOULD_*`, `NO_TRADE` + reason otherwise) and
`FM_PARITY` shows decision/veto/intent detail. What remains is live validation
in order — see `docs/FUTURE_ROADMAP.md` § "Next moves (ordered)": MetaEditor
compile + Strategy Tester visual run → EA↔Indicator parity comparison run
(`docs/EA_INDICATOR_PARITY_TESTING.md` Workflow B) → walk-forward review from
exported CSVs. No profitability claims; see roadmap before any live use.

## Docs

`docs/RESEARCH.md` · `docs/BROOKS_CONCEPTS.md` ·
`docs/BAR_BY_BAR_ENGINE.md` · `docs/PULLBACK_PATTERNS.md` ·
`docs/MARKET_STATE.md` ·
`docs/BREAKOUT_ENGINE.md` ·
`docs/REVERSAL_ENGINE.md` ·
`docs/SETUP_ENGINE.md` ·
`docs/GENERAL_SETUPS.md` ·
`docs/DECISION_ENGINE.md` ·
`docs/MARKET_CONTEXT.md` ·
`docs/SYSTEMATIC_SPECIFICATION.md` ·
`docs/ARCHITECTURE.md` · `docs/TESTING.md` · `docs/VALIDATION.md` ·
`docs/LIMITATIONS.md` · `docs/CONFIGURATION.md` · `docs/USER_GUIDE.md` ·
`docs/ROADMAP.md` · `docs/FUTURE_ROADMAP.md` · `docs/FM_ENGINE.md` ·
`docs/SIGNAL_SCORING.md` · `docs/NON_REPAINTING.md` ·
`docs/INDICATOR_EA_PARITY_AUDIT.md` · `docs/INDICATOR_REFERENCE.md` ·
`docs/EA_INDICATOR_PARITY_TESTING.md` · `docs/CHANGELOG.md`

## Self-critique

Honest proxies, not "official Brooks rules"; thresholds are ATR-normalized but
still ours. Inverse-MM target anchoring is the weakest point (symmetric
far-side anchor since v1.1) — flagged for walk-forward review. Breakout and
reversal objectives are fixed `2.0×ATR` measurement proxies, not structural
magnets (documented in `docs/GENERAL_SETUPS.md` §0). No statistical validation
yet — see roadmap before any live use.
