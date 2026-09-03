# SETUP ENGINE (FM MODULE) — systematic specification (Phase 6, normative)

> Companion to `BROOKS_CONCEPTS.md` (§2: signal bar → entry bar → entry;
> §7: entry / stop / target / trader's equation) and
> `SYSTEMATIC_SPECIFICATION.md` (§6: FM states; §8: signal geometry).
> Normative for the FM setup-plan layer: identical closed-bar input →
> identical plans (float tol 1e-9, ints/enums/bools exact). Read-only in
> Phase 6 (DEBUG log); Phases 7–8 consume these plans for non-FM setup
> types and the trader's-equation gate. No profitability claims.

## 0. Conventions (same as prior layers)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed, older = larger shift).
  Python mirror: oldest-first indices (`0` = oldest).
- Only closed bars feed plans. `atr<=0` → no plan. Bar 0 never feeds.
- `CFMEngine` / `CConfirmation` are UNTOUCHED. This layer reads setup
  snapshots (`id/family/dir/target/b0.price/state/signal_time`) plus the
  signal bar's OHLC (resolved from `signal_time`, §3) and publishes a
  structured plan. It never writes buffers, objects, alerts, or states.
- Honesty record: entry is modelled AT the signal-bar extreme. Live
  stop-orders rest one tick beyond it (Brooks); the tick is execution
  detail, negligible next to the ATR stop, and intentionally not modelled.
  The 1-tick is therefore documented here, not hidden in a constant.

## 1. Inputs (new; all prior inputs unchanged)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpSetupStopBufATRMult` | double | 0.10 | stop buffer beyond structure (×ATR) |
| `InpSetupMinRR` | double | 1.0 | R flag threshold (report-only; veto is Phase 8) |
| `InpEnableSetup` | bool | true | master switch; false = layer idle |

Validation: `0.0<=StopBuf<=1.0`, `0.25<=MinRR<=5.0`; clamp + `Validate()` false.

## 2. Scope (which setups get plans)

- `DEVELOPING` → plan, marked `provisional=true` (touch + exhaustion only;
  no reversal bar yet — entry level may move on confirmation).
- `CONFIRMED` → plan, `provisional=false` (firm: reversal bar printed).
- `PROJECTED / POTENTIAL / INVALIDATED / COMPLETED` → no plan (no signal
  bar yet, or terminal). `POTENTIAL` has approached but never touched, so
  there is no signal extreme to reference.

## 3. Signal-bar resolution

`signal_time` = bar time of the last transition (SPEC §6: `POTENTIAL`,
`DEVELOPING`, and both `CONFIRMED` paths all stamp it). The hook scans
closed shifts for `rates[sh].time == signal_time`; the first (newest)
match is the signal bar. No match (aged out of the copied series) → no
plan, silently skipped. The planner itself takes the signal OHLC
explicitly, so resolution is hook-only and unit-testable.

## 4. Plan math (sell fade of a bull MM; buy mirrors with high/low swapped)

Fade direction `f = −mmDir` (`SPEC §10`: `SELL` fades `dir=+1`,
`BUY` fades `dir=−1`). `mmDir` must be `±1`, else invalid.

```
tol      = MMToleranceATRMult × atr      (target-zone half-width, SPEC §6)
buf      = SetupStopBufATRMult × atr
over     = MaxOvershootATRMult × atr     (invalidation distance, SPEC §6)

SELL (mmDir=+1):
  entry        = S.low                    (stop-order level proxy, §0)
  structure    = max(S.high, T + tol)     (signal extreme vs target zone)
  stop         = structure + buf
  objective    = B0.price                 (pullback extreme: first magnet)
  reward       = entry − objective
  risk         = stop − entry
  invalidClose = T + over                 (close above kills the setup)

BUY (mmDir=−1): entry = S.high; structure = min(S.low, T − tol);
  stop = structure − buf; objective = B0.price; reward = objective − entry;
  risk = entry − stop; invalidClose = T − over.

valid  = EnableSetup AND atr > 0 AND reward > 0 AND risk > 0
rMult  = reward / risk
rrOK   = rMult + 1e-9 >= clamp(MinRR, 0.25, 5.0)   (report-only flag)
```

Rationale (concepts §7): the stop sits beyond BOTH the signal extreme
and the target zone because either one failing kills the fade thesis;
the objective is the pullback extreme the MM was measured from (the
nearest structural magnet, not a promise). `rrOK` annotates the
trader's-equation input; nothing is vetoed in this layer.

## 5. Output struct (`SetupEngine.mqh`)

```
SetupPlan {valid, setupId, family, fadeDir(±1), entry, stop, objective,
  riskPts, rewardPts, rMult, rrOK, provisional, invalidClose, signalShift}
```

`riskPts/rewardPts` are plain price differences (points conversion is
execution-layer concern). `family` passes through for Phase-7 grouping.

## 6. No-look-ahead / repaint contract (extends prior layers)

1. Signal bar is a closed bar (`sh>=1`); bar 0 never feeds a plan.
2. Pure/stateless: `(signal OHLC, mmDir, target, b0, atr, cfg)` → plan.
   Extending history with newer bars never changes an old plan (tested).
3. No buffers, alerts, objects, or projections from this layer.

## 7. Python mirror + tests

- Mirror: `tests/setup_engine.py` — `plan(...)`, oldest-first indexing;
  `SetupCfg(stop_buf=0.10, min_rr=1.0, enable=True, tol_mult=0.25,
  over_mult=0.50)` (mults mirror the v1 zone constants).
- Suites (`tests/test_setup.py`, 10): sell geometry exact; buy mirror;
  stop anchored on signal extreme; stop anchored on target zone; invalid
  when objective beyond entry; invalid on zero risk (flat bar, zero buf);
  rrOK threshold both sides; provisional flag + family passthrough (all
  five families); invalidClose echo + disabled/zero-ATR/bad-dir safety;
  determinism (identical re-run, history extension leaves old plan
  untouched).
