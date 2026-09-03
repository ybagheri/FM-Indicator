# REVERSAL ENGINE — systematic specification (Phase 5, normative)

> Companion to `BROOKS_CONCEPTS.md` (§5: pullback legs, MTR vs minor reversal,
> wedge/doubles, climax) and `BREAKOUT_ENGINE.md` (opposite-BO leg of MTR).
> Normative for the reversal layer: identical closed-bar input → identical
> reports (float tol 1e-9, ints/enums/bools exact). Read-only in Phase 5
> (DEBUG log); Phases 7–8 consume these signals. No profitability claims.

## 0. Conventions (same as prior layers)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed, older = larger shift).
  Python mirror: oldest-first indices (`0` = oldest).
- Only closed bars feed detection. `atr<=0` → no signal. Bar 0 never feeds.
- `CConfirmation` (SPEC §8 OR-list, `PushCount`/`IsWedge`) is UNTOUCHED.
  The dedicated analyzer below publishes the same predicates as named
  components (one formula source: SPEC §8 / `ExhaustionAnyCfg`).
- Honesty record (pre-existing v1 divergences, NOT changed here — compat):
  `fm_engine.py`'s overshoot (`beyond SMA + window extreme`, window on the
  newer side) and uncapped `push_count` differ slightly from MQL5 (`max(SMA,
  HH−20%range)` gate on the older side, cap 6). Deeper: `CConfirmation::
  PushCount/IsWedge` scan newer-ward for `b>1` (loop `i--` compares bar `i`
  with older `i+1`, so the run extends toward the present), and `IsWedge`
  excludes the two newest closed bars (`b<3`) — live `b=1` can never report a
  wedge through `ExhaustionAnyCfg`. This layer therefore owns backward
  (older-ward, run ending at `b`) push/wedge predicates with the SAME
  thresholds (cap 6, shrink ×1.05, ≥4-push bypass), so the live bar is covered.
  This layer's mirror follows this spec + MQL5; v1 files stay byte-compatible
  until a dedicated alignment pass.

## 1. Inputs (new; all prior inputs unchanged)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpRevLookback` | int | 10 | cross/retest window (bars) |
| `InpRevRetestTolATRMult` | double | 0.25 | EMA touch/close-through band (×ATR) |
| `InpRevMinPressure` | int | 5 | pushes needed for the pressure leg (Brooks 5–10) |
| `InpEnableReversal` | bool | true | master switch; false = layer idle |

Validation: `5<=Lookback<=50`, `0.05<=RetestTol<=1.0`, `3<=MinPressure<=10`;
clamp + `Validate()` false. Exhaustion components reuse SPEC-§8 constants
(climax 2.0 / stall 0.5+0.4+0.4 / overshoot SMA20+0.3) and `InpMinPushes` /
`InpUseWedgeExhaustion` — no new knobs.

## 2. Exhaustion report (per closed bar b, toward dir ±1)

Same five predicates as `ExhaustionAnyCfg`, published separately:

```
climax   = range[b] >= 2.0×atr
stall    = range[b] < 0.5×atr(+eps) AND upperWick > 0.4×range AND lowerWick > 0.4×range
pushes   = BackwardPushCount(b, dir): run ending at b toward OLDER bars
           (same close/high-low predicates as PushCount, cap 6)
pushOK   = pushes >= max(2, MinPushes)
wedge    = UseWedge AND WedgeAt(b, dir): pushes ≥ 3 AND (ranges shrink ×1.05
           toward older bars OR pushes ≥ 4); needs 2 older bars.
           (Same predicates as IsWedge WITHOUT its b<3 newest-bar exclusion.)
overshoot= b+20<count AND close beyond max(SMA20, HH−20%range) [dir>0] /
           min(SMA20, LL+20%range) [dir<0] by > 0.3×atr  (SPEC §8.4 exactly)
breadth  = climax+stall+pushOK+wedge+overshoot (0..5)
```

`breadth>0` whenever `ExhaustionAnyCfg(...)` is true (superset: the fixed
wedge fires at the newest bar where the v1 OR-list cannot — the fix, not a
bug; tested in the mirror). `Describe()`, e.g. `EXH bull n=3
climax+pushes(4)+wedge`.

## 3. Pullback leg counter (confirmed swings only)

Bull case (`dir=+1`; bear mirrors with highs/lows swapped):

```
anchor  = most recent swing high; none → invalid
origin  = most recent swing low OLDER than anchor (leg-up origin); none → depth −1 (unknown)
lows    = swing lows strictly newer than anchor, chrono
legs    = 0 if lows empty
        = else 1 + #{lows[i] lower than every newer-than-anchor low before it}
          (successive lower lows; capped at 3)
minLow  = min over lows
depth   = (anchor − minLow)/(anchor − origin) (−1 when no origin)
deep    = depth > 0.6  (Brooks: deep pullback demotes trend confidence)
```

Output `{valid, legs(0..3), deep, depth, anchorBar, extremeBar}`.
`legs==1/2/2+` feeds Phase-7 with-trend entries; `deep` feeds Phase-8
demotion. Two-leg counting needs confirmed swings — delay is honest (§5).

## 4. MTR proxy (per closed bar b, reversal direction revDir ±1)

Brooks MTR = trend break + failed retest + opposite BO with follow-through +
pressure. Trend lines are HARD to automate (concepts §5) — substitution:
EMA20 cross for the line break (documented). Four unit-weight legs:

```
ema[.]   = oldest-seed EMA20 over closes ≤ b (same convention as TrendGap)
side(j)  = +1 if close[j] > ema[j]+tol; −1 if close[j] < ema[j]−tol; else 0
tol      = RevRetestTolATRMult × atr
emaBreak = side(b)==revDir AND exists j in (b..b+K−1] with side(j)==−revDir
crossBar = newest such j (−1 when none)
retest   = exists j in [b..crossBar−1] testing EMA and holding:
           bull: low[j] ≤ ema[j]+tol AND close[j] > ema[j]−tol
           bear: high[j] ≥ ema[j]−tol AND close[j] < ema[j]+tol
boFollow = Phase-4 active BO at b with dir==revDir AND outcome FOLLOW_THROUGH
pressN   = PushCount(b, revDir); pressureOK = pressN >= RevMinPressure
score    = 25 × (emaBreak+retest+boFollow+pressureOK)   (0..100, unit weights)
verdict  = MAJOR if all four; MINOR if ≥1; NONE if 0
```

Sufficiency: closed bars ending at `b` ≥ `RevLookback+2`, else NONE
(`found=false`). `boFollow` reuses `CBreakoutEngine::Analyze` (needs `sw[]`).
Without 5–10 bars of pressure the reversal is minor — scalp at best (concepts).

## 5. Output structs + enums (`Defs.mqh`)

```
ExhaustionReport {climax, stall, pushes, pushOK, wedge, overshoot, breadth}
LegCount  {valid, legs, deep, depth, anchorBar, extremeBar}
ReversalSignal {found(verdict≥MINOR), verdict(NONE/MINOR/MAJOR), dir,
  emaBreak, retest, boFollow, pressureOK, pressN, score, crossBar}
```

`REV_NONE=0, REV_MINOR, REV_MAJOR`. Full reversal setup states belong to
Phase 7 (not added now).

## 6. No-look-ahead / repaint contract (extends prior layers)

1. All scans end at closed bar `b` (`>=1`); bar 0 never feeds detection.
2. Leg counter + swing-BO leg use confirmed swings only.
3. Closed-bar freeze: extending history with newer bars returns identical
   results for old `b` (tested).
4. Pure/stateless: no buffers, alerts, objects, or projections from this layer.

## 7. Python mirror + tests

- Mirror: `tests/reversal.py` — `exhaustion(...)`, `leg_count(...)`,
  `mtr(...)`, oldest-first indexing; MQL5/SPEC-§8 formulas (see §0 record).
- Suites (`tests/test_reversal.py`, 10): climax bar; stall bar; pushes+wedge
  (shrinking 4-push); overshoot spike; breadth OR-parity; bull legs 1→2+deep;
  bear legs mirror; MTR MAJOR (all four legs incl. Phase-4 FOLLOW); MTR MINOR
  (partial); NONE + freeze + no-look-ahead + zero-ATR/tiny/disabled safety.
