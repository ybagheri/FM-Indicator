# FM Indicator Reference (parity build, Phases 1–6)

## 1. What the indicator is now

A non-trading visualization and decision mirror of `FM_EA.mq5`. Both programs
consume the same `CFMAnalysis` pipeline and the same `CStrategyRegistry`
selection (`CParityBuilder`), so for identical symbol, timeframe, history,
closed bar, and inputs they reach the same analytical decision. The indicator
never places orders (no execution imports; `CHECK`: it includes
`TradeIntent.mqh` only for the closed-bar intent *projection*).

## 2. Inputs

### 2.1 Analysis inputs (shared, verbatim)

All `InpSwingK … InpLogLevel` come from `MQL5/Include/FM/Inputs.mqh`, the single
source also included by the EA (`FM_ApplyInputs`). Names, order, and Balanced
defaults are identical; `.set` presets bind by name and load in both programs.
See `docs/SYSTEMATIC_SPECIFICATION.md` §1 for the full table.

### 2.2 Parity selection inputs (mirror of `FM_EA.mq5`, identical defaults)

| Indicator input | EA source | Default | Effect |
|---|---|---|---|
| `InpStratMode` | `FM_EA.mq5:27` | `STRAT_MODE_AUTO` | SINGLE / MULTI / AUTO |
| `InpSingleStrategy` | `:28` | `STRAT_FM_FADE` | strategy used in SINGLE |
| `InpUseFM/Pullback/Breakout/Reversal/Double/FailedBO` | `:29-34` | all `true` | enable mask (MULTI/AUTO) |
| `InpAutoTrendBonus/ProvPenalty/RRBonus/RRLevel` | `:63-66` | `10/5/5/2.0` | AUTO final-score tuning |
| `InpApplyStructuralVeto` | `:71` | `true` | `false` counts vetoes but proceeds (EXP-0002 apparatus) |
| `InpTradeProvisional` | `:59` | `false` | provisional setups need `true` to project WOULD_ |
| `InpChaseATRMult` | `:61` | `0.50` | chase guard twin of `InpMaxLateEntryATRMult` |
| `InpRiskMinRR` | `InpRiskMinRR :48` | `1.0`, `0`=off | LOW_RR projection (strict `<`, verbatim `Check`) |
| `InpMaxHoldBars` | `:60` | `5` | carried in the projected intent record |

Defined in `FM_Indicator.mq5` (NOT in shared `Inputs.mqh` — the EA already
defines them there; duplicating would break the EA build).

### 2.3 Visualization / diagnostic inputs

| Input | Default | Effect |
|---|---|---|
| `InpShowParityLabel` | `true` | `FM_PARITY` detail label (decision/veto/intent, WAIT-visible) |
| `InpShowParityLevels` | `false` | `FM_P_ENTRY/STOP/TP` lines at the selected candidate's levels |
| `InpDiagnosticMode` | `false` | verbose per-bar `DIAG` dashboard at `LOG_DEBUG` |
| `InpShowScore/Legs/Pullbacks/Targets/Zones`, alerts, `InpLogLevel` | — | unchanged (shared analysis inputs) |

## 3. Chart objects

- FM states (unchanged): `FM_<id>_LEG/PB/TGT/ZONE/LABEL/ARROW`, colors by state
  (gray/silver/dashed target; blue POTENTIAL, orange DEVELOPING, lime CONFIRMED),
  fade direction in labels, arrows on DEVELOPING/CONFIRMED signal bars.
- `FM_DECISION` (final signal, current closed bar, top-right anchored):
  `BUY R=2.10 AUTO PULLBACK f=94` (lime), `SELL …` (red),
  `NO_TRADE DECISION_VETO_CONFLICT AUTO BREAKOUT` /
  `NO_TRADE SKIP_LATE_ENTRY SINGLE FM_FADE` /
  `NO_TRADE NO_SETUP MULTI NONE` (gray).
  This is the EA-mirror outcome: BUY/SELL = the EA would log `WOULD_*`;
  NO_TRADE + reason = veto / risk / intent gate (or no candidate).
- `FM_PARITY` (detail, at bar low, toggle `InpShowParityLabel`):
  `DEC WAIT LOW_SCORE | VETO - | INTENT WOULD_BUY` — exposes the Phase-8
  decision (`DEC …`, WAIT-visible here), the veto, and the intent projection.
- `FM_P_ENTRY` (aqua dash), `FM_P_STOP` (red dash), `FM_P_TP` (lime dash):
  selected candidate's levels while a BUY/SELL projection exists and
  `InpShowParityLevels=true`; deleted otherwise (never stale).
- All `FM_*` objects are deleted on deinit (`Visualizer::DeleteAll`).

## 4. Buffers (unchanged, EA-readable)

`0 Target`, `1 Potential`, `2 Developing`, `3 Confirmed` (`DRAW_ARROW`, frozen
at the issuing closed bar), `4–5` ATR/swing calculation buffers.
Appending indicator buffers was deliberately avoided: parity state travels via
`FMAnalysisResult`/`FMParityDecision` includes and DEBUG/CSV diagnostics.

## 5. Diagnostic mode

Set `InpLogLevel=LOG_DEBUG` + `InpDiagnosticMode=true`. Per closed bar the log
carries, in order: phase DEBUG lines (pre-existing), `REGISTRY cands=N:
STRAT/score[P]…` (candidate universe incl. FAILED_BO), `PARITY final=… dec=…/…
veto=… intent=…`, and the `DIAG …` dashboard (mode/single, full candidate table
with direction/score/R/PROV/OFF flags, selection + AUTO final, decision, veto +
applied flag, intent, final). Compare against the EA's `[FM_EA] … WOULD_…` and
`EXPLAIN …` lines bar-by-bar.

## 6. Signal meanings

- `BUY` / `SELL`: selection survived veto, risk-RR projection, and intent gates
  at the closed-bar close — the EA logs `WOULD_BUY/SELL` for the same bar
  (live-tick chase/side evaluation at Ask/Bid can still SKIP; see §7).
- `NO_TRADE DECISION_VETO_*`: context-level veto (barbwire/mid-range/conflict/
  no-edge/trap-repeat), same trigger the EA applies in all modes.
- `NO_TRADE SKIP_LOW_RR / SKIP_PROVISIONAL_OFF / SKIP_LATE_ENTRY /
  SKIP_WRONG_SIDE`: risk/intent projection rejected the selection.
- `NO_TRADE NO_SETUP`: no enabled+valid candidate under the current mode.
- `WAIT` never appears in `FM_DECISION` by design (the EA does not gate on
  WAIT reasons — a LOW_SCORE selection still yields `WOULD_*`); WAIT states
  remain visible in `FM_PARITY` (`DEC WAIT …`) and the DEBUG log.

## 7. Known limitations (parity-relevant)

1. Intent gates are projected at the closed-bar close (`res.dctx.close`); the EA
   evaluates them at next-tick Ask/Bid. `LATE_ENTRY`/`WRONG_SIDE` can therefore
   differ on fast bars — expected, not a bug.
2. Risk gates beyond LOW_RR (spread, daily loss, trades/day, open caps, volume)
   and SafetyManager halts/sessions/modes are EA-only (account/live state) and
   are not projected; both programs document the same exclusion list.
3. `RiskManager::Check` LOW_RR is strict `<` while setup `rrOK` carries `+1e-9`:
   the band `[minRR-1e-9, minRR)` is `rrOK=true` yet risk-rejected. Mirrored
   exactly, not "fixed" (spec §20: no EA behavior changes).
4. No per-historical-bar parity visualization; history analysis uses the DEBUG
   log and (Phase 7) the parity CSV/test harness.
5. MT5 compile/Strategy Tester runs require MetaEditor/terminal on Windows
   (see `docs/BACKTESTING_GUIDE.md`); this environment validates via the Python
   mirrors plus static structural checks.
