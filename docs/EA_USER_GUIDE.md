# EA USER GUIDE — modes, inputs, presets, safe operation (Phase 33)

> Practical companion to `EA_ARCHITECTURE.md`, `RISK_MANAGEMENT.md`,
> `TRADE_DECISION_SPECIFICATION.md`. No profitability claims.

## 1. Trading modes (`InpTradeMode`, default ANALYSIS_ONLY)

| Mode | Orders | Use |
|---|---|---|
| ANALYSIS_ONLY | never | research, selection census, EXPLAIN logs |
| PAPER | never (virtual) | forward-simulation, equity curve without risk |
| DEMO | yes, non-real accounts only | baselines, optimization, forward tests |
| LIVE | yes, real account + `InpLiveToken=TRADE_LIVE` | live only after Phase 44 review |

The EA logs `mode=` + `acctTradeMode=` at init — verify before trusting a run.

## 2. Strategy selection

`InpStratMode` SINGLE (one `InpSingleStrategy`) / MULTI (checkboxes incl.
`InpUseFailedBO`) / AUTO (SelectAuto + vetoes). Provisional setups need
`InpTradeProvisional=true`. Intent gates: chase (`InpChaseATRMult` 0.5),
hold (`InpMaxHoldBars` 5).

## 3. Safety

`InpEmergencyStop` halts now; `InpMaxDrawdownPct` (20) and `InpMaxDailyLoss`
latch; session hours pause (no latch); `InpCloseOnHalt` closes all on halt.
Halt reason is logged (`HALT ...`). Latches clear on EA reload.

## 4. Presets (`Presets/`, versioned per §30)

`FM_EA_Auto_Baseline.set` (Phase 34) — always keep a blessed baseline;
never overwrite validated presets, version the filename.

## 5. Reading the log

Per bar: selection + `risk=REASON vol=` + intent (`WOULD_`/`SKIP_`) +
`EXPLAIN` block; PAPER opens/closes; vetoes (`DECISION_VETO_*`);
`done` census + `PAPER ...` summary at end.
