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

## 6. Later (PLANNED)

Phases 25–26 execution/position layers; 27–30 strategy wiring;
31 AUTO + conflict resolution; 32 explanation; 33 safety + modes;
34+ baselines/optimization/OOS/walk-forward per strategy. Each phase:
implement → compile → unit tests → MT5 test → inspect → document →
commit → push.
