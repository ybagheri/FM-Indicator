# BASELINE REPORTS — default-parameter references (§18)

> Baselines are REFERENCE POINTS, never claims. Every number below is an
> MT5 BACKTEST result (see `docs/MT5_TESTING_STATUS.md` for full run tables).
> Common setup: FM_EA 1.00, EURUSD H1, 2025.11.03–12.03, Model=1 (1-min OHLC),
> broker-current spread, no commission, $10k 1:100, Balanced + EA defaults,
> InpTradeMode=DEMO. Full tester `.htm` reports sit beside each summary.

## T-014 — AUTO (default; the blessed baseline)

- Trades 3 · Wins 0 (0%) · Net −353.49 · PF 0.00 · Expectancy −117.83
- Balance DD 353.49 (3.53%) · Equity DD 373.84 (3.73%)
- Selections 93 (PB 58/BO 3/DBL 32), vetoes 435, EXEC_DONE ×3,
  EXEC_INVALID_STOPS ×3 (SELL-double stops vs stop-level — under review)
- Files: `T-014_AUTO_DEMO_EURUSD-H1.htm`

## T-015 — SINGLE_PULLBACK

- Trades 0 (51 SKIP_LATE_ENTRY + 18 SKIP_PROVISIONAL_OFF; mechanism
  verified, no silent failure). No metrics to report.
- Files: `T-015_SINGLE_PB_DEMO_EURUSD-H1.htm`

## T-016 — SINGLE_DOUBLE

- Trades 4 · Wins 1 (25%) · Net −37.44 · PF 0.86 · Expectancy −9.36
- Balance DD 268.69 (2.63%) · Equity DD 316.93 (3.08%)
- Files: `T-016_SINGLE_DBL_DEMO_EURUSD-H1.htm`

## Reading

Weak/choppy-window baselines are EXPECTED at this stage (82% structural
veto, defaults unoptimized). Optimization (Phase 35) must beat these
numbers on IS *and* hold on OOS (Phase 38) — otherwise REJECT.
