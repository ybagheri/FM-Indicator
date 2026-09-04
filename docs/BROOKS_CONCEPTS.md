# BROOKS CONCEPTS — systematic knowledge base (Brooks-style interpretation)

> Status: Phase-1 knowledge base. No profitability claims.
> For every concept: **Brooks** (what the methodology teaches, per sources in
> `RESEARCH.md`) vs **Systematic interpretation** (our deterministic proxy) vs
> **Implementation** (exact algorithm + file). Automation difficulty: EASY /
> MEDIUM / HARD / NOT-AUTOMATABLE (documented, not silently approximated).
> Terminology throughout: "Al Brooks-inspired / Brooks-style systematic
> interpretation" — never "official Brooks rules".

## How to read this file

```text
Concept: ...
Brooks: ...            (attributable, see RESEARCH.md §2)
Observable in OHLC: ...
Not observable: ...
Systematic interpretation: ...
Implementation: ...
Automation: EASY/MEDIUM/HARD/NOT-AUTOMATABLE
Limitations / false-positive risks: ...
```

---

## 1. Bar anatomy

### Concept: Bull / bear bar
Brooks: a bar whose close is above (bull) / below (bear) its open. Trend bars
close near the favorable extreme; dojis are one-bar trading ranges.
Observable: O/H/L/C fully determine direction, body, tails, close position.
Systematic: `dir = sign(close-open)`; `body/range`, `closePos =
(close-low)/range`; trend bar if body/range ≥ `MinBodyRatio` AND close in
extreme `SignalClosePct` toward dir.
Implementation: `CBarAnalyzer::Analyze` (`MQL5/Include/FM/BarAnalyzer.mqh`),
mirror `bar_analyze` (`tests/bar_analyzer.py`).
Automation: EASY. Risks: none at bar level; meaning is 100% contextual.

### Concept: Doji (one-bar trading range)
Brooks: "Doji bars are one-bar trading ranges. Never buy above one in a bear
or sell below one in a bull." A doji after a long trend is a pause, not a
reversal signal.
Observable: tiny body relative to range.
Systematic: `body/range < 0.15` (input `InpDojiMaxBodyRatio`, default 0.15)
→ `isDoji=true`; doji alone NEVER emits a signal; it demotes signal quality.
Implementation: `CBarAnalyzer`, mirror.
Automation: EASY. Risks: low; the risk is in *using* dojis as signals, which
we forbid.

### Concept: Tails / buying & selling pressure
Brooks: tails show rejection; cumulative pressure (bull bars, lower tails,
two-bar reversals) precedes higher prices and vice versa. Effect is cumulative
over 5–10 bars, not decided by one bar.
Observable: upper tail = high − max(close,open); lower tail =
min(close,open) − low; comparable across bars via ATR normalization.
Systematic: tail ratios per bar + `pressureBull/bear` counters (strong closes
in direction over last N bars). Single bar never flips context.
Implementation: `CBarAnalyzer` (per-bar tails) + context engine (cumulative).
Automation: MEDIUM (per-bar EASY, cumulative interpretation MEDIUM).
Risks: over-weighting one large tail.

### Concept: Inside bar (i), consecutive inside bars (ii), outside bar (OO / engulf)
Brooks: inside = consolidation / pause; ii = tightening, breakout imminent in
either direction (breakout mode); outside bar that closes strongly after
engulfing = powerful signal; outside bar closing mid-range after a trend =
exhaustion.
Observable: fully determined by two bars' H/L + close position.
Systematic: `isInside = H[b]<=H[b+1] && L[b]>=L[b+1]` (MT5 shift terms);
`isOutside/engulf` on bodies for signal confirmation; `iiCount` consecutive.
Implementation: `CBarAnalyzer` (+ `CConfirmation::IsSignalBar` engulf path).
Automation: EASY. Risks: ii breaks fail ~50% either way — must pair with
breakout-mode context, never direction alone.

### Concept: Overlap / barbwire
Brooks: three or more largely overlapping bars with dojis = tight trading
range (barbwire); trading it is low-probability; wait for breakout + follow-through.
Observable: overlap ratio between consecutive bodies/ranges.
Systematic: `overlap = bodyOverlap / min(range0,range1)`; `barbwire =
overlap>0.5 on ≥3 of last 5 bars AND ≥1 doji` → context demote to
NO-TRADE / WAIT.
Implementation: `CBarAnalyzer` (pairwise overlap) + market-state engine.
Automation: MEDIUM. Risks: threshold choice is ours.

## 2. Signal bars, entry bars, follow-through

### Concept: Signal bar → entry bar → entry
Brooks: the signal bar is the final bar of a setup; the entry bar is the bar
in which the stop order fills. "Enter on a stop at one tick beyond the signal
bar. You want to be swept into the trade by the market going your way."
Observable: signal-bar geometry (OHLC) + next-bar behavior (entry fills or not).
Systematic: three SEPARATE states — `SETUP_FORMING` (signal bar detected,
no order) → `ENTRY_TRIGGERED` (price trades beyond signal extreme) →
`CONFIRMED` (follow-through close beyond extreme, if required). Indicator
draws setup at stage 1, arrow only at stage 2+.
Implementation: setup engine (Phase 7); FM engine already models
DEVELOPING→CONFIRMED this way (§6 SPEC).
Automation: MEDIUM. Risks: conflating setup with entry (we separate them).

### Concept: Strong vs. weak (bad) signal bar
Brooks: strong = large body, small adverse tail, close near extreme, with-trend
context; bad (BBSB) = small body / mid close / large adverse wick / doji at
wrong location. A good shape in terrible context is still a bad trade.
Observable: geometry fully; context partially (location vs. swings, trend).
Systematic: `ScoreSignal` 0–100 (already implemented, display-only):
body 0–20, wick 0–15, close position 0–15, engulf +10, follow-through +10,
exhaustion breadth 0–20, context 0–10, distance-to-target 0–10.
Implementation: `CConfirmation::ScoreSignal` + mirror `score_signal`.
Automation: MEDIUM. Risks: weights are ours, uncalibrated — labeled scores,
not probabilities.

### Concept: Follow-through (FT) / bad follow-through (BFT)
Brooks: after a breakout/signal, the next bar(s) must extend the move (bull
FT = no bear body, ideally big bull close near high). BFT = disappointment →
trading range likely.
Observable: next 1–2 closed bars fully.
Systematic: `FollowThrough(sig,f)`: next closed bar closes beyond signal
extreme toward f. `RequireFollowThrough` input: with it ON, a signal on the
newest closed bar NEVER confirms same-bar (1-bar delayed path).
Implementation: `CConfirmation::FollowThrough` + engine delayed path.
Automation: EASY. Risks: none; the delay semantics are tested (TESTING #8–9).

### Concept: Second entry (H2/L2)
Brooks: H1 = first bull break above a pullback bar high in a bull trend
(often fails — pullback may not be done); H2 = second such break after another
low = primary entry. Mirror L1/L2 in bear trends. Reliable ONLY in trends;
in ranges every H1/H2 fails.
Observable: pullback swing lows + breaks of their highs (needs swing + trend).
Systematic (planned): H1/H2 counter in pullback analyzer gated on
`context==TREND` with matching direction; range context suppresses to WAIT.
Implementation: Phase 5 (pullback analyzer). Automation: MEDIUM.
Risks: requires trend classification first — wrong context = false H2s.

## 3. Trend / range / transition

### Concept: Trend (strong / weak / channel / spike-and-channel)
Brooks: trends = persistent HH/HL (bull) or LH/LL (bear) with pullbacks that
don't break structure; strong trends have big bars closing on extremes +
follow-through; weak/broad channels overlap more; spike-and-channel = fast
spike then two-sided channel (don't chase the spike, trade the channel or wait).
Observable: HH/HL/LH/LL from swings; body/close stats; overlap.
Systematic: trend_score = (EMA20−EMA50)/ATR; TREND if |score|>0.8 and
range_score>3. Planned extension: overlap% + consecutive-close counts to split
strong vs. channel vs. spike-and-channel.
Implementation: `CContextClassifier` now; extension Phase 3/4.
Automation: MEDIUM. Risks: EMA-gap lags; whipsaw at transitions (hence
TRANSITION state exists).

### Concept: Trading range / breakout mode (BOM)
Brooks: balance; boundaries contain early bull AND bear trends; breakout mode
= tightening range where a breakout either way should have follow-through, but
the FIRST breakout up/down reverses ~50% (trap). Middle of range = NO-TRADE
zone.
Observable: HH−LL bounded over N bars; closes oscillating; ii/barbwire.
Systematic: RANGE if |trend_score|<0.4 and range_score<6; breakout mode if
range narrows 3+ bars + ii present. Middle-third of range → explicit NO-TRADE
with reason.
Implementation: context now; breakout-mode + mid-range veto Phase 4/8.
Automation: MEDIUM. Risks: range boundaries are hindsight-obvious, live-fuzzy.

### Concept: Transition / Always-In ambiguity
Brooks: Always-In = if forced to pick long/short you'd be confident; else the
market is unclear (transition). Almost all Always-In trades need a spike first.
Observable: NOT directly — it is a confidence statement.
Systematic: we operationalize as TRANSITION state with conf≈0.5 + WAIT; never
force a direction. Confidence scores, never "probability".
Implementation: context classifier default. Automation: HARD (judgment call).
Risks: presenting 50/50 as insight — we present it as "no edge, wait".

## 4. Breakouts & failed breakouts

### Concept: Breakout (BO) / breakout bar / breakout pullback
Brooks: close beyond support/resistance (swing, bar extreme, EMA, trend line).
Bulls want a big bull bar closing on its high far above resistance + follow-through.
A small pullback 1–5 bars after the breakout that resumes = breakout pullback
(bullish); if you instead expect failure you call the same bars a failed
breakout, not a pullback (terminology follows belief — we keep both hypotheses
until follow-through decides).
Observable: close vs. reference level + next bars.
Systematic: BO event = close beyond last N-bar extreme or swing ± tolerance;
state PENDING until next bar: follow-through → breakout pullback watch;
reversal back inside → failed-breakout hypothesis wins.
Implementation: `CFailedBreakout` plan Phase 4 (extends existing inverse-MM).
Automation: MEDIUM. Risks: reference-level choice dominates results.

### Concept: Failed breakout / bull & bear traps (2LBLTP / 2LBRTP)
Brooks: big second-leg breakout that quickly reverses, trapping trend chasers;
then range or opposite trend. Wedge-top breakout: ~50% MM / 50% failed BO.
Observable: BO + opposite close back inside within K bars + opposite pressure.
Systematic: failed-BO detector (already: closes beyond leg extreme within
`FailedBOBars` then reclaims → inverse-MM projection, symmetric far-side
anchor). Planned: generalize beyond legs to any reference + trap labels.
Implementation: `CInverseMMHelper` now; generalized engine Phase 4.
Automation: MEDIUM. Risks: inverse anchor unvalidated on real data (flagged).

### Concept: Trapped traders
Brooks: failed BO traps late entrants; their exits fuel the reversal. Exits
above failures / below failures become magnets.
Observable: NOT directly (no order-flow in OHLC).
Systematic: proxy = failure extreme ± small buffer as invalidation/exit magnet
level; never claim to know positioning.
Implementation: S/R engine levels. Automation: HARD (proxy only).
Risks: narrative without order-flow data — keep as level, not story.

## 5. Pullbacks & reversals

### Concept: Pullback (one-leg H1/L1, two-leg H2/L2, deep, shallow)
Brooks: countertrend pause that doesn't break structure; can be one tick or an
inside bar; two-legged pullbacks are the core with-trend entry; shallow =
strong trend; deep = weak trend / possible range.
Observable: depth vs. leg (ratios), leg count via swing pairs, bars elapsed.
Systematic: depth bands — channel family owns [0.02, MinPullbackRatio),
regular owns [MinPullbackRatio, MaxPullbackRatio]; two-leg = two swing pairs
against trend; deep (>0.6) demotes trend confidence.
Implementation: `CLegEqualityMM`/`CChannelMM` now; two-leg counter Phase 5.
Automation: MEDIUM. Risks: leg counting needs confirmed swings (delay honest).

### Concept: Reversal: MTR (major trend reversal) vs. minor reversal (scalp)
Brooks: MTR = trend-line break + failed retest (second entry, often LH/HL
with strong BO) → 2 legs / swing; selling BEFORE the strong BO ≈40%, AFTER
≈60% (bigger stop). Without 5–10 bars of cumulative pressure the reversal is
minor = scalp at best, then flag/range resumes.
Observable: trend-line break (needs line fit — HARD), retest failure, BO
strength, pressure count.
Systematic: MTR proxy = (break of EMA20/slope + retest fail + opposite BO
with follow-through + pressure ≥5 bars) → reversal setup with score; else
minor-reversal label (scalp expectations, tight target).
Implementation: Phase 5. Automation: HARD. Risks: trend lines are the weakest
automation point — use EMA/slope + swings, document substitution.

### Concept: Wedge top/bottom, double top/bottom (incl. micro), H&S
Brooks: 3-push shrinking-range wedge into a level = exhaustion; double top/bottom
= two spikes to ~same price then reversal (often inside flags); micro variants
on 3–5 bars; H&S = failed double-top variant (rare intraday, don't overfit).
Observable: pushes + ranges + level tests — all OHLC-computable with tolerances.
Systematic: `IsWedge` now (≥3 pushes + shrinking ranges ×1.05 or ≥4 pushes);
double = two extremes within tolerance (0.25×ATR) within K bars + reversal bar;
H&S: implement ONLY if double-top generalization covers it (avoid special-case).
Implementation: wedge now; doubles Phase 5. Automation: MEDIUM.
Risks: wedge needs direction + level; doubles without tolerance = noise.

### Concept: Climax / exhaustion
Brooks: move too far too fast → reverses to range or opposite trend (usually
range, not opposite trend!); climax ⇒ ~75% chance of ≥2 legs / hours sideways.
A climax alone is NEVER a reversal — needs break + failed test.
Observable: range ≥2×ATR, consecutive pushes, channel overshoot, stall bars.
Systematic: `ExhaustionAnyCfg` OR-list (climax/stall/pushes≥MinPushes/wedge/
overshoot). Exhaustion is INPUT to DEVELOPING, never a signal alone.
Implementation: `CConfirmation` now; dedicated `CExhaustionAnalyzer` Phase 5.
Automation: MEDIUM. Risks: fading every climax = catching knives; gate on
touch + signal + location.

### Concept: Measuring vs. exhaustion gaps
Brooks: measuring gap (trend-bar gap) projects a MM; exhaustion gap (late
second-leg) gets faded; indistinguishable in real time ("50% MM / 50% failed
BO" above wedges; every trend bar is a BO/gap).
Observable: gap size, close position, push count, level — but TYPE only
knowable after.
Systematic: NEVER label prospectively; gap family projects neutrally, type
assigned retrospectively in DEBUG logs only; live states neutral.
Implementation: `CGapMM` + logger now. Automation: HARD (by doctrine).
Risks: any real-time gap-type label would be dishonest — forbidden.

## 6. Measured moves & fading (existing FM core)

Covered in RESEARCH.md §2–4 + SPEC §4–6; preserved as the MM/FM module
(§13 of master prompt). Rules: Leg1=Leg2 + range/channel/gap/inverse families;
POTENTIAL (approach) → DEVELOPING (touch + exhaustion) → CONFIRMED (reversal
bar + optional follow-through); touch alone never confirms; invalidation on
close-through >0.5×ATR or expiry. FM becomes ONE module feeding the setup
engine, never auto-fading without context.

## 7. Entries, exits, stops, targets, no-trade

### Concept: Entry / stop / target / trader's equation
Brooks: enter on stop 1 tick beyond signal bar; stop below signal/structural
low; target = prior extreme / MM; trader's equation = direction confidence ×
reward/risk must favor the trade; second entries beat first entries; mid-range
and late entries are NO-TRADE.
Observable: levels from bars/swings/MM; equation needs score + R (ours).
Systematic: every setup emits entry/stop/target/R + invalidation; `MinRR`
input (default 1.0) vetoes; mid-range location vetoes; late (beyond 0.5×ATR
past signal extreme) vetoes. Setup ≠ entry ≠ confirmation (three states).
Implementation: Phase 7/8 (setup + decision engines).
Automation: MEDIUM (levels EASY, equation gating MEDIUM).
Risks: R uses our stop/target proxies — honest about construction.

## 8. Explicitly NOT automated (documented limits)

- Exact discretionary trend-line placement (we use EMA/slope + swing proxies).
- Order-flow / trapped-trader positioning (we use failure-extreme proxy levels).
- News/fundamental context (out of scope; indicator is price-only).
- Real-time measuring-vs-exhaustion gap typing (forbidden by doctrine).
- "Probability" claims (scores stay scores until calibrated per §26/Phase 17).
- H&S as a special pattern (covered only via double-top generalization, if at all).
- Predicting the future — engine outputs structured interpretation + WAIT
  liberally, never certainty.

---

## Concept → implementation index (Phase 1 status)

| Concept | State | Files |
|---|---|---|
| Bar anatomy, doji, tails, inside/outside, overlap | NEW Phase 1 | `BarAnalyzer.mqh`, `bar_analyzer.py`, `test_bar.py` |
| Signal bar, follow-through, 2nd-entry delay | DONE (v1–v1.1) | `Confirmation.mqh`, `FMEngine.mqh` |
| Score 0–100 display-only | DONE (v1.2) | `Confirmation::ScoreSignal` |
| Wedge/push exhaustion | DONE (v1.2) | `Confirmation::PushCount/IsWedge` |
| Context Trend/Range/Transition | DONE (v1) → extend Phase 3/4 | `Context.mqh` |
| MM/FM module | DONE (v1–v1.2) | `MeasuredMove.mqh`, `FMEngine.mqh` |
| H1/H2/L1/L2, doubles, MTR, breakout-mode, setup/decision engines | DONE Phases 2/4/5/7/8 | `PullbackPatterns/Breakout/Reversal/GeneralSetups/DecisionEngine.mqh` |
