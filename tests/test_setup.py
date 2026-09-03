"""FM setup-plan tests (docs/SETUP_ENGINE.md).
Run: python3 -m pytest tests/test_setup.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from setup_engine import SetupCfg, plan


def sig(o, h, l, c):
    assert h >= max(o, c) and l <= min(o, c), (o, h, l, c)
    return {'o': o, 'h': h, 'l': l, 'c': c}


def test_sell_geometry_exact():
    s = sig(108, 110, 106, 107)
    p = plan(s, +1, 110.0, 100.0, 2.0, setup_id=7, confirmed=True, shift=3)
    assert p['valid'] and p['fade_dir'] == -1, p
    assert p['entry'] == 106.0, p
    assert p['stop'] == 110.7, p          # max(110, 110+0.5) + 0.2
    assert p['objective'] == 100.0, p
    assert p['reward'] == 6.0 and abs(p['risk'] - 4.7) < 1e-9, p
    assert abs(p['r_mult'] - 6.0 / 4.7) < 1e-9, p
    assert p['rr_ok'] and not p['provisional'], p
    assert p['invalid_close'] == 111.0, p
    assert p['setup_id'] == 7 and p['signal_shift'] == 3, p
    print("PASS sell_exact")


def test_buy_mirror():
    s = sig(92, 94, 90, 93)
    p = plan(s, -1, 90.0, 100.0, 2.0, confirmed=True)
    assert p['valid'] and p['fade_dir'] == +1, p
    assert p['entry'] == 94.0 and p['stop'] == 89.3, p  # min(90, 90-0.5) - 0.2
    assert p['reward'] == 6.0 and abs(p['risk'] - 4.7) < 1e-9, p
    assert abs(p['r_mult'] - 6.0 / 4.7) < 1e-9 and p['rr_ok'], p
    assert p['invalid_close'] == 89.0, p
    print("PASS buy_mirror")


def test_stop_anchored_on_signal_extreme():
    s = sig(109, 112, 107, 108)  # high dominates the zone
    p = plan(s, +1, 110.0, 100.0, 2.0)
    assert p['valid'] and p['stop'] == 112.2, p  # max(112, 110.5) + 0.2
    b = sig(91, 93, 88, 92)      # low dominates the zone
    q = plan(b, -1, 90.0, 100.0, 2.0)
    assert q['valid'] and q['stop'] == 87.8, q  # min(88, 89.5) - 0.2
    print("PASS stop_on_extreme")


def test_stop_anchored_on_target_zone():
    s = sig(108, 109.5, 106, 107)  # zone top 110.5 above signal high
    p = plan(s, +1, 110.0, 100.0, 2.0)
    assert p['valid'] and p['stop'] == 110.7, p
    print("PASS stop_on_zone")


def test_invalid_objective_beyond_entry():
    s = sig(108, 110, 106, 107)
    assert plan(s, +1, 110.0, 107.0, 2.0)['valid'] is False      # reward -1
    b = sig(92, 94, 90, 93)
    assert plan(b, -1, 90.0, 93.0, 2.0)['valid'] is False        # reward -1
    print("PASS invalid_objective")


def test_invalid_zero_risk():
    cfg = SetupCfg(stop_buf=0.0)
    flat = sig(100, 100, 100, 100)
    p = plan(flat, +1, 99.0, 95.0, 2.0, cfg=cfg)  # struct 100, stop 100
    assert p['reward'] == 5.0 and p['risk'] == 0.0, p
    assert p['valid'] is False, p
    print("PASS zero_risk")


def test_rr_threshold_both_sides():
    s = sig(108, 110, 106, 107)  # R = 6/4.7 ~= 1.2766
    assert plan(s, +1, 110.0, 100.0, 2.0)['rr_ok'] is True
    hi = SetupCfg(min_rr=2.0)
    p = plan(s, +1, 110.0, 100.0, 2.0, cfg=hi)
    assert p['valid'] and p['rr_ok'] is False, p
    print("PASS rr_threshold")


def test_provisional_and_family_passthrough():
    s = sig(108, 110, 106, 107)
    assert plan(s, +1, 110.0, 100.0, 2.0, confirmed=False)['provisional'] is True
    assert plan(s, +1, 110.0, 100.0, 2.0, confirmed=True)['provisional'] is False
    for fam in ("REGULAR", "INVERSE", "RANGE", "CHANNEL", "GAP"):
        p = plan(s, +1, 110.0, 100.0, 2.0, family=fam)
        assert p['valid'] and p['family'] == fam, (fam, p)
    print("PASS provisional_family")


def test_invalid_close_and_safety():
    s = sig(108, 110, 106, 107)
    assert plan(s, +1, 110.0, 100.0, 2.0)['invalid_close'] == 111.0
    b = sig(92, 94, 90, 93)
    assert plan(b, -1, 90.0, 100.0, 2.0)['invalid_close'] == 89.0
    off = SetupCfg(enable=False)
    assert plan(s, +1, 110.0, 100.0, 2.0, cfg=off)['valid'] is False
    assert plan(s, +1, 110.0, 100.0, 0.0)['valid'] is False
    assert plan(s, 0, 110.0, 100.0, 2.0)['valid'] is False
    print("PASS invalid_close_safety")


def test_determinism():
    s = sig(108, 110, 106, 107)
    a = plan(s, +1, 110.0, 100.0, 2.0, setup_id=7, confirmed=True, shift=3)
    b = plan(s, +1, 110.0, 100.0, 2.0, setup_id=7, confirmed=True, shift=3)
    assert a == b, "pure planner must be deterministic"
    print("PASS determinism")


if __name__ == "__main__":
    test_sell_geometry_exact()
    test_buy_mirror()
    test_stop_anchored_on_signal_extreme()
    test_stop_anchored_on_target_zone()
    test_invalid_objective_beyond_entry()
    test_invalid_zero_risk()
    test_rr_threshold_both_sides()
    test_provisional_and_family_passthrough()
    test_invalid_close_and_safety()
    test_determinism()
    print("ALL SETUP TESTS PASS")
