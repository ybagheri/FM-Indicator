# FINAL FORENSIC REVIEW - pre-forward diagnostic (no logic changes)

> Scope: HEAD `db79511`. Every trade number below was re-parsed from the
> committed `reports/*.htm` deal tables (strategy from `FM|strat|` order
> comments, P/L from matched OUT deals) or quoted from `docs/MT5_TESTING_STATUS.md`
> run records and `docs/experiments/EXP-0001`. Strategy enum: 1=FM_FADE,
> 2=PULLBACK, 3=BREAKOUT, 4=REVERSAL_MTR, 5=DOUBLE, 6=FAILED_BO.
> Nothing here is inferred beyond what the files contain.

## 1. Trade census (all order-generating runs; 23 real trades total)

| Run | Trades | W/L | Net | PF | By strategy (net) |
|---|---|---|---|---|---|
| T-014 AUTO EURUSD | 3 | 0/3 | -353.49 | 0.00 | BO -99.00; DBL -173.53, -80.96 (all SL) |
| T-016 SINGLE_DBL EURUSD | 4 | 1/3 | -37.44 | 0.86 | DBL +231.25 (TP), -179.56, -83.52, -5.61 (SL) |
| T-019 OOS AUTO EURUSD | 5 | 2/5 | +487.82 | 2.26 | DBL -175.54, -81.28, +665.50 (TP); BO -129.72 (SL), +208.86 (TP) |
| T-020 XAUUSD AUTO | 10 | 5/5 | +158.32 | 1.33 | DBL -184.20, +2.80*, -147.90, -55.20, -19.03, +2.00*, +1.40*, +630.30 (TP), -72.45; PB +0.60* |
| T-015 SINGLE_PB | 0 | - | - | - | 51 LATE + 18 PROV_OFF, verified in log |
| T-018 IS AUTO | 1 | 0/1 | -99.00 | 0.00 | BO (IN comment strat 3) |

`*` = SL exit at a profit (BE-moved stop - BE path proven live).
Per-strategy totals: DOUBLE 18 trades (6/18, about +274 net); BREAKOUT 4
trades (-99.00, -129.72, +208.86, IS -99.00: net about -119); PULLBACK 1
(+0.60); FM_FADE 0; REVERSAL_MTR 0; FAILED_BO 0.

## 2. Sample size vs performance (Q3 - separated explicitly)

- INSUFFICIENT SAMPLE (no conclusion possible either way): everything.
  Largest arm is DOUBLE with 18 trades; FM/REVERSAL/FAILED_BO have ZERO
  live trades; PULLBACK has ONE scratch. No win rate, PF, or expectancy
  anywhere here clears a significance bar - including the "good" ones
  (T-019 PF 2.26 on 5 trades; T-020 PF 1.33 on 10 trades).
- EVIDENCE OF POOR PERFORMANCE (not just small-n): T-014 AUTO 0/3 with all
  SL exits and OnTester -0.15 (ranks below do-nothing BY CONSTRUCTION of the
  criterion); SINGLE_PB structurally unable to fill on H1 (293 selections to
  0 fills: entries systematically stale, see section 5). These are mechanism
  observations, not noise complaints.

## 3. Strategy activity audit (Q4)

- DOUBLE: the ONLY consistently active strategy (220 selections/528 bars;
  18/23 live trades; 6 of 7 total wins). Carries 100% of gross profit
  (+1526.75 from 3 TP wins: +231.25, +665.50, +630.30).
- BREAKOUT: marginal (14 selections; 4 trades; 1 TP win +208.86).
- PULLBACK: selection-rich (293) but fill-dead on H1 (chase-blocked); the
  single fill is an XAU scratch. Effectively inactive as a trade source.
- FM_FADE: 1 selection in 1294+ bars (vetoed LOW_RR, R 0.63) - the flagship
  concept is empirically near-dormant at Balanced thresholds.
- REVERSAL_MTR: 0 selections in every census on record - dormant.
- FAILED_BO: 0 outcomes in every window - dormant (a failure simply never
  printed on these bars/TFs).

## 4. Why AUTO shows no value (Q5)

AUTO (T-014: -353.49, PF 0.00) underperforms SINGLE_DBL (T-016: -37.44,
PF 0.86) on the same window because AUTO's mix adds a BREAKOUT loss and the
same DOUBLE losses while contributing no offsetting winners; SINGLE_PB adds
nothing (0 fills). AUTO's theoretical benefit (regime rotation) cannot
manifest when 4 of 6 strategies never fire. Verdict stands: diversification
logic with nothing to diversify across yet.

## 5. EXP-0001 rejection - precise evidence (Q6)

Grid (SINGLE_DBL, 9 H1 cells, re-verified from `FM_EA_grid_*.htm` today):
rows chase {0.25: 5/-116.89/PF0.66; 0.50: 6/+541.16/PF2.49;
1.00: 9/+811.78/PF2.22}, columns minRR {0.5,1.0,1.5} byte-identical within
rows. Rejected because: (a) 5-9 trades/cell is noise - the "best" cell's
+811.78 rests on about 2 TP wins; (b) no plateau - net rises monotonically
with looser chase, the signature of fitting noise, not finding structure;
(c) minRR is a dead knob here (all double Rs at 1.5 or above); (d) IS-only,
single window. Correct call; nothing to salvage except the consec-cap
finding (section 6).

## 6. The two bugs - fixed and verified (Q7)

- (a) Consec-loss freeze masking grid: with cap 3, cells saturated
  (`CONSEC_LOSSES` lines in agent log; first grid attempt compressed).
  Design-correct behavior, measurement confounder. Re-ran grid cap-0 for
  measurement; production default stays 3; baselines T-014/16 froze
  terminally (3 consec losses) exactly as designed.
- (b) Inverted-risk fills: SELL filled above its stop (4 cases, phantom +R
  up to R 11.27 in pre-fix PAPER). Fixed by `GateSide` in all six builders
  (+ mirror `side_ok` + 5 suites); post-fix PAPER T-021: 6 trades, 4
  `SKIP_WRONG_SIDE`, sane R. T-013 numbers (+3605.51) are SUPERSEDED and
  must never be cited.
- Baseline re-runs post-fix (AUTO/PB/DBL): byte-identical metrics
  (-353.49 / 0 trades / -37.44) - the fix binds only the 4 cases and
  send-time stop-level had covered DEMO. Committed reports predate the fix
  but are numerically unaffected (stated, not hidden).

## 7. Over-restriction audit (Q8 - the full funnel, H1 EURUSD T-010/11)

528 bars into 528 candidates into 435 structural vetoes (82%; sampled
reasons CONFLICT/MID_RANGE - context-driven, mode-independent) into 93
selections into 86 riskOK (LOW_RR 47 pre-veto in T-010) into intents:
125 WOULD_ vs 356 LATE_ENTRY + provisionals OFF (18) + WRONG_SIDE (4).
Session filter never binds (0/24); spread gate never observed binding;
emergency never used; drawdown halt never near (max 7% vs 20%).
Suppression ranking: (1) structural vetoes 82% - by far the largest gate;
(2) chase 67% of remainder; (3) RR/provisional/side small. Whether (1) is
"too much" is calibration-unknown: CONFLICT fires on flat state splits and
MID_RANGE on third-of-range - both plausible in a choppy month, both
unvalidated against outcomes. This is the highest-leverage unknown in the
system.

## 8. Diagnosis - lack of edge, ranked (Q9)

1. INSUFFICIENT SAMPLE (dominant): 23 trades total; 0 for half the
   strategies. Nothing else can be concluded firmly.
2. OVERLY RESTRICTIVE FILTERS (likely, unquantified): 82% veto + 67% chase
   block leaves about 17% of bars tradeable; the vetoes were never
   back-tested against outcomes (they filter analysis, not validated edge).
3. WEAK SETUP DEFINITIONS (suspected for FM/REVERSAL/FAILED_BO):
   near-zero occurrence at Balanced thresholds across 1294+ bars suggests
   thresholds describe rare events, not necessarily good ones.
4. POOR ENTRY TIMING (confirmed for PULLBACK): 293/293 stale - entries are
   systematically behind H1 market speed at 0.5xATR chase.
5. STRATEGY SELECTION (confirmed): AUTO mixes a loss-making tail (BO) with
   DBL without compensation.
6. STOP/TARGET logic: no adverse evidence (losses are clean SL exits at
   planned stops; 3 TPs paid 4-7R; BE scratches work). Not a suspect.
7. REGIME MISMATCH (hypothesis-grade, n=6): range 2/4 +704.63 vs trend 0/2
   -226.16 - directionally sensible, statistically weightless.
8. GENUINELY WEAK PERFORMANCE: not established - sample forbids the claim.

## 9. What is proven / not proven / inconclusive

- PROVEN: determinism (parity runs, byte-identical censuses); 100% buffer
  readability; alert path; order/modify/BE/deal-scan mechanics; all gates
  fire as specified; 0 runtime errors in 20+ runs; scoring/reporting
  integrity (phantom-R bug caught by regime table, fixed, re-verified).
- NOT PROVEN: any edge; AUTO value; preset suitability (M1 never EA-tested);
  trail/halt/adopt live behavior; visual correctness; repaint-freedom
  (untested vs history); CSV walk-forward path.
- INCONCLUSIVE (and must stay labeled so): T-019/T-020 green numbers,
  regime split, chase monotonicity, XAU-vs-EURUSD difference.

## 10. Recommended next experiments (in order; none started)

1. EXP-0002: veto-ablation measurement - run AUTO with vetoes
   logged-but-not-applied (code flag, one phase) to measure what the 435
   vetoed bars would have done. Highest information value in the system.
2. EXP-0003: pullback entry-timing - chase {0.5,1.0,1.5} x hold {5,10} on
   SINGLE_PB across 3 months (needs fills first; if still 0, redefine
   entry, don't loosen blindly).
3. Dormant-strategy study: 6-month M15/H4 scan counting FM/REVERSAL/
   FAILED_BO occurrences before any threshold change (are they rare or
   misdefined?).
4. Only then: re-grid on 30-plus-trade arms with plateau rule + OOS hold.

## 11. What must NOT change yet

Thresholds, veto structure, score formulas, family definitions, permits,
sizing, modes, presets (esp. the blessed baseline). The system just earned
trust in its plumbing by REPORTING bad news accurately - tuning now would
trade that for fitted noise.

## 12. PAPER forward requirements (2 weeks - exact)

- Build: current HEAD; mode PAPER; `FM_EA_Auto_Baseline.set` + documented
  overrides only; EURUSD H1 primary (XAUUSD H1 mirror optional).
- Logging: `InpLogLevel=DEBUG` first 48h (veto/reason mix), then INFO;
  preserve Experts log daily; no log gaps over 1h unexplained.
- Halt drill once: `InpEmergencyStop=true` gives `HALT EMERGENCY_STOP`,
  zero new virtuals; then reload with flag off.
- Success data (not profit): 90%+ bars analyzed; veto/reason mix within
  15pts of T-011 shares; at least 1 virtual trade closed per week OR a
  written dormancy note (feeds EXP-0003/0001 follow-ups).
- Abort (then report, don't tweak): any runtime error; any REAL order
  (`EXEC_` in PAPER mode = critical defect); halt latch without cause.
- Delivered at end: log archive + regime table + degradation note vs T-021
  expectations. No parameter changes during the 2 weeks, whatever happens.
