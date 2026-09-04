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

## 6. AUTO validation status (§27) — VERDICT: NO MEASURED VALUE YET (Phase 42)

Intent level, H1 window (T-011): AUTO 93 sel/86 riskOK · SINGLE_PB 78/69
(+69 no-candidate) · SINGLE_DBL 93/93.
Order level, same window: AUTO 3 trades −353.49 PF 0.00 (T-014) ·
SINGLE_PB 0 trades (T-015) · SINGLE_DBL 4 trades −37.44 PF 0.86 (T-016).
XAUUSD: AUTO 10 trades +158.32 PF 1.33 (T-020). OOS: AUTO 5 trades
+487.82 PF 2.26 (T-019).
Verdict: SINGLE_DBL beats AUTO on the EURUSD window; AUTO shows nothing
beyond mix-dilution. Samples (3–10 trades/arm) cannot support a superiority
claim either way. AUTO stays default for diversification logic, NOT for
performance. Re-validate with ≥30 trades/arm after the first ACCEPTED edge.
