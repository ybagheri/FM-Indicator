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
