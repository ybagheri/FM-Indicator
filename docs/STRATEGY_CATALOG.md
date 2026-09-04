# STRATEGY CATALOG — deep per-strategy reference (Phases 27–30)

> One section per genuinely-implemented strategy. Each answers the §34
> question list. FM section is normative for Phase 27; FAILED_BO (28),
> pullback/breakout (29), reversal/double (30) are added by their phases.
> No profitability claims. Scores are context scores, never probabilities.

## FM_FADE — fading the measured-move target zone (Phase 27 ✅)

- What: shorting a bull-MM target zone (or buying a bear-MM zone) after
  touch + exhaustion + reversal-bar confirmation. Fades the ZONE, never
  the trend.
- Why it matters: Brooks MM targets are profit-taking magnets; the first
  test often overshoots/undershoots, and the reversal bar + exhaustion
  filter selects tests with observable rejection.
- Context required: any (LOG_ONLY default); larger scores near range
  extremes / prior S/R (location is scored, not gated).
- Chart: gray Leg1 → silver pullback → dashed target line; blue POTENTIAL
  (approach), orange DEVELOPING (touch+exhaustion), lime CONFIRMED (signal
  bar) + red/green arrow; label `STATE SIDE #id T=.. S=..`.
- Detection: `MeasuredMove.mqh` projection (§4 SPEC) → `CFMEngine` states
  (§6) → `CSetupPlanner::Plan` entry/stop/objective/R.
- Why displayed: DEVELOPING=objective test in progress; CONFIRMED=reversal
  evidence complete. Touch alone never confirms (stays POTENTIAL).
- Causing bars: Leg1 swings (A0/A1), pullback swing (B0), touch bar(s),
  signal bar `sh`, optional follow-through bar.
- Confirms it: signal bar (close extreme 50%, body ≥30%, adverse wick ≤60%,
  engulf optional) within tol of T (+1-bar follow-through if required).
- Invalidates it: close beyond T by >overmax×ATR, expiry past
  MaxBarsForward, or (EA intent) `invalidClose` close-through / stop.
- EA entry (v1): market at next open after CONFIRMED-plan selection with
  risk-OK + chase guard (|open−entry| ≤ 0.5×ATR).
- EA stop: plan stop (signal extreme AND target zone + ATR buffer).
- EA target: plan objective (B0 structural magnet).
- When EA trades it: SINGLE_FM_FADE / MULTI incl. FM / AUTO winner +
  risk-OK + firm (CONFIRMED) or provisional allowed (DEVELOPING + flag).
- When EA refuses: provisional when `InpTradeProvisional=false`,
  LATE_ENTRY chase, risk veto (RR/spread/caps), max-hold expiry (5 bars).
- False positives: touch without exhaustion (rightly held at POTENTIAL);
  strong trends running through T (overshoot → INVALIDATED, no fade);
  inverse-family confusion (family prefix disambiguates).
- Repaint: no — states advance ≤1/bar on closed bars; confirmation delay
  is honest backfill (see NON_REPAINTING.md).
- Automation limits: exhaustion is a proxy (climax/stall/pushes/wedge/
  overshoot); discretionary "quality of the test" is NOT observable;
  inverse-MM anchor is the weakest point (walk-forward pending).

## FAILED_BO — fading the failed breakout (Phase 28, PLANNED)
## PULLBACK — H1/H2/L1/L2 trend resumption (Phase 29, PLANNED)
## BREAKOUT — FOLLOW/pending continuation (Phase 29, PLANNED)
## REVERSAL_MTR — major/minor reversal (Phase 30, PLANNED)
## DOUBLE — swing/micro double top/bottom (Phase 30, PLANNED)
