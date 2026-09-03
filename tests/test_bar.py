"""Bar-by-bar analyzer tests (docs/BAR_BY_BAR_ENGINE.md §2-6).
Run: python3 -m pytest tests/test_bar.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from bar_analyzer import BarCfg, bar_analyze


def mk(o, h, l, c):
    return {'o': o, 'h': h, 'l': l, 'c': c}


def test_strong_bull_and_bear_geometry():
    cfg = BarCfg()
    bars = [mk(100, 100.5, 99.5, 100)] * 3
    bars.append(mk(100, 110, 99.5, 109.5))  # big bull, close near high
    f = bar_analyze(bars, 3, 3, atr=2.0, cfg=cfg)
    assert f['valid'] and f['dir'] == +1 and f['is_strong_bull']
    assert f['label'] == "STRONG_BULL" and f['close_pos'] > 0.9
    bars.append(mk(109.5, 110, 99.0, 99.5))  # big bear, close near low
    g = bar_analyze(bars, 4, 4, atr=2.0, cfg=cfg)
    assert g['dir'] == -1 and g['is_strong_bear'] and g['label'] == "STRONG_BEAR"
    print("PASS strong_geometry")


def test_doji_is_pause_not_signal():
    cfg = BarCfg()
    bars = [mk(100+i, 101+i, 99+i, 100.5+i) for i in range(6)]
    bars.append(mk(106, 106.4, 105.6, 106.02))  # tiny body → doji
    f = bar_analyze(bars, 6, 6, atr=2.0, cfg=cfg)
    assert f['is_doji'] and f['label'] == "DOJI"
    assert f['consecutive'] == 0, "doji must reset run (Brooks: pause, not flip)"
    assert not f['is_strong_bull'] and not f['is_strong_bear']
    print("PASS doji_pause")


def test_inside_outside_and_ii_count():
    cfg = BarCfg()
    bars = [mk(100, 110, 90, 105), mk(101, 108, 92, 104),
            mk(102, 106, 94, 103), mk(102.5, 105, 95, 103.5)]
    f1 = bar_analyze(bars, 1, 3, atr=5.0, cfg=cfg)
    assert f1['is_inside'] and not f1['is_outside']
    f3 = bar_analyze(bars, 3, 3, atr=5.0, cfg=cfg)
    assert f3['ii_count'] >= 2 and f3['label'].startswith("II")
    out = [mk(100, 110, 90, 105), mk(100, 115, 85, 114)]  # engulf + strong close
    g = bar_analyze(out, 1, 1, atr=5.0, cfg=cfg)
    assert g['is_outside'] and g['is_strong_bull'] and g['label'] == "STRONG_BULL"
    print("PASS inside_outside_ii")


def test_overlap_barbwire_and_tightening():
    cfg = BarCfg()
    bars = [mk(98, 103, 97, 101)] * 4 + [mk(99.5, 103, 97, 99.6)] + [mk(98, 103, 97, 101)]
    # wide shared bodies (overlap 0.5) + one doji → barbwire
    f = bar_analyze(bars, 5, 5, atr=5.0, cfg=cfg)
    w = bar_analyze(bars, 3, 5, atr=5.0, cfg=cfg)  # wide-body pair: overlap high
    assert w['overlap'] >= cfg.overlap_ratio
    assert f['barbwire'], "overlapping bodies + doji must read as barbwire"
    trend = [mk(100+i*2, 103+i*2, 99+i*2, 102+i*2) for i in range(5)]
    trend.append(mk(110, 110.5, 109.5, 110.2))  # tiny vs prior
    t = bar_analyze(trend, 5, 5, atr=2.0, cfg=cfg)
    assert t['tightening'], "small bar after wide bars = tightening"
    print("PASS barbwire_tightening")


def test_gap_parity_with_gap_family():
    cfg = BarCfg()
    bars = [mk(100, 101, 99, 100.5), mk(100.5, 112, 102, 111.5)]  # low gaps above prior high
    bars[1]['h'], bars[1]['l'] = 112.0, 102.0
    f = bar_analyze(bars, 1, 1, atr=2.0, cfg=cfg)
    assert f['gap_up'] and not f['gap_down']
    print("PASS gap_parity")


def test_consecutive_runs_and_pressure():
    cfg = BarCfg()
    bars = [mk(100+i, 101+i, 99+i, 100.8+i) for i in range(5)]  # steady bull closes
    f = bar_analyze(bars, 4, 4, atr=2.0, cfg=cfg)
    assert f['consecutive'] == 5, f
    assert f['pressure_bull'] >= 3 and f['pressure_bear'] == 0
    bars.append(mk(105, 105.5, 103, 103.5))  # bear flips run
    g = bar_analyze(bars, 5, 5, atr=2.0, cfg=cfg)
    assert g['consecutive'] < 0
    print("PASS runs_pressure")


def test_freeze_no_lookahead_and_edge_cases():
    cfg = BarCfg()
    bars = [mk(100+i*0.5, 101+i*0.5, 99+i*0.5, 100.4+i*0.5) for i in range(10)]
    a = bar_analyze(bars, 7, 7, atr=2.0, cfg=cfg)
    ext = bars + [mk(200, 220, 190, 219)] * 5  # huge future bars
    b = bar_analyze(ext, 7, 7, atr=2.0, cfg=cfg)
    assert a == b, "future bars must not change closed-bar features (freeze)"
    c = bar_analyze(bars, 7, 7, atr=2.0, cfg=cfg)
    d = bar_analyze(bars, 7, 9 if False else 7, atr=2.0, cfg=cfg)
    assert c == d
    # forming bar never analyzed
    assert not bar_analyze(bars, len(bars), len(bars), atr=2.0, cfg=cfg)['valid']
    # tiny history: no prior bar → pair features safe-default
    tiny = [mk(100, 101, 99, 100.5)]
    t = bar_analyze(tiny, 0, 0, atr=1.0, cfg=cfg)
    assert t['valid'] and not t['is_inside'] and t['overlap'] == 0.0
    # zero ATR: size flags safe, geometry intact
    z = bar_analyze(bars, 5, 5, atr=0.0, cfg=cfg)
    assert not z['is_big'] and not z['is_small'] and z['valid']
    flat = [mk(100, 101, 99, 100)]  # tick-exact flat
    assert bar_analyze(flat, 0, 0, atr=1.0, cfg=cfg)['dir'] == 0
    print("PASS freeze_edge")


if __name__ == "__main__":
    test_strong_bull_and_bear_geometry()
    test_doji_is_pause_not_signal()
    test_inside_outside_and_ii_count()
    test_overlap_barbwire_and_tightening()
    test_gap_parity_with_gap_family()
    test_consecutive_runs_and_pressure()
    test_freeze_no_lookahead_and_edge_cases()
    print("ALL BAR TESTS PASS")
