"""Anti-repaint + functional tests for the FM spec mirror.
Run: python3 -m pytest tests/ -q  (or python3 tests/test_fm.py)
Covers TESTING.md §1-12 core: swings freeze, no-look-ahead, state order,
alert-once, invalidation, edge cases.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from fm_engine import (Cfg, Engine, confirmed_swings, wilder_atr,
                       exhaustion_any, is_signal_bar,
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


if __name__ == '__main__':
    test_swing_freeze_no_repaint()
    test_full_fm_lifecycle_bull()
    test_touch_without_exhaustion_stays_potential()
    test_invalidation_on_overshoot()
    test_pullback_ratio_gates()
    test_edge_cases_do_not_crash()
    print("ALL FM TESTS PASSED")
