# SESSION MM — pre-open session-range dual projection (v1.3, normative)

> New MM family (`MM_SESSION`), `CSessionRangeMM` in `SessionMeasuredMove.mqh`.
> Companion to `docs/FM_ENGINE.md` (state machine) and `RISK_MANAGEMENT.md`
> §5 (`CMMRiskModel`, sizing off this family's `mm_range`). Read-only,
> closed-bars-only, non-repainting — same guarantees as every other family
> in `MeasuredMove.mqh`. No profitability claims.

## 0. What this models

Setup this was built for (recurring on US30/YM and other US index futures,
in both Globex and RTH): before the US cash session opens, the overnight
range is treated as a trading range. Unlike every other MM family here,
this one projects **both** sides of that range *before* either side has
broken:

- upside target  = session range **high** + range **height**
- downside target = session range **low**  − range **height**

i.e. the classic "double the range" technique — mark the pre-open range,
then watch for a break of either edge toward 2× the range. This is
distinct from a Leg1=Leg2 (`MM_REGULAR`) projection, which needs a
completed swing leg and only ever points one direction, and from
`MM_RANGE` (`CRangeHeightMM`), which uses a rolling N-bar lookback and only
fires **after** a confirmed breakout close, on the side that broke.

## 1. Inputs (`Inputs.mqh`)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpEnableSessionMM` | bool | false | master switch; false = family idle |
| `InpSessionStartHour` / `Min` | int | 18 / 0 | session window start, **broker/server time** |
| `InpSessionCutoffHour` / `Min` | int | 9 / 30 | window end — set to your broker's US cash-open time |
| `InpSessionMinBars` | int | 5 | min bars required inside the window to bother projecting |
| `InpSessionMaxBars` | int | 400 | backward-scan cap (safety bound, not a lookback tuning knob) |

Validation (`Config.mqh`): hours clamped `0..23`, minutes `0..59`,
`2<=SessionMinBars<=50`, `SessionMinBars<=SessionMaxBars<=2000`.

**Server time, not UTC / not your local time.** `SessionCutoffHour:Min`
must equal the US cash-open bar in *your broker's* server clock, which
shifts with US/EU DST changes at different calendar weeks — the defaults
(18:00 → 09:30) assume a common EET/EEST-style broker offset and will be
wrong for other brokers. Check against a known session boundary on your
own chart before relying on this in an EA.

## 2. Trigger (`CSessionRangeMM::ProjectPair`, called from `CFMEngine::FormProjections`)

- Evaluated on the newest closed bar (`rates[1]`) every call, like the
  rest of `FormProjections` — but only *acts* once per calendar day.
- Fires the **first** closed bar whose time-of-day is at/after
  `SessionCutoffHour:Min` (not an exact-match check, so a missed bar at
  the exact cutoff minute still triggers on the next one that day).
- A `static int s_lastDayKey` guard (function-local, persists for the
  indicator/EA instance lifetime) marks the day handled immediately once
  the cutoff is crossed — success or not — so it never re-fires or
  re-scans later the same day.
- Session window: `[SessionStart, SessionCutoff)`. If
  `SessionStart >= SessionCutoff` (e.g. 18:00 → 09:30) the window is
  treated as **overnight** (spans the previous calendar day's evening
  into today); otherwise it's a same-day window.
- Backward scan is bounded by `min(SessionMaxBars, count-1)` bars and
  breaks early once it walks back past the window's start (plus one extra
  calendar day of slack for the overnight case, as a safety net against
  data gaps — it never scans more than ~2 calendar days back).
- `barsCounted < SessionMinBars` → no projection today (short history /
  weekend gap / holiday).
- `height = hh - ll < cfg.MinLegATRMult * atr_ref` → range too small,
  no projection today (same size gate every other family uses).

## 3. Projections emitted

Two `Projection` structs, both `family=MM_SESSION`, sharing the same
`a0`/`a1` range extremes (mirrored) and `mm_range = height`:

| | `dir` | `a0` | `a1` | `b0` (objective) | `target` |
|---|---|---|---|---|---|
| Upside  | +1 | range low  | range high | range **high** | `hh + height` |
| Downside | -1 | range high | range low  | range **low**  | `ll - height` |

`b0.bar` is set to shift `1` (the cutoff bar) for both — there is no
breakout bar yet at creation time, unlike `MM_RANGE`. Both projections are
added via the normal `AddProjection` / `SameProjection` path, so from this
point on they are indistinguishable to the rest of the engine from any
other family: the existing `FM_PROJECTED → FM_POTENTIAL → FM_DEVELOPING →
FM_CONFIRMED` state machine (`CFMEngine::Update`) watches price approach
*whichever side breaks first* and confirms a fade candidate there — the
other side simply ages out / gets evicted once price has clearly gone the
other way, same as any two competing projections would.

## 4. Sizing a confirmed session-MM fade

`Projection.mm_range` (price units) from either side feeds
`CMMRiskModel` directly (`RISK_MANAGEMENT.md` §5):

```mql5
double stopPrice, targetPrice, lots, riskMoney;
CMMRiskModel::BuildOrderPlan(_Symbol, entry, dir, setup.mm_range,
                             MM_RR_DOUBLE,      // or MM_RR_EQUAL
                             500.0,             // minFloorPoints
                             1.0,               // riskPercent
                             stopPrice, targetPrice, lots, riskMoney);
```

## 5. Known limitations / next steps

- No session-identity tagging on the `Projection`/`FMSetupSnapshot` structs
  yet (can't tell from the snapshot alone that a given active setup came
  from the pre-open window vs. an intraday range) — deferred, matches the
  project's existing phased approach (see `fm-indicator-mm-upgrade`
  session-mode item in `ROADMAP.md` / `FUTURE_ROADMAP.md`).
- No Python-oracle parity test yet (unlike most other families —
  see `EA_INDICATOR_PARITY_AUDIT.md`). Add one before trusting this in the
  Strategy Tester or live.
- Session window is a fixed daily clock time; it does not shift
  automatically for symbol-specific holidays or early-close days.
