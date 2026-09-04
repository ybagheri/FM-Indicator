# TRADE DECISION SPECIFICATION — selection, AUTO conflicts, vetoes (Phase 31)

> Normative for the EA decision path. Deterministic: identical
> `FMAnalysisResult` + config → identical selection. No ML, no fitted
> weights. Scores stay scores.

## 1. Pipeline (per new closed bar, EA `OnTick`)

```text
CFMAnalysis::Update → BuildCandidates (+BuildFailedBO)
  → SINGLE: Select | MULTI: Select | AUTO: SelectAuto
  → Phase-8 structural veto (all modes)
  → risk Check → intent builder (FromFM/FailedBO/Pullback/Breakout/Reversal/Double)
  → (Phase 33:) execution gate by trading mode
```

## 2. SINGLE / MULTI (Phase-22 rule, unchanged)

Max setup score among enabled+valid; ties: firm > provisional, lower
strategy enum, lower entry. Empty → NO TRADE.

## 3. AUTO (Phase 31, replaces score-max for AUTO only)

Final = score + alignment(±trendBonus vs state-winner direction; RANGE/
TRANSITION/BREAKOUT_MODE/UNKNOWN = neutral) − provPenalty (provisional) +
rrBonus (rMult ≥ rrLevel). Defaults: 10/5/5/2.0 (`InpAuto*`).
Max final wins; same tie-breaks as §2. Worked §10 example: PULLBACK BUY 84
vs FM SELL 41 in bull context → 94 vs 31 → Pullback BUY ("strong bull
context + high-quality pullback + favorable location + acceptable R:R").

## 4. Structural vetoes (EA, all modes)

Phase-8 reasons BARBWIRE / MID_RANGE / CONFLICT / NO_EDGE / TRAP_REPEAT →
`DECISION_VETO_<reason>`, selection discarded before risk. Score/RR/late
vetoes live natively (risk Check + chase guard) and are NOT duplicated here.

## 5. NO-TRADE doctrine (EA path)

NO TRADE whenever: no candidates · veto (§4) · risk veto (LOW_RR etc.) ·
intent skip (PROVISIONAL_OFF / LATE_ENTRY / STALE). Every skip logs its
machine-checkable reason. AUTO may always answer NO TRADE — it never means
"trade everything".

## 6. AUTO validation status (§27, intent level — no orders yet)

T-011 (H1 window): AUTO vs SINGLE_* intent census compared (see
MT5_TESTING_STATUS). Order-level PF/expectancy/drawdown comparison requires
Phase 33 execution + Phase 34 baselines — NOT YET (honest).
