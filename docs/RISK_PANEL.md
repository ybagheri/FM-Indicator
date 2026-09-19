# RISK PANEL — indicator-side risk/position-size display (v1.5, normative)

> Display-only addition to `FM_Indicator.mq5` — shows a suggested stop
> distance and lot size for each of several MM-size ratios, for every
> currently actionable MM/FM zone, given a user-configured risk amount.
> **This indicator still never places an order or computes anything the
> state machine reads.**

## v1.5 change: two independent displays, both toggleable

v1.4 drew a single multi-line `OBJ_LABEL` in the top-left corner. On some
terminal builds, an `OBJ_LABEL` with embedded `\n` only reliably renders its
**first line** — that was the "only Risk/Commission shows, nothing else"
bug. Fixed by switching to one `OBJ_LABEL` **per row** (each with its own
pixel Y-offset) — the standard, universally-reliable MQL5 dashboard
pattern. `DrawCornerLine()` / `DeleteObjectsByPrefix("FM_RPRow")`.

v1.5 also adds a second, independent display: the same Ratio/Stop/Lot rows
drawn **next to each zone's own box/line on the chart** (price+time
anchored `OBJ_TEXT`, so it moves with that zone exactly like its target
line does), not only in the corner. `DrawZoneLine()` /
`DeleteObjectsByPrefix("FM_RZ_")`.

Two separate inputs control the two displays independently:

| Input | Controls |
|---|---|
| `InpShowRiskPanel` | the top-left corner summary panel |
| `InpShowZoneRiskTable` | the inline rows drawn next to each zone |

Either, both, or neither can be on.

## 0. What each one shows

**Corner panel** (`InpShowRiskPanel`) — one block per row, stacked at
`InpRiskPanelXDistance`/`YDistance`:

```
FM Risk Panel
Risk: 1.00% ($123.45)
Commission: $6.00/lot (auto)

SESN CONFIRMED SELL #7 MM=250.0pt
Ratio Stop(pts) Lot
 25%       500  2.15
 33%       500  1.63
 50%       750  1.09
 66%       990  0.82
```

**Inline zone table** (`InpShowZoneRiskTable`) — for each zone, a small
header + one row per ratio, stacked in price *outward* from the target
(away from current price, in the direction the MM itself points — so it
never overlaps the price action between entry and target):

```
Ratio  Stop   Lot
 25%   500pt  2.15L
 33%   500pt  1.63L
 50%   750pt  1.09L
 66%   990pt  0.82L
```
— positioned right at/beyond that zone's own target line, colored to match
the zone's state (blue=POTENTIAL, orange=DEVELOPING, lime=CONFIRMED), same
convention as the zone's own target line/label.

## 1. Inputs (`FM_Indicator.mq5`, group "Risk / Position-Size Panel")

| Input | Meaning |
|---|---|
| `InpShowRiskPanel` | corner summary panel on/off |
| `InpShowZoneRiskTable` | inline per-zone rows on/off |
| `InpRiskType` | `RISK_TYPE_PERCENT` (% of `ACCOUNT_BALANCE`) or `RISK_TYPE_DOLLAR` (fixed amount) |
| `InpRiskPercentPreset` | `1.00` / `0.50` / `0.25` / `CUSTOM` — percent mode |
| `InpRiskPercentCustom` | used only when preset = CUSTOM |
| `InpRiskDollarPreset` | `100` / `500` / `1000` / `CUSTOM` — dollar mode |
| `InpRiskDollarCustom` | used only when preset = CUSTOM |
| `InpAutoDetectCommission` | try recent closed-deal history on this symbol first |
| `InpCommissionPerLot` | manual value, used when auto-detect is off or finds nothing |
| `InpMMRatiosString` | comma list, percent-of-MM-size per row (default `"25,33,50,66"`) |
| `InpRiskPanelMaxSetups` | cap on how many concurrent zones either display lists (default 5) |
| `InpRiskPanelMinStopPoints` | floor applied to every row's stop distance (default 500) |
| `InpRiskPanelXDistance` / `YDistance` | corner panel position (pixels) |
| `InpRiskPanelColor` / `FontSize` | corner panel styling (zone rows use state color + a slightly smaller font automatically) |

## 2. Which active zones qualify (`CollectMMSetupsForPanel`) — unchanged from v1.4

- Eligible states: `POTENTIAL`, `DEVELOPING`, `CONFIRMED` — a bare
  `PROJECTED` target (price nowhere near it yet) is skipped.
- Sorted most-advanced-state first, ties broken by distance to target,
  capped at `InpRiskPanelMaxSetups`.
- Raw MM size is re-derived as `|a1_price − a0_price|` from the same
  `FMSetupSnapshot` the engine already exposes
  (`CFMEngine::ActiveSnapshots`) — no new struct fields needed. Same
  technique as `CMMRiskModel` in the EAs (`RISK_MANAGEMENT.md` §5).

## 3. Commission auto-detection — unchanged from v1.4

See `RISK_MANAGEMENT.md` §5 / this file's earlier version:
`HistorySelect` + up to the 20 most recent closed deals on the chart's
symbol, `|DEAL_COMMISSION| / DEAL_VOLUME` — best-effort, sanity-check once
against your statement. Falls back to `InpCommissionPerLot` if no history.

## 4. Row math (`ComputeRatioRow`) — unchanged from v1.4

```
stopPoints = ratio × mmRangePoints
if stopPoints < InpRiskPanelMinStopPoints: stopPoints = InpRiskPanelMinStopPoints

moneyPerLotAtSL = (stopPoints × SYMBOL_POINT / SYMBOL_TRADE_TICK_SIZE) × SYMBOL_TRADE_TICK_VALUE
costPerLot      = moneyPerLotAtSL + commissionPerLot
lot             = riskMoney / costPerLot     (normalized to volume step/min/max)
```

Every zone shown — in both displays — uses the *same* full `riskMoney`; if
you actually take more than one zone at once, real combined risk is the
sum, not any single row.

## 5. Known limitations

- Both displays refresh once per closed bar, not on every tick.
- No Python-oracle parity test (pure display feature).
- `InpMMRatiosString` isn't validated/clamped like `Config.mqh` fields — a
  malformed value falls back to a single 66% row.
- The inline zone table's stacking offset (`rowStep`) is ATR-based
  (`0.12 × ATR` per row); on very low-volatility symbols/timeframes this
  can visually crowd rows together — reduce `InpRiskPanelMaxSetups` or
  widen the chart's price scale if that happens.
