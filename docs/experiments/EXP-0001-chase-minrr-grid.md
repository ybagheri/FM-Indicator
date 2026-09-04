# EXP-0001 — chase × minRR robustness on SINGLE_DOUBLE (Phase 36)

```text
Experiment ID: EXP-0001
Date: 2026-09-04
Git Commit: (Phase-36 HEAD)
EA Version: FM_EA 1.00
Strategy / Mode: SINGLE_DOUBLE
Symbol / Timeframe: EURUSD / H1
IS Range: 2025.11.03–12.03 (same window as baselines; OOS split is Phase 38)
Parameters: InpChaseATRMult {0.25,0.50,1.00} x InpRiskMinRR {0.5,1.0,1.5}
Optimization Range: manual grid (9 cells; genetic overkill for 2 params)
Optimization Criterion: OnTester composite (Phase 35)
```

## Results (MT5 BACKTEST, Model 1, $10k, broker spread, no commission)

Design correction mid-run: first attempt with `InpMaxConsecLoss=3`
saturated (CONSEC_LOSSES ×106 — freeze working as designed, masking param
effects). Grid re-ran with the cap at 0 for clean measurement; production
default stays 3.

| chase \ minRR | 0.5 | 1.0 | 1.5 |
|---|---|---|---|
| 0.25 | 5 / −116.89 / PF 0.66 | identical | identical |
| 0.50 | 6 / +541.16 / PF 2.49 | identical (≡ cell 5) | identical |
| 1.00 | 9 / +811.78 / PF 2.22 | identical | identical |

Cells: (trades / net / PF). 9 × H1 runs, 0 runtime errors throughout.

## Robustness

- Optimal value: chase 1.00 by net (+811.78), 0.50 by PF (2.49).
- Robust range: NONE demonstrated — net rises monotonically with looser
  chase (no plateau), minRR is dead (all double Rs ≥ 1.5 on this window).
- Sensitivity: chase dominates; minRR insensitive here — drop from tuning
  list until a window with sub-1.5R setups appears.
- Confounder found: consec-cap 3 flips cell-5 economics (T-016 capped:
  4 trades −37.44; uncapped: 6 trades +541.16). Freezelevel itself needs
  OOS study (Phase 38), not a grid tweak.

## Decision: REJECT
## Reason: 6–9 trades per cell is noise, no plateau, IS-only single window.
Nothing here justifies changing defaults. Value = methodology proven +
consec-cap finding. OOS verdict in Phase 38.
