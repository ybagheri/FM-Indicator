# BREAKOUT ENGINE — systematic specification (Phase 4, normative)

> Companion to `BROOKS_CONCEPTS.md` (§4) and `MARKET_STATE.md` (BREAKOUT_MODE
> score). Normative for the breakout/trap layer: identical closed-bar input →
> identical signals (float tol 1e-9, enums/bools exact). Read-only in Phase 4
> (DEBUG log); Phases 7–8 consume these signals. No profitability claims.

## 0. Conventions (same as prior layers)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed, older = larger shift).
  Python mirror: oldest-first indices (`0` = oldest).
- Only closed bars feed detection. `atr<=0` → no signal. No levels from bar 0.
- Relationship to v1: `CInverseMMHelper` (leg-anchored break+reclaim →
  inverse-MM *projection*) is UNTOUCHED. This engine generalizes *detection*
  to any reference (N-bar extreme, confirmed swing) and reports the
  PENDING→FOLLOW/FAILED lifecycle + second-leg trap flag. It emits NO targets
  (the inverse anchor is the repo's weakest point — flagged, not extended).

## 1. Inputs (new; all prior inputs unchanged)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpBOLookback` | int | 20 | N bars for Donchian reference extreme |
| `InpBOToleranceATRMult` | double | 0.10 | close must clear ref by this ×ATR |
| `InpBOFollowBars` | int | 5 | window holding the active breakout bar |
| `InpBOTrapLookback` | int | 20 | window scanning for a prior same-dir failure |
| `InpEnableBreakout` | bool | true | master switch; false = layer idle |

Validation: `10<=Lookback<=100`, `0<=Tol<=0.5`, `1<=Follow<=20`,
`5<=Trap<=100`; clamp + `Validate()` false.

## 2. References at bar k (both computed from bars STRICTLY older than k)

- **NBAR**: `refHigh = max H`, `refLow = min L` over the `BOLookback` closed
  bars older than `k` (MT5 shifts `[k+1 .. k+N]`; mirror `[k−N .. k−1]`).
  Needs ≥10 such bars, else this reference is unavailable (the other may fire).
- **SWING**: most recent confirmed swing high / low older than `k`
  (same `sw[]` the FM engine uses, chrono oldest→newest). None older → unavailable.

## 3. Breakout event at bar k (closed, `k>=1`)

```
bullBO(k) = close[k] > refHigh + Tol×atr   (per available reference)
bearBO(k) = close[k] < refLow  − Tol×atr
```

Both references evaluated; most-recent event wins, swing breaks ties
(swing levels are structural — Brooks). `tol = BOToleranceATRMult×atr`.

## 4. Active breakout + lifecycle at analysis bar b

Search `k` in `[b .. b+FollowBars]` (MT5; newer→older → most recent first;
mirror `[idx−Follow .. idx]`, newest first). First `k` with an event is the
active breakout (`boBar=k`, `dir`, `refPrice`, `refKind`). None → no signal.
Newer bars = MT5 `[b .. k−1]` / mirror `(k .. b]`:

```
FAILED  = exists newer close back past ref∓tol
          (bull: close < ref−tol; bear: close > ref+tol)
FOLLOW  = !FAILED AND exists newer close still beyond ref±tol
          (bull: close > ref+tol; bear: close < ref−tol)
PENDING = otherwise (includes b==k; hovering inside the tol band stays PENDING)
```

`failBar`/`followBar` = newest bar deciding the outcome (−1 when PENDING).
FAILED takes precedence (a breakout that extended then reversed is a failure —
the trap Brooks warns about, not a success).

## 5. Second-leg trap flag (Brooks 2LBLTP/2LBRTP, wedge ~50/50)

`trapArmed` = exists older same-direction event `m` in
`(k .. k+TrapLookback]` that FAILED using only bars in `[k .. m−1]`
(between `m` and `k` — decided before `k` printed, no look-ahead).
A second-leg breakout after a same-dir failure is trap-prone: chasers enter,
early trapped traders exit into them. Flag only; Phase 8 decides.

## 6. Output struct + Describe

```
{found, dir(+1/−1), boBar, refPrice, refKind(NBAR/SWING),
 outcome(NONE/PENDING/FOLLOW_THROUGH/FAILED), trapArmed, decideBar}
```

`Describe()`, e.g. `BO bull #12>104.50(NBAR) FOLLOW [TRAP]` /
`BO bear #9<98.20(SWING) PENDING` — every token has a predicate in §3–5.

## 7. Enum (`Defs.mqh`)

`BO_NONE=0, BO_PENDING, BO_FOLLOW_THROUGH, BO_FAILED`. Full lifecycle states
(BULL_BREAKOUT etc.) belong to Phase 7 setup engine (not added now).

## 8. No-look-ahead / repaint contract (extends prior layers)

1. References use bars strictly older than `k`; outcomes use bars newer than
   `k` but never newer than `b`; bar 0 never feeds detection.
2. Swing references use confirmed swings only (same `sw[]` as FM projections).
3. Closed-bar freeze: extending history with newer bars returns identical
   results for old `b` (tested).
4. Pure/stateless: no buffers, alerts, objects, or projections from this layer.

## 9. Python mirror + tests

- Mirror: `tests/breakout.py` — `analyze(bars, idx, last_closed, atr, swings,
  cfg)` + `event_at(...)` helper, oldest-first indexing.
- Suites (`tests/test_breakout.py`, 9): bull BO pending at newest bar; bull
  follow-through; bull failed (extend-then-reverse → FAILED precedence); bear
  mirror; swing-reference BO (tie-break); tolerance (poke inside tol = none);
  second-leg trap armed (fail then re-break); stale BO outside FollowBars →
  none; freeze + no-look-ahead + zero-ATR/tiny-history/disabled safety.
