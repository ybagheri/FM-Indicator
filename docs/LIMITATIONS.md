# LIMITATIONS — honest proxies, weak points, non-goals

> Companion to `RESEARCH.md` (Brooks vs proxy), `BROOKS_CONCEPTS.md`
> (automation grades), `VALIDATION.md`. Read before any live use. No
> profitability claims.

## 1. Proxies, not official rules

All thresholds are ours (ATR-normalized but still ours): swings `k=3`,
legs `1.0×ATR / 3–100 bars`, pullback `0.15–0.90`, FM approach `1.0×ATR` /
tol `0.25×ATR` / overshoot `0.50×ATR`, signal bar close-50%/body-30%/
wick-60%, exhaustion climax `2.0×ATR` / stall `0.5×ATR` / pushes `3` /
wedge toggle, state EMA gaps `0.8/0.4`, decision score `40` / late `0.5×ATR`
/ conflict `10 ppts` / trap `≥2 fails`. Documented in SPEC §1; tunable via
`Inp*`; presets do not curve-fit (see §4).

## 2. Known weak points (flagged, not hidden)

- Inverse-MM anchor (v1.1 symmetric far-side anchor) is the weakest point —
  needs walk-forward review on real data.
- Breakout + reversal objectives are fixed `2.0×ATR` measurement proxies,
  not structural magnets (`GENERAL_SETUPS.md` §0).
- `CContextClassifier` + Phase-3 `CMarketState` default LOG_ONLY: they
  annotate, never veto — faithful to Brooks "context, not trigger", but it
  means counter-context FM setups still project (by design).
- HTF/LTF overlays + Phase-8 decision are read-only interpretation labels
  (BUY/SELL never orders); per-bar tags (B1/B2/PB/BO/…) live in DEBUG logs,
  not chart objects, to keep the chart readable (see `USER_GUIDE.md`).
- No dedicated `CSupportResistanceEngine` class: S/R = confirmed swings +
  range HH/LL + BO refs + MM targets (documented mapping in `ARCHITECTURE.md`).
  No trend-line object engine (only EMA-gap + overlap proxies).

## 3. NOT validated

No statistical validation yet (see `VALIDATION.md` §2). Scores are not
probabilities. No tick-level MT5 tester run in Linux CI. Do not live-trade
on this indicator without completing the ordered next moves.

## 4. Anti-overfit stance (§38 master)

No curve fitting on small samples, no hardcoded symbol/timeframe behavior
(except documented ATR normalization), no look-ahead, no repainting, no
hidden exceptions, no ML in this repo (feature export only — see
`FUTURE_ROADMAP.md`). Families default OFF so setup counts match v1 unless
the researcher opts in.

## 5. Non-goals for this repo

Auto-trading, profitability claims, repainted-history "perfect signals",
per-tick CONFIRMED states, order execution (v3 lives in a separate repo).
