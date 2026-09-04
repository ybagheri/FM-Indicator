# OPTIMIZATION GUIDE — objective, parameters, robustness (§19–21, Ph.35–36)

## 1. What may be optimized (and what may not)

Genuinely-tunable numerics ONLY: `InpChaseATRMult`, `InpMinDecisionScore`,
`InpDecisionConflictPpts`, `InpMMToleranceATRMult`, `InpMaxOvershootATRMult`,
`InpSetupStopBufATRMult`, `InpRiskMinRR`, `InpAutoTrendBonus/ProvPenalty/
RRBonus/RRLevel`, `InpMaxHoldBars`. NEVER: strategy logic, veto structure,
score formulas, family definitions (§29: logic changes are separate phases
with hypothesis + OOS validation).

## 2. Custom criterion (`OnTester`, Phase 35)

```text
score = 0.35·min(PF,3)/3 + 0.25·clip(expR,−2,2)/2 + 0.15·min(deals,50)/50
        − 0.25·min(balDD%,20)/20
```

`expR` = tester expected payoff / mean entry risk (entry→SL via
`OrderCalcProfit` on IN deals, own magic). No-trade runs score 0 (never
optimal). Rationale: PF quality + per-risk expectancy + activity floor +
drawdown brake. Net profit alone is explicitly NOT the objective.

## 3. How to run (genetic, then grid around the peak)

```ini
[Tester]
Expert=FM\FM_EA
...
Optimization=1
OptimizationCriterion=6   ; custom (OnTester value)
```

TesterInputs ranges use `start||step||stop` syntax, e.g.
`InpChaseATRMult=0.50||0.25||0.25||1.00`. Keep ≤2–3 params per experiment;
record everything in `docs/experiments/EXP-*.md`.

## 4. Robustness rule (Phase 36)

Never take an isolated peak. Report optimal value + robust range (neighbors
within 10% of peak score) + sensitivity (score slope per step). Prefer the
plateau center over the spike. A spike with dead neighbors = REJECT.
