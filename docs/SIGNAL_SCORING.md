# SIGNAL SCORING — context / setup / signal scores (normative)

> Companion to `SYSTEMATIC_SPECIFICATION.md` (§7–§8), `MARKET_STATE.md`,
> `SETUP_ENGINE.md`, `GENERAL_SETUPS.md`, `DECISION_ENGINE.md`. Scores are
> CONTEXT / CONFIDENCE SCORES (0–100), never probabilities (§26 master).
> No profitability claims, no calibration claims.

## 1. Principles

- Every score is explainable: published with the additive inputs that
  produced it. No "AI magic".
- Scores are DISPLAY + CONTEST inputs only in default `LOG_ONLY` mode. Only
  Phase-8 `Decide` consumes a score as a veto (`InpMinDecisionScore=40`);
  nothing gates the FM state machine.
- Zero ATR → score 0, never crash. Deterministic: identical inputs →
  identical scores.

## 2. Market-state scores (Phase 3, `MarketState.mqh`)

Six unit-weight raws (trend/range/chop/pressure/tight + lean) → largest-
remainder percents summing to 100 (`pctBullTrend/pctBearTrend/pctBullChannel/
pctBearChannel/pctRange/pctBreakout`) + argmax winner + weak-floor
TRANSITION (all raws <1.0). Formula + evidences in `MARKET_STATE.md` §2–§3
and `Describe()`. Used by Phase 8 conflict rule (top-two gap
`InpDecisionConflictPpts=10`).

## 3. Signal score `ScoreSignal` (v1.2, `Confirmation.mqh`, display-only)

0–100: body 0–20, adverse-wick 0–15, close position 0–15, engulf +10 (or +5
neutral credit when not required), follow-through shape +5/+5, exhaustion
breadth 0–20 (climax/stall/pushes≥2/wedge), context confidence 0–10,
distance-to-target 0–10 (center → full, ≥0.5 ATR → 0). Shown as `S=` in
labels when `InpShowScore`. Never auto-trades.

## 4. Setup scores (Phases 6–7)

- FM plans: reuse `ScoreSignal` at contest time (Phase-7 hook).
- General catalog (`GeneralSetups.mqh`): pullback H2 firm 70 / H1
  provisional 40; swing double firm 60 / micro provisional 30; breakout
  FOLLOW firm 70 (trap penalty → 50) / PENDING provisional 40 / FAILED
  silent; reversal MAJOR firm 80 / MINOR provisional 40. `SelectBest` =
  max score, type-order tie-break. R flag `rrOK` (`R >= InpSetupMinRR`)
  is report-only except Phase-8 RR veto.

## 5. Decision threshold (Phase 8)

`Decide` veto order (§3 `DECISION_ENGINE.md`): DISABLED → NO_SETUP →
BARBWIRE → MID_RANGE → CONFLICT → NO_EDGE → LOW_SCORE (<40) → LOW_RR →
LATE_ENTRY → TRAP_REPEAT → BUY/SELL. Score veto emits WAIT (not NO_TRADE).

## 6. What scores are NOT

Not win rates, not expectancies, not calibrated probabilities. Statistical
calibration (win rate / expectancy / precision / recall / R-distribution) is
future work gated on walk-forward CSV data — see `VALIDATION.md`. Until
then the label is always "Score", never "Probability".

## 7. Tests

Score bounds (good bar ≥50, zero ATR → 0), general selection (max wins,
ties ordered), decision boundary (40 earns direction), determinism. Suites
in `test_fm.py` #14, `test_general.py`, `test_decision.py`. All pass.
