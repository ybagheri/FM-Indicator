# BAR-BY-BAR ENGINE — systematic specification (Phase 1, normative)

> Companion to `BROOKS_CONCEPTS.md` (concept → proxy mapping) and
> `SYSTEMATIC_SPECIFICATION.md` (FM module). This document is normative for
> the bar-by-bar layer: two implementations fed identical closed-bar series
> must produce identical `BarFeatures`. Everything discretionary is an `Inp*`
> input. No profitability claims. Scores are scores, never probabilities.

## 0. Conventions

- MT5 series indexing in MQL5: `0` = forming bar, `>=1` = closed bars.
  Python mirror uses oldest-first indexing; the mapping is tested, not assumed.
- Only closed bars (`shift>=1` / oldest-first `idx<=last_closed`) feed features.
  Bar 0 is NEVER analyzed (no intrabar features — POTENTIAL preview stays in
  the FM engine only).
- ATR: Wilder `InpAtrPeriod` (14) on closed bars; any ATR-normalized rule with
  `atr<=0` returns the safe default (false / 0 / UNKNOWN), never NaN.
- `NEAR(x,y,tol)` = `|x-y|<=tol`. Tolerances ATR-normalized.

## 1. Inputs (new; FM inputs unchanged, see SPEC §1)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpDojiMaxBodyRatio` | double | 0.15 | body/range below this → doji (one-bar range) |
| `InpBigBarATRMult` | double | 2.0 | range ≥ this × ATR → big/climax-candidate bar |
| `InpSmallBarATRMult` | double | 0.5 | range < this × ATR → small bar (stall candidate) |
| `InpStrongClosePct` | double | 0.70 | close in extreme N% toward dir → strong close |
| `InpOverlapRatio` | double | 0.50 | body-overlap / min range above this → overlapping pair |
| `InpBarbwireBars` | int | 5 | window for barbwire scan |
| `InpBarbwireMinOverlap` | int | 3 | overlapping pairs in window → barbwire |
| `InpPressureLookback` | int | 10 | bars for cumulative pressure counters |
| `InpEnableBarAnalysis` | bool | true | master switch; false = engine idle (zero behavior change to FM) |

Validation: `0.05<=Doji<=0.4`, `BigBar>SmallBar`, `0.5<=StrongClose<=1.0`,
`3<=BarbwireBars<=10`, `1<=PressureLookback<=20`; clamp + `Validate()` false.

## 2. BarFeatures (per closed bar, deterministic)

```
dir:            +1 bull (close>open) | -1 bear (close<open) | 0 doji-flat (close==open tick-exact)
range, body:    absolute prices; bodyRange = body/range in [0,1]
closePos:       (close-low)/range in [0,1]  (1 = closed on high)
upperTail, lowerTail: absolute; upperRatio, lowerRatio: /range
isDoji:         bodyRange < InpDojiMaxBodyRatio
isBig:          range >= InpBigBarATRMult*atr
isSmall:        range <  InpSmallBarATRMult*atr
isStrongBull:   dir>0 AND closePos>=StrongClose AND bodyRange>=MinBodyRatio(cfg 0.30)
isStrongBear:   mirror (closePos<=1-StrongClose)
isInside:       H[b]<=H[b+1] AND L[b]>=L[b+1]   (needs prior closed bar; newest window edge → false)
isOutside:      H[b]>=H[b+1] AND L[b]<=L[b+1]   (strict on at least one side: H>L or L<L)
overlap:        bodyOverlap(b,b+1)/min(range_b,range_b+1) in [0,1]; 0 if either range<=0
gapUp/gapDown:  L[b]<H? MT5-shift: bull micro-gap L[b]>H[b+1]; bear R[b]<L[b+1] (same as CGapMM, reused)
consecutive:    signed run ending at b toward dir (+n bull / -n bear / 0 reset on doji-flat or dir flip)
iiCount:        consecutive trailing inside bars ending at b (b inside, b-1 inside(oldest-first b+1)…)
```

Notes:
- `dir==0` only on tick-exact `close==open`; near-zero bodies are dojis with
  dir from sign (keeps trend counting stable — Brooks treats dojis as pauses,
  not direction flips; `consecutive` resets on `isDoji`, not on small bodies).
- `isInside/isOutside/overlap/gap` need the prior closed bar; when it does not
  exist (oldest bar, tiny history) they are false/0 — never an error.
- No future bars: feature(b) uses bars ≤ b (older-or-equal in time) + ATR at b.

## 3. Window features (still no-future; window ends at b)

```
pressureBull:   count of isStrongBull in (b-Lookback, b] (closed bars only)
pressureBear:   mirror
barbwire:       overlapping pairs (overlap>=InpOverlapRatio) in last BarbwireBars >= MinOverlap
                AND ≥1 doji in window → true
tightening:     range[b] < median(range[b-1..b-4]) (needs 5 bars; else false)
```

## 4. Bar label (visualization aid, configurable; NOT a signal)

```
"STRONG_BULL" / "STRONG_BEAR"  (isStrong*)
"BIG"          (isBig, non-strong close → climax-candidate, needs context)
"DOJI"         (isDoji)
"INSIDE" / "OUTSIDE" / "II2+"/"II3+"
"GAP"          (gapUp/gapDown)
else "BAR"
```

Labels exist for chart archaeology + tests; the decision engine (Phase 8) is
the only component allowed to emit BUY/SELL/WAIT.

## 5. Interpretation string (structured, evidence-generated)

```
Bar #<shift> <Bull|Bear|Doji> [Strong] [Big|Small] [Doji] [Inside|Outside|iiN] [Gap]
Close: <near-high|mid|near-low> Body <pct>% Wick adv <pct>%
vs prior: <inside|outside|overlap NN%|clean>
Pressure(10): +<n>/−<m> [Barbwire]
```

Generated from measured fields only. No generic text: every token has a
predicate in §2–3. Used by the explanation engine (Phase 8) and DEBUG logs.

## 6. No-look-ahead / repaint contract (extends SPEC §9)

1. `Analyze(rates,count,shift)` requires `shift>=1`; `shift==0` returns
   `valid=false` (forming bar never analyzed).
2. Pair/window features need older closed bars (`shift+1..` in MT5 terms);
   missing history → false/0, never an exception.
3. Closed-bar freeze: re-running on an extended history returns identical
   features for old bars (tested: freeze + no-look-ahead suites).
4. The analyzer is stateless/pure: no internal buffers, no alerts, no objects.
   Higher layers own state.

## 7. Python mirror + tests

- Mirror: `tests/bar_analyzer.py` — `bar_analyze(bars, idx, atr, cfg)` with
  oldest-first indexing; field-for-field identical semantics (float tolerance
  1e-9; booleans exact).
- Suites (`tests/test_bar.py`): strong/weak/doji geometry; inside/outside/ii;
  overlap+barbwire; gap parity with `CGapMM` predicates; consecutive counting
  with doji reset; freeze (append future bars → old features unchanged);
  no-look-ahead (feature(b) independent of bars newer than b); tiny-history
  safety; zero-ATR safety.
- MQL5 must match the mirror on identical synthetic series (same oracle rule
  as the FM engine).

## 8. Integration (Phase 1: read-only)

- `CFMEngine`/indicator call `CBarAnalyzer::Analyze` per new closed bar and
  DEBUG-log the interpretation string when `InpEnableBarAnalysis=true`.
- No state-machine input, no visualization, no alerts from this layer in
  Phase 1. Phases 3–8 consume `BarFeatures` (context → setups → decisions).
- EA reuse: `BarFeatures` is a plain struct; a future EA may include
  `BarAnalyzer.mqh` with no chart dependency.
