# RISK MANAGEMENT — sizing, gates, accounting (Phase 24/26/33)

> Normative for `CRiskManager`. All rejections carry machine reasons the
> tests assert. No profitability claims.

## 1. Sizing (`ComputeVolume`)

- FIXED: `InpFixedLot` normalized (step floor, min/max clamp).
- RISK_PCT: risk = equity × pct/100 (default 1%).
- MONEY: fixed money (default $100).
- Volume = risk / loss-on-1.0-lot(entry→stop via `OrderCalcProfit`,
  direction-aware) → normalized. Zero/negative inputs → symbol minimum
  (never zero, never crash).

## 2. Gate order (`Check`) — first veto wins

`NO_SETUP → LOW_RR → HIGH_SPREAD → DAILY_LOSS → MAX_TRADES_DAY →
CONSEC_LOSSES → MAX_OPEN → MAX_PER_SYMBOL → OK`. Defaults: minRR 1.0,
spread 50pt, 5 trades/day, 1 open, 1/symbol, 3 consec losses; daily-loss
off (safety halt covers it when configured).

## 3. Accounting (`OnNewDay` / `NotifyTradeClosed` / `NotifyTradeOpened`)

Day rollover resets trades/P/L (consec losses persist across days — they
measure psychology-freeze, not calendar). EA feeds closes from
`CPositionManager::ScanClosedDeals` (first scan fast-forwards: no history
replay). Mirror: `tests/risk_manager.py`.

## 4. Stop-level / freeze / margin

Stop-level distance + margin + quotes are EXECUTION gates (Phase 25, need
live prices), not risk gates. Risk assumes structural stops; execution
refuses unplaceable ones (`INVALID_STOPS`, `NO_MONEY`).

## 5. MM-percentage sizing (`CMMRiskModel`, v1.3, `MMRiskModel.mqh`)

EA-side-only optional alternative sizing path, kept outside `Config.mqh` /
`Inputs.mqh` on purpose — same reasoning as `CRiskManager` itself: position
sizing is an execution concern, not an analysis-engine one. Use this when a
setup's stop/target should scale off the *Measured-Move size itself*
(`Projection.mm_range`) rather than off an ATR buffer.

- Two RR modes off the same MM size, `ENUM_MM_RR_MODE`:
  - `MM_RR_EQUAL` (1:1): stop = 66% of MM size, target = same distance.
  - `MM_RR_DOUBLE` (1:2): stop = 33% of MM size, target = 2× that distance.
- Stop distance is always floored at a caller-supplied `minFloorPoints`
  (500 by default per the original spec) so an early/small MM projection
  never produces an unrealistically tight stop.
- `ComputeLotByRiskPercent(symbol, slPoints, riskPercent, riskMoney)`: manual
  `contractSize` / `tickSize` / `tickValue` formula — `riskMoney = balance ×
  pct/100`; `lots = riskMoney / (slPoints × point / tickSize × tickValue)`.
  `contractSize` itself isn't part of the formula (tick value already folds
  it in per MT5 docs) — fetched only for logging/sanity-checking.
- `BuildOrderPlan(symbol, entry, dir, mmRangePrice, mode, minFloorPoints,
  riskPercent, ...)` chains both steps: MM size → stop/target prices → sized
  lot, in one call.
- Prefer `CRiskManager::ComputeVolume` (§1, `OrderCalcProfit`-based) instead
  whenever both entry AND stop PRICES already exist — it additionally
  adjusts for non-linear `SYMBOL_TRADE_CALC_MODE` symbols. `CMMRiskModel` is
  for the earlier moment: only a stop *distance in points* is known yet
  (right after `ComputeStopTargetPoints`, before an entry price is chosen).
- No tests yet (unlike §1's `tests/risk_manager.py`) — add
  `tests/mm_risk_model.py` before wiring this into a live EA's execution
  path.
