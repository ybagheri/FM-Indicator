"""Pullback-pattern tests (docs/PULLBACK_PATTERNS.md).
Run: python3 -m pytest tests/test_pullback.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from pullback_patterns import (PVCfg, trend_dir, detect_bull, detect_bear,
                               find_double_top, find_double_bottom,
                               micro_double_top, micro_double_bottom)


def mk(o, h, l, c):
    return {'o': o, 'h': h, 'l': l, 'c': c}


def flat_top_uptrend(n=50, h=200.0, l=190.0, c0=193.0, slope=0.1):
    # Flat extremes (no H/L breaks) + climbing closes (gate +1 via EMA gap).
    return [mk(c0 + i * slope - 0.5, h, l, c0 + i * slope) for i in range(n)]


def flat_top_downtrend(n=50, h=210.0, l=200.0, c0=207.0, slope=0.1):
    return [mk(c0 - i * slope + 0.5, h, l, c0 - i * slope) for i in range(n)]


def cfg12():
    c = PVCfg()
    c.max_pullback_bars = 12  # local window: keeps H1/lowAt on the pullback
    return c


def test_h1_h2_two_legs():
    cfg = cfg12()
    bars = flat_top_uptrend(50)
    bars += [mk(198, 200, 189, 196),   # 50 pullback dip (no H break: 200 !> 200)
             mk(196, 202, 191, 201),   # 51 H1: 202 > 200
             mk(201, 200, 187, 192),   # 52 second leg: 187 < lowAt 189
             mk(192, 203, 190, 202),   # 53 H2: 203 > 200
             mk(202, 205, 200, 204),   # 54
             mk(204, 207, 202, 206)]   # 55
    idx = last = 55
    assert trend_dir(bars, idx, last, 2.0, cfg) == +1
    s = detect_bull(bars, idx, last, 2.0, cfg)
    assert s['found'] and s['legs'] == 2, s
    assert s['anchor'] == 51 and s['signal'] == 53, s
    assert s['ref'] == 203 and s['stop'] == 187, s
    print("PASS h1_h2_two_legs")


def test_h1_only_no_second_leg():
    cfg = cfg12()
    bars = flat_top_uptrend(50)
    bars += [mk(198, 200, 189, 196),   # 50 dip
             mk(196, 202, 191, 201),   # 51 H1
             mk(201, 200, 190, 198),   # 52 no lower low (190 !< 189)
             mk(198, 203, 191, 202),   # 53 higher but no second leg first
             mk(202, 205, 200, 204),
             mk(204, 207, 202, 206)]
    s = detect_bull(bars, 55, 55, 2.0, cfg)
    assert s['found'] and s['legs'] == 1, s
    assert s['signal'] == 51 and s['anchor'] == 51, s
    print("PASS h1_only")


def test_l1_l2_mirror():
    cfg = cfg12()
    bars = flat_top_downtrend(50)
    bars += [mk(202, 211, 200, 204),   # 50 rally (no L break: 200 !< 200)
             mk(204, 209, 198, 199),   # 51 L1: 198 < 200
             mk(199, 213, 200, 208),   # 52 second leg: 213 > highAt 211
             mk(208, 210, 197, 198),   # 53 L2: 197 < 200
             mk(198, 205, 194, 195),
             mk(195, 202, 191, 192)]
    assert trend_dir(bars, 55, 55, 2.0, cfg) == -1
    s = detect_bear(bars, 55, 55, 2.0, cfg)
    assert s['found'] and s['legs'] == 2, s
    assert s['anchor'] == 51 and s['signal'] == 53, s
    assert s['ref'] == 197 and s['stop'] == 213, s
    # bull side must stay silent in a bear gate
    assert not detect_bull(bars, 55, 55, 2.0, cfg)['found']
    print("PASS l1_l2_mirror")


def test_gate_zero_suppresses():
    cfg = cfg12()
    bars = [mk(100, 101, 99, 100 + (0.1 if i % 2 else -0.1)) for i in range(60)]
    bars += [mk(99, 102, 98, 101), mk(101, 103, 99, 102)]  # H-break shape
    idx = last = len(bars) - 1
    assert trend_dir(bars, idx, last, 2.0, cfg) == 0
    assert not detect_bull(bars, idx, last, 2.0, cfg)['found']
    assert not detect_bear(bars, idx, last, 2.0, cfg)['found']
    print("PASS gate_zero")


def test_chop_with_gate_forced_needs_h2():
    # Mild up-drift chop: gate passes (+1) but only a weak H1-only fires.
    # Documents spec §3 note: H1 alone carries higher failure risk — Phase 8
    # should require H2 or extra confirmation, not trade legs==1 blindly.
    cfg = cfg12()
    bars = []
    for i in range(55):
        hi = 202.0 if i % 2 else 200.0
        bars.append(mk(195, hi, 190, 190 + i * 0.15))
    bars.append(mk(198, 201, 191, 199))
    idx = last = len(bars) - 1
    assert trend_dir(bars, idx, last, 3.0, cfg) == +1  # gate forced by drift
    s = detect_bull(bars, idx, last, 3.0, cfg)
    assert s['found'] and s['legs'] == 1, s
    print("PASS chop_gate_forced")


def test_swing_double_top_in_tol():
    cfg = PVCfg()
    sw = [{'bar': 0, 'price': 100.0, 'dir': +1},
          {'bar': 2, 'price': 94.0, 'dir': -1},
          {'bar': 4, 'price': 100.1, 'dir': +1},
          {'bar': 6, 'price': 93.0, 'dir': -1},
          {'bar': 8, 'price': 100.05, 'dir': +1}]
    d = find_double_top(sw, 2.0, cfg)
    assert d['found'] and d['dir'] == -1 and not d['micro'], d
    assert (d['bar1'], d['bar2']) == (4, 8), d  # most-recent pair wins
    print("PASS double_top_in_tol")


def test_swing_double_top_rejected():
    cfg = PVCfg()
    # (a) out of tolerance: |101-100|=1.0 > 0.25*2=0.5
    sw = [{'bar': 0, 'price': 100.0, 'dir': +1},
          {'bar': 5, 'price': 95.0, 'dir': -1},
          {'bar': 10, 'price': 101.0, 'dir': +1}]
    assert not find_double_top(sw, 2.0, cfg)['found']
    # (b) shallow trough: base 100 - 99.8 = 0.2 < 0.5*2=1.0
    sw2 = [{'bar': 0, 'price': 100.0, 'dir': +1},
           {'bar': 5, 'price': 99.8, 'dir': -1},
           {'bar': 10, 'price': 100.1, 'dir': +1}]
    assert not find_double_top(sw2, 2.0, cfg)['found']
    # (c) too far apart: 25 > MaxDoubleBars 20
    sw3 = [{'bar': 0, 'price': 100.0, 'dir': +1},
           {'bar': 12, 'price': 95.0, 'dir': -1},
           {'bar': 25, 'price': 100.1, 'dir': +1}]
    assert not find_double_top(sw3, 2.0, cfg)['found']
    print("PASS double_top_rejected")


def test_double_bottom_mirror():
    cfg = PVCfg()
    sw = [{'bar': 1, 'price': 90.0, 'dir': -1},
          {'bar': 6, 'price': 95.0, 'dir': +1},
          {'bar': 11, 'price': 90.2, 'dir': -1}]
    d = find_double_bottom(sw, 2.0, cfg)
    assert d['found'] and d['dir'] == +1 and not d['micro'], d
    assert (d['bar1'], d['bar2']) == (1, 11), d
    # bottom without intervening high must not fire
    sw2 = [{'bar': 1, 'price': 90.0, 'dir': -1},
           {'bar': 11, 'price': 90.1, 'dir': -1}]
    assert not find_double_bottom(sw2, 2.0, cfg)['found']
    print("PASS double_bottom_mirror")


def test_micro_double():
    cfg = PVCfg()
    bars = flat_top_uptrend(55)
    n = len(bars)
    bars[n - 3] = mk(198, 150.0, 140, 145)   # older extreme
    bars[n - 2] = mk(145, 146, 139, 144)     # deep trough between
    bars[n - 1] = mk(144, 150.1, 142, 149)   # newer extreme (0.1 within tol)
    d = micro_double_top(bars, n - 1, n - 1, 2.0, cfg)
    assert d['found'] and d['micro'] and d['dir'] == -1, d
    assert (d['bar1'], d['bar2']) == (n - 3, n - 1), d
    # halved trough: 0.5*0.5*2 = 0.5; shallow dip must reject
    bars[n - 2] = mk(145, 150.05, 149.9, 149)
    assert not micro_double_top(bars, n - 1, n - 1, 2.0, cfg)['found']
    # micro bottom mirror
    bars[n - 3] = mk(142, 150, 140.0, 145)
    bars[n - 2] = mk(145, 151, 141, 146)
    bars[n - 1] = mk(146, 150, 140.1, 144)
    b = micro_double_bottom(bars, n - 1, n - 1, 2.0, cfg)
    assert b['found'] and b['micro'] and b['dir'] == +1, b
    print("PASS micro_double")


def test_freeze_no_lookahead_and_safety():
    cfg = cfg12()
    bars = flat_top_uptrend(50)
    bars += [mk(198, 200, 189, 196), mk(196, 202, 191, 201),
             mk(201, 200, 187, 192), mk(192, 203, 190, 202),
             mk(202, 205, 200, 204), mk(204, 207, 202, 206)]
    a = detect_bull(bars, 55, 55, 2.0, cfg)
    sw = [{'bar': 0, 'price': 100.0, 'dir': +1},
          {'bar': 5, 'price': 95.0, 'dir': -1},
          {'bar': 10, 'price': 100.1, 'dir': +1}]
    da = find_double_top(sw, 2.0, cfg)
    ma = micro_double_top(bars, 55, 55, 2.0, cfg)
    ext = bars + [mk(206 + i, 208 + i, 204 + i, 207 + i) for i in range(5)]
    assert detect_bull(ext, 55, 60, 2.0, cfg) == a, "future bars changed old signal"
    assert find_double_top(sw, 2.0, cfg) == da
    assert micro_double_top(ext, 55, 60, 2.0, cfg) == ma
    # forming bar (idx beyond last_closed) never feeds detection
    assert not detect_bull(bars, 56, 55, 2.0, cfg)['found']
    assert trend_dir(bars, 56, 55, 2.0, cfg) == 0
    assert not micro_double_top(bars, 56, 55, 2.0, cfg)['found']
    # zero ATR: safe defaults, no crash
    assert not detect_bull(bars, 55, 55, 0.0, cfg)['found']
    assert not detect_bear(bars, 55, 55, 0.0, cfg)['found']
    assert trend_dir(bars, 55, 55, 0.0, cfg) == 0
    assert not find_double_top(sw, 0.0, cfg)['found']
    assert not micro_double_top(bars, 55, 55, 0.0, cfg)['found']
    # tiny history: gate needs 50 closes; layers stay silent, never raise
    tiny = [mk(100, 101, 99, 100.5)] * 10
    assert trend_dir(tiny, 9, 9, 1.0, cfg) == 0
    assert not detect_bull(tiny, 9, 9, 1.0, cfg)['found']
    assert not detect_bear(tiny, 9, 9, 1.0, cfg)['found']
    assert not find_double_top([], 1.0, cfg)['found']
    print("PASS freeze_safety")


if __name__ == "__main__":
    test_h1_h2_two_legs()
    test_h1_only_no_second_leg()
    test_l1_l2_mirror()
    test_gate_zero_suppresses()
    test_chop_with_gate_forced_needs_h2()
    test_swing_double_top_in_tol()
    test_swing_double_top_rejected()
    test_double_bottom_mirror()
    test_micro_double()
    test_freeze_no_lookahead_and_safety()
    print("ALL PULLBACK TESTS PASS")
