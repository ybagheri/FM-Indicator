# PAPER FORWARD — live-data procedure (Phase 43: READY, NOT EXECUTED)

> PAPER mode is proven in tester (T-013/T-021). Live forward needs the EA on
> a live chart (a GUI attach step) + calendar time — both outside a headless
> session. This doc is the executable procedure, not a report.

## 1. Setup (user, 5 minutes)

1. Terminal on any account (PAPER places no orders; unfunded is fine).
2. Drag `FM_EA` onto an H1 chart (EURUSD first), load
   `Presets/FM_EA_Auto_Baseline.set` (ANALYSIS_ONLY default inside).
3. Set `InpTradeMode=PAPER`, `InpLogLevel=DEBUG` (first 48h), confirm,
   enable Algo Trading.

## 2. Acceptance (2 weeks live)

- EXPLAIN lines sane (strategy/context/scores match chart markers).
- `PAPER_OPEN/CLOSE` with ctx; weekly `PAPER ...` summary saved.
- Halt drill: set `InpEmergencyStop=true` → `HALT EMERGENCY_STOP` logged,
  no new virtuals (then remove EA / reset flag).
- No `WRONG_SIDE`/error spam; journal shows 0 real orders (PAPER never sends).

## 3. Evidence already banked (tester)

- BE modify path: 5× `BE #N DONE` server-accepted (XAUUSD T-020).
- Trail: never fired (OFF by default — expected, NOT proven).
- Halt/adopt/CloseAll: code-complete, mirror-covered, NOT live-fired.
- Close/partial paths: exercised via tester fills (T-014/16/20 closes).

## 4. Verdict when executed

Forward curve + regime split vs IS/OOS expectations → Phase 44 input.
Degradation vs tester is EXPECTED (spread/slippage/latency); quantify, don't hide.
