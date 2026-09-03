# FUTURE ROADMAP — FM Indicator → Brooks-style bar-by-bar engine

## Phase 0 (audit) — DONE
- [x] Repo/history/code/docs audit (v1.2+v2 preserved, committed `206501b`).

## Phase 1 (bar-by-bar foundation) — DONE (this milestone)
- [x] `BROOKS_CONCEPTS.md` knowledge base (Brooks vs proxy vs implementation).
- [x] `BAR_BY_BAR_ENGINE.md` normative spec + `MARKET_CONTEXT.md` plan.
- [x] `CBarAnalyzer` (MQL5, pure/read-only) + `bar_analyzer.py` mirror + 7 tests.
- [x] Read-only indicator hook (DEBUG log, never gates FM state machine).

## v1.1 (correctness) — DONE
- [x] Follow-through 1-bar delay path (signal on newest bar never confirms
  same-bar with `RequireFollowThrough`).
- [x] `IsSignalBar` newest-bar fix (was `c<2`, now `c>=1`).
- [x] Inverse-MM anchor made symmetric (far side of failure bar, both legs).
- [ ] MetaEditor compile + Strategy Tester visual run on majors/H1 (user-side);
  screenshot log.

## v1.2 (families) — DONE (code + mirror + tests; live review pending)
- [x] `CRangeHeightMM`, `CChannelMM`, `CGapMM` (flag-gated, default OFF).
- [x] Wedge/3-push as first-class exhaustion (`InpMinPushes`, `InpUseWedgeExhaustion`).
- [x] Signal scoring 0–100 display-only (`InpShowScore`, `S=` in labels).
- [ ] Walk-forward review per family (MAE/MFE via CSV/backtest) on real data.

## v2 (research tooling) — DONE (tooling; analysis pending)
- [x] Historical signal export (CSV) + `backtest_run` + MAE/MFE harness.
- [x] Multi-timeframe read-only overlay (`InpMTFTrendTFMinutes`, LOG_ONLY).
- [x] EA foundation: `CFMEngine::ActiveSnapshots()` + DATA buffers.
- [ ] Parameter sensitivity / Monte Carlo notes from exported data.

## v3 (EA foundation, separate repo)
- Signal engine reuse (`CFMEngine::ActiveSnapshots()` + DATA buffers) by an EA
  in a separate repo; indicator repo stays execution-free.
- Optimization framework + walk-forward analysis.

## Phases 2–8 (bar-by-bar expansion, planned)
- [x] Phase 2: H1/H2/L1/L2 pullback counter + doubles (DT/DB) on confirmed swings
  (`PULLBACK_PATTERNS.md` + `PullbackPatterns.mqh` + mirror + 10 tests, read-only hook).
- [x] Phase 3: market-state engine (TREND/CHANNEL/RANGE/BREAKOUT_MODE scores)
  (`MARKET_STATE.md` + `MarketState.mqh` + mirror + 9 tests, read-only hook).
- Phase 3: market-state engine (TREND/CHANNEL/RANGE/BREAKOUT_MODE scores).
- Phase 4: breakout + generalized failed-breakout/trap engine.
- Phase 5: pullback/reversal/MTR + dedicated exhaustion analyzer.
- Phase 6: FM as setup-engine module (entry/stop/target/R per setup).
- Phase 7: setup engine (trend-continuation, pullback, BO, reversals).
- Phase 8: decision engine (BUY/SELL/WAIT/NO_TRADE + reasons) + visualization.

Non-goals for this repo: auto-trading, profitability claims, repainted-history
"perfect signals", per-tick CONFIRMED states.
