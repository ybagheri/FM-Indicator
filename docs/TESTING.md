# TESTING — FM Indicator v1.2 + v2 research + Phase-1..8 engines

## Method

- Oracle: `tests/fm_engine.py` (1:1 mirror of SPEC). MQL5 must match it on
  identical synthetic series.
- Bar oracle: `tests/bar_analyzer.py` (1:1 mirror of BAR_BY_BAR_ENGINE.md).
- Pullback oracle: `tests/pullback_patterns.py` (1:1 mirror of PULLBACK_PATTERNS.md).
- State oracle: `tests/market_state.py` (1:1 mirror of MARKET_STATE.md).
- Breakout oracle: `tests/breakout.py` (1:1 mirror of BREAKOUT_ENGINE.md).
- Reversal oracle: `tests/reversal.py` (1:1 mirror of REVERSAL_ENGINE.md).
- Setup oracle: `tests/setup_engine.py` (1:1 mirror of SETUP_ENGINE.md).
- General oracle: `tests/general_setups.py` (1:1 mirror of GENERAL_SETUPS.md).
- Decision oracle: `tests/decision.py` (1:1 mirror of DECISION_ENGINE.md).
- LTF oracle: `ltf_bias` + `ltf_confirm` in `tests/fm_engine.py` (mirror of
  MARKET_CONTEXT.md §5; same SMA-gap math as `mtf_bias` via shared helper).
- Run: `python3 -m pytest tests/ -q` → 97 tests, ALL PASS (19 FM + 7 bar +
  10 pullback + 9 state + 9 breakout + 10 reversal + 10 setup + 10 general +
  10 decision + 3 LTF; or per-file via `__main__`).
- MQL5 compile: MetaEditor on Windows (F7). Linux env has no
  `metaeditor.exe`/`wine`; static check = balanced-delimiter scan
  (comment/string-stripped) over all 21 MQL5 files → OK.

## Cases → expected

| # | Case | Expected | Result |
|---|---|---|---|
| 1 | Swing appears before k bars | absent (no look-ahead) | PASS |
| 2 | Bull lifecycle A0 90/A1 100/B0 95 → T 105, approach→stall→signal | POTENTIAL→DEVELOPING→CONFIRMED→COMPLETED | PASS |
| 3 | Touch target, no exhaustion | stays POTENTIAL | PASS |
| 4 | Close 1.5 over target (>0.5×ATR 1.0) | INVALIDATED | PASS |
| 5 | Pullback depth 0.10 / 1.10 | rejected (needs 0.15–0.90) | PASS |
| 6 | Flat market, ATR≈0; 4-bar history | no crash, no swings | PASS |
| 7 | Close mode ignores wick spike | H/L catches, CLOSE ignores | PASS |
| 8 | Follow-through delay (RequireFT) | no same-bar confirm; confirm next bar | PASS |
| 9 | Follow-through without close-through | stays DEVELOPING | PASS |
| 10 | Push count + wedge (4 shrinking pushes) | wedge true, exhaustion true | PASS |
| 11 | Range-height breakout (close > HH) | RANGE proj, T=close+height | PASS |
| 12 | Channel shallow-only (depth 0.10) | CHANNEL fires; depth 0.50 rejected | PASS |
| 13 | Measuring gap (micro-gap + strong close) | GAP proj, T=close+gap | PASS |
| 14 | Score bounds (good bar ≥50, zero ATR →0) | 0..100, no crash | PASS |
| 15 | Signal bar on newest closed bar | allowed (v1.1 fix) | PASS |
| 16 | Dedup family-aware | cross-family same target coexists | PASS |
| 17 | MTF bias + MAE/MFE | +1/−1/0; MAE/MFE exact | PASS |
| 18 | CSV export + backtest harness | no crash, schema valid | PASS |
| 19 | Exhaustion cfg variants | zero ATR never exhausts | PASS |
| 20 | H1→H2 two-leg (bull gate) | legs==2, signal/anchor/ref/stop exact | PASS |
| 21 | H1-only, no second leg | legs==1, signal==anchor | PASS |
| 22 | L1/L2 mirror (bear gate) | legs==2; bull side silent | PASS |
| 23 | Gate 0 (sideways) | no pullback signals either side | PASS |
| 24 | Chop with gate forced | H1-only fires → documents H1-alone risk | PASS |
| 25 | Swing double-top in tol | found, most-recent pair wins | PASS |
| 26 | Swing double-top rejected | out-of-tol / shallow-trough / too-far → none | PASS |
| 27 | Double-bottom mirror | found; no-trough variant silent | PASS |
| 28 | Micro double (top+bottom) | found micro:true; shallow dip rejected | PASS |
| 29 | Freeze + no-look-ahead + safety | identical after extension; zero-ATR/tiny-history safe | PASS |
| 30 | Bull trend state | BULL_TREND, pcts sum 100, trend+pressure evidence | PASS |
| 31 | Bear trend mirror | BEAR_TREND, pcts sum 100 | PASS |
| 32 | Bull channel grind | BULL_CHANNEL on overlap+bounded+lean | PASS |
| 33 | Trading range | TRADING_RANGE, balanced pressure | PASS |
| 34 | Breakout mode | tightening tips RANGE→BOM | PASS |
| 35 | Transition weak floor | all raws <1.0 → TRANSITION, pcts kept | PASS |
| 36 | Unknown tiny history | UNKNOWN, pcts all 0 | PASS |
| 37 | State freeze + safety | identical after extension; zero-ATR/disabled safe | PASS |
| 38 | Pcts sum + determinism | sum==100 + identical re-run on 3 regimes | PASS |
| 39 | Bull BO pending at newest | event at idx, ref NBAR, decideBar −1 | PASS |
| 40 | Bull follow-through | hold beyond ref → FOLLOW | PASS |
| 41 | Bull failed precedence | extend-then-reverse → FAILED | PASS |
| 42 | Bear mirror | bear FOLLOW, NBAR ref | PASS |
| 43 | Swing ref tie-break | swing wins, newest swing price | PASS |
| 44 | Tolerance poke | inside tol → none | PASS |
| 45 | Second-leg trap armed | fail then re-break → TRAP + PENDING | PASS |
| 46 | Stale BO outside window | beyond FollowBars → none | PASS |
| 47 | BO freeze + safety | identical after extension; zero-ATR/tiny/disabled safe | PASS |
| 48 | Climax bar (range ≥2×ATR) | climax true, breadth OR-sum exact | PASS |
| 49 | Stall bar (narrow, two-sided wicks) | stall true, no climax | PASS |
| 50 | 4 shrinking pushes | pushes 4, wedge true, bear silent | PASS |
| 51 | Overshoot spike | overshoot true; short history silent | PASS |
| 52 | Breadth OR-parity | quiet 0; single-flag ≥1; beyond-close/zero-ATR 0 | PASS |
| 53 | Bull pullback legs 1→2+deep | legs 1/2, depth 0.5/0.8, DEEP; empty/no-anchor safe | PASS |
| 54 | Bear legs mirror | legs 2, depth 0.8, DEEP | PASS |
| 55 | MTR MAJOR (all four legs) | MAJOR, score 100, BO FOLLOW + pressure | PASS |
| 56 | MTR MINOR (partial legs) | MINOR, score 50, EMA + retest only | PASS |
| 57 | Reversal freeze + safety | identical after extension; zero-ATR/tiny/disabled safe | PASS |
| 58 | Sell plan geometry | entry/stop/obj/R exact, RRok, firm | PASS |
| 59 | Buy plan mirror | entry/stop/obj/R exact, invalidClose echo | PASS |
| 60 | Stop on signal extreme | structure = signal extreme + buffer | PASS |
| 61 | Stop on target zone | structure = T+tol + buffer | PASS |
| 62 | Objective beyond entry | reward ≤0 → invalid | PASS |
| 63 | Zero risk (flat, no buffer) | risk 0 → invalid | PASS |
| 64 | MinRR threshold | RRok above, RRlow below | PASS |
| 65 | Provisional + families | DEVELOPING prov; all 5 families pass through | PASS |
| 66 | InvalidClose + safety | ±over echo; disabled/zero-ATR/bad-dir safe | PASS |
| 67 | Plan determinism | identical re-run | PASS |
| 68 | Pullback H2 firm | entry/stop/obj/R exact, score 70 | PASS |
| 69 | Pullback H1 provisional | tick/buf math, score 40, bear mirror | PASS |
| 70 | Swing double-top | entry/stop/trough/R exact, score 60 | PASS |
| 71 | Micro double + bottom mirror | provisional, score 30; buy geometry | PASS |
| 72 | Breakout FOLLOW + trap | firm, score 70→50 on trap | PASS |
| 73 | Breakout PENDING/FAILED | provisional 40; FAILED/none silent | PASS |
| 74 | Reversal MAJOR/MINOR | firm 80 / provisional 40, EMA stop | PASS |
| 75 | General RR + invalid | MinRR flag; bad obj / zero risk invalid | PASS |
| 76 | Selection + safety | max-score wins, type-order ties; disabled/zero-ATR/bad-dir safe | PASS |
| 77 | General determinism + freeze | identical re-run; extension untouched | PASS |
| 78 | Clean BUY/SELL | direction pass-through with OK | PASS |
| 79 | Disabled + no setup | NO_TRADE DISABLED/NO_SETUP | PASS |
| 80 | Barbwire + mid-range | NO_TRADE structural vetoes | PASS |
| 81 | Conflict + no-edge | CONFLICT veto; UNKNOWN-guard; TRANSITION→NO_EDGE ordering | PASS |
| 82 | Low score + low RR | WAIT both sides incl. boundary 40 | PASS |
| 83 | Late chase | WAIT both sides past 0.5×ATR | PASS |
| 84 | Trap repeat | NO_TRADE ≥2 fails; FOLLOW rescues; <2 passes | PASS |
| 85 | Priority order | barbwire > mid-range > conflict > score | PASS |
| 86 | Zero-ATR late guard | no crash, no false late | PASS |
| 87 | Decision determinism + freeze | identical re-call; pure inputs | PASS |
| 88 | LTF bias geometry | up +1 / down −1 / short-history + flat 0; matches HTF math | PASS |
| 89 | LTF confirm states | AGREE / DISAGREE / NEUTRAL (zero bias/dir) | PASS |
| 90 | LTF determinism | pure re-call identical | PASS |

## Coverage map (prompt §TESTING 1–12 + v1.2/v2)

1 Compilation — MetaEditor (user-side) + static scan here. 2 Init — `OnInit`
buffers/`PLOT_DRAW_BEGIN`/config validate. 3 History — full recompute on
first `prev_calculated==0`. 4 New-bar — `time[1]` change gate. 5 Intrabar —
preview-only flag, never DEVELOPING/CONFIRMED. 6 Alerts — `ClaimAlert`
once-per-(id,state) + cooldown. 7 Objects — `FM_<id>_*` diff-sync + delete.
8 Multi-setup — capped list (nearest-first eviction via `EvictIfNeeded` +
INVALIDATED prune), per-setup state, family-aware dedup. 9 Edge —
flat/zero-ATR/tiny-history/gaps/large bars safe. 10 Recalc —
closed-bar freeze, shifts never rewritten. 11 No-look-ahead — test 1.
12 Repaint — swing-price freeze + one-transition-per-bar.
v1.2 — families (11–13), wedge counter + score (10, 14), newest-bar signal (15).
v2 — MTF/MAE/MFE/CSV/backtest (17–18).
Phase 1 bar engine (`test_bar.py`, 7 suites): strong/doji geometry + doji
run-reset; inside/outside/ii; overlap/barbwire/tightening; gap parity with
`CGapMM`; runs + pressure counters; freeze/no-look-ahead/tiny-history/zero-ATR.
Phase 2 pullbacks (`test_pullback.py`, 10 suites): H1→H2 two-leg; H1-only;
L1/L2 mirror + bull-side silence; gate-0 suppression; chop-with-gate-forced
(H1-alone risk record); swing double-top in-tol (most-recent wins) + rejected
(tol/trough/distance); double-bottom mirror; micro top+bottom (halved trough);
freeze/no-look-ahead/zero-ATR/tiny-history safety.
Phase 3 states (`test_state.py`, 9 suites): bull/bear trend; bull-channel
grind; trading range; breakout-mode (tightening tips RANGE→BOM); transition
weak floor (all raws <1.0, pcts still published for Phase-8 conflict rule);
unknown tiny history; freeze/no-look-ahead/zero-ATR/disabled safety;
pct-sum-100 + winner determinism across regimes.
Phase 4 breakouts (`test_breakout.py`, 9 suites): bull pending/follow/failed
(FAILED precedence); bear mirror; swing-ref tie-break; tolerance poke silent;
second-leg trap armed; stale BO outside FollowBars silent;
freeze/no-look-ahead/zero-ATR/tiny-history/disabled safety.
Phase 5 reversals (`test_reversal.py`, 10 suites): climax/stall geometry;
shrinking 4-push wedge (+bear-side silence); overshoot spike vs short-history
silence; breadth OR-parity (quiet 0, single-flag ≥1, beyond-close/zero-ATR 0);
bull legs 1→2+deep (depth 0.5/0.8) + empty/no-anchor cases; bear mirror;
MTR MAJOR (EMA-cross + retest + Phase-4 FOLLOW + pressure, score 100);
MTR MINOR (EMA + retest only, score 50);
NONE/freeze/no-look-ahead/zero-ATR/tiny-history/disabled safety.
Phase 6 setup plans (`test_setup.py`, 10 suites): sell geometry exact
(entry/stop/objective/R/invalidClose); buy mirror; stop anchored on signal
extreme vs on target zone; invalid on objective-beyond-entry and on zero
risk; MinRR flag both sides; provisional flag + all-five-family
passthrough; invalidClose echo + disabled/zero-ATR/bad-dir safety;
determinism.
Phase 7 general setups (`test_general.py`, 10 suites): pullback H2 firm
geometry (tick-proxy entry, buffered stop, window objective, score 70);
H1 provisional + bear mirror (score 40); swing double-top geometry exact
(score 60); micro provisional (score 30) + double-bottom mirror; breakout
FOLLOW firm + trap penalty (70→50); PENDING provisional (40) + FAILED
silence; reversal MAJOR firm (80, EMA stop) + MINOR provisional (40);
MinRR threshold + invalid reward/risk; selection (max-score, type-order
ties) + disabled/zero-ATR/bad-dir safety; determinism + freeze.
Phase 8 decisions (`test_decision.py`, 10 suites): clean BUY/SELL
pass-through; disabled + no-setup; barbwire + mid-range structural vetoes;
conflict veto (UNKNOWN-guard, TRANSITION→NO_EDGE ordering); low-score
(boundary 40 earns) + low-RR waits; late chase veto both sides; trap-repeat
veto + follow rescue + sub-threshold pass; priority order; zero-ATR safety;
determinism + freeze (pure inputs).
LTF confirmation (`test_ltf.py`, 3 suites): bias geometry (up/down/flat/
short-history; parity with `mtf_bias`); confirm AGREE/DISAGREE/NEUTRAL;
purity + determinism.

## Reproduce

```
cd FM-indicator && python3 -m pytest tests/ -q
```

## Known limits

No tick-level MT5 tester run in this env; no statistical/PTR walk-forward yet;
inverse-MM anchoring (v1.1 symmetric far-side anchor) unvalidated on real data —
run `FM-Families.set` + CSV export in Strategy Tester visual mode, then review
MAE/MFE per family before any live use.
