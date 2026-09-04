# PAPER FORWARD TEST PLAN — observation only (no tuning, no logic changes)

> Status: PLAN. The test itself is NOT started. Purpose is evidence
> collection, NOT optimization. Findings feed experiments, never direct edits.

## 1. Exact PAPER configuration

- Commit/version: `697d5b3` (EXP-0002 apparatus, veto flag default ON) /
  FM_EA v1.00 + FM_Indicator v1.30. Any rebuild invalidates comparability.
- EA mode: `TRADE_PAPER` (`InpTradeMode=1`). ANALYSIS_ONLY for the first
  48h is acceptable only as a logging shakedown, then PAPER.
- Strategy mode: AUTO (`InpStratMode=2`), all six `InpUse*` true.
- Analysis inputs: Balanced SPEC §1 verbatim (`Inputs.mqh` defaults).
- Symbols/timeframes: EURUSD H1 primary; XAUUSD H1 mirror optional
  (same build, separate log archive).
- Session: `InpSessionStartH=0` / `InpSessionEndH=24` (always open).
- Risk: 1% equity (`InpLotMode=1`), minRR 1.0, spread cap 50pt,
  5 trades/day, 1 open, 1/symbol, 3 consec losses, BE 300/20pt on,
  trailing off, slippage 10pt. Magic 20260904, history 1500.
- Vetoes: `InpApplyStructuralVeto=true` (production), provisional OFF,
  chase 0.50 ATR, hold 5 bars, AUTO tuning 10/5/5/2.0.
- Safety: DD halt 20%, daily-loss cap off (0.0), emergency off,
  close-on-halt off, live token empty.

## 2. Frozen during PAPER

Parameters, strategy rules, veto structure/thresholds, entry/stop/target
geometry, AUTO selection, scoring, permits, sizing, modes, presets.
Only `InpLogLevel` may move (DEBUG first 48h, then INFO) — logging only.

## 3. Measured (per bar/day/week from Experts log + paper ledger)

Bars analyzed; candidates; selections by strategy; veto counts by reason
(MID_RANGE/CONFLICT/TRAP_REPEAT/BARBWIRE/NO_EDGE); fills/triggers;
virtual opens/closes with entry/stop/objective; planned R vs realized R;
MFE/MAE where the ledger supports it (SL-first OHLC settle; intrabar
excursion unknowable — state the bound); W/L; expectancy; paper equity;
EXPLAIN blocks; rejected candidates + reasons (DISABLED/LOST/veto/chase/
RR/provisional/side); AUTO `final=` vs runner-up gap; regime (ctx) of
every open/close.

## 4. Hypotheses under observation (NOT to be forced true)

- H1: veto protective in trend conditions (EXP-0002 OOS: TREAT 0/3 in trend).
- H2: veto suppresses range opportunities (EXP-0002: 435 bypassed bars).
- H3: planned-R weakly/inversely predictive (treatment fills: 13.6R lost,
  1.26R won) and possibly regime-dependent.
- H4: AUTO vs singles unresolved (T-011 intent only; order-level pending).
- H5: PULLBACK stays fill-dead by design (oldest-match + chase; sig age logged).
Counter-evidence counts fully: any hypothesis failing in PAPER is weakened,
none is confirmed by PAPER alone (sample + single regime window).

## 5. Success/failure criteria (operational, profit is NOT one)

- Coverage: 10+ trading days, 200+ H1 bars, zero log gaps over 1h unexplained.
- Health: 0 runtime errors; 100% bars analyzed; veto mix within 15pts of
  T-011 shares (CONFLICT ~62 / MID_RANGE ~19 / TRAP ~1 of vetoes) else
  regime-shift note; no `EXEC_`, no real orders/positions.
- Triggers: WOULD_/SKIP_ reasons parseable every bar; EXPLAIN per intent.
- Failure (abort, report, don't tweak): any real order; mode leaves
  PAPER/ANALYSIS_ONLY; halt latch without cause; feed gaps; error spam.

## 6. Mandatory safety rules (abort = invalid run)

Any real order sent; any `EXEC_` action; mode not PAPER/ANALYSIS_ONLY;
unexpected position/order activity; runtime errors compromising observation;
data/feed integrity compromised. On abort: detach EA, preserve logs intact,
file incident note, do NOT edit code to "fix forward" inside the window.

## 7. Reporting (traceability per observation)

Final PAPER report contains: commit hash + EA/indicator versions; full
input set (exported `.set` at start AND end, diffed); symbol/TF;
date range with server-timezone note; environment (live-paper vs tester);
all section-3 tables; regime split; hypothesis scoreboard (H1–H5:
supported/weakened/unresolved with counts); incident log (or "none").
Every table row traces to a dated log line or ledger entry.

## 8. Decision tree after PAPER

A. Evidence insufficient -> extend observation (more data, same config).
B. Concrete defect (reproducible, spec-violating) -> fix + re-test in tester
   before any further forward run.
C. Strong hypothesis support -> design a CONTROLLED experiment (new EXP doc,
   A/B, pre-registered verdict rule). Never direct edits.
D. Poor strategy performance with adequate sample -> strategy-logic
   investigation phase (hypothesis first, per project rule 29).
E. Useful AUTO selection with adequate sample -> dedicated AUTO experiment
   (>=30 trades/arm).
F. Safety/technical failure -> fix, re-prove in tester, restart PAPER clock.
No parameter changes prescribed in advance, whatever the outcome.
