# MT5 TESTING STATUS — real tester runs on record (no invented results)

> Rule: every entry states EA/Indicator version, git commit, symbol, TF, date
> range, model, spread, commission, balance, parameters, result. Anything not
> executed is marked NOT TESTED. UNIT TEST results are never presented as
> MT5 BACKTEST results.

## Environment

- Terminal: Alpari MT5_2, build 6090, account 15144344 (Alpari-MT5 hedge).
- Data folder: `...Terminal\AF19ECCF568F855DF9D3196BBF8BF315`
  (origin.txt verified `C:\Program Files\Alpari MT5_2`).
- Indicator build: v1.30 + `eeabb48` fix, MetaEditor 0 errors / 0 warnings.
  Repo↔terminal SHA256 identical (21 files, verified 2026-09-04).
- Test driver: `FM_SmokeTest.mq5` v1.00 (terminal-only, NOT in repo).
  `iCustom(_Symbol,_Period,"FM_Indicator")` with ALL DEFAULTS (Balanced,
  `InpLogLevel=INFO`), reads DATA buffers 0–3 at shift 1 per new bar,
  prints edge events + final SUMMARY. Places NO orders.

## Run T-001 — MT5 BACKTEST (smoke) ✅ PASS

```text
Git commit:      eeabb48 (engine) — docs-only delta to 7009511
EA version:      FM_SmokeTest 1.00 / Indicator v1.30+eeabb48
Symbol:          EURUSD
Timeframe:       H1
Date range:      2025.11.03 – 2025.12.03
Model:           1 (1-minute OHLC)
Spread:          broker current at run time (not fixed)
Commission:      none
Initial balance: 10000 USD, 1:100
Parameters:      all defaults (Balanced)
Result:          Test passed in 0:00:01 (124811 ticks, 528 bars)
Reads:           528/528 bars (100%)
Edges:           target 528 / POTENTIAL 91 / DEVELOPING 11 / CONFIRMED 5
Runtime errors:  0 | Warnings: 0
Trades:          0 (by design) → win rate / PF / drawdown: N/A
```

## Run T-002 — MT5 BACKTEST (smoke, noisy TF) ✅ PASS

```text
Git commit:      eeabb48 (engine)
EA version:      FM_SmokeTest 1.00 / Indicator v1.30+eeabb48
Symbol:          EURUSD
Timeframe:       M1
Date range:      2025.11.10 – 2025.11.13
Model:           1 (1-minute OHLC)
Spread:          broker current (not fixed)
Commission:      none
Initial balance: 10000 USD, 1:100
Parameters:      all defaults (Balanced; NOT the M1-Scalp preset)
Result:          Test passed in 0:11:36 (17035 ticks, 4260 bars)
Reads:           4260/4260 bars (100%)
Edges:           target 4138 / POTENTIAL 912 / DEVELOPING 177 / CONFIRMED 43
Runtime errors:  0 (agent log error-pattern scan: 0 hits)
Alerts:          FM POTENTIAL/CONFIRMED Alert: lines present (alert path live)
Trades:          0 (by design) → win rate / PF / drawdown: N/A
```

## What the runs prove / do NOT prove

- Prove: indicator loads in tester, calculates every bar on H1+M1, buffers
  EA-readable at 100%, alert path fires, zero runtime errors.
- Do NOT prove: visual correctness, no-repaint vs history, signal quality,
  profitability, preset suitability (M1 ran Balanced, not M1-Scalp).

## NOT TESTED (explicit)

Visual-mode chart inspection · repaint/history-diff comparison · CSV export
walk-forward · calibration · optimization · multi-symbol/TF comparison ·
Phase 1–8 DEBUG-log content in tester (runs used INFO) · any live/demo/paper
trading · any EA that places orders (none exists yet).

## Log locations (machine-local, not in repo)

- Agent logs: `...\Tester\AF19ECCF...\Agent-127.0.0.1-3000\logs\20260904.log`
  (T-001) and `...\Agent-127.0.0.1-3001\logs\20260904.log` (T-002).
- Terminal journal: `...\Terminal\AF19ECCF...\logs\20260904.log`.
