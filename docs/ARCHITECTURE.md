# ARCHITECTURE — FM Indicator v1.2 + v2 research

## 1. Layout

```
MQL5/Indicators/FM_Indicator.mq5      entry: inputs, buffers, OnCalculate routing
MQL5/Include/FM/
  Config.mqh        CFMConfig (all Inp*), presets, validation
  MarketData.mqh    CBar, CMarketData (MT5 series copy, closed-bar discipline)
  ATR.mqh           CATR (Wilder)
   BarAnalyzer.mqh   CBarAnalyzer (Phase 1: pure per-closed-bar features + Describe)
   PullbackPatterns.mqh CPullbackPatterns (Phase 2: TrendDir + H1/H2/L1/L2 + swing/micro doubles, read-only)
   MarketState.mqh   CMarketState (Phase 3: TREND/CHANNEL/RANGE/BOM scores + Describe, read-only)
   BreakoutEngine.mqh CBreakoutEngine (Phase 4: BO events + FOLLOW/FAILED + trap flag, read-only)
   ReversalEngine.mqh CExhaustionAnalyzer + CLegCounter + CMajorReversal (Phase 5: exhaustion + legs + MTR proxy, read-only)
  Swings.mqh        CSwingDetector (fractal-k, confirmed-only output)
  Context.mqh       CContextClassifier (Trend/Range/Transition + confidence)
  MeasuredMove.mqh  CLeg, CMeasuredMove (regular + inverse projection)
  FMEngine.mqh      CFMSetup, CFMEngine (state machine §6, alert-once, caps)
  Confirmation.mqh  CConfirmation (ExhaustionAny + SignalBar + follow-through)
  Visualizer.mqh    CVisualizer (object lifecycle FM_<id>_*)
  Alerts.mqh        CAlertManager (popup/sound/push/email, per-state, throttled)
  Logger.mqh        CLogger (OFF/ERROR/INFO/DEBUG)
Include/FM/ expected under MQL5/Include/FM/ on user terminal.
tests/fm_engine.py   Python 1:1 mirror of spec (oracle for TESTING.md)
tests/test_*.py      synthetic + anti-repaint suites
docs/*.md            RESEARCH / SPEC / ARCH / TESTING / ROADMAP
```

## 2. Data flow (per OnCalculate)

```
rates[] → CMarketData.Refresh (new-bar detect, freeze closes)
   → CATR.Update → CBarAnalyzer.Analyze (Phase 1 read-only DEBUG log)
   → CPullbackPatterns (Phase 2 read-only DEBUG log: TrendDir + H1/H2/L1/L2 + doubles)
   → CMarketState.Analyze (Phase 3 read-only DEBUG log: 6 state scores/pcts)
   → CBreakoutEngine.Analyze (Phase 4 read-only DEBUG log when found)
   → CExhaustionAnalyzer/CLegCounter/CMajorReversal (Phase 5 read-only DEBUG log when found)
   → CSwingDetector.Update (confirmed swings only)
  → CMeasuredMove.Project (legs → projections, inverse if enabled)
  → CContextClassifier.Update → CConfirmation.Evaluate
  → CFMEngine.Update (transitions, alert-once set, expiry)
  → Buffers.Write (DATA buffers on closed-bar index only)
  → CVisualizer.Sync (create/move/delete objects) → CAlertManager.Dispatch
```

Tick with no new closed bar: only optional intrabar POTENTIAL preview
(bar 0) + object price nudge; never DEVELOPING/CONFIRMED.

## 3. Key classes

- `CFMConfig`: plain struct + `Validate()` clamping nonsense (e.g. Min>Max).
- `CMarketData`: owns copied `MqlRates[]`, exposes `Closed(i)` with
  `i>=1` mapping; `LastClosed()`; `IsNewBar()`.
- `CBarAnalyzer`: static pure `Analyze(rates,count,shift,atr,cfg)→BarFeatures`
  + `Describe()` evidence string; no state, no future bars (Phase 1, read-only).
- `CPullbackPatterns`: static pure `TrendDir` (EMA20/50 gap gate) +
  `DetectBull/DetectBear` (H1/H2/L1/L2, most-advanced-wins) +
  `FindDoubleTop/FindDoubleBottom` (confirmed swings, most-recent wins) +
  `MicroDoubleTop/MicroDoubleBottom` (raw extremes, halved trough) +
  `DescribePB/DescribeDouble`; no state, no future bars (Phase 2, read-only).
- `CMarketState`: static pure `Analyze(rates,count,shift,atr,cfg)→MarketState`
  (trend/range/chop/pressure/tight evidences → six unit-weight raws →
  largest-remainder pcts + argmax winner + weak-floor TRANSITION) +
  `Describe()`; reuses `TrendGap` + `PairOverlap` + `WindowStats` (one
  predicate source each); v1 `CContextClassifier` untouched (Phase 3, read-only).
- `CBreakoutEngine`: static pure `EventAt` (N-bar + swing refs, swing tie-break)
  + `Analyze` (most-recent event in FollowBars → PENDING/FOLLOW/FAILED with
  FAILED precedence + second-leg `trapArmed` scan) + `Describe()`; v1
  `CInverseMMHelper` untouched, no targets emitted (Phase 4, read-only).
- `CExhaustionAnalyzer` + `CLegCounter` + `CMajorReversal`: static pure
  `Report` (SPEC-§8 five predicates, backward push/wedge runs so the live
  bar is covered) + `CountBull/CountBear` (successive countertrend swings,
  depth/deep flag) + `Analyze` (EMA-cross + retest + Phase-4 FOLLOW +
  pressure → MINOR/MAJOR, unit weights) + `Describe()`s; v1
  `CConfirmation` untouched (Phase 5, read-only).
- `CSwingDetector`: `AddBar()`; outputs `Swing{index, price, dir, confirmed_bar}`.
  Internal pending buffer of size k; never exposes unconfirmed.
- `CMeasuredMove : CMeasuredMoveBase` with subclasses
  `CLegEqualityMM` (v1) + `CRangeHeightMM` (static, v1.2), `CChannelMM` (v1.2),
  `CGapMM` (static, v1.2). Dedup key `(b0.bar, dir, family, target)`.
- `CFMSetup`: `{id, family, dir, A0,A1,B0, target, state, created_bar,
  state_bar[3], alerted[3], context}` + `TransitionTo()` guard.
- `CFMEngine`: `Update(closed_bar)` loop over ≤ MaxActiveSetups, nearest-first
  eviction; owns id counter; exposes active list to visualizer/buffers.
- `CConfirmation`: stateless pure functions → unit-testable.
  v1.1: `IsSignalBar` accepts newest closed bar; delayed follow-through path.
  v1.2: `PushCount`/`IsWedge` first-class, `ExhaustionAnyCfg(minPushes,useWedge)`,
  `ScoreSignal` 0–100 display-only.
- `CVisualizer`: `Sync(setups)` diffs desired vs. existing `FM_*` objects.
- `CAlertManager`: `Fire(id, state, text)` with sent-set + bar throttle.
- `CLogger`: level-gated `PrintFormat`, retrospective gap labels only at DEBUG.

## 4. State machine

`PROJECTED → POTENTIAL → DEVELOPING → CONFIRMED → COMPLETED`
with `→ INVALIDATED` from any state. Transitions per SPEC §6, evaluated in
that order once per closed bar so a setup can advance at most one state per
bar (prevents same-bar POTENTIAL→CONFIRMED jumps that would hide history).

## 5. Buffer / object lifecycle

- DATA buffers set only at the issuing closed-bar shift; never rewritten
  when later bars arrive (freeze). `PLOT_DRAW_BEGIN` skips warmup.
- Objects: created at PROJECTED (LEG/PB/TGT), ZONE added at POTENTIAL,
  LABEL updated at each transition, all deleted at INVALIDATED/COMPLETED
  expiry or `OnDeinit`/symbol-timeframe change (`ObjectsDeleteAll("FM_")`).

## 6. Extension points (v1.2/v2 implemented; v3 reserved)

v1.2 families subclass `CMeasuredMoveBase::Project()` (range/gap as static
`Project(rates,count,bar,…)` since they scan bars, not swing triples);
confirmation modes extend `CConfirmation`; context modes extend enum. v2:
`MTFBias()` + `ExportSignalRow()` in the indicator (read-only/export only),
`backtest_run`/`mae_mfe`/`export_signals_csv`/`mtf_bias` in the Python mirror.
EA reuse: `#include <FM/FMEngine.mqh>` + read DATA buffers or call
`CFMEngine::ActiveSnapshots()` — no chart code required. v3 (separate repo):
execution EA + optimization/walk-forward framework.
