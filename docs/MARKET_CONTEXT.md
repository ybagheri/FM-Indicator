# MARKET CONTEXT — systematic specification (Phase 1 scope; Phases 3–4 build)

> What exists today, what Phase 1 adds, and the exact upgrade path. Normative
> for the parts marked DONE; planning for the rest. Scores are context /
> confidence scores, never probabilities (§26 of master prompt).

## 1. Current state (DONE, preserved)

`CContextClassifier::Classify` (closed bars only): `trend_score =
(EMA20−EMA50)/ATR`, `range_score = (HH50−LL50)/ATR`.
TREND if |trend|>0.8 and range>3; RANGE if |trend|<0.4 and range<6; else
TRANSITION (conf 0.5). `InpContextFilterMode` LOG_ONLY (default) / DEMOTE /
VETO. FM engine consumes it read-only by default. Tests: MTF bias + confidence
plumbing (TESTING #17).

## 2. Phase 1 additions (this milestone)

- `CBarAnalyzer` window features (`pressureBull/Bear`, `barbwire`,
  `tightening`) are logged alongside context at DEBUG level — human-readable
  confirmation that per-bar pressure and range-tightening agree or disagree
  with the EMA-gap classifier.
- No gating changes: context still never vetoes in LOG_ONLY (Brooks "context,
  not trigger" preserved).

## 3. Planned market-state engine (Phases 3–4, NOT implemented yet)

States: UNKNOWN, BULL_TREND, BEAR_TREND, BULL_CHANNEL, BEAR_CHANNEL,
TRADING_RANGE, BREAKOUT_MODE, BULL_BREAKOUT, BEAR_BREAKOUT,
PULLBACK_IN_BULL/BEAR, POSSIBLE_BULL/BEAR_REVERSAL, TRANSITION.
Probabilistic output = named context scores with exact formulas, e.g.:

```
trendScore   = clamp((EMA20-EMA50)/ATR / 2, -1, 1)
channelScore = overlap% of last 10 bodies  (high overlap → channel/range)
pressureScore= (pressureBull-pressureBear)/lookback
```

Final per-state scores normalized to sum 100; each published with the formula
and the inputs that produced it (explainability requirement, §9 master).
No ML, no fitted weights in Phase 3–4; weights (if any) are 1.0 with documented
sign until calibration data exists (Phase 17).

## 4. No-trade doctrine (Phase 8 preview, enforced in specs now)

The decision engine MUST output NO_TRADE/WAIT with a machine-checkable reason
whenever: mid-range third of a RANGE state; barbwire true; signal score <40;
conflicting context (top two states within 10 points); RR < `InpMinRR`;
late entry (>0.5×ATR past signal extreme); ≥2 failed breakouts in last 20 bars
without follow-through. Reasons are enum values, not free text, so tests can
assert them.

## 5. MTF architecture (reserved, not built in Phase 1)

HTF bias = current `MTFBias()` (SMA20/50 gap, LOG_ONLY). LTF entry confirmation
reserved: `InpLTFMinutes` input + `LTFConfirm()` stub documented but NOT
implemented — architecture holds the slot so later work doesn't refactor call
sites. Current-TF setup detection is authoritative; HTF/LTF never gate in
LOG_ONLY mode.
