# EA ARCHITECTURE — shared engine, adapters, EA track (Phases 21+)

> Companion to `ARCHITECTURE.md` (indicator internals), `CURRENT_STATE.md`
> (audit), `MT5_TESTING_STATUS.md` (runs). Status labels: DONE vs PLANNED.
> No profitability claims. Indicator repo stays execution-free until the EA
> track explicitly adds execution — and even then behind `ANALYSIS_ONLY`
> default (see Phase 33 plan).

## 1. Target structure (§5 of EA track)

```text
Market Data
     ↓
Shared Price Action Engine  (MQL5/Include/FM/*.mqh — single source)
     ↓
Context → Setup Detection → Decision
     ↓
┌───────────────┬────────────────┐
Indicator       EA               Research
Chart/alerts    Execution/risk   CSV/backtest
```

## 2. Phase 21 — Shared Analysis Contract ✅ DONE (commit: this phase)

- New `MQL5/Include/FM/Analysis.mqh`: `struct FMAnalysisResult` (bar,
  trendDir, pullbacks, doubles, market state, breakout, reversal legs/MTR,
  FM plans[20], general best incl. FM contest, decision + context, engine
  census) + `class CFMAnalysis` (owns `CATR`/`CSwingDetector`/`CFMEngine`;
  `Setup(cfg,log)`, `Reset()`, `Update(rates,count,cfg,shift,res)`,
  `EnginePtr()`, `AtrAt()`).
- The `Update` body is a VERBATIM move of the old `OnCalculate` pipeline
  (only identifier scope changed: `g_*`→`m_*`, `close[1]`→`rates[1].close`
  etc.; one MQL5-mandated change: engine exposed via pointer, not reference
  — error 229 — behavior-neutral).
- `FM_Indicator.mq5` is now a thin adapter: new-bar gating, prev-state
  snapshot, `Update`, MTF/LTF overlays, DATA buffers, viz, alerts, CSV.
- Parity proof (acceptance): MetaEditor 0/0; 97 UNIT TESTS pass; MT5
  BACKTEST T-003 (same config as T-001) reproduces edge counts EXACTLY
  (528/528 reads, 91/11/5). See `MT5_TESTING_STATUS.md`.

## 3. Phase 22 — Strategy Registry ✅ DONE (commit: this phase)

- `Analysis.mqh`: `FMAnalysisResult` gains `candidates[12]` + `candCount`
  (full general catalog + FM-contest entry even when it does not win).
  Additive only — indicator behavior unchanged (parity: MT5 T-004 reproduces
  T-001 exactly, 528/528, 91/11/5; 0/0 compile; unit tests pass).
- New `MQL5/Include/FM/StrategyRegistry.mqh`: `ENUM_FM_STRATEGY`
  (NONE/FM_FADE/PULLBACK/BREAKOUT/REVERSAL/DOUBLE — only genuinely
  implemented), `ENUM_STRATEGY_MODE` (SINGLE/MULTI/AUTO),
  `StrategyCandidate`/`StrategySelection`, `CStrategyRegistry::Configure/
  IsEnabled/BuildCandidates/Select` (deterministic score-max, firm beats
  provisional on ties, then enum order, then entry).
- FAILED_BO as a separate strategy deferred to Phase 28 (needs
  inverse-family plumbing in the trade intent).

## 4. Phase 23 — EA Skeleton ✅ DONE (commit: this phase, ANALYSIS_ONLY)

- New `MQL5/Include/FM/Inputs.mqh`: analysis inputs moved VERBATIM from the
  indicator (same names/order/defaults → `.set` presets keep loading);
  `FM_ApplyInputs(cfg)` shared. Indicator adopts it (behavior unchanged).
- New `MQL5/Experts/FM_EA.mq5` v1.00: `CFMAnalysis` + `CStrategyRegistry`,
  new-closed-bar gating, 1500-bar history, per-bar selection log,
  `OnDeinit` per-strategy census. NO order functions exist yet.
- Registry mirror: `tests/strategy_registry.py` + `tests/test_registry.py`
  (5 suites: single/multi/auto/tie-breaks/empty+determinism) — all pass.
  Total UNIT TEST: 102 (97+5).
- MT5 BACKTEST T-005 (EURUSD H1 11.03–12.03, defaults, AUTO): pass, 528 bars,
  selections FM_FADE=1/PULLBACK=293/BREAKOUT=14/REVERSAL=0/DOUBLE=220,
  0 orders (by design), 0 errors. Note: selection fires almost every bar —
  NO_TRADE intelligence is Phase 8-decision gating + Phase 31, not yet wired
  into the EA path (honest gap, see §6).

## 5. Phase 24 — Risk Management ✅ DONE (commit: this phase)

- New `MQL5/Include/FM/RiskManager.mqh`: `ENUM_LOT_MODE` (FIXED/RISK_PCT/
  MONEY), `RiskDecision{allowed,reason,volume,riskMoney,rMult}`,
  `CRiskManager::Configure/OnNewDay/NotifyTradeClosed/NotifyTradeOpened/
  ComputeVolume/Check` (veto order NO_SETUP→LOW_RR→HIGH_SPREAD→DAILY_LOSS→
  MAX_TRADES_DAY→CONSEC_LOSSES→MAX_OPEN→MAX_PER_SYMBOL→OK). Volume via
  `OrderCalcProfit` + symbol step/min/max normalization; stop-level is an
  execution-layer check (Phase 25, needs live prices).
- Mirror: `tests/risk_manager.py` + `tests/test_risk.py` (gates, volume
  norm, day-book) — pass. Total UNIT TEST: 105.
- EA wires Check per selection (logs `risk=REASON vol=`; still no orders).
- MT5 BACKTEST T-006 (same H1 window): pass, selections identical to T-005,
  riskOK=481 / LOW_RR=47, 0 errors.

## 6. Phase 25 — Execution Engine ✅ DONE (commit: this phase, dormant)

- New `MQL5/Include/FM/ExecutionEngine.mqh`: `ExecResult{ok,reason,order/
  dealTicket,price,volume}`, `CExecutionEngine::Configure/Buy/Sell/Send`
  over `CTrade`. Pre-send gates (trade-mode direction, spread recheck,
  volume bounds, quotes, stop-level distance, margin) + retcode
  classification (`sent && DONE/DONE_PARTIAL` only). Build-6090 API fixes
  found by compiling: `SetExpertMagicNumber` (not `SetMagicNumber`),
  `PRICE_CHANGED` (not `PRICE_CHANGES`), no `NO_CONNECTION`/`PENDING`/
  `NO_QUOTES` retcodes, no `SymbolInfoPoint(sym)` (use `SYMBOL_POINT`).
- Mirror: `tests/execution.py` + `tests/test_execution.py` — pass.
  Total UNIT TEST: 107.
- EA constructs+configures it; makes NO calls yet (orders need Phase 33
  mode). MT5 BACKTEST T-007: pass, census byte-identical to T-006,
  0 errors. Live-order proof deferred to Phase 34 baselines (honest).

## 7. Phase 26 — Position Management ✅ DONE (commit: this phase)

- New `MQL5/Include/FM/PositionManager.mqh`: `PositionFix` record,
  `CPositionManager::Configure/Refresh/Count/HasOpen/ModifySLTP/
  MaybeBreakEven/MaybeTrail/ClosePosition/CloseAll/PartialClose/
  ScanClosedDeals`. Magic+symbol filtered (foreign never touched);
  `FM|<strategy>|<setupId>` comment codec with restart adoption;
  stop-level/freeze validation on modify; retcode-checked close/partial.
  Restart rule: first deal scan fast-forwards (no history replay into P/L).
- Mirror: `tests/positions.py` + `tests/test_positions.py` (codec, BE,
  trail) — pass. Total UNIT TEST: 110.
- EA: per-bar Refresh + BE/trail (strategy-permits all-true until 27–30) +
  closed-deal → risk accounting + init adoption log.
- MT5 BACKTEST T-008: pass, census identical (528/481, 1/293/14/0/220),
  0 errors. Modify/close paths untested live (no positions exist while
  execution dormant) — honest gap, closed in Phase 34.

## 8. Phase 27 — FM Integration ✅ DONE (commit: this phase)

- New `MQL5/Include/FM/TradeIntent.mqh`: `TradeIntent` record +
  `CTradeIntentBuilder` (permits table: BE always, trail only
  PULLBACK/BREAKOUT, no partials v1; provisional gate; chase guard mirroring
  Phase-8 late rule with 1e-9 epsilon — boundary flake caught by mirror and
  fixed both sides). `FromFM` matches the winning setup to its FM plan by
  dir+entry for `invalidClose` (else STOP-only invalidation).
- Mirror: `tests/trade_intent.py` + `tests/test_intent.py` — pass.
  Total UNIT TEST: 114.
- EA: intent inputs (provisional OFF, hold 5, chase 0.5×ATR); FM intent logged
  (`WOULD_BUY/SELL` / `SKIP_reason`) when risk-OK.
- New `docs/STRATEGY_CATALOG.md` (FM section deep; rest per phase).
- MT5 BACKTEST T-009 (H1 defaults): pass, census identical, FM selection
  correctly held (LOW_RR), 0 errors. T-009b (minRR 0.5): `WOULD_BUY FM fade
  BUY score=62 R=0.63 risk=OK vol=0.44` — FromFM proven live.

## 9. Phases 28–30 — Strategy Intents ✅ DONE (3 commits)

- Phase 28: `SETUP_FAILED_BO`/`STRAT_FAILED_BO` (registry `BuildFailedBO`,
  proxy geometry entry=level/stop=level+buf/obj=2ATR/score 55) + `FromFailedBO`
  + EA candidate append + dispatch + catalog section.
- Phase 29: `FromPullback`/`FromBreakout` (firm/provisional semantics) + EA
  dispatch + catalog sections + full type-map tests.
- Phase 30: `FromReversal`/`FromDouble` + dispatch completion + catalog.
- MT5 BACKTEST T-010 (H1 defaults): pass, census 528/481 +
  FAILED_BO=0 (no failed-BO outcome in window — path exists, unexercised).
  Intent distribution over 528 bars: WOULD_ ×125 (Double 111, Breakout 14),
  SKIP_LATE_ENTRY ×356, LOW_RR ×47. Observation (not a defect): pullback
  selections went 293/293 late — spot-checked stale levels left behind by
  the market (entry 1.16059, market already toward obj 1.15211); chase
  calibration (0.5×ATR, 5-bar hold) is Phase-34 tuning material.
- 0 errors throughout.

## 10. Phase 31 — AUTO + Conflict Resolution ✅ DONE (commit: this phase)

- Registry: `AutoTuning` + `ContextDir` + `AutoFinal` + `SelectAuto`
  (replaces score-max for AUTO only; SINGLE/MULTI keep Phase-22 rule).
  New `docs/TRADE_DECISION_SPECIFICATION.md` (pipeline, AUTO formula with
  worked §10 example, veto table, NO-TRADE doctrine).
- EA: AUTO branch (logs `final=`), all-mode Phase-8 structural veto
  (`DECISION_VETO_*`: barbwire/mid-range/conflict/no-edge/trap).
- Mirror: auto/conflict/veto suites — pass. Total UNIT TEST: ~120.
- MT5 BACKTEST T-011 (H1 window, 3 runs): AUTO 93 sel/86 riskOK/435 veto;
  SINGLE_PB 78/69/381 (+69 no-candidate); SINGLE_DBL 93/93/435.
  Veto reasons sampled: CONFLICT/MID_RANGE (context-driven, mode-independent;
  counts differ only via hasTrade coverage — verified consistent). EA is now
  highly selective (82% veto in this choppy window) — calibration, Phase 34.
  Order-level AUTO-vs-single comparison needs execution (honest gap).

## 11. Phase 32 — Trade Explanation ✅ DONE (commit: this phase)

- New `MQL5/Include/FM/TradeExplanation.mqh`: `TradeExplanation` record +
  `CTradeExplainer::Build/RenderText` (engine-data-only; FM signal quality =
  ScoreSignal, others N/A; alternates DISABLED_BY_MODE/veto/LOST_SELECTION).
  New `docs/TRADE_EXPLANATION.md` (§36 map; modify/close reasons Phase 34).
- Mirror: alternate-classification suites — pass. Total UNIT TEST: ~125.
- MT5 BACKTEST T-012: pass, census identical to T-011 (86/435), 10 EXPLAIN
  blocks with alternates verified in log, 0 errors.

## 12. Phase 33 — Safety + Modes ✅ DONE (commit: this phase)

- `SafetyManager.mqh`: ANALYSIS_ONLY/PAPER/DEMO/LIVE (default safest);
  DEMO refuses real accounts, LIVE needs real account + `TRADE_LIVE` token;
  latching halts (emergency/drawdown/daily-loss), session pause, close-on-halt.
- `PaperTrader.mqh`: virtual fills, per-bar OHLC settle (SL-first),
  R accounting, summary. New `RISK_MANAGEMENT.md`, `EA_USER_GUIDE.md`.
- Mirror: `tests/safety.py` + `tests/test_safety.py` — pass.
  Total UNIT TEST: ~130.
- MT5 BACKTEST T-013 (PAPER, H1): pass; 10 PAPER_OPEN/10 PAPER_CLOSE
  (6/4, +3605.51, avgR 3.61 — objectives, not a profit claim), 0 real orders
  (`EXEC_` ×0), tester `acctTradeMode=0` (DEMO class → DEMO baselines
  permitted in Phase 34), 0 errors.

## 13. Phase 34 — MT5 Baseline Testing ✅ DONE (commit: this phase)

- First REAL order flow: EXEC_DONE ×3 (+EXEC_INVALID_STOPS ×3 on
  SELL-doubles — stop-level at send time, under review), closed-deal scan
  fed risk accounting (`closed profit=` lines), BE path armed.
- `reports/` created: T-014/15/16 `.htm` + `README.md` summaries.
  Baselines (H1 window, defaults, DEMO): AUTO 3 trades 0/3 −353.49 PF 0.00;
  SINGLE_PB 0 trades (51 late + 18 prov-off, mechanism verified);
  SINGLE_DBL 4 trades 1/3 −37.44 PF 0.86. Weak choppy-window baselines are
  EXPECTED — they are the bar optimization must beat (IS+OOS).
- New `docs/BACKTESTING_GUIDE.md` (ini, record template, §17 fields) +
  `Presets/FM_EA_Auto_Baseline.set` v1 (123/123 params resolve-checked,
  ANALYSIS_ONLY default; DEMO override lives in tester ini only).

## 14. Phase 35 — Optimization Objective ✅ DONE (commit: this phase)

- `FM_EA::OnTester` custom criterion (PF/expectancy-R/activity/DD composite;
  no-trade = 0). New `docs/OPTIMIZATION_GUIDE.md` (tunable list, formula,
  genetic-then-grid procedure, plateau rule) + `docs/experiments/
  EXP-0000-template.md` (registry rules: OOS never tunes, spikes rejected).
- MT5 BACKTEST T-017 (AUTO DEMO rerun): `OnTester result -0.15118625`
  (losing baseline ranks below do-nothing — correct), census identical,
  0 errors.

## 15. Phase 36 — Parameter Robustness ✅ DONE (commit: this phase)

- `docs/experiments/EXP-0001` (chase × minRR 3×3, SINGLE_DBL H1, consec-cap
  understood mid-run and set 0 for measurement): minRR dead (all Rs ≥ 1.5),
  chase monotonic (no plateau), best cell 9 trades +811.78 PF 2.22.
  Verdict REJECT (noise-sized sample, IS-only). Confounder: consec-cap 3
  flips cell economics (capped −37.44 vs uncapped +541.16) — needs OOS study.
- 9 MT5 runs, 0 errors. Methodology (grid + plateau rule) proven.

## 16. Phases 37–39 — Forward / OOS / Walk-Forward ✅ DONE (3 commits)

- `docs/VALIDATION_METHODOLOGY.md` (IS/OOS/forward definitions, no-relabel
  rule, WF protocol). T-018 IS: 1 trade −99.00 PF 0.00. T-019 OOS: 5 trades
  2/5 +487.82 PF 2.26. Verdict: negative degradation but noise-sized;
  no overfit (nothing tuned), no edge demonstrated; OOS unchanged by results.
- WF demo with defaults (W1→F1 above): protocol ready, data too thin to
  promote anything. Reports `T-018*`, `T-019*` committed.
- Process lesson recorded: `[Tester]` keys must precede `[TesterInputs]`.

## 17. Phase 40 — Multi-Symbol Validation ✅ DONE (commit: this phase)

- T-020 XAUUSD H1 AUTO DEMO (same window/defaults): 502 bars, 10 trades
  5/5, +158.32, PF 1.33, exp +15.83, balDD 4.03%, eqDD 7.08%, veto 369.
- Comparison: EURUSD AUTO 3 trades −353.49 PF 0.00 vs XAUUSD 10 trades
  +158.32 PF 1.33. Different symbols behave differently (expected);
  NO per-symbol tuning applied (§25 — unjustified by this evidence).
  Report committed: `reports/T-020_XAUUSD-H1_AUTO_DEMO.htm`.

## 18. Phase 41 — Regime Analysis + Entry-Side Fix ✅ DONE (commit: this phase)

- `PaperTrader` carries entry regime (`ctx=` on OPEN/CLOSE). T-021 PAPER
  H1 (post-fix): 6 trades 2/4 +403.51 avgR 0.67 — TRADING_RANGE 2/4 +704.63,
  BULL_TREND 0/2 −226.16 (n=6: hypothesis-grade only, no claims).
- REAL BUG found via the table: fills could occur on the WRONG SIDE of the
  stop (SELL filled above its stop → inverted risk, phantom +R). Fixed with
  `GateSide` in all six `From*` builders (BUY needs price>stop, SELL
  price<stop) + mirror `side_ok` + 5 suites. 4 such fills blocked in-window.
- Re-ran all DEMO baselines post-fix (AUTO/PB/DBL): numbers IDENTICAL
  (fix only binds the 4 cases; send-time stop-level had covered DEMO).
  Baselines stand verified across rebuilds.
- Account note: terminal stays on real 15144344 (unfunded — live orders
  impossible; tester runs use simulated deposit and are unaffected).

## 19. Phase 42 — AUTO Validation ✅ DONE (commit: this phase)

- Order-level numbers: AUTO PF 0.00 (T-014) vs SINGLE_DBL PF 0.86 (T-016)
  vs SINGLE_PB no-trades (T-015); XAUUSD AUTO PF 1.33 (T-020); OOS AUTO
  PF 2.26 (T-019). Verdict in `TRADE_DECISION_SPECIFICATION.md` §6:
  no measured value yet (3–10 trades/arm); AUTO stays default for
  diversification logic only; re-validate at ≥30 trades/arm.

## 20. Phase 43 — Paper-Trading Readiness ✅ DONE (procedure ready)

- New `docs/PAPER_FORWARD.md` (attach procedure, 2-week acceptance, halt
  drill). Evidence banked: BE modify 5× DONE (XAUUSD); trail OFF-by-default
  (expected, unproven); halt/adopt/CloseAll code-complete, not live-fired.
- Execution needs GUI chart-attach + calendar time → NOT EXECUTED here.

## 21. Later (PLANNED)

Phase 44 live-readiness review (final gate).
