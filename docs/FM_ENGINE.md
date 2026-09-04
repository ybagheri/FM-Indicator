# FM ENGINE — measured-move + fading module (normative summary)

> Companion to `SYSTEMATIC_SPECIFICATION.md` (§4–§6 normative), `RESEARCH.md`
> (Brooks vs proxy), `SETUP_ENGINE.md` (Phase-6 plans), `ARCHITECTURE.md` (§4).
> No profitability claims. Terminology: "Al Brooks-inspired / Brooks-style
> systematic interpretation" — never "official Brooks rules".

## 0. Role in the larger system (master prompt §13)

FM is ONE module of the bar-by-bar engine. It owns Leg1=Leg2 projection and
the fade state machine only. Context (Phases 1–5), catalog (Phase 7) and
decision (Phase 8) are separate read-only layers that never gate FM states.

## 1. Measured-move projection (SPEC §4–§4b, §5)

- Regular (Leg1=Leg2): legs from confirmed swings (`Swings.mqh`), pullback
  depth `0.15–0.90` / `50` bars, `Target = B0 ± |A1−A0|`
  (bull `T = L[B0] + (H[A1]−L[A0])`, bear mirrors). Impl `MeasuredMove.mqh`
  `CLegEqualityMM`, mirror `tests/fm_engine.py`.
- v1.2 families (flag-gated, default OFF): RANGE (`close + height`),
  CHANNEL (shallow depth `0.02–MinPullbackRatio` only, mutually exclusive
  with regular), GAP (`close + gap`). Dedup key
  `(b0.bar, dir, family, target)`.
- Inverse (failed-BO, `InpEnableInverseMM`): break+reclaim within
  `InpFailedBOBars` → opposite projection from FAR SIDE of failure bar
  (bull-inverse `T = low[flowBar] − range`, bear mirrors). Weakest point —
  flagged for walk-forward review (see `LIMITATIONS.md`).

## 2. FM state machine (SPEC §6, `FMEngine.mqh`)

`PROJECTED → POTENTIAL → DEVELOPING → CONFIRMED → COMPLETED`, with
`→ INVALIDATED` from any state. Max one transition per closed bar.

- PROJECTED: on projection creation (`created_bar` recorded).
- POTENTIAL: `0 <= dist <= approach×ATR` (default `1.0×ATR`). Intrabar bar-0
  preview only if `InpUseIntrabarPotential` (default false).
- DEVELOPING: touch `|extreme − T| <= tol×ATR` (default `0.25×ATR`) AND
  `ExhaustionAny` (SPEC §8: climax / stall / pushes≥`InpMinPushes` / wedge /
  overshoot). Touch alone stays POTENTIAL.
- CONFIRMED: reversal signal bar in fade direction within `tol` of `T`
  (close extreme 50%, body ≥30%, adverse wick ≤60%, engulf optional) +
  optional 1-bar-delayed follow-through (`InpRequireFollowThrough`).
- INVALIDATED: close beyond `T` by `> overmax×ATR` (`0.50×ATR`), or
  `b − created > MaxBarsForward` (`100`), or structure destroyed.
- COMPLETED: terminal informational (kept for viz until expiry).

Alert-once per `(id, state)` + 60s throttle (CONFIRMED exempt).

## 3. Fading discipline

Fade the TARGET ZONE only, never the trend. Touch ≠ fade. No auto-fade:
DEVELOPING needs exhaustion, CONFIRMED needs a signal bar. Score `S=0..100`
is display-only (see `SIGNAL_SCORING.md`).

## 4. Buffers / objects / EA reuse

DATA buffers `Target/Potential/Developing/Confirmed` frozen at issuing
closed bar (never rewritten). Objects `FM_<id>_LEG/PB/TGT/ZONE/LABEL`,
family prefixes `INV/RNG/CH/GAP`, side `SELL` (fade bull) / `BUY` (fade
bear). EA: read buffers or `#include <FM/FMEngine.mqh>` →
`CFMEngine::ActiveSnapshots()`. CSV export per CONFIRMED (v2).

## 5. Tests

`tests/test_fm.py` 19 suites (lifecycle, touch-without-exhaustion,
overshoot invalidation, ratio gates, follow-through delay, wedge, families,
score bounds, newest-bar signal, dedup, MTF/MAE-MFE/CSV/backtest). All pass.
