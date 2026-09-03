# SYSTEMATIC SPECIFICATION — FM (Fading Measured Move) v1.2 + v2 research

> Companion to `docs/RESEARCH.md`. This document is normative: another
> developer implementing it verbatim must produce the same signals
> (up to floating-point tolerance). Everything Brooks-discretionary is
> converted to a deterministic proxy with an `Inp*` input. No profitability
> claims. v1.2 adds three MM families + first-class wedge counter + display
> score; v2 adds read-only research tooling (MTF overlay, CSV export,
> MAE/MFE, deterministic backtest harness).

Conventions:

- Bars indexed MT5-style: `0` = forming bar, `1` = last closed bar.
  All detection uses **closed bars only** (`shift >= 1`) unless a rule
  explicitly says "intrabar POTENTIAL".
- Prices: `H[i], L[i], O[i], C[i]`. ATR = Wilder ATR(`InpAtrPeriod`, default 14)
  computed on closed bars.
- `NEAR(x, y, tol)` means `|x - y| <= tol`. Tolerances are ATR-normalized.
- Directions: `+1` = bullish (up-leg / bull MM), `-1` = bearish.

---

## 1. Inputs (normative defaults = Balanced preset)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpSwingK` | int | 3 | fractal arm: swing at `s` confirmed only when `s >= InpSwingK+1` (k bars each side) |
| `InpMinLegATRMult` | double | 1.0 | min leg price range as ATR multiple |
| `InpMinLegBars` | int | 3 | min bars from leg start swing to leg end swing |
| `InpMaxLegBars` | int | 100 | max bars leg may span |
| `InpMinPullbackRatio` | double | 0.15 | min pullback depth / Leg1 range |
| `InpMaxPullbackRatio` | double | 0.90 | max pullback depth / Leg1 range |
| `InpMaxPullbackBars` | int | 50 | max bars Leg1-end → Leg2-start |
| `InpMMToleranceATRMult` | double | 0.25 | half-width of target tolerance band |
| `InpMaxOvershootATRMult` | double | 0.50 | penetration beyond target before INVALIDATED |
| `InpApproachATRMult` | double | 1.0 | POTENTIAL when distance-to-target <= this × ATR |
| `InpSignalClosePct` | double | 0.50 | reversal bar must close in extreme N% of range (0.5 = upper/lower half) |
| `InpMinBodyRatio` | double | 0.30 | min body/range of signal bar |
| `InpMaxWickRatio` | double | 0.60 | max adverse wick/range of signal bar |
| `InpRequireEngulf` | bool | false | require engulf/outside-bar for CONFIRMED |
| `InpRequireFollowThrough` | bool | false | require next closed bar to close beyond signal-bar extreme |
| `InpEnableInverseMM` | bool | true | enable failed-BO inverse-MM family |
| `InpFailedBOBars` | int | 5 | lookback for failed-BO pivot (leg extreme broken then reclaimed) |
| `InpEnableRangeMM` | bool | false | v1.2: range-height breakout family (SPEC §4b) |
| `InpRangeLookback` | int | 50 | v1.2: range window in bars (10–200) |
| `InpEnableChannelMM` | bool | false | v1.2: shallow-pullback channel family (SPEC §4b) |
| `InpEnableGapMM` | bool | false | v1.2: measuring-gap family (SPEC §4b) |
| `InpMinGapATRMult` | double | 1.0 | v1.2: min gap-bar range as ATR multiple |
| `InpMinPushes` | int | 3 | v1.2: exhaustion push threshold 2–5 (SPEC §8) |
| `InpUseWedgeExhaustion` | bool | true | v1.2: count shrinking-range wedge as exhaustion |
| `InpShowScore` | bool | true | v1.2: append display-only S=0..100 to labels |
| `InpMTFTrendTFMinutes` | int | 0 | v2: higher-TF overlay minutes, 0=off (LOG_ONLY) |
| `InpExportCSV` | bool | false | v2: append CSV row per CONFIRMED |
| `InpCSVFile` | string | FM_signals.csv | v2: CSV filename under MQL5/Files |
| `InpContextFilterMode` | enum | LOG_ONLY | `LOG_ONLY` / `DEMOTE` / `VETO` (see §7) |
| `InpMaxActiveSetups` | int | 20 | cap on live projections (nearest-first eviction) |
| `InpMaxBarsForward` | int | 100 | projection expires after this many bars past Leg2 start |
| `InpUseIntrabarPotential` | bool | false | if true, bar 0 may raise POTENTIAL only (never DEVELOPING/CONFIRMED) |
| `InpAlertPotential/Developing/Confirmed` | bool | true/true/true | per-state alert enable |
| `InpAtrPeriod` | int | 14 | ATR period |

Presets: **Conservative** = (`SwingK` 4, `MinLegATR` 1.5, `Tolerance` 0.20,
`Approach` 0.75, `MinBody` 0.40, `FollowThrough` true);
**Aggressive** = (`SwingK` 2, `MinLegATR` 0.75, `Tolerance` 0.35,
`Approach` 1.5, `MinBody` 0.25, `FollowThrough` false).
Balanced = table defaults.

---

## 2. Swings (the only source of structure)

A **swing high** at closed-bar index `s` (s >= 1):

```
H[s] = max(H[s-k .. s+k])  AND  strictly greater than at least one neighbor
each side (ties broken by earliest bar) AND s-k >= 1 (all bars closed).
```

Swing low mirrors on `L`. Confirmation rule (anti-repaint):

- A swing at `s` **does not exist** until bar `s+k` closes, i.e. current
  last-closed bar `b` satisfies `b >= s+k`. `confirmed_shift = s`.
- Intrabar bar 0 is never a swing. Recomputing history with frozen closes
  yields identical swings (property tested in §9).

No ATR/size filter at swing level — size filters apply at leg level so
debugging can show rejected legs.

---

## 3. Legs

A **bull leg** is an ordered swing pair `(a, b)` with `a` = swing low,
`b` = swing high, `b < a` in time (a older), satisfying:

```
bars   = a_index - b_index ... (positive distance in bars) in [MinLegBars, MaxLegBars]
range  = H[b] - L[a] >= MinLegATRMult * ATR[b]
```

Bear leg mirrors (`H[a] - L[b]`). Legs are built only from **confirmed**
swings. Overlapping legs allowed; engine keeps every qualifying pair but
downstream MM formation prefers the most recent (see §4).

Rationale: Brooks has no bar-count rule; these bounds are ours, inputs.

---

## 4. Pullback + Leg1=Leg2 projection (regular family)

Given Leg1 `(A0 -> A1)` with direction `d` (+1 bull / -1 bear):

1. **Pullback end `B0`**: the first confirmed opposite swing after `A1`
   within `MaxPullbackBars` bars. Bull case: `B0` = swing low after `A1`-high.
   Depth ratio:

   ```
   depth = (H[A1] - L[B0]) / (H[A1] - L[A0])   (bull)
   depth = (H[B0→ uses H?] ...) bear mirrors with L[A1], H[B0]
   require MinPullbackRatio <= depth <= MaxPullbackRatio
   ```

   Inside-bar pause: if no opposite confirmed swing but a closed bar after
   `A1` has range `< 0.25×ATR` and stays within Leg1 extreme ±0.1×ATR, it
   counts as pullback with `depth ≈ 0` — accepted only if
   `MinPullbackRatio == 0` (default 0.15 rejects it; documented).

2. **Projection**: at the moment `B0` confirms (bar `B0+k` closes):

   ```
   MM_range  = |Extreme(A1) - Extreme(A0)|   (H-high minus L-low, bull)
   Target_T  = Extreme(B0) + d * MM_range
   ```

   Bull: `T = L[B0] + (H[A1]-L[A0])`. Bear: `T = H[B0] - (H[A0]-L[A1])`.

3. **Leg2 tracking**: Leg2 is the move from `B0` toward `T`. No Leg2-end
   swing is required for POTENTIAL/DEVELOPING — the setup is about
   *approaching* `T`.

---

## 4b. v1.2 MM families (flag-gated, mutually exclusive where noted)

All families feed the identical state machine (§6). Dedup key is
`(b0.bar, dir, family, target)` — same target from different families coexists.

- **RANGE (`CRangeHeightMM`)**: range = HH−LL over `RangeLookback` closed bars
  before breakout bar `bo`. Bull: `close[bo] > HH` → `T = close[bo] + height`;
  bear mirrors. Height must be ≥ `MinLegATRMult×ATR`. a0/a1 carry range low/high
  bars for visualization; b0 = breakout bar.
- **CHANNEL (`CChannelMM`)**: same geometry as Leg1=Leg2 but fires ONLY when
  pullback depth is BELOW the regular minimum: `0.02 <= depth < MinPullbackRatio`
  (default 0.02–0.15). Regular owns `>= MinPullbackRatio` → mutually exclusive
  by construction. Target `T = B0 ± MM_range` as usual.
- **GAP (`CGapMM`)**: gap bar `g`: range ≥ `MinGapATRMult×ATR`, closes in extreme
  25% toward direction, and micro-gaps away from the prior extreme
  (bull: `low[g] > high[g+1]` in MT5 shift terms; bear mirrors).
  `gap = |close[g] − prior extreme|`, must be ≥ 0.25×ATR.
  `T = close[g] + dir×gap`. Brooks note: every trend bar is a BO/gap; the gap
  size is the measured impulse.

Presets: families default OFF (setup count unchanged from v1); `FM-Families.set`
enables all three for research.

---

## 5. Inverse-MM family (failed-BO; flag-gated)

v1.1 anchor (symmetric, conservative): anchor is the FAR SIDE of the
failure-extreme bar — bull-inverse `T = low[flowBar] − leg_range` where
`flowBar` printed the failure-high; bear-inverse mirrors
(`T = high[lowBar] + leg_range`). ATR-independent (range ATR-gated at leg
level). Flagged for walk-forward review once tester data exists.

If `InpEnableInverseMM == true`: when a bull Leg1 `(A0->A1)` high `H[A1]`
is broken by closes above it within `FailedBOBars` bars and then a closed
bar closes back **below** `H[A1]` (failed bull BO), project a **bearish**
inverse-MM from the failure extreme `F` (highest high of the failure excursion):

```
InvT = L[F] - MM_range   (bearish target below)
```

Bull-inverse mirrors. Inverse setups carry `family = INVERSE` and are
otherwise processed by the identical state machine (§6). If flag is false,
no inverse projections are created.

---

## 6. FM state machine (per setup; deterministic)

Each projection owns one state. Transitions evaluated once per **closed
bar** `b` (plus optional intrabar POTENTIAL). Let:

```
tol      = MMToleranceATRMult * ATR[b]
approach = ApproachATRMult    * ATR[b]
overmax  = MaxOvershootATRMult* ATR[b]
dist(b)  = d>0 ? T - H[b] : L[b] - T ... (signed distance alleys; negative = penetrated)
```

States:

- `IDLE → PROJECTED`: on §4-step-2 / §5 creation. Record
  `created_bar = b`, `target T`, `direction d`, `family`.
- `PROJECTED → POTENTIAL`: when `0 <= dist(b) <= approach` (approaching but
  outside tolerance) OR bar 0 intrabar enters approach zone (only if
  `UseIntrabarPotential`). Alert once per setup.
- `POTENTIAL → DEVELOPING`: when bar `b` **touches tolerance band**:
  `|extreme(b) - T| <= tol` where extreme = `H[b]` (bull target above) /
  `L[b]` (bear) **AND** exhaustion/stall proxy true (§8 ExhaustionAny).
  Touch without exhaustion stays POTENTIAL (Brooks: touch ≠ fade).
- `DEVELOPING → CONFIRMED`: when a subsequent closed bar `c` is a valid
  **reversal signal bar** (§8 SignalBar) in fade direction (`-d`) whose
  extreme is within `tol` of `T`, and optional follow-through
  bar closes beyond the signal extreme (if `RequireFollowThrough`).
  v1.1: with `RequireFollowThrough`, a signal on the newest closed bar NEVER
  confirms same-bar — confirmation lands exactly one closed bar later via the
  delayed path (signal on `b+1` in MT5 shift terms / `b-1` oldest-first +
  `FollowThrough` on `b`). v1.1 fix: `IsSignalBar` accepts the newest closed
  bar (was `c<2`, now `c>=1` with prior bar for the engulf check).
- `* → INVALIDATED`: if close beyond target exceeds `overmax`:
  bull: `C[b] - T > overmax`; bear: `T - C[b] > overmax`. Or `b - created_bar > MaxBarsForward`. Or a confirmed swing against `d` exceeding `MM_range` before POTENTIAL (structure destroyed).
- `CONFIRMED → COMPLETED`: terminal informational state after alert; kept
  for visualization until expiry (`MaxBarsForward`) then pruned.
- Demotion by context (§7) may force `CONFIRMED → DEVELOPING` (DEMOTE mode)
  instead of alerting CONFIRMED.

Alert-once invariant: each `(setup_id, state)` pair alerts at most once.

---

## 7. Context classifier (Trend / Range / Transition + confidence)

Computed per closed bar from closed data only (no future):

```
body_avg(N=20)  = mean(|C-O| / ATR)
trend_score     = (EMA20 - EMA50) / ATR  clamped [-2, +2]
range_score     = (HH50 - LL50) / ATR
```

- `TREND` if `|trend_score| > 0.8` and `range_score > 3`.
- `RANGE` if `|trend_score| < 0.4` and `range_score < 6`.
- else `TRANSITION`. Confidence = normalized margin (0..1), logged.

Effect controlled by `ContextFilterMode`:

- `LOG_ONLY` (default): context recorded + drawn, never blocks transitions.
- `DEMOTE`: CONFIRMED requires `confidence >= 0.5` else stays DEVELOPING.
- `VETO`: POTENTIAL never forms when context confidence < 0.3 against fade.

Default LOG_ONLY is faithful to Brooks ("context, not trigger").

---

## 8. Exhaustion proxy + signal bar (operationalized)

`ExhaustionAny(b)` = OR of (all on closed bars, ATR-normalized):

1. ClimaxBar: `range(b) >= 2.0×ATR` and body in trend direction.
2. StallBar: `range(b) < 0.5×ATR` with upper+lower wicks each > 40% of range
   (doji/stall at target).
3. PushCount ≥ `InpMinPushes` (v1.2 first-class counter, default 3):
   consecutive closes in direction `d` with higher highs (bull) / lower lows
   (bear). 3b. Wedge (v1.2, `InpUseWedgeExhaustion`): ≥3 pushes with shrinking
   ranges (each ≤ prior ×1.05) or ≥4 pushes regardless.
4. ChannelOvershoot: extreme(b) beyond 20-bar SMA band by
   > 0.3×ATR (newest 20-bar window including `b`).

`SignalBar(c, fade_dir f = -d)` requires ALL:

```
dir(c) == f  AND  body(c)/range(c) >= MinBodyRatio
AND adverse_wick(c)/range(c) <= MaxWickRatio
AND close in extreme SignalClosePct of bar range toward f
AND (NOT RequireEngulf OR engulfs prior bar body)
```

`FollowThrough`: next closed bar closes beyond signal extreme toward `f`.

`ScoreSignal` (v1.2, display only — never auto-trades, 0..100): body 0–20,
adverse-wick 0–15, close position 0–15, engulf +10 (or +5 neutral credit when
not required), follow-through shape +5/+5, exhaustion breadth 0–20 (climax /
stall / pushes≥2 / wedge), context confidence 0–10, distance-to-target 0–10
(0 at center → 0 pts at ≥0.5 ATR). Zero ATR → 0, never crashes.

These thresholds are ours; labeled as proxies in UI/README.

---

## 9. No-look-ahead / repaint contract (testable)

1. Only bars `>= 1` feed swings/legs/states; bar 0 feeds POTENTIAL only
   under explicit flag.
2. Swing `s` usable only when `last_closed >= s+k`.
3. Closed-bar freeze: once bar `b` closes, its OHLC and any state reached
   on `b` never change when later bars arrive (backfill draws carry the
   `confirmed_shift` marker so history shows delay honestly).
4. Retrospective gap-type labels (measuring vs. exhaustion) appear only in
   debug logs, never as live states.

Python mirror (`tests/fm_engine.py`) implements this spec 1:1 and the
MQL5 engine must match it on identical synthetic series (see TESTING.md).

---

## 10. Buffers / objects / alerts contract

- DATA buffers (EA-readable, never repaint after close): `BufTarget`,
  `BufPotential`, `BufDeveloping`, `BufConfirmed` (target price / signal
  price at issuing closed bar, else EMPTY_VALUE).
- CALC buffers internal: ATR, swing markers.
- Chart objects per setup: `FM_<id>_LEG`, `FM_<id>_PB`, `FM_<id>_TGT`,
  `FM_<id>_ZONE`, `FM_<id>_LABEL`. Deleted on invalidation/expiry or
  timeframe/symbol change. Toggles: `InpShowLegs/Pullbacks/Targets/Zones`.
- Alerts: popup/sound/push/email per state with `Inp*` enables + once-per
  `(id,state)` guard + new-closed-bar throttle (no per-tick repeats).
- Labels: `FAM STATE SIDE #id T=target S=score` where FAM ∈ {`''`, `INV`, `RNG`,
  `CH`, `GAP`}, SIDE ∈ {`SELL` (fade bull), `BUY` (fade bear)}, S shown when
  `InpShowScore` (display only).

---

## 11. v2 research tooling (read-only; never gates the state machine)

- **MTF overlay** (`InpMTFTrendTFMinutes`, 0=off): 20/50 SMA gap on higher-TF
  closes, ATR-normalized; `>0.8 → +1`, `<−0.8 → −1`, else 0. Logged at INFO;
  default context mode LOG_ONLY is unchanged.
- **CSV export** (`InpExportCSV`/`InpCSVFile`): one row per CONFIRMED edge on
  the just-closed bar: `time,id,family,dir,target,price,score,symbol,tf`.
- **MAE/MFE** (Python `mae_mfe`, horizon 20): max adverse/favorable excursion
  in price after the CONFIRMED close — pure measurement, no profit claims.
- **Deterministic backtest harness** (Python `backtest_run`): bar-by-bar engine
  run over oldest-first bars forming regular+channel on swing triples and
  range+gap on the newest bar; returns signal rows with MAE/MFE + score.
  For walk-forward review only, not a profitability backtest.
- **EA reuse (v3-ready)**: `CFMEngine::ActiveSnapshots()` exports read-only
  `{id,family,dir,a0/a1/b0,target,state,created_bar,context,confidence}` for
  an EA in a separate repo; this indicator repo never trades.
