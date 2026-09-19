# RISK PANEL — indicator-side risk/position-size display (v1.4, normative)

> New, display-only addition to `FM_Indicator.mq5` — draws a top-left corner
> panel showing a suggested stop distance and lot size for each of several
> MM-size ratios, given a user-configured risk amount. **This indicator
> still never places an order or computes anything the state machine
> reads** — the panel is purely informational, same guarantee as the rest
> of `FM_Indicator.mq5`.

## 0. What it shows

Once per closed bar, a single multi-line `OBJ_LABEL` at the chart's top-left
corner (`FM_RiskPanel`) is redrawn with:

```
FM Risk Panel
Risk: 1.00% ($123.45)
Commission: $6.00/lot (auto)
Setup: SESN SELL #7  MM=250.0 pts
Ratio  Stop(pts)   Lot
 25%        500    2.15
 33%        500    1.63
 50%        750    1.09
 66%        990    0.82
```

Each row answers: *"if I put my stop at this % of the active setup's raw
Measured-Move size, how many points is that, and what lot size spends
exactly my configured risk budget at that stop?"*

## 1. Inputs (`FM_Indicator.mq5`, group "Risk / Position-Size Panel")

| Input | Meaning |
|---|---|
| `InpShowRiskPanel` | master switch |
| `InpRiskType` | `RISK_TYPE_PERCENT` (% of `ACCOUNT_BALANCE`) or `RISK_TYPE_DOLLAR` (fixed amount) |
| `InpRiskPercentPreset` | `1.00` / `0.50` / `0.25` / `CUSTOM` — percent mode |
| `InpRiskPercentCustom` | used only when preset = CUSTOM |
| `InpRiskDollarPreset` | `100` / `500` / `1000` / `CUSTOM` — dollar mode |
| `InpRiskDollarCustom` | used only when preset = CUSTOM |
| `InpAutoDetectCommission` | try recent closed-deal history on this symbol first |
| `InpCommissionPerLot` | manual value, used when auto-detect is off or finds nothing |
| `InpMMRatiosString` | comma list, percent-of-MM-size per row (default `"25,33,50,66"`) |
| `InpRiskPanelMinStopPoints` | floor applied to every row's stop distance (default 500) |
| `InpRiskPanelXDistance` / `YDistance` | panel position (pixels from top-left) |
| `InpRiskPanelColor` / `FontSize` | panel styling |

## 2. Which active setup drives the panel

The engine can have several active MM/FM setups at once (one per drawn zone).
The panel picks exactly one — `GetPrimaryMMSetup()`:

1. Highest state wins: `CONFIRMED > DEVELOPING > POTENTIAL > PROJECTED`
   (`INVALIDATED`/`COMPLETED` are skipped).
2. Ties broken by whichever is currently closest (mid-price) to its target.

The raw MM size fed into the ratio table is **not** the setup's `objective`/
`target` distance — it's the underlying leg/range height itself, re-derived
as `|a1_price − a0_price|` from the same `FMSetupSnapshot` the engine already
exposes (`CFMEngine::ActiveSnapshots`), converted to points. This is the
same technique already used for `CMMRiskModel` in the `FM_Ilan_GridEA`/
`FM_EA` EAs (`RISK_MANAGEMENT.md` §5) — no new struct fields needed.

## 3. Commission auto-detection (`AutoDetectCommissionPerLot`)

Scans up to the 20 most recent closed deals on the chart's symbol
(`HistorySelect` + `HistoryDealsTotal`), sums `|DEAL_COMMISSION|` and
`DEAL_VOLUME`, and returns their ratio as $/lot. **Best-effort, not exact**:
brokers differ in whether round-turn commission is charged fully on entry,
fully on exit, or split across both deals — summing both sides' commission
and volume approximates the round-turn $/lot correctly in the common
(symmetric) case, but sanity-check the auto-detected number against your
account statement once. Falls back to `InpCommissionPerLot` if there is no
matching history yet (fresh account/symbol) or `InpAutoDetectCommission` is
off.

## 4. Row math (`ComputeRatioRow`)

```
stopPoints = ratio × mmRangePoints
if stopPoints < InpRiskPanelMinStopPoints: stopPoints = InpRiskPanelMinStopPoints

moneyPerLotAtSL = (stopPoints × SYMBOL_POINT / SYMBOL_TRADE_TICK_SIZE) × SYMBOL_TRADE_TICK_VALUE
costPerLot      = moneyPerLotAtSL + commissionPerLot
lot             = riskMoney / costPerLot          (then normalized to the
                                                    symbol's volume step/min/max)
```

Commission is included in the denominator on purpose — the lot shown already
accounts for round-turn cost eating into the configured risk budget, not
just the price-move loss at the stop.

## 5. Known limitations

- Panel refreshes once per closed bar (same cadence as the rest of the
  indicator's drawing), not on every tick — `ACCOUNT_BALANCE` and spread can
  move intrabar without the panel reflecting it until the next bar closes.
- No Python-oracle parity test (this is a pure display feature, not part of
  the signal/state-machine pipeline that parity testing covers).
- `InpMMRatiosString` is not validated/clamped the way `Config.mqh` fields
  are — a malformed value falls back to a single 66% row.
