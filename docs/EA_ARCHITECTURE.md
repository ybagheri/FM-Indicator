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

## 10. Later (PLANNED)

Phase 31 AUTO + conflict resolution; 32 explanation; 33 safety + modes;
31 AUTO + conflict resolution; 32 explanation; 33 safety + modes; 31 AUTO + conflict resolution; 32 explanation;
33 safety + modes; 34+ baselines/optimization/OOS/walk-forward per strategy.
Each phase: implement → compile → unit tests → MT5 test → inspect →
document → commit → push.
