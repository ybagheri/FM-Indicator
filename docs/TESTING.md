# TESTING — FM Indicator v1

## Method

- Oracle: `tests/fm_engine.py` (1:1 mirror of SPEC). MQL5 must match it on
  identical synthetic series.
- Run: `python3 tests/test_fm.py` → 6 suites, ALL PASS (2026-09-03).
- MQL5 compile: MetaEditor on Windows (F7). Linux env has no
  `metaeditor.exe`/`wine`; static check = balanced-delimiter scan
  (comment/string-stripped) over all 13 MQL5 files → OK.

## Cases → expected

| # | Case | Expected | Result |
|---|---|---|---|
| 1 | Swing appears before k bars | absent (no look-ahead) | PASS |
| 2 | Bull lifecycle A0 90/A1 100/B0 95 → T 105, approach→stall→signal | POTENTIAL→DEVELOPING→CONFIRMED→COMPLETED | PASS |
| 3 | Touch target, no exhaustion | stays POTENTIAL | PASS |
| 4 | Close 1.5 over target (>0.5×ATR 1.0) | INVALIDATED | PASS |
| 5 | Pullback depth 0.10 / 1.10 | rejected (needs 0.15–0.90) | PASS |
| 6 | Flat market, ATR≈0; 4-bar history | no crash, no swings | PASS |

## Coverage map (prompt §TESTING 1–12)

1 Compilation — MetaEditor (user-side) + static scan here. 2 Init — `OnInit`
buffers/`PLOT_DRAW_BEGIN`/config validate. 3 History — full recompute on
first `prev_calculated==0`. 4 New-bar — `time[1]` change gate. 5 Intrabar —
preview-only flag, never DEVELOPING/CONFIRMED. 6 Alerts — `ClaimAlert`
once-per-(id,state) + cooldown. 7 Objects — `FM_<id>_*` diff-sync + delete.
8 Multi-setup — capped list, nearest-first eviction, per-setup state.
9 Edge — flat/zero-ATR/tiny-history/gaps/large bars safe. 10 Recalc —
closed-bar freeze, shifts never rewritten. 11 No-look-ahead — test 1.
12 Repaint — swing-price freeze + one-transition-per-bar.

## Reproduce

```
cd FM-indicator && python3 tests/test_fm.py
```

## Known limits

No tick-level MT5 tester run in this env; no statistical/PTR walk-forward yet;
inverse-MM anchoring unvalidated on real data (see ROADMAP).
