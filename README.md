# FM-Indicator — Fading Measured Moves (Al Brooks Price Action) for MT5

Systematic, configurable, testable MQL5 indicator (v1.30) that projects
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
3. Open MetaEditor, compile `FM_Indicator.mq5` (F7), attach to chart.
4. No DLLs, no dependencies beyond the standard library.

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

- v1.2 families + v2 tooling are implemented and mirror-tested (19 Python
  tests), but live statistical validation is still pending — see roadmap
  before any live use.
- Context (Trend/Range/Transition) defaults to LOG_ONLY — it annotates, never
  vetoes, faithful to Brooks "context, not trigger". MTF overlay is likewise
  read-only.
- Compile in MetaEditor on Windows; this Linux env validates logic via the
  Python mirror (`tests/`), not `metaeditor.exe`.

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
`docs/ARCHITECTURE.md` · `docs/TESTING.md` · `docs/FUTURE_ROADMAP.md`

## Self-critique (v1)

Honest proxies, not "official Brooks rules"; thresholds are ATR-normalized but
still ours. Inverse-MM target anchoring is the weakest point (failure-low
minus leg range) — flagged for walk-forward review. No statistical validation
yet — see roadmap before any live use.
