# TESTING — FM Indicator v1.2 + v2 research + Phase-1/2/3 engines

## Method

- Oracle: `tests/fm_engine.py` (1:1 mirror of SPEC). MQL5 must match it on
  identical synthetic series.
- Bar oracle: `tests/bar_analyzer.py` (1:1 mirror of BAR_BY_BAR_ENGINE.md).
- Pullback oracle: `tests/pullback_patterns.py` (1:1 mirror of PULLBACK_PATTERNS.md).
- State oracle: `tests/market_state.py` (1:1 mirror of MARKET_STATE.md).
- Run: `python3 -m pytest tests/ -q` → 45 tests, ALL PASS (19 FM + 7 bar +
  10 pullback + 9 state; or per-file via `__main__`).
- MQL5 compile: MetaEditor on Windows (F7). Linux env has no
  `metaeditor.exe`/`wine`; static check = balanced-delimiter scan
  (comment/string-stripped) over all 16 MQL5 files → OK.

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

## Reproduce

```
cd FM-indicator && python3 -m pytest tests/ -q
```

## Known limits

No tick-level MT5 tester run in this env; no statistical/PTR walk-forward yet;
inverse-MM anchoring (v1.1 symmetric far-side anchor) unvalidated on real data —
run `FM-Families.set` + CSV export in Strategy Tester visual mode, then review
MAE/MFE per family before any live use.
