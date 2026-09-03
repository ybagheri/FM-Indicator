"""Market-state engine tests (docs/MARKET_STATE.md).
Run: python3 -m pytest tests/test_state.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from market_state import StateCfg, analyze


def mk(o, h, l, c):
    return {'o': o, 'h': h, 'l': l, 'c': c}


def pct_sum(m):
    return sum(m['pct'])


def test_bull_trend():
    cfg = StateCfg()
    bars = [mk(100 + 2 * i, 103 + 2 * i, 99 + 2 * i, 102 + 2 * i)
            for i in range(60)]
    m = analyze(bars, 59, 59, 2.0, cfg)
    assert m['valid'] and m['state'] == "BULL_TREND", m
    assert pct_sum(m) == 100 and m['max_raw'] >= 1.0, m
    assert m['trend'] > 0.8 and m['pressure'] == 1.0, m
    assert m['pct'][0] > m['pct'][2], m  # trend beats channel
    print("PASS bull_trend")


def test_bear_trend_mirror():
    cfg = StateCfg()
    bars = [mk(302 - 2 * i, 303 - 2 * i, 299 - 2 * i, 300 - 2 * i)
            for i in range(60)]
    m = analyze(bars, 59, 59, 2.0, cfg)
    assert m['valid'] and m['state'] == "BEAR_TREND", m
    assert pct_sum(m) == 100, m
    assert m['trend'] < -0.8 and m['pressure'] == -1.0, m
    print("PASS bear_trend")


def test_bull_channel_grind():
    # Slow overlapping grind: directional + overlapping + bounded.
    cfg = StateCfg()
    bars = [mk(100 + 0.2 * i, 104 + 0.2 * i, 98 + 0.2 * i, 103.5 + 0.2 * i)
            for i in range(60)]
    m = analyze(bars, 59, 59, 3.0, cfg)
    assert m['valid'] and m['state'] == "BULL_CHANNEL", m
    assert pct_sum(m) == 100 and m['chop'] >= 0.5, m
    print("PASS bull_channel")


def test_trading_range():
    cfg = StateCfg()
    bars = []
    for i in range(60):
        if i % 2 == 0:
            bars.append(mk(98, 102, 98, 101.5))    # strong bull
        else:
            bars.append(mk(102, 102, 98, 98.5))    # strong bear
    m = analyze(bars, 59, 59, 2.0, cfg)
    assert m['valid'] and m['state'] == "TRADING_RANGE", m
    assert pct_sum(m) == 100, m
    assert abs(m['trend']) < 0.2 and abs(m['pressure']) < 0.2, m
    print("PASS trading_range")


def test_breakout_mode_tightening():
    cfg = StateCfg()
    bars = [mk(99, 104, 96, 100 + (0.5 if i % 2 else -0.5))
            for i in range(45)]
    for i in range(15):
        hw = 10.0 - (i * 0.5)
        o = 100 + (0.3 if i % 2 else -0.3)
        c = 100 - (0.3 if i % 2 else -0.3)
        bars.append(mk(o, 100 + hw, 100 - hw, c))
    # one-sided pressure inside the squeeze: 3 strong bulls at the end
    for k in (57, 58, 59):
        bars[k] = mk(99, 101, 97, 100.8)
    m = analyze(bars, 59, 59, 4.0, cfg)
    assert m['valid'] and m['tight'], m
    assert m['state'] == "BREAKOUT_MODE", m
    assert pct_sum(m) == 100, m
    print("PASS breakout_mode")


def test_transition_weak_floor():
    # Alternating levels: no overlap, mid range, moderate one-sided pressure,
    # no trend (<50-bar history → trend 0). Every raw < 1.0 → TRANSITION.
    cfg = StateCfg()
    bars = []
    for i in range(30):
        if i % 2 == 0:
            bars.append(mk(99, 101, 98.8, 100.8))      # strong bull
        elif i < 20 or i % 3 == 0:
            bars.append(mk(104, 106.3, 103.8, 105.8))  # strong bull, high level
        else:
            bars.append(mk(104, 106.3, 103.8, 104.2))  # weak (thin body)
    m = analyze(bars, 29, 29, 2.0, cfg)
    assert m['valid'], m
    assert m['max_raw'] < 1.0, m
    assert m['state'] == "TRANSITION", m
    assert pct_sum(m) == 100, m
    print("PASS transition_floor")


def test_unknown_tiny_history():
    cfg = StateCfg()
    tiny = [mk(100, 101, 99, 100.5)] * 10
    m = analyze(tiny, 9, 9, 1.0, cfg)
    assert not m['valid'] and m['state'] == "UNKNOWN", m
    assert m['pct'] == [0] * 6, m
    print("PASS unknown_tiny")


def test_freeze_no_lookahead_and_safety():
    cfg = StateCfg()
    bars = [mk(100 + 2 * i, 103 + 2 * i, 99 + 2 * i, 102 + 2 * i)
            for i in range(60)]
    a = analyze(bars, 59, 59, 2.0, cfg)
    ext = bars + [mk(220 + i, 223 + i, 219 + i, 222 + i) for i in range(5)]
    assert analyze(ext, 59, 64, 2.0, cfg) == a, "future bars changed old state"
    # forming bar never feeds detection
    assert analyze(bars, 60, 59, 2.0, cfg)['state'] == "UNKNOWN"
    # zero ATR → UNKNOWN, no crash
    assert analyze(bars, 59, 59, 0.0, cfg)['state'] == "UNKNOWN"
    # disabled layer → UNKNOWN
    off = StateCfg()
    off.enable = False
    assert analyze(bars, 59, 59, 2.0, off)['state'] == "UNKNOWN"
    print("PASS freeze_safety")


def test_pcts_sum_and_determinism():
    cfg = StateCfg()
    series = [
        [mk(100 + 2 * i, 103 + 2 * i, 99 + 2 * i, 102 + 2 * i)
         for i in range(60)],
        [mk(98, 102, 98, 101.5) if i % 2 == 0 else mk(102, 102, 98, 98.5)
         for i in range(60)],
        [mk(100 + 0.2 * i, 104 + 0.2 * i, 98 + 0.2 * i, 103.5 + 0.2 * i)
         for i in range(60)],
    ]
    for bars in series:
        m = analyze(bars, 59, 59, 2.0 if bars[0]['h'] < 150 else 3.0, cfg)
        assert pct_sum(m) == 100, m
        assert analyze(bars, 59, 59, 2.0 if bars[0]['h'] < 150 else 3.0,
                       cfg) == m, "nondeterministic winner/pcts"
    print("PASS pct_sum_determinism")


if __name__ == "__main__":
    test_bull_trend()
    test_bear_trend_mirror()
    test_bull_channel_grind()
    test_trading_range()
    test_breakout_mode_tightening()
    test_transition_weak_floor()
    test_unknown_tiny_history()
    test_freeze_no_lookahead_and_safety()
    test_pcts_sum_and_determinism()
    print("ALL STATE TESTS PASS")
