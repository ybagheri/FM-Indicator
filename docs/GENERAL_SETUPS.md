# GENERAL SETUPS — systematic specification (Phase 7, normative)

> Companion to `BROOKS_CONCEPTS.md` (§2: signal→entry→entry; §5: pullbacks,
> doubles, MTR; §4: breakouts; §7: entry/stop/target/trader's equation),
> `PULLBACK_PATTERNS.md`, `BREAKOUT_ENGINE.md`, `REVERSAL_ENGINE.md`,
> `MARKET_STATE.md`, and `SETUP_ENGINE.md` (FM plans).
> Normative for the non-FM setup catalog: identical closed-bar input →
> identical setups (float tol 1e-9, ints/enums/bools exact). Read-only in
> Phase 7 (DEBUG log); Phase 8 consumes these setups for the decision gate.
> No profitability claims. Scores stay scores.

## 0. Conventions (same as prior layers)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed, older = larger shift).
  Python mirror: oldest-first indices (`0` = oldest).
- Only closed bars feed builders. `atr<=0` → no setup. Bar 0 never feeds.
- `CFMEngine` / `CConfirmation` / `CInverseMMHelper` are UNTOUCHED. This layer
  reads already-detected signals (`PullbackSignal`, `DoubleSignal`,
  `BreakoutSignal`, `ReversalSignal`) plus bar/EMA prices and publishes
  structured setups. It never writes buffers, objects, alerts, or states.
- Honesty records: (1) the pullback entry tick (`_Point` in
  `PullbackPatterns.mqh`) is execution detail; this layer models it as
  `TickProxy×ATR` (default 0.05, §1) so the Python mirror is exact.
  (2) Breakout/reversal objectives are `ObjMult×ATR` proxies (default 2.0,
  §1) — a fixed-measurement placeholder, not a structural magnet like the
  pullback window extreme or the double trough. Documented here, not hidden.

## 1. Inputs (new; all prior inputs unchanged and reused, not duplicated)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpEnableGeneralSetups` | bool | true | master switch; false = layer idle |
| `InpGeneralTickProxyATRMult` | double | 0.05 | pullback entry beyond extreme (×ATR; models the 1-tick stop order) |
| `InpGeneralObjectiveATRMult` | double | 2.0 | breakout/reversal objective distance (×ATR; measurement proxy) |

Validation: `0.0<=TickProxy<=0.5`, `0.5<=ObjMult<=5.0`; clamp + `Validate()` false.
Reused (one source of truth, not new knobs): `SetupStopBufATRMult`,
`SetupMinRR` (stop buffer + R flag), `DoubleTopTolATRMult` (double stop),
`RevRetestTolATRMult` (reversal stop), `MaxPullbackBars` window extremes.

## 2. Scope (which signals become setups)

- `TREND_PULLBACK` ← `PullbackSignal.found` (H1/H2 or L1/L2). `legs==2`
  firm, `legs==1` provisional (H1-alone risk — pullback may not be done).
- `DOUBLE` ← `DoubleSignal.found` (swing or micro). Swing firm, micro
  provisional (lower confidence by construction, per pullback spec §5).
- `BREAKOUT` ← `BreakoutSignal.found` with `FOLLOW_THROUGH` (firm) or
  `PENDING` (provisional — hovering inside the tol band). `FAILED` → no setup
  (thesis dead; the failure itself is Phase-8 veto input, not a setup).
- `REVERSAL` ← `ReversalSignal.found` (`MINOR` provisional, `MAJOR` firm).
- FM fades stay in `CSetupPlanner` (Phase 6); the Phase-7 hook logs them
  side-by-side and Phase 8 picks the max-score candidate (selection §6).

## 3. Setup math (per type; buy mirrors with high/low swapped)

```
buf      = SetupStopBufATRMult × atr
tick     = GeneralTickProxyATRMult × atr
objD     = GeneralObjectiveATRMult × atr
minRR    = clamp(SetupMinRR, 0.25, 5.0)

PULLBACK bull (trade dir +1; bear mirrors):
  entry     = H[sig] + tick
  stop      = pbStop − buf            (pbStop = pullback low from Detect)
  objective = winHigh                 (max H over the pullback window)
  reward    = objective − entry;  risk = entry − stop
  score     = legs==2 ? 70 : 40

DOUBLE top (trade dir −1; bottom mirrors):
  tol       = DoubleTopTolATRMult × atr
  entry     = price2                  (most-recent extreme)
  stop      = max(p1,p2) + tol + buf
  objective = trough                  (caller-supplied separation extreme)
  reward    = entry − objective;  risk = stop − entry
  score     = micro ? 30 : 60
  (bottom: stop = min(p1,p2) − tol − buf; reward = objective − entry;
   risk = entry − stop)

BREAKOUT (dir = bo.dir; closeB = close at analysis bar b):
  entry     = closeB
  stop      = ref ∓ buf               (bull: ref − buf; bear: ref + buf)
  objective = entry ± objD            (bull +, bear −)
  reward    = |objective − entry| (= objD); risk = |entry − stop|
  score     = (FOLLOW ? 70 : 40) − (trapArmed ? 20 : 0), floor 0

REVERSAL (dir = rv.dir; emaB = EMA20 at b):
  tolR      = RevRetestTolATRMult × atr
  entry     = closeB
  stop      = emaB − dir×(tolR + buf) (bull: below EMA; bear: above)
  objective = entry + dir×objD
  reward    = dir×(objective − entry) (= objD); risk = dir×(entry − stop)
  score     = MAJOR ? 80 : 40

valid  = EnableGeneral AND atr > 0 AND reward > 0 AND risk > 0
rMult  = reward / risk
rrOK   = rMult + 1e-9 >= minRR   (report-only flag; veto is Phase 8)
```

Rationale (concepts §7): stops sit beyond structure + buffer (pullback low,
double level + tol, breakout ref, EMA); objectives are the nearest structural
magnet where one exists (window extreme, trough) and the documented ATR proxy
where none does (breakout/reversal). `rrOK` annotates the trader's-equation
input; nothing is vetoed in this layer.

## 4. Output struct (`GeneralSetups.mqh`)

```
GeneralSetup {valid, type(ENUM_SETUP_TYPE), dir(±1), entry, stop, objective,
  riskPts, rewardPts, rMult, rrOK, provisional, signalBar, refPrice, score(0..100)}
```

`type` is one of `TREND_PULLBACK / DOUBLE / BREAKOUT / REVERSAL` from the
builders below, plus `FM_FADE` for a Phase-6 FM plan converted by the hook
for the Phase-8 contest (§5; conversion copies entry/stop/objective/R/rrOK
from the `SetupPlan` and scores it with `ScoreSignal`).

`riskPts/rewardPts` are plain price differences. `refPrice` = structural
reference (signal extreme / double level / BO ref / EMA). `score` is a fixed
unit-weight confidence proxy per §3 (never a probability).

## 5. Selection (hook-side; deterministic)

Candidates = up to 4 valid general setups + optional FM plan at the same bar.
Winner = max `score`; ties among general setups broken by fixed type order
`TREND_PULLBACK < DOUBLE < BREAKOUT < REVERSAL` (lowest enum wins), then
lowest `signalBar` (most recent). The FM plan joins with its `ScoreSignal`
(display score, SPEC §8) and displaces the general best only on a strictly
greater score (ties keep the general setup); the winner is converted to a
`GeneralSetup` with `type=FM_FADE` for the Phase-8 gate. Selection is hook
code + a tested mirror helper (`select_best` for the general contest); builders stay pure.

## 6. No-look-ahead / repaint contract (extends prior layers)

1. All prices are closed bars (`sh>=1`); bar 0 never feeds a builder.
2. Pure/stateless builders: `(signal, prices, atr, cfg)` → setup. Extending
   history with newer bars never changes an old setup (tested).
3. No buffers, alerts, objects, or projections from this layer.

## 7. Python mirror + tests

- Mirror: `tests/general_setups.py` — `GeneralCfg(...)`,
  `build_pullback/build_double/build_breakout/build_reversal`,
  `select_best`, oldest-first indexing.
- Suites (`tests/test_general.py`, 10): pullback H2 firm geometry; H1
  provisional + tick/buf math; double swing-top geometry + micro provisional;
  double-bottom mirror; breakout FOLLOW firm + trap penalty; breakout PENDING
  provisional + FAILED silent; reversal MAJOR firm + MINOR provisional; rrOK
  threshold + invalid reward/risk; selection max-score + tie order +
  disabled/zero-ATR safety; determinism + freeze (history extension leaves old
  setup untouched).
