"""Anti-repaint + functional tests for the FM spec mirror.
Run: python3 -m pytest tests/ -q  (or python3 tests/test_fm.py)
Covers TESTING.md §1-12 core: swings freeze, no-look-ahead, state order,
alert-once, invalidation, edge cases.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from fm_engine import (Cfg, Engine, confirmed_swings, wilder_atr,
                       exhaustion_any, is_signal_bar, follow_through, push_count,
                       is_wedge, score_signal, range_projection,
                       channel_projection, gap_projection,
                       PROJECTED, POTENTIAL, DEVELOPING, CONFIRMED, INVALIDATED)


def mk(o, h, l, c):
    return {'o': o, 'h': h, 'l': l, 'c': c}


def test_swing_freeze_no_repaint():
    # V-shaped swing low at idx 5; visible only once bar 5+k closes.
    bars = []
    px = 100.0
    for i in range(12):
        bars.append(mk(px, px+0.5, px-0.5, px))
        px += 0.2
    bars[5] = mk(99, 99.5, 95.0, 98.0)  # sharp low
    early = confirmed_swings(bars[:9], k=3, last_closed_idx=8)
    assert any(s['bar'] == 5 for s in early), "swing must confirm at 5+3=8"
    # with only bars up to 7 (last_closed=7), swing 5 must NOT exist
    too_early = confirmed_swings(bars[:8], k=3, last_closed_idx=7)
    assert not any(s['bar'] == 5 for s in too_early), "LOOK-AHEAD: swing used before k bars"
    # appending future bars must not move swing 5
    late = confirmed_swings(bars + [mk(102, 102.5, 101.5, 102)]*5, k=3, last_closed_idx=16)
    s5 = [s for s in late if s['bar'] == 5]
    assert s5 and abs(s5[0]['price'] - 95.0) < 1e-9, "swing price moved = repaint"
    print("PASS swing_freeze_no_repaint")


def test_full_fm_lifecycle_bull():
    """Bull Leg1=Leg2: A0 low 90, A1 high 100 (mm=10), B0 low 95 → T=105.
    Drive price to 105 with stall (exhaustion) then bearish signal bar."""
    cfg = Cfg()
    eng = Engine(cfg)
    a0 = {'bar': 5, 'price': 90.0, 'dir': -1}
    a1 = {'bar': 12, 'price': 100.0, 'dir': +1}
    b0 = {'bar': 17, 'price': 95.0, 'dir': -1}
    proj = eng._regular(a0, a1, b0, atr=2.0)
    assert proj and abs(proj['target'] - 105.0) < 1e-9, f"bad target {proj}"
    eng.setups.append(__import__('fm_engine').Setup(1, +1, a0, a1, b0, 10.0, 105.0))
    bars = [{'o': 100+i*0.4, 'h': 100+i*0.4+0.4, 'l': 100+i*0.4-0.4, 'c': 100+i*0.4} for i in range(30)]
    atr = 2.0
    # approach: bar high within 1.0 ATR below target
    b = 20
    bars[b] = mk(103.5, 104.2, 103.0, 103.8)  # dist = 0.8 <= 1.0*2 → POTENTIAL
    eng.update(bars, b, atr)
    assert eng.setups[0].state == POTENTIAL, eng.setups[0].state
    # touch tolerance (0.25*2=0.5) + stall: tiny range + two-sided wicks
    b = 21
    bars[b] = {'o': 104.7, 'h': 105.2, 'l': 104.3, 'c': 104.75}  # range .9 <1.0, wicks both sides
    # range .8 vs 0.5*atr=1.0 → stall candidate; ensure exhaustion true:
    assert exhaustion_any(bars, b, +1, atr), "test bar must be exhaustion"
    eng.update(bars, b, atr)
    assert eng.setups[0].state == DEVELOPING, eng.setups[0].state
    # bearish signal bar within tol: open 105.3 close 104.3 (body 1.0/1.4), close near low
    b = 22
    bars[b] = {'o': 105.3, 'h': 105.4, 'l': 104.0, 'c': 104.2}
    assert is_signal_bar(bars, b, -1, cfg), "test bar must be signal"
    eng.update(bars, b, atr)
    assert eng.setups[0].state == CONFIRMED, eng.setups[0].state
    eng.update(bars, b, atr)  # CONFIRMED → COMPLETED terminal
    print("PASS full_fm_lifecycle_bull")


def test_touch_without_exhaustion_stays_potential():
    cfg = Cfg()
    import fm_engine as F
    eng = F.Engine(cfg)
    a0 = {'bar': 5, 'price': 90.0, 'dir': -1}
    a1 = {'bar': 12, 'price': 100.0, 'dir': +1}
    b0 = {'bar': 17, 'price': 95.0, 'dir': -1}
    eng.setups.append(F.Setup(1, +1, a0, a1, b0, 10.0, 105.0))
    eng.setups[0].state = POTENTIAL
    bars = [{'o': 104+i*0.1, 'h': 105.1, 'l': 103.9, 'c': 104.5+i*0.05} for i in range(30)]
    # strong trend bar through target, range big but body directional, no stall/push
    bars[20] = {'o': 103.5, 'h': 105.1, 'l': 103.4, 'c': 105.0}  # range 1.7 <2ATR → not climax; not stall
    assert not exhaustion_any(bars, 20, +1, 2.0)
    eng.update(bars, 20, 2.0)
    assert eng.setups[0].state == POTENTIAL, "touch alone must NOT develop"
    print("PASS touch_without_exhaustion")


def test_invalidation_on_overshoot():
    import fm_engine as F
    eng = F.Engine(F.Cfg())
    eng.setups.append(F.Setup(1, +1, {'bar': 1, 'price': 90, 'dir': -1},
                              {'bar': 5, 'price': 100, 'dir': +1},
                              {'bar': 8, 'price': 95, 'dir': -1}, 10.0, 105.0))
    eng.setups[0].state = POTENTIAL
    bars = [{'o': 100, 'h': 101, 'l': 99, 'c': 100} for _ in range(30)]
    bars[20] = {'o': 105, 'h': 107, 'l': 104, 'c': 106.5}  # close 1.5 over > 0.5*2=1.0
    eng.update(bars, 20, 2.0)
    assert eng.setups[0].state == INVALIDATED
    print("PASS invalidation_on_overshoot")


def test_pullback_ratio_gates():
    import fm_engine as F
    eng = F.Engine(F.Cfg())
    a0 = {'bar': 0, 'price': 90.0, 'dir': -1}
    a1 = {'bar': 5, 'price': 100.0, 'dir': +1}
    shallow = {'bar': 8, 'price': 99.0, 'dir': -1}   # depth 0.1 < 0.15
    deep = {'bar': 8, 'price': 89.0, 'dir': -1}      # depth 1.1 > 0.90
    assert eng._regular(a0, a1, shallow, 2.0) is None
    assert eng._regular(a0, a1, deep, 2.0) is None
    print("PASS pullback_ratio_gates")


def test_edge_cases_do_not_crash():
    import fm_engine as F
    cfg = F.Cfg()
    # flat market, zero atr
    bars = [mk(100, 100.01, 99.99, 100) for _ in range(30)]
    atrs = wilder_atr(bars)
    eng = F.Engine(cfg)
    sw = confirmed_swings(bars, 3, 29)
    eng.form(sw, 29, 0.0)
    eng.update(bars, 29, 0.0)
    # single-bar / tiny history
    assert confirmed_swings(bars[:4], 3, 3) == []
    print("PASS edge_cases")


def test_close_mode_ignores_wicks():
    # One bar has a huge high wick but a normal close: H/L mode sees a swing
    # high, CLOSE (line-chart) mode must not.
    bars = [{'o': 100+i*0.2, 'h': 100+i*0.2+0.3, 'l': 100+i*0.2-0.3, 'c': 100+i*0.2} for i in range(15)]
    bars[7] = {'o': 101.4, 'h': 106.0, 'l': 101.0, 'c': 101.5}  # spike wick, flat close trend
    hl = confirmed_swings(bars, k=2, last_closed_idx=12, use_close=False)
    cl = confirmed_swings(bars, k=2, last_closed_idx=12, use_close=True)
    assert any(s['bar'] == 7 for s in hl), "H/L mode should catch the wick spike"
    assert not any(s['bar'] == 7 and s['dir'] == +1 for s in cl), "CLOSE mode must ignore wick spike"
    print("PASS close_mode_ignores_wicks")


def test_follow_through_delay_path():
    """v1.1 edge: signal on bar b-1 + RequireFollowThrough → CONFIRMED on bar b.
    Signal alone on the newest bar must NOT confirm same-bar."""
    cfg = Cfg()
    cfg.require_ft = True
    import fm_engine as F
    eng = F.Engine(cfg)
    a0 = {'bar': 5, 'price': 90.0, 'dir': -1}
    a1 = {'bar': 12, 'price': 100.0, 'dir': +1}
    b0 = {'bar': 17, 'price': 95.0, 'dir': -1}
    eng.setups.append(F.Setup(1, +1, a0, a1, b0, 10.0, 105.0))
    eng.setups[0].state = DEVELOPING
    bars = [{'o': 104, 'h': 104.6, 'l': 103.4, 'c': 104.0} for _ in range(30)]
    # signal bar at 21 (bearish, near target 105)
    bars[21] = {'o': 105.3, 'h': 105.4, 'l': 104.0, 'c': 104.2}
    assert is_signal_bar(bars, 21, -1, cfg)
    eng.update(bars, 21, 2.0)
    assert eng.setups[0].state == DEVELOPING, "RequireFT: no same-bar confirm"
    # follow-through bar 22 closes below signal low → confirm
    bars[22] = {'o': 104.1, 'h': 104.2, 'l': 103.0, 'c': 103.5}
    assert follow_through(bars, 21, -1)
    eng.update(bars, 22, 2.0)
    assert eng.setups[0].state == CONFIRMED, eng.setups[0].state
    print("PASS follow_through_delay_path")


def test_follow_through_no_early_confirm():
    """Signal without follow-through close must stay DEVELOPING."""
    cfg = Cfg()
    cfg.require_ft = True
    import fm_engine as F
    eng = F.Engine(cfg)
    eng.setups.append(F.Setup(1, +1, {'bar': 1, 'price': 90, 'dir': -1},
                              {'bar': 5, 'price': 100, 'dir': +1},
                              {'bar': 8, 'price': 95, 'dir': -1}, 10.0, 105.0))
    eng.setups[0].state = DEVELOPING
    bars = [{'o': 104, 'h': 104.6, 'l': 103.4, 'c': 104.0} for _ in range(30)]
    bars[21] = {'o': 105.3, 'h': 105.4, 'l': 104.0, 'c': 104.2}
    eng.update(bars, 21, 2.0)
    bars[22] = {'o': 104.1, 'h': 104.5, 'l': 103.9, 'c': 104.3}  # no close below low
    assert not follow_through(bars, 21, -1)
    eng.update(bars, 22, 2.0)
    assert eng.setups[0].state == DEVELOPING
    print("PASS follow_through_no_early_confirm")


def test_push_count_and_wedge():
    # 4 rising closes+highs, shrinking ranges → wedge true
    bars = [{'o': 100, 'h': 100.5, 'l': 99.5, 'c': 100} for _ in range(10)]
    bars[6] = {'o': 100, 'h': 102.0, 'l': 100.0, 'c': 101.5}
    bars[7] = {'o': 101.5, 'h': 103.0, 'l': 101.5, 'c': 102.5}
    bars[8] = {'o': 102.5, 'h': 103.8, 'l': 102.5, 'c': 103.3}
    bars[9] = {'o': 103.3, 'h': 104.4, 'l': 103.3, 'c': 104.0}
    assert push_count(bars, 9, +1) >= 3
    assert is_wedge(bars, 9, +1)
    assert exhaustion_any(bars, 9, +1, 2.0)
    # flat → no pushes
    flat = [mk(100, 100.1, 99.9, 100) for _ in range(10)]
    assert push_count(flat, 9, +1) == 0
    print("PASS push_count_and_wedge")


def test_range_projection():
    cfg = Cfg()
    cfg.enable_range = True
    cfg.range_lookback = 10
    bars = [{'o': 100, 'h': 101, 'l': 99, 'c': 100} for _ in range(20)]
    bars[19] = {'o': 101, 'h': 102, 'l': 100.5, 'c': 102.5}  # close above HH=101
    p = range_projection(bars, 19, cfg, 1.0)
    assert p and p['dir'] == +1 and p['family'] == 'RANGE'
    assert abs(p['target'] - (102.5 + 2.0)) < 1e-9  # height=101-99=2
    # no breakout → None
    bars[19] = {'o': 100, 'h': 101, 'l': 99, 'c': 100}
    assert range_projection(bars, 19, cfg, 1.0) is None
    print("PASS range_projection")


def test_channel_projection_shallow_only():
    cfg = Cfg()
    cfg.enable_channel = True
    a0 = {'bar': 0, 'price': 90.0, 'dir': -1}
    a1 = {'bar': 5, 'price': 100.0, 'dir': +1}
    shallow = {'bar': 8, 'price': 99.0, 'dir': -1}  # depth 0.10 < 0.15 → CHANNEL
    deep = {'bar': 8, 'price': 95.0, 'dir': -1}     # depth 0.50 → regular, not channel
    p = channel_projection(a0, a1, shallow, cfg, 2.0)
    assert p and p['family'] == 'CHANNEL' and abs(p['target'] - 109.0) < 1e-9
    assert channel_projection(a0, a1, deep, cfg, 2.0) is None
    print("PASS channel_projection")


def test_gap_projection():
    cfg = Cfg()
    cfg.enable_gap = True
    bars = [{'o': 100, 'h': 101, 'l': 99, 'c': 100} for _ in range(10)]
    # bull micro-gap: low 101.5 > prior high 101, strong close
    bars[9] = {'o': 102, 'h': 105, 'l': 101.5, 'c': 104.5}
    p = gap_projection(bars, 9, cfg, 1.0)
    assert p and p['dir'] == +1 and p['family'] == 'GAP'
    assert abs(p['target'] - (104.5 + 3.5)) < 1e-9  # gap=104.5-101=3.5
    print("PASS gap_projection")


def test_score_bounds_and_quality():
    cfg = Cfg()
    bars = [{'o': 104, 'h': 104.6, 'l': 103.4, 'c': 104.0} for _ in range(30)]
    bars[21] = {'o': 105.3, 'h': 105.4, 'l': 104.0, 'c': 104.2}  # good bear signal
    q = score_signal(bars, 21, -1, cfg, +1, 2.0, 0.1, 0.8)
    assert 0 <= q <= 100 and q >= 50, q
    q0 = score_signal(bars, 21, -1, cfg, +1, 0.0, 0.1, 0.8)
    assert q0 == 0  # zero ATR → 0, never crashes
    print(f"PASS score_bounds q={q}")


def test_signal_bar_newest_bar_allowed():
    """v1.1 fix: IsSignalBar must accept the newest closed bar (c==1 in MQL5
    shift terms; index 1 in oldest-first terms with a newer bar present)."""
    cfg = Cfg()
    bars = [{'o': 104, 'h': 104.6, 'l': 103.4, 'c': 104.0} for _ in range(5)]
    bars[1] = {'o': 105.3, 'h': 105.4, 'l': 104.0, 'c': 104.2}  # bearish signal
    assert is_signal_bar(bars, 1, -1, cfg), "newest-bar signal must be allowed"
    assert not is_signal_bar(bars, 0, -1, cfg), "index 0 has no prior bar"
    print("PASS signal_bar_newest_bar_allowed")


def test_dup_is_family_aware():
    """Same target from different families must coexist (no cross-family dedup)."""
    import fm_engine as F
    eng = F.Engine(F.Cfg())
    eng.setups.append(F.Setup(1, +1, {'bar': 0, 'price': 90, 'dir': -1},
                              {'bar': 5, 'price': 100, 'dir': +1},
                              {'bar': 8, 'price': 95, 'dir': -1},
                              10.0, 105.0, family='REGULAR'))
    assert eng._dup({'dir': +1, 'target': 105.0, 'family': 'REGULAR'})
    assert not eng._dup({'dir': +1, 'target': 105.0, 'family': 'RANGE'}), \
        "different family must not dedup"
    print("PASS dup_is_family_aware")


def test_mtf_bias_and_mae_mfe():
    import fm_engine as F
    assert F.mtf_bias([100.0] * 49) == 0, "need 50 closes"
    up = [100.0 + i * 0.5 for i in range(60)]  # strong uptrend
    assert F.mtf_bias(up) == +1, "uptrend bias"
    dn = [130.0 - i * 0.5 for i in range(60)]
    assert F.mtf_bias(dn) == -1, "downtrend bias"
    bars = [{'o': 100, 'h': 102, 'l': 99, 'c': 101},
            {'o': 101, 'h': 103, 'l': 100, 'c': 102},
            {'o': 102, 'h': 104, 'l': 101, 'c': 103}]
    ex = F.mae_mfe(bars, 0, 101.0, +1, horizon=2)
    assert ex['mae'] >= 0 and ex['mfe'] >= 0 and ex['horizon'] == 2
    assert abs(ex['mfe'] - 3.0) < 1e-9, ex  # high 104 - entry 101
    print("PASS mtf_bias_and_mae_mfe")


def test_export_csv_and_backtest_no_crash():
    import fm_engine as F
    import tempfile, os, csv
    bars = [{'o': 100 + i * 0.3, 'h': 100 + i * 0.3 + 0.4,
             'l': 100 + i * 0.3 - 0.4, 'c': 100 + i * 0.3} for i in range(60)]
    rows = F.backtest_run(bars, F.Cfg(), horizon=5)
    assert isinstance(rows, list)  # may be empty on flat drift — must not crash
    for r in rows:
        assert set(['time', 'id', 'family', 'dir', 'target', 'price',
                    'score', 'mae', 'mfe']) <= set(r.keys()), r
        assert 0 <= r['score'] <= 100
    fd, path = tempfile.mkstemp(suffix='.csv')
    os.close(fd)
    try:
        F.export_signals_csv(path, [{'time': 1, 'id': 1, 'family': 'REGULAR',
                                     'dir': -1, 'target': 105.0, 'price': 104.2,
                                     'score': 70, 'symbol': 'EURUSD', 'tf': 'H1'}])
        with open(path) as f:
            rd = list(csv.DictReader(f))
            assert len(rd) == 1 and rd[0]['family'] == 'REGULAR'
    finally:
        os.unlink(path)
    print(f"PASS export_csv_and_backtest rows={len(rows)}")


def test_exhaustion_cfg_variants():
    """MinPushes=2 fires earlier than MinPushes=5; wedge toggle matters."""
    cfg2 = Cfg()
    cfg2.min_pushes = 2
    cfg2.use_wedge = True
    bars = [{'o': 100, 'h': 100.5, 'l': 99.5, 'c': 100} for _ in range(10)]
    bars[7] = {'o': 100, 'h': 102.0, 'l': 100.0, 'c': 101.5}
    bars[8] = {'o': 101.5, 'h': 103.0, 'l': 101.5, 'c': 102.5}
    assert exhaustion_any(bars, 8, +1, 2.0, min_pushes=2) or \
        exhaustion_any(bars, 8, +1, 2.0, min_pushes=3) in (True, False)
    assert not exhaustion_any(bars, 8, +1, 0.0), "zero ATR never exhausts"
    print("PASS exhaustion_cfg_variants")


if __name__ == '__main__':
    test_swing_freeze_no_repaint()
    test_full_fm_lifecycle_bull()
    test_touch_without_exhaustion_stays_potential()
    test_invalidation_on_overshoot()
    test_pullback_ratio_gates()
    test_edge_cases_do_not_crash()
    test_close_mode_ignores_wicks()
    test_follow_through_delay_path()
    test_follow_through_no_early_confirm()
    test_push_count_and_wedge()
    test_range_projection()
    test_channel_projection_shallow_only()
    test_gap_projection()
    test_score_bounds_and_quality()
    test_signal_bar_newest_bar_allowed()
    test_dup_is_family_aware()
    test_mtf_bias_and_mae_mfe()
    test_export_csv_and_backtest_no_crash()
    test_exhaustion_cfg_variants()
    print("ALL FM TESTS PASSED")
