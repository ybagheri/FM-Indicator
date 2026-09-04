# VALIDATION — what is tested, what is NOT validated (honest record)

> Companion to `TESTING.md` (synthetic suites), `FUTURE_ROADMAP.md` (ordered
> next moves), `LIMITATIONS.md`. No profitability claims. Nothing here is
> "validated" for live use until §3 is done.

## 1. Done (deterministic, reproducible)

- 97 Python mirror suites, all pass (`python tests/test_fm.py` etc. or
  per-file `__main__`; `pytest` optional): 19 FM + 7 bar + 10 pullback +
  9 state + 9 breakout + 10 reversal + 10 setup + 10 general + 10 decision +
  3 LTF. Oracle parity: MQL5 must match `tests/*.py` on identical series.
- MQL5 compile: MetaEditor64 `0 errors, 0 warnings` (warning-43 fix in
  `MeasuredMove.mqh` `flow` double; re-verify on each change).
- Static delimiter scan (comment/string-stripped balanced braces/parens)
  over all MQL5 files as Linux-CI stand-in for MetaEditor.
- No-look-ahead / freeze suites per layer (see `NON_REPAINTING.md`).
- Strategy Tester smoke runs (Alpari MT5 build 6090, 2026-09-04, temp EA
  `FM_SmokeTest` via iCustom defaults — EA lives in the terminal only, never
  committed here):
  - EURUSD H1 2025.11.03–2025.12.03 (Model=1): 528/528 bars read,
    target 528 / POTENTIAL 91 / DEVELOPING 11 / CONFIRMED 5, 0 errors.
  - EURUSD M1 2025.11.10–2025.11.13 (Model=1): 4260/4260 bars read,
    target 4138 / POTENTIAL 912 / DEVELOPING 177 / CONFIRMED 43, 0 errors.
  This proves no runtime errors + EA-readable buffers; it does NOT replace
  the visual run (§2.1) or walk-forward (§2.2).

## 2. NOT done (do not skip)

1. Strategy Tester visual run on majors/H1 (+ M1 with `FM-M1-Scalp.set`).
   Accept: no runtime errors, DEBUG logs show bar/pullback/state/BO/MTR/
   plan/decision lines, `FM_DECISION` updates per closed bar. Owner: human
   on Windows. Screenshot log (never committed — see `.gitignore`).
2. Walk-forward review from exported CSVs (`InpExportCSV` + `FM-Families.set`
   per-family data, `backtest_run` + MAE/MFE horizon 20). Accept: written
   review of inverse-MM anchor and `2.0×ATR` BO/reversal objectives,
   parameter sensitivity + Monte Carlo notes. Owner: human/analyst.
3. Statistical calibration (win rate / expectancy / precision / recall /
   R-distribution) only after (2). Until then scores stay scores
   (see `SIGNAL_SCORING.md` §6).

## 3. Reproduce

```
cd FM-indicator && python tests/test_fm.py && python tests/test_bar.py
# … (all test_*.py) — every file ends ALL * TESTS PASSED
```

MetaEditor: copy `MQL5/Indicators/FM_Indicator.mq5` +
`MQL5/Include/FM/*.mqh` to the terminal data folder, compile (F7).

## 4. v3 gate

EA work (separate repo, reuse `ActiveSnapshots()` + DATA buffers) is blocked
on §2 items 1–2. This indicator repo stays execution-free.
