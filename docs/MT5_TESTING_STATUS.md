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

## Run T-005 — MT5 BACKTEST (EA skeleton, ANALYSIS_ONLY) ✅ PASS

```text
Git commit:      Phase-23 HEAD (FM_EA v1.00, engine aa60515 + shared inputs)
EA version:      FM_EA 1.00 / Indicator v1.30 (adapter)
Symbol:          EURUSD
Timeframe:       H1
Date range:      2025.11.03 – 2025.12.03
Model:           1 (1-minute OHLC)
Spread:          broker current (not fixed)
Commission:      none
Initial balance: 10000 USD, 1:100
Parameters:      all defaults, mode=AUTO, all strategies enabled
Result:          Test passed in 0:00:00 (124811 ticks, 528 bars)
Bars analyzed:   528; selections FM_FADE=1 / PULLBACK=293 / BREAKOUT=14 /
                 REVERSAL_MTR=0 / DOUBLE=220
Runtime errors:  0
Trades:          0 (no order code exists yet) → trading metrics N/A
```

## Run T-006 — MT5 BACKTEST (EA + risk layer, still no orders) ✅ PASS

```text
Git commit:      Phase-24 HEAD (RiskManager + EA wiring)
EA version:      FM_EA 1.00 / risk defaults (1% equity, minRR 1.0, maxSpread 50pt)
Symbol/TF/Dates/Model/Balance: same as T-005
Result:          Test passed (124811 ticks, 528 bars)
Selections:      identical to T-005 (1/293/14/0/220 — analysis untouched)
Risk:            OK=481 / LOW_RR=47
Runtime errors:  0
Trades:          0 (no order code yet) → trading metrics N/A
```

## Run T-007 — MT5 BACKTEST (EA + dormant execution layer) ✅ PASS

```text
Git commit:      Phase-25 HEAD (ExecutionEngine constructed, never called)
EA version:      FM_EA 1.00
Symbol/TF/Dates/Model/Balance: same as T-005/T-006
Result:          Test passed (124811 ticks, 528 bars)
Census:          byte-identical to T-006 (bars=528 riskOK=481, 1/293/14/0/220)
Runtime errors:  0
Trades:          0 (execution dormant) → trading metrics N/A
```

## Run T-008 — MT5 BACKTEST (EA + positions layer, still no orders) ✅ PASS

```text
Git commit:      Phase-26 HEAD (PositionManager wired: BE/trail/deal-scan)
EA version:      FM_EA 1.00
Symbol/TF/Dates/Model/Balance: same as T-005/T-006/T-007
Result:          Test passed (124811 ticks, 528 bars)
Census:          byte-identical (bars=528 riskOK=481, 1/293/14/0/220)
Runtime errors:  0
Trades:          0 → trading metrics N/A; modify/close paths not yet exercised
```

## Run T-009 / T-009b — MT5 BACKTEST (EA + FM intent) ✅ PASS

```text
Git commit:      Phase-27 HEAD (TradeIntent + FromFM + EA intent logging)
EA version:      FM_EA 1.00
Symbol/TF/Dates/Model/Balance: same H1 window as T-005
T-009 defaults:  pass, census identical; FM selection held at LOW_RR (correct)
T-009b minRR 0.5: pass; live line WOULD_BUY FM fade BUY score=62 R=0.63
                 risk=OK vol=0.44 (FromFM proven end-to-end)
Runtime errors:  0
Trades:          0 (no order code yet) → trading metrics N/A
```

## Run T-010 — MT5 BACKTEST (EA, all six intents) ✅ PASS

```text
Git commit:      Phase-30 HEAD (all From* builders + dispatch)
EA version:      FM_EA 1.00, defaults (AUTO, provisional OFF)
Symbol/TF/Dates/Model/Balance: same H1 window
Result:          Test passed (124811 ticks, 528 bars)
Census:          bars=528 riskOK=481; FM_FADE=1 PULLBACK=293 BREAKOUT=14
                 REVERSAL_MTR=0 DOUBLE=220 FAILED_BO=0
Intents:         WOULD_BUY/SELL x125 (Double 111, Breakout 14),
                 SKIP_LATE_ENTRY x356, LOW_RR x47 (=528-481)
Runtime errors:  0
Trades:          0 (no order code yet) → trading metrics N/A
Note:            pullback 293/293 late is stale-level skips (spot-verified),
                 not a gate bug; chase calibration deferred to Phase 34.
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
