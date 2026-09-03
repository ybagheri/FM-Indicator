"""Breakout-engine tests (docs/BREAKOUT_ENGINE.md).
Run: python3 -m pytest tests/test_breakout.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from breakout import BOCfg, analyze


def mk(o, h, l, c):
    return {'o': o, 'h': h, 'l': l, 'c': c}


def base(n=29, h=110.0, l=100.0, c=105.0):
    return [mk(c, h, l, c) for _ in range(n)]


def test_bull_bo_pending_at_newest():
    cfg = BOCfg()
    bars = base() + [mk(108, 113, 108, 112.5)]  # 29: close clears 110 + 0.2
    s = analyze(bars, 29, 29, 2.0, [], cfg)
    assert s['found'] and s['dir'] == +1, s
    assert s['bo_bar'] == 29 and s['outcome'] == "PENDING", s
    assert s['ref'] == 110.0 and not s['ref_swing'], s
    assert s['decide_bar'] == -1 and not s['trap'], s
    print("PASS bull_pending")


def test_bull_follow_through():
    cfg = BOCfg()
    bars = base() + [mk(108, 113, 108, 112.5),   # 29: BO vs ref 110
                     mk(112, 112.5, 110, 112)]   # 30: holds beyond, no new event
    s = analyze(bars, 30, 30, 2.0, [], cfg)
    assert s['found'] and s['bo_bar'] == 29, s
    assert s['outcome'] == "FOLLOW" and s['decide_bar'] == 30, s
    print("PASS bull_follow")


def test_bull_failed_precedence():
    cfg = BOCfg()
    bars = base() + [mk(108, 113, 108, 112.5),   # 29: BO
                     mk(112, 112.5, 110, 112),   # 30: extends (follow)
                     mk(108, 109, 106, 108)]     # 31: back inside (fail)
    s = analyze(bars, 31, 31, 2.0, [], cfg)
    assert s['found'] and s['bo_bar'] == 29, s
    assert s['outcome'] == "FAILED" and s['decide_bar'] == 31, s
    print("PASS bull_failed_precedence")


def test_bear_mirror():
    cfg = BOCfg()
    bars = base(h=110.0, l=100.0) + [mk(92, 93, 87, 87.5),   # 29: BO vs 100
                                     mk(88, 89, 86, 87)]     # 30: holds below
    s = analyze(bars, 30, 30, 2.0, [], cfg)
    assert s['found'] and s['dir'] == -1, s
    assert s['bo_bar'] == 29 and s['outcome'] == "FOLLOW", s
    assert s['ref'] == 100.0 and not s['ref_swing'], s
    print("PASS bear_mirror")


def test_swing_reference_tiebreak():
    cfg = BOCfg()
    sw = [{'bar': 2, 'price': 104.0, 'dir': +1},
          {'bar': 5, 'price': 106.0, 'dir': +1}]
    bars = base()[:28] + [mk(100, 108, 99, 100)]  # 28: wick lifts NBAR ref
    bars += [mk(106, 107, 105, 107)]              # 29: clears swing, not NBAR
    s = analyze(bars, 29, 29, 2.0, sw, cfg)
    assert s['found'] and s['dir'] == +1, s
    assert s['ref_swing'] and s['ref'] == 106.0, s  # newest swing wins
    print("PASS swing_tiebreak")


def test_tolerance_poke_is_none():
    cfg = BOCfg()
    bars = base() + [mk(109, 110.5, 108, 110.15)]  # 110.15 < 110 + 0.2
    s = analyze(bars, 29, 29, 2.0, [], cfg)
    assert not s['found'] and s['outcome'] == "NONE", s
    print("PASS tolerance_none")


def test_second_leg_trap_armed():
    cfg = BOCfg()
    bars = [mk(98, 100, 96, 98)] * 10              # 0..9: NBAR ref 100
    bars += [mk(99, 102, 98, 101.5)]               # 10: BO (101.5 > 100.2)
    bars += [mk(100, 101, 98, 99.0)]               # 11: fail (99 < 99.8)
    bars += [mk(99, 100.5, 98.5, 99.5)] * 8        # 12..19: flat, no events
    bars += [mk(100, 104, 99, 103.5)]              # 20: re-break (ref incl 102)
    s = analyze(bars, 20, 20, 2.0, [], cfg)
    assert s['found'] and s['bo_bar'] == 20, s
    assert s['outcome'] == "PENDING" and s['trap'], s
    print("PASS trap_armed")


def test_stale_bo_outside_window():
    cfg = BOCfg()
    bars = [mk(98, 100, 96, 98)] * 10
    bars += [mk(99, 102, 98, 101.5)]               # 10: BO
    bars += [mk(99, 100.5, 98.5, 99.5)] * 10       # 11..20: inside, no fail/follow?
    s = analyze(bars, 20, 20, 2.0, [], cfg)
    # k-search covers [15..20]: event at 10 is stale → none
    assert not s['found'], s
    print("PASS stale_none")


def test_freeze_no_lookahead_and_safety():
    cfg = BOCfg()
    bars = base() + [mk(108, 113, 108, 112.5), mk(112, 112.5, 110, 112)]
    a = analyze(bars, 30, 30, 2.0, [], cfg)
    ext = bars + [mk(112 + i, 114 + i, 110 + i, 113 + i) for i in range(5)]
    assert analyze(ext, 30, 35, 2.0, [], cfg) == a, "future changed old signal"
    assert analyze(bars, 31, 30, 2.0, [], cfg)['outcome'] == "NONE"
    assert analyze(bars, 30, 30, 0.0, [], cfg)['found'] is False
    tiny = [mk(100, 101, 99, 100.5)] * 5
    assert analyze(tiny, 4, 4, 1.0, [], cfg)['found'] is False
    off = BOCfg()
    off.enable = False
    assert analyze(bars, 30, 30, 2.0, [], off)['found'] is False
    print("PASS freeze_safety")


if __name__ == "__main__":
    test_bull_bo_pending_at_newest()
    test_bull_follow_through()
    test_bull_failed_precedence()
    test_bear_mirror()
    test_swing_reference_tiebreak()
    test_tolerance_poke_is_none()
    test_second_leg_trap_armed()
    test_stale_bo_outside_window()
    test_freeze_no_lookahead_and_safety()
    print("ALL BREAKOUT TESTS PASS")
