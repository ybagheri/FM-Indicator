# PULLBACK PATTERNS — systematic specification (Phase 2, normative)

> Companion to `BROOKS_CONCEPTS.md` (§5) and `BAR_BY_BAR_ENGINE.md`.
> Normative for the pullback-counter + double-top/bottom layer: identical
> closed-bar input → identical signals (float tol 1e-9, booleans exact).
> Read-only in Phase 2 (DEBUG log); Phases 7–8 consume these signals.
> No profitability claims. Scores stay scores.

## 0. Conventions (same as bar engine)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed, older = larger shift).
  Python mirror: oldest-first indices (`0` = oldest).
- Only closed bars feed detection. `atr<=0` → safe default (no signal).
- `NEAR(x,y,tol)` = `|x-y|<=tol`, ATR-normalized.

## 1. Inputs (new; all prior inputs unchanged)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpMinPullbackDepthATRMult` | double | 0.50 | min window range (×ATR) for an H1/L1 to count |
| `InpDoubleTopTolATRMult` | double | 0.25 | two highs/lows within this ×ATR → double candidate |
| `InpMaxDoubleBars` | int | 20 | max bars between the two extremes of a double |
| `InpMinDoubleTroughATRMult` | double | 0.50 | min trough depth (×ATR) between double extremes |
| `InpMicroDoubleBars` | int | 5 | window for micro doubles on raw bar extremes |
| `InpEnablePullbackPatterns` | bool | true | master switch; false = layer idle |

Validation: `0.1<=Depth<=2.0`, `0.05<=Tol<=1.0`, `2<=MaxDouble<=100`,
`0.1<=Trough<=2.0`, `3<=MicroBars<=10`; clamp + `Validate()` false.

## 2. Trend direction gate

```
TrendDir(b): EMA20/EMA50 gap on closes ending at closed bar b:
  gap = (EMA20 − EMA50) / atr(b); atr<=0 → 0
  gap > +0.4 → +1 (bull); gap < −0.4 → −1 (bear); else 0 (no-trade context)
```

Needs 50+ closed bars of history (else 0). H1/H2 run ONLY when `+1`; L1/L2
ONLY when `−1`; `0` → no pullback signals (Brooks: H2 reliable only in trends;
in ranges every H1/H2 fails — we suppress rather than mislead). Doubles are
direction-agnostic (no gate).

## 3. H1/H2 (bull pullback) — definitions on closed bars

Window: `W = [b+MaxPullbackBars .. b]` (MT5 shifts, capped at `count-1`).

1. Depth filter: `maxH(W) − minL(W) >= MinPullbackDepthATRMult × atr` else none.
2. **H1** = oldest `i` in `(w0+1 .. b)` (forward in time) with
   `H[i] > H[i+1]` (first break above prior bar high = first sign pullback
   may be ending). `lowAtH1 = min L[w0..i]`.
3. **Second leg**: exists `j` newer than `i` (`b<=j<i`) with
   `L[j] < lowAtH1` (pullback made another low).
4. **H2** = oldest `k` newer than the second-leg-low bar with
   `H[k] > H[k+1]` (second break = primary entry signal).
5. Output: most advanced available — `H2` if found else `H1` if found;
   `legs` = 2 / 1. Entry level = `H[signal]+1 tick` (`_Point`); stop =
   pullback low (`min L`); both recorded, never traded by the indicator.

L1/L2 mirror with `L[i] < L[i+1]`, `highAtL1 = max H`, second leg
`H[j] > highAtL1`, entry `L[signal]−_Point`, stop = pullback high.

Notes:
- H1 alone carries higher failure risk (pullback may not be done) — the
  `legs==1` flag exists so Phase 8 can require H2 or demand confirmation.
- Scan bound `MaxPullbackBars` (default 50) reuses the FM pullback window.

## 4. Double tops / bottoms on confirmed swings

Input: chrono swing array (oldest→newest, confirmed only — same `sw[]` the
FM engine uses) + `atr`.

- **DoubleTop** = pair of swing highs `(i<j)`, `j` = most recent first:
  `|p_j − p_i| <= DoubleTopTolATRMult × atr` AND
  `(bar_j − bar_i) <= MaxDoubleBars` (shift differences ≈ bars apart) AND
  exists swing low `k` between with `min(p_i,p_j) − trough_k >=
  MinDoubleTroughATRMult × atr` (real separation, not one flat top).
- **DoubleBottom** mirrors on swing lows / intervening high.
- Output: `{dir: −1 top (bearish) / +1 bottom (bullish), bar1, bar2,
  price1, price2, micro:false}`. Most-recent pair wins. No signal bar
  required at this layer (Phase 7 pairs doubles with signals).

## 5. Micro doubles on raw bar extremes

Same geometry on bar H/L over `MicroDoubleBars` (default 5) newest closed
bars, same `tol`, trough requirement halved (`×0.5`) for the short window.
Output identical struct with `micro:true`. Micro doubles are lower-confidence
by construction (documented; Phase 8 scores them below swing doubles).

## 6. MTR note (built in Phase 5 — honesty record retained)

A full Major Trend Reversal needs trend-line break + failed retest + second
entry with strong BO (HARD automation: discretionary line placement). Phase 2
deliberately shipped only the components (TrendDir, second-leg counting,
doubles) and did NOT emit "MTR" labels. The MTR proxy (EMA-cross for the
line break + retest + Phase-4 FOLLOW + pressure → MINOR/MAJOR, unit weights)
was built in Phase 5 — see `REVERSAL_ENGINE.md` §4. This layer's contract is
unchanged: it emits components, never verdicts.

## 7. No-look-ahead / repaint contract (extends SPEC §9, bar spec §6)

1. All scans end at closed bar `b` (`>=1`); bar 0 never feeds detection.
2. Swing doubles use confirmed swings only (same `sw[]` as FM projections).
3. Closed-bar freeze: extending history with newer bars returns identical
   results for old `b` (tested).
4. Pure/stateless: no buffers, alerts, or objects from this layer.

## 8. Python mirror + tests

- Mirror: `tests/pullback_patterns.py` — `trend_dir`, `detect_h bull`,
  `detect_l bear`, `find_double_top/bottom` (swings), `micro_double_top/bottom`
  (bars), oldest-first indexing.
- Suites (`tests/test_pullback.py`, 10): H1→H2 two-leg; H1-only (no second
  leg → legs==1, no H2); L1/L2 mirror; gate 0 (no signals); chop with gate
  forced (documents why gating matters); swing double-top in/out of tol;
  shallow-trough rejection; double-bottom mirror; micro double; freeze +
  no-look-ahead + zero-ATR/tiny-history safety.
