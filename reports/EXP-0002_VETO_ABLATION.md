# EXP-0002 - structural veto ablation (CONTROL vs TREATMENT)

> Controlled A/B. No parameters optimized. No production logic changed
> (apparatus defaults to production behavior). No edge declared.
> All conclusions provisional (small sample).

## 1. Apparatus audit (can the veto change alone? YES)

- The veto is a SINGLE choke point (`FM_EA.mq5` selection block): Phase-8
  reasons BARBWIRE/MID_RANGE/CONFLICT/NO_EDGE/TRAP_REPEAT skip the bar.
  New input `InpApplyStructuralVeto` (default true) converts skip into
  count-and-continue; `vetoWhy` retained for tagging; reason counters
  `g_vetoByReason[11]` added; `sig=` (setup.signalBar age) appended to the
  selection log. Risk/intent/execution/registry/selection untouched.
- Isolation proof: CONTROL (flag default) reproduces T-014 byte-exact -
  census 38/435 58/3/32, 3 trades -353.49 - PLUS first exact veto split:
  MID_RANGE=102, CONFLICT=326, TRAP_REPEAT=7 (BARBWIRE=0, NO_EDGE=0).

## 2. Arms (identical except the flag; FM_EA 1.00+apparatus, EURUSD H1,
Model 1, $10k 1:100, broker spread, no commission, all defaults, DEMO)

| Arm | Dates | Veto | Report |
|---|---|---|---|
| CTRL_FULL | 11.03-12.03 (528 bars) | ON | T-014 (committed) |
| TREAT_FULL | same | BYPASSED | `FM_EA_X2_TREAT.htm` (local) |
| CTRL_IS | 11.03-11.17 (240) | ON | same as T-018 config |
| TREAT_IS | same | BYPASSED | `FM_EA_X2_TREAT_IS.htm` (local) |
| CTRL_OOS | 11.18-12.03 (264) | ON | same as T-019 config |
| TREAT_OOS | same | BYPASSED | `FM_EA_X2_TREAT_OOS.htm` (local) |

IS/OOS control runs reproduce T-018/T-019 exactly (1/-99.00; 5/+487.82).

## 3. Results

| Segment | Arm | Veto (MID/CONFL/TRAP) | Selections | riskOK | Trades | W/L | Net | PF | Exp |
|---|---|---|---|---|---|---|---|---|---|
| FULL | CTRL | 435 (102/326/7) | 93 | 38 | 3 | 0/3 | -353.49 | 0.00 | -117.83 |
| FULL | TREAT | 435 bypassed | 528 | 199 | 9 | 2/7 | +23.42 | 1.04 | +2.60 |
| IS | CTRL | 207 (51/156/0) | 33 | 33 | 1 | 0/1 | -99.00 | 0.00 | -99.00 |
| IS | TREAT | 207 bypassed | 240 | 190 | 6 | 2/4 | +290.72 | 1.89 | +48.45 |
| OOS | CTRL | 205 (48/155/2) | 59 | 50 | 5 | 2/5 | +487.82 | 2.26 | +97.56 |
| OOS | TREAT | 205 bypassed | 264 | 20 | 3 | 0/3 | -437.41 | 0.00 | -145.80 |

Drawdown (balance): FULL 353->267 | IS 99->203 | OOS 257->437 (treat worse
where it loses). Avg planned-R of fills: CTRL_FULL 5.10, TREAT_FULL 6.42.
MFE/MAE per trade: unavailable in report text (charts only) - not reported.

## 4. The 10 questions

1. Removed: 435/528 (82%), IS 207/240 (86%), OOS 205/264 (78%).
2. Fill rate of removed universe (arm delta): FULL +6/435 (1.4%),
   IS +5/207 (2.4%), OOS -2 (interaction: bypassed fills occupy the single
   slot and displace others - arms are NOT nested, deltas are net effects).
3/4. Profitable share (net deltas): FULL +376.91/6 fills; IS +389.72/5;
   OOS -925.23 (veto protective there).
5. Expectancy: veto hurts IS (-99->+48 without it), helps OOS (+98->-146).
6. Drawdown: veto lowers DD on FULL/OOS, raises nothing on IS (99->203).
7. Quality vs opportunity: bypass multiplies selections ~5.7x (93->528) for
   +6 net fills; veto "quality" shows only in OOS.
8. By strategy: vetoed fills are DOUBLE+BREAKOUT only. PULLBACK fills ZERO
   even unbypassed (chase still blocks - veto is not its problem).
   FM/REVERSAL/FAILED_BO never selected in either arm.
9. By regime (TREAT_FULL 9 fills, EXPLAIN-joined): RANGE 4 trades +439.30
   (2/4: +122.40, +493.29 TP vs -56.07, -120.32 SL); TREND 5 trades -415.88
   (0/5). Planned-R inversely predicted outcome (13.6R plans lost, 1.26R
   won) - far objectives, low hit rate. n=9: hypothesis-grade only.
10. IS vs OOS: OPPOSITE verdicts. The veto's value is regime/window
    dependent on current evidence - the strongest finding of the experiment.

## 5. PULLBACK investigation (no defect found - behavior UNCHANGED)

- Detector scans oldest-first over a 50-bar window (`DetectBull/Bear` break
  at the first match from the old side); the spec (`PULLBACK_PATTERNS.md`)
  requires recency NOWHERE (unlike doubles' "most-recent wins").
- Empirical: pullback signal bars sit ~40+ bars back (`sig=40,43` in log;
  my first `sig=0` reading was my own regex bug matching a group-less
  pattern - corrected, data re-pulled).
- Entries from 40-bar-old extremes are systematically >0.5 ATR behind H1
  market -> chase guard correctly refuses (293/293, incl. firm H2 score-70
  R-6.29 setups). Mechanism correct; no typo/logic defect exists.
- Diagnosis: missing recency requirement = DESIGN characteristic. Fixing it
  (e.g. signal-within-N-bars) is a design change needing its own phased
  hypothesis per project rule 29 - explicitly NOT this experiment.

## 6. Conclusion (provisional, confidence: low - 3-9 trades/arm)

The veto rejects 82% of candidates; bypassing it adds a trickle of fills
(1-2%) whose value flips sign between IS (+) and OOS (-). There is NO
evidence the veto improves trade quality systematically, and NO evidence it
harms it systematically either - its effect is window-dependent at current
sample sizes. It DOES suppress volume ~6x and CANNOT be called "worth it"
on this data. Production logic UNCHANGED (flag defaults ON; apparatus only).
Do not tune, do not relax, do not remove - measure again after EXP-0003/
dormant-strategy work raises per-arm counts.

## 7. Reproduction

Inis (local): `fm_ea_demo_auto.ini` (control), `fm_x2_treat_full.ini`,
`fm_x2_{ctrl,treat}_{is,oos}.ini` - identical except dates + the flag.
Commit: apparatus build used for all 6 runs (this HEAD). Reports
`FM_EA_X2_*.htm` machine-local; tables above are the committed record.
