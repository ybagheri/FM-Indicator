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

## 4. Phase 23 — EA Skeleton (PLANNED, ANALYSIS_ONLY first)

EA adapter calls `CFMAnalysis::Update` per new closed bar, attaches strategy
+ explanation records, makes BUY/SELL/WAIT/NO_TRADE decisions — places NO
orders until Phases 24–26 (risk/execution/positions) land and baselines pass.

## 5. Later (PLANNED)

Phases 24–26 risk/execution/position layers; 27–30 strategy wiring;
31 AUTO + conflict resolution; 32 explanation; 33 safety + modes;
34+ baselines/optimization/OOS/walk-forward per strategy. Each phase:
implement → compile → unit tests → MT5 test → inspect → document →
commit → push.
