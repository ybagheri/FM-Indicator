# ARCHITECTURE — FM Indicator v1

## 1. Layout

```
MQL5/Indicators/FM_Indicator.mq5      entry: inputs, buffers, OnCalculate routing
MQL5/Include/FM/
  Config.mqh        CFMConfig (all Inp*), presets, validation
  MarketData.mqh    CBar, CMarketData (MT5 series copy, closed-bar discipline)
  ATR.mqh           CATR (Wilder)
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
  → CATR.Update → CSwingDetector.Update (confirmed swings only)
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
- `CSwingDetector`: `AddBar()`; outputs `Swing{index, price, dir, confirmed_bar}`.
  Internal pending buffer of size k; never exposes unconfirmed.
- `CMeasuredMove : CMeasuredMoveBase` with subclasses
  `CLegEqualityMM` (v1) reserving `CRangeHeightMM`, `CChannelMM`, `CGapMM`.
- `CFMSetup`: `{id, family, dir, A0,A1,B0, target, state, created_bar,
  state_bar[3], alerted[3], context}` + `TransitionTo()` guard.
- `CFMEngine`: `Update(closed_bar)` loop over ≤ MaxActiveSetups, nearest-first
  eviction; owns id counter; exposes active list to visualizer/buffers.
- `CConfirmation`: stateless pure functions → unit-testable.
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

## 6. Extension points (no rewrite for v2)

New MM families subclass `CMeasuredMoveBase::Project()`; new confirmation
modes implement `IConfirmationRule`; context modes extend enum. EA reuse:
`#include <FM/FMEngine.mqh>` + read DATA buffers or call
`CFMEngine::Active()` — no chart code required.
