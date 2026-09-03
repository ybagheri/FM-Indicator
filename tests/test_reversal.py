"""Reversal-engine tests (docs/REVERSAL_ENGINE.md).
Run: python3 -m pytest tests/test_reversal.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from reversal import (RevCfg, exhaustion, leg_count, mtr, push_back, wedge_at)


def mk(o, h, l, c):
    assert h >= max(o, c) and l <= min(o, c), (o, h, l, c)
    return {'o': o, 'h': h, 'l': l, 'c': c}


def test_climax_bar():
    cfg = RevCfg()
    bars = [mk(100, 101, 99, 100)] * 4 + [mk(100, 103, 98, 101)]
    r = exhaustion(bars, 4, 4, +1, 2.0, cfg)
    assert r['climax'] and r['breadth'] >= 1, r
    assert r['breadth'] == sum([r['climax'], r['stall'], r['pushOK'],
                                r['wedge'], r['overshoot']]), r
    print("PASS climax")


def test_stall_bar():
    cfg = RevCfg()
    bars = [mk(100, 101, 99, 100)] * 4 + [mk(100, 102, 98, 100.2)]
    r = exhaustion(bars, 4, 4, +1, 10.0, cfg)
    assert r['stall'] and not r['climax'] and r['breadth'] >= 1, r
    print("PASS stall")


def test_pushes_and_wedge_shrinking():
    cfg = RevCfg()
    bars = [mk(100, 102, 98, 100),      # 0: range 4.0
            mk(100.5, 103, 99.5, 101),    # 1: range 3.5
            mk(101.5, 104, 101, 102),     # 2: range 3.0
            mk(102.5, 104.5, 102, 103),   # 3: range 2.5
            mk(103.5, 105, 103, 104)]     # 4: range 2.0
    assert push_back(bars, 4, 4, +1) == 4
    assert wedge_at(bars, 4, 4, +1) is True
    r = exhaustion(bars, 4, 4, +1, 2.0, cfg)
    assert r['pushes'] == 4 and r['pushOK'] and r['wedge'], r
    assert r['breadth'] >= 2, r
    # bear side silent on bull pushes
    assert push_back(bars, 4, 4, -1) == 0
    print("PASS pushes_wedge")


def test_overshoot_spike():
    cfg = RevCfg()
    bars = [mk(100, 101, 99, 100)] * 19 + [mk(100, 115, 99, 100)]
    r = exhaustion(bars, 19, 19, +1, 2.0, cfg)
    assert r['overshoot'] and r['breadth'] >= 1, r
    # short history: no window -> no overshoot, no crash
    short = [mk(100, 101, 99, 100)] * 5
    assert exhaustion(short, 4, 4, +1, 2.0, cfg)['overshoot'] is False
    print("PASS overshoot")


def test_breadth_or_parity():
    cfg = RevCfg()
    quiet = [mk(100, 101, 99, 100)] * 6
    r = exhaustion(quiet, 5, 5, +1, 2.0, cfg)
    assert r['breadth'] == 0, r
    # each single-flag bar reports breadth>0 (superset incl. newest-bar wedge)
    climax = quiet + [mk(100, 104, 98, 102)]
    assert exhaustion(climax, 6, 6, +1, 2.0, cfg)['breadth'] >= 1
    assert exhaustion(quiet, 6, 5, +1, 2.0, cfg)['breadth'] == 0  # beyond close
    assert exhaustion(quiet, 5, 5, +1, 0.0, cfg)['breadth'] == 0  # zero ATR
    print("PASS breadth_parity")


def test_bull_legs_one_two_deep():
    one = [{'bar': 0, 'price': 90.0, 'dir': -1},
           {'bar': 5, 'price': 100.0, 'dir': +1},
           {'bar': 8, 'price': 95.0, 'dir': -1}]
    l1 = leg_count(one, +1)
    assert l1['valid'] and l1['legs'] == 1 and not l1['deep'], l1
    assert abs(l1['depth'] - 0.5) < 1e-9 and l1['anchor'] == 5, l1
    two = one + [{'bar': 12, 'price': 92.0, 'dir': -1}]
    l2 = leg_count(two, +1)
    assert l2['legs'] == 2 and l2['deep'] and l2['extreme'] == 12, l2
    assert abs(l2['depth'] - 0.8) < 1e-9, l2
    # no countertrend lows yet -> legs 0, depth unknown
    empty = [{'bar': 0, 'price': 90.0, 'dir': -1},
             {'bar': 5, 'price': 100.0, 'dir': +1}]
    l0 = leg_count(empty, +1)
    assert l0['valid'] and l0['legs'] == 0 and l0['depth'] == -1.0, l0
    assert leg_count([], +1)['valid'] is False
    print("PASS bull_legs")


def test_bear_legs_mirror():
    sw = [{'bar': 0, 'price': 110.0, 'dir': +1},
          {'bar': 5, 'price': 100.0, 'dir': -1},
          {'bar': 8, 'price': 105.0, 'dir': +1},
          {'bar': 12, 'price': 108.0, 'dir': +1}]
    l = leg_count(sw, -1)
    assert l['valid'] and l['legs'] == 2 and l['deep'], l
    assert abs(l['depth'] - 0.8) < 1e-9 and l['anchor'] == 5, l
    # bull side with no bull anchor is invalid
    no_bull = [{'bar': 0, 'price': 100.0, 'dir': -1},
               {'bar': 5, 'price': 98.0, 'dir': -1}]
    assert leg_count(no_bull, +1)['valid'] is False
    print("PASS bear_legs")


def _mtr_series(n_grind=5):
    """Flat 100 -> dip 96 -> 3x2.5 surge -> tiny grind (valid OHLC)."""
    bars = []
    c = 100.0
    for _ in range(15):
        bars.append(mk(c, c + 1, c - 1, c))
    c -= 2.0
    bars.append(mk(c + 0.5, c + 1, c - 1, c))
    c -= 2.0
    bars.append(mk(c + 0.5, c + 1, c - 1, c))
    prev_h = bars[-1]['h']
    for _ in range(3):
        c += 2.5
        h = max(prev_h + 0.3, c + 0.5)
        bars.append(mk(c - 0.5, h, c - 1.0, c))
        prev_h = h
    for _ in range(n_grind):
        c += 0.15
        h = max(prev_h + 0.2, c + 0.3)
        bars.append(mk(c - 0.05, h, c - 0.3, c))
        prev_h = h
    return bars


def test_mtr_major_all_four_legs():
    cfg = RevCfg()
    bars = _mtr_series(5)
    idx = len(bars) - 1
    s = mtr(bars, idx, idx, 2.0, [], +1, cfg)
    assert s['found'] and s['verdict'] == "MAJOR", s
    assert s['ema_break'] and s['retest'], s
    assert s['bo_follow'] and s['pressure_ok'], s
    assert s['press_n'] >= 5 and s['score'] == 100 and s['cross_bar'] >= 0, s
    print("PASS mtr_major")


def test_mtr_minor_partial_legs():
    cfg = RevCfg()
    bars = _mtr_series(0)  # surge top: EMA cross + retest, no pressure/BO-follow
    idx = len(bars) - 1
    s = mtr(bars, idx, idx, 2.0, [], +1, cfg)
    assert s['found'] and s['verdict'] == "MINOR", s
    assert s['ema_break'] and s['retest'], s
    assert not s['bo_follow'] and not s['pressure_ok'], s
    assert s['score'] == 50, s
    print("PASS mtr_minor")


def test_none_freeze_no_lookahead_and_safety():
    cfg = RevCfg()
    bars = _mtr_series(5)
    idx = len(bars) - 1
    # wrong direction is silent
    assert mtr(bars, idx, idx, 2.0, [], -1, cfg)['verdict'] == "NONE"
    # tiny history insufficient for the lookback window
    tiny = [mk(100, 101, 99, 100.5)] * 5
    assert mtr(tiny, 4, 4, 1.0, [], +1, cfg)['found'] is False
    # no look-ahead: analysis point beyond last close
    assert mtr(bars, idx + 1, idx, 2.0, [], +1, cfg)['found'] is False
    assert exhaustion(bars, idx + 1, idx, +1, 2.0, cfg)['breadth'] == 0
    # zero ATR never signals
    assert mtr(bars, idx, idx, 0.0, [], +1, cfg)['found'] is False
    # disabled layer is idle
    off = RevCfg()
    off.enable = False
    assert mtr(bars, idx, idx, 2.0, [], +1, off)['found'] is False
    # freeze: extending history leaves the old-bar signal identical
    a = mtr(bars, idx, idx, 2.0, [], +1, cfg)
    ext = bars + [mk(109 + 0.1 * i, 111 + 0.1 * i, 108 + 0.1 * i, 109.5 + 0.1 * i)
                  for i in range(5)]
    assert mtr(ext, idx, idx + 5, 2.0, [], +1, cfg) == a
    print("PASS none_freeze_safety")


if __name__ == "__main__":
    test_climax_bar()
    test_stall_bar()
    test_pushes_and_wedge_shrinking()
    test_overshoot_spike()
    test_breadth_or_parity()
    test_bull_legs_one_two_deep()
    test_bear_legs_mirror()
    test_mtr_major_all_four_legs()
    test_mtr_minor_partial_legs()
    test_none_freeze_no_lookahead_and_safety()
    print("ALL REVERSAL TESTS PASS")
