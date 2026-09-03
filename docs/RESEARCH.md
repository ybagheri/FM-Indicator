# RESEARCH — Fading Measured Moves (Al Brooks Price Action)

> Status: Phase-0 research record. No profitability claims. All systematic
> choices derived below are documented as *our interpretation* unless they
> are direct paraphrases of Brooks' published glossary/course material.

## 1. Sources investigated

Primary (Brooks-authored or Brooks-course-authored):

1. Al Brooks, *Trading Price Action Trends* / *Ranges* / *Reversals*
   (glossary definitions of leg, pullback, measuring gap, measured move,
   fade, breakout, climax, exhaustion, reversal bar). Accessed via the
   *Ranges* PDF glossary and the official Brooks glossary page
   (`brookstradingcourse.com/price-action-trading-terms-glossary`).
2. Brooks Trading Course webinar PDF, *Distinguishing Strong Legs within
   Trading Ranges and Trends* (Al Brooks, May 2016) — measuring vs.
   exhaustion gaps, 2nd-leg trap, "strong breakout above wedge: 50% MM /
   50% failed BO".
3. Brooks CME PDFs: *Advanced Big-Bar Techniques* (Jul 2018) and
   *Advanced Gap Techniques* (2018) — big-bar MM probabilities
   (60–70%), exhaustion vs. measuring gap disambiguation, "every trend
   bar is a BO and a gap", multiple candidate MM bottoms.
4. Brooks coaching PDF *Session #3: MTRs* (Aug 2025) — major-trend-reversal
   structure (trend-line break + failed test), MA-gap bars leading to
   final legs.
5. Brooks Trading Course support forum threads: "Measured Move for Taking
   Profit in Bear Trend" (Jul 2024), "Measured Move from Failed Leg 1 =
   Leg 2" (Jan 2024) — practitioner evidence that (a) traders start from
   the *conservative* target and step to further targets, (b) inverse
   (opposite-direction) MMs from failed legs are watched in practice.
6. Brooks Trading Room recaps (Nov 2024) — MM as *magnet/cluster*,
   profit-taking at MM targets by bulls AND scalping by bears, tick-level
   test overshoot/undershoot, exhaustion-gap closure logic.
7. Flashcards / acronyms derived from the course (L1=2 = "Leg 1 equals
   Leg 2 measured move"; H1/H2, L1/L2 second-entry counts).

Secondary (methodology summaries, used only for cross-checking):

8. TradeLossTracker extended summary of *Trading Price Action Trends* —
   table of MM variants (Leg1=Leg2 ~60%, channel/TR breakout ~55–60%,
   gap projection ~50%), exhaustion checklist (climax, channel overshoot,
   wedge/3-pushes, trend-line break, failed retest, MM target reached).
9. Trasignal blog, *Al Brooks Price Action Explained: 10 Key Concepts
   (2026)* — Always-In thought experiment, High-2/Low-2 as
   context-dependent (not automatic) entries, trend vs. range vs.
   transition triage.

MQL5 engineering sources:

10. Boyko (2026), *Modular Indicator Architecture in MQL5 (Part 1)* —
    sub-indicator classes, `CSubIndiBase`/`CIndicatorBase`, buffer
    ownership, incremental recalculation, `tester_everytick_calculate`.
11. Cercos Pérez (2022), *Complex indicators made easy using objects* —
    buffer/plot encapsulation, polymorphism for draw styles.
12. Maroa (2026), *Custom Indicator Workshop Parts 1 & 3* (Supertrend,
    UT Bot) — non-repainting discipline (freeze closed bars, update only
    last closed bar + forming bar), separation of DATA vs. CALCULATIONS
    buffers, documented EA-readable buffers.
13. MQL5 Reference, *Indicator Styles in Examples*; Umarov (2013),
    *Extending MQL5 Standard Library* (ZigZag wrapper) — buffer limits,
    `SetIndexBuffer`, `PLOT_DRAW_BEGIN`.

No single forum post, video, or AI summary was treated as authoritative.
Where Brooks is silent or ambiguous, this document says so.

## 2. What Brooks actually says (attributable)

- **Leg**: "a small trend that breaks a trend line of any size; the term
  is used only where there are at least two legs on the chart" (glossary).
  A leg can be with-trend or a pullback leg.
- **Pullback**: "a temporary pause or countertrend move … that does not
  retrace beyond the start of the trend/swing/leg" (glossary). Can be as
  small as one tick beyond the prior bar or an inside bar.
- **Measured move (bull/bear trend)**: "a leg … about equal in size to
  something earlier in the trend, e.g. an earlier leg or the height of a
  trading range" (glossary). Deliberately approximate ("about equal").
- **Measuring gap**: a breakout (trend bar) whose gap (close vs. breakout
  point) leads to a MM; **micro measuring gap**: non-overlap around a
  strong trend bar often leads to a MM.
- **Fade**: "to place a trade in the opposite direction of the trend
  (e.g. selling a bull breakout you expect to fail)" (glossary).
- **Test**: approaching a significant price "can overshoot or undershoot
  the target" (glossary). Exact touches are NOT required.
- **Probabilities Brooks states** (empirical, market/order-flow beliefs,
  not mathematical theorems): strong breakouts lead to MM ~60–70%;
  wedge-top breakout ~50% MM / 50% failed BO and reversal; bull channel
  BO fails ~75%; climax ⇒ ~75% chance of ≥2 legs / 2 hours sideways-down
  on intraday. We do NOT hard-code these as detection thresholds; they
  inform alert wording and default tolerances only.
- **Several candidate MM bottoms usually exist** ("different computers
  use different starting points"); traders take profits at *whichever*
  target stalls first, then watch the others (Gap Techniques PDF).
- **2nd-leg trap**: a strong 2nd leg in a trading range/channel is often
  an *exhaustion* gap, not a measuring gap — the expert fades it while
  the beginner chases it (2016 webinar). This is the closest Brooks comes
  to an explicit "fade the MM" doctrine.
- **Major trend reversal = trend-line break + failed retest**
  ("everything else is decoration"). A climax alone is never a reversal.
- **Inverse MMs**: a strong BO has a MM target "in either direction";
  failed Urbull legs produce bearish inverse-MMs and vice versa (room
  recap; forum thread). Brooks mentions "MM in opposite direction from a
  failed breakout" explicitly (forum Q, consistent with course video 20A
  per recap).

## 3. Conflicts / ambiguities and our resolutions

| # | Ambiguity | Resolution for v1 (configurable) |
|---|-----------|----------------------------------|
| 1 | Leg start/end have no official bar-count or size rule. | Fractal swing (k left/right) + `MinLegATRMult` (default 1.0×ATR) + `MinLegBars` (3) + `MaxLegBars` (100). All inputs. |
| 2 | "About equal" is not a number. | `MMToleranceATRMult` (default 0.25×ATR) band around target; `MaxOvershootATRMult` (0.5) before invalidation. |
| 3 | Pullback depth unbounded ("one tick … to almost 100%"). | `MinPullbackRatio` 0.15, `MaxPullbackRatio` 0.90 of Leg1 by price; `MaxPullbackBars` 50. Inside-bar pause counts as pullback (ratio ~0). |
| 4 | Which MM variant? (Leg1=Leg2, range height, channel, gap, spike+channel, inverse…) | v1 implements **Leg1=Leg2 (AB=CD)** + optional **inverse-MM from failed BO** flag. Range/channel/gap variants are architecture-reserved (subclass `CMeasuredMove`) but NOT implemented — see ROADMAP. |
| 5 | Measuring vs. exhaustion gap indistinguishable in real time. | Never label prospectively. Gap type is assigned *retrospectively* only in debug logs; live states are neutral (APPROACHING/POTENTIAL/DEVELOPING/CONFIRMED). |
| 6 | Touch ≠ fade (Brooks: tests overshoot/undershoot; profit-taking clusters). | Three states: POTENTIAL (in approach zone) → DEVELOPING (touches tolerance band + exhaustion/stall proxy) → CONFIRMED (objective reversal bar + optional next-bar follow-through). Touch alone only yields DEVELOPING, never CONFIRMED. |
| 7 | Signal-bar definition is discretionary. | Operationalized: opposite-direction trend bar closing in extreme 50% (configurable `SignalClosePct`), min body ratio, max wick ratio, optional engulf/outside-bar and failed-BO modes. |
| 8 | Brooks is discretionary about context (trend vs. range). | Context classifier outputs Trend/Range/Transition with a *confidence* and never vetoes silently: weak context demotes CONFIRMED→DEVELOPING only if `ContextFilterMode` demands it; default logs context without veto (faithful to "context, not trigger"). |
| 9 | "Conservative first target, then step out" (forum). | Engine keeps ALL active projections (bounded list); visualization emphasizes nearest unhit target; alerts fire per-setup with ID so stepping is visible. |
| 10 | Repaint risk from fractal/swing confirmation delay. | Swings confirmed only after k bars; MM exists only from confirmed swings; backfill draws with `confirmed_shift` marker; real-time signals only on closed-bar or explicit intrabar POTENTIAL (documented). |

## 4. What is Brooks vs. what is ours

- **Brooks**: legs, pullbacks, measuring/exhaustion gaps, MM ≈ prior
  swing, fade = counter-trend trade, tests overshoot/undershoot,
  MTR = break + failed test, 2nd-leg trap, multiple candidate targets.
- **Ours (systematic proxies)**: fractal-k swings, ATR-normalized sizes,
  pullback ratios, tolerance bands, exhaustion proxy checklist
  (climax bar, consecutive pushes, channel overshoot, wedge count,
  stall/doji), signal-bar geometry thresholds, state machine
  (IDLE→…→CONFIRMED/INVALIDATED), ATR-based invalidation. These are
  *defensible operationalizations*, not "official Brooks rules", and are
  labeled as such in the spec and README.

## 5. Implications for the MVP scope

- One MM family (Leg1=Leg2 + failed-BO inverse), one confirmation
  family (reversal-bar + optional follow-through), three FM states.
- Quality over quantity: defaults tuned so a day chart shows a handful
  of setups, not hundreds.
- Honest history: confirmation-delay markers, no future-bar swings,
  frozen closed-bar signals.
