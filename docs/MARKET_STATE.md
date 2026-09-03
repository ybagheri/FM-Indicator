# MARKET STATE — systematic specification (Phase 3, normative)

> Companion to `BROOKS_CONCEPTS.md` (§3) and `MARKET_CONTEXT.md` (§3).
> Normative for the market-state layer: identical closed-bar input → identical
> scores (float tol 1e-9, pcts exact ints summing to 100, winner exact).
> Read-only in Phase 3 (DEBUG log); Phases 7–8 consume these scores.
> No profitability claims. Scores stay scores.

## 0. Conventions (same as bar/pullback layers)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed, older = larger shift).
  Python mirror: oldest-first indices (`0` = oldest).
- Only closed bars feed detection. `atr<=0` → UNKNOWN (scores cannot normalize).
- `clamp01(x)` = `min(max(x,0),1)`; `clamp11(x)` = `min(max(x,-1),1)`.
- The v1 `CContextClassifier` (Trend/Range/Transition) is UNTOUCHED — preserved
  for compat. The new engine uses the Phase-2 EMA convention (seed = oldest
  close, iterate forward to `b`; see `TrendGap`), which differs slightly from
  the v1 local seeding. Both deterministic; honesty record, not a bug.

## 1. Inputs (new; all prior inputs unchanged)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpStateLookback` | int | 20 | bars for range height HH−LL |
| `InpStateOverlapBars` | int | 10 | bars for body-overlap (channel) fraction |
| `InpEnableMarketState` | bool | true | master switch; false = layer idle |

Validation: `10<=StateLookback<=100`, `5<=StateOverlapBars<=20`; clamp +
`Validate()` false. Pressure predicates reuse `InpPressureLookback` /
`InpStrongClosePct` / `InpMinBodyRatio` / `InpOverlapRatio` (documented, not
duplicated — one source of truth per predicate).

## 2. Data sufficiency → UNKNOWN

Let `need = max(StateLookback+1, StateOverlapBars+1, 6)`. If closed bars
ending at `b` (`count−b` in MT5 terms) `< need` → UNKNOWN (all pcts 0).
`atr<=0` → UNKNOWN. `b<1` (forming) → UNKNOWN. Otherwise `valid=true`.

## 3. Evidences (all deterministic, no future bars)

All windows end at closed bar `b`:

```
trendScore = clamp11( ((EMA20−EMA50)/atr) / 2 )        // §3 of MARKET_CONTEXT
  EMA20/50 = oldest-seed EMA over closes ≤ b (== TrendGap/atr).
  <50 closes ending at b → gap 0 (Phase-2 gate philosophy), score 0.
rangeScore = (HH−LL)/atr over last StateLookback closed bars
chop       = fraction of adjacent body-overlap pairs ≥ InpOverlapRatio
             over last StateOverlapBars closed bars (pairs = bars−1)
pressure   = (pressureBull − pressureBear)/PressureLookback in [−1,1]
             (same strong-close predicates as CBarAnalyzer::WindowStats)
tight      = 1 if range[b] < median(range of 4 older closed bars) else 0
             (same predicate as CBarAnalyzer tightening)
```

Derived [0,1] evidences:

```
bullT = clamp01(trendScore)      bearT = clamp01(−trendScore)
bullP = clamp01(pressure)        bearP = clamp01(−pressure)
expand  = clamp01((rangeScore−3)/3)   // room moved: trends (v1 TREND needs range>3)
compact = clamp01((6−rangeScore)/4)   // bounded: ranges (v1 RANGE needs range<6)
balance = 1 − |pressure|              // directionless: ranges
```

## 4. State raws (every coefficient 1.0 — no fitted weights, per §3 plan)

```
BULL_TREND   = bullT + bullP + expand
BEAR_TREND   = bearT + bearP + expand
BULL_CHANNEL = bullT + chop + compact
BEAR_CHANNEL = bearT + chop + compact
TRADING_RANGE= compact + chop + balance
BREAKOUT_MODE= tight + compact + chop
```

Rationale (Brooks §3): trends need direction + conviction + room; channels are
weak-directional + overlapping + bounded (grinding HH/HL or LH/LL inside a
loose range); ranges are bounded + two-sided + directionless; breakout mode is
a tightening bounded two-sided market (first breakout traps ~50% — Phase 4).
BO / pullback-in-trend / reversal states need Phase 4–5 machinery (breakout
events, MTR) and are NOT emitted here.

## 5. Normalization → pcts (ints, sum exactly 100)

`sum` = six raws. `sum<=0` → TRANSITION, pcts all 0 (dead-flat guard).
Else `exact_i = raw_i/sum*100`, `pct_i = floor(exact_i)`, remainder
`100 − Σpct` dealt one point at a time to the largest fractional part
(strict `>` scan → first-max-wins, deterministic). Winner = argmax over fixed
order `[BULL_TREND, BEAR_TREND, BULL_CHANNEL, BEAR_CHANNEL, TRADING_RANGE,
BREAKOUT_MODE]` (strict `>` → ties keep earliest, deterministic).

Weak-evidence floor: `maxRaw < 1.0` → winner TRANSITION (no state earned it;
"no edge, wait"), pcts still reported. Close-call conflicts (top two pcts
within 10) are NOT overridden here — that is Phase 8's decision rule
(doctrine §4 preview); Phase 3 publishes the machine-checkable pcts it needs.

## 6. Output struct

```
{valid, state (enum §7), pct[6] (sum 100 when valid),
 trendScore, rangeScore, chop, pressure, tight, maxRaw}
```

`Describe()` evidence line, e.g.:
`MS #1 BULL_TREND 45/12/20/5/12/6 T=+0.62 R=4.1 chop=0.20 P=+0.40` —
every token has a predicate in §3–5.

## 7. Enum (new, `Defs.mqh`)

`MS_UNKNOWN=0, MS_BULL_TREND, MS_BEAR_TREND, MS_BULL_CHANNEL,
MS_BEAR_CHANNEL, MS_TRADING_RANGE, MS_BREAKOUT_MODE, MS_TRANSITION`.
BO/pullback/reversal members reserved for Phases 4–5 (not added now).

## 8. No-look-ahead / repaint contract (extends SPEC §9, bar §6, pullback §7)

1. All scans end at closed bar `b` (`>=1`); bar 0 never feeds detection.
2. Closed-bar freeze: extending history with newer bars returns identical
   results for old `b` (tested).
3. Pure/stateless: no buffers, alerts, or objects from this layer.

## 9. Python mirror + tests

- Mirror: `tests/market_state.py` — `trend_gap`, `analyze(bars, idx,
  last_closed, atr, cfg)` returning the struct above, oldest-first indexing.
  `entry`-style tick adjustments: none (no price levels emitted).
- Suites (`tests/test_state.py`, 9): bull trend; bear mirror; bull channel
  (grind + overlap); trading range; breakout mode (tightening tips RANGE→BOM);
  transition (weak floor); unknown (tiny history); freeze + no-look-ahead +
  zero-ATR safety; pct-sum-100 + deterministic winner on every case.
