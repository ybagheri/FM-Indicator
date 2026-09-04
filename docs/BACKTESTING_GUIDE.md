# BACKTESTING GUIDE — how baselines are produced (Phase 34)

## 1. One-command baseline (this machine)

1. Deploy: copy `MQL5/Experts/FM_EA.mq5` + `MQL5/Include/FM/*.mqh` to the
   terminal data folder (see `docs/USER_GUIDE.md` §1 for the path).
2. Compile both `FM_Indicator.mq5` and `Experts/FM/FM_EA.mq5` (F7, 0/0).
3. Run: `terminal64.exe /config:<ini> /skipupdate` with an ini like below.
4. Collect: data-folder `<Report>[N].htm` → copy to `reports/T-*.htm`;
   agent log (`Tester/.../Agent-*/logs/`) for census/EXEC/EXPLAIN lines.

## 2. Baseline ini (T-014 reference)

```ini
[Tester]
Expert=FM\FM_EA
Symbol=EURUSD
Period=H1
Model=1
ExecutionMode=0
Optimization=0
FromDate=2025.11.03
ToDate=2025.12.03
ForwardMode=0
Deposit=10000
Currency=USD
ProfitInPips=1
Leverage=1:100
Report=FM_EA_baseline_AUTO
ReplaceReport=true
ShutdownTerminal=true
[TesterInputs]
InpTradeMode=2
```

Strategy variants append `InpStratMode=0` + `InpSingleStrategy=<1..6>`.
Default parameters ALWAYS first (§18); deviations are experiments
(`docs/experiments/`, Phase 35+).

## 3. What to record (§17, per run)

Git commit · EA version · strategy · symbol · TF · dates · deposit · spread
(broker-current unless fixed) · commission · model · parameters ·
trades · win rate · net · PF · expectancy · max DD · avg R (from report or
PAPER summary) · MFE/MAE (report charts) · consec losses. Template:
`reports/README.md`. No metric without a run; no run without a log.
