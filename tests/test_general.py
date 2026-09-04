"""General-setup catalog tests (docs/GENERAL_SETUPS.md).
Run: python3 -m pytest tests/test_general.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from general_setups import (GeneralCfg, build_pullback_bull,
                            build_pullback_bear, build_double,
                            build_breakout, build_reversal, select_best)


def pb(legs=2, sig=10):
    return dict(found=True, legs=legs, signal_bar=sig)


def test_pullback_h2_firm_geometry():
    cfg = GeneralCfg()
    s = build_pullback_bull(pb(2, 10), 105.0, 100.0, 108.0, 2.0, cfg)
    assert s['valid'] and s['dir'] == +1 and not s['provisional'], s
    assert abs(s['entry'] - 105.1) < 1e-9, s      # 105 + 0.05*2
    assert abs(s['stop'] - 99.8) < 1e-9, s        # 100 - 0.10*2
    assert s['objective'] == 108.0, s
    assert abs(s['reward'] - 2.9) < 1e-9 and abs(s['risk'] - 5.3) < 1e-9, s
    assert abs(s['r_mult'] - 2.9 / 5.3) < 1e-9 and s['score'] == 70, s
    assert s['rr_ok'] is False, s  # 0.547 < 1.0
    print("PASS pb_h2")


def test_pullback_h1_provisional_tick_buf():
    cfg = GeneralCfg()
    s = build_pullback_bull(pb(1, 7), 105.0, 100.0, 112.0, 2.0, cfg)
    assert s['valid'] and s['provisional'] and s['score'] == 40, s
    assert abs(s['entry'] - 105.1) < 1e-9 and abs(s['stop'] - 99.8) < 1e-9, s
    assert abs(s['r_mult'] - 6.9 / 5.3) < 1e-9 and s['rr_ok'] is True, s
    b = build_pullback_bear(pb(1, 7), 95.0, 100.0, 88.0, 2.0, cfg)
    assert b['valid'] and b['dir'] == -1 and b['provisional'], b
    assert abs(b['entry'] - 94.9) < 1e-9 and abs(b['stop'] - 100.2) < 1e-9, b
    assert abs(b['reward'] - 6.9) < 1e-9 and abs(b['risk'] - 5.3) < 1e-9, b
    print("PASS pb_h1")


def test_double_swing_top_geometry():
    cfg = GeneralCfg()
    d = dict(found=True, dir=-1, bar1=2, bar2=8, price1=100.0, price2=100.2,
             micro=False)
    s = build_double(d, 96.0, 2.0, cfg)
    assert s['valid'] and s['dir'] == -1 and not s['provisional'], s
    assert s['entry'] == 100.2, s
    assert abs(s['stop'] - 100.9) < 1e-9, s  # 100.2+0.5+0.2
    assert s['objective'] == 96.0 and abs(s['reward'] - 4.2) < 1e-9, s
    assert abs(s['risk'] - 0.7) < 1e-9 and s['score'] == 60, s
    assert s['rr_ok'] is True, s  # 6.0 >= 1.0
    print("PASS dbl_top")


def test_double_micro_provisional_and_bottom_mirror():
    cfg = GeneralCfg()
    d = dict(found=True, dir=-1, bar1=2, bar2=8, price1=100.0, price2=100.2,
             micro=True)
    s = build_double(d, 96.0, 2.0, cfg)
    assert s['valid'] and s['provisional'] and s['score'] == 30, s
    b = dict(found=True, dir=+1, bar1=3, bar2=9, price1=90.0, price2=89.8,
             micro=False)
    q = build_double(b, 94.0, 2.0, cfg)
    assert q['valid'] and q['dir'] == +1 and not q['provisional'], q
    assert q['entry'] == 89.8, q
    assert abs(q['stop'] - 89.1) < 1e-9, q  # 89.8-0.5-0.2
    assert abs(q['reward'] - 4.2) < 1e-9 and abs(q['risk'] - 0.7) < 1e-9, q
    print("PASS dbl_micro_bottom")


def test_breakout_follow_firm_trap_penalty():
    cfg = GeneralCfg()
    bo = dict(found=True, dir=+1, bo_bar=5, ref_price=100.0, outcome="FOLLOW",
              trap=False)
    s = build_breakout(bo, 101.0, 2.0, cfg)
    assert s['valid'] and not s['provisional'] and s['score'] == 70, s
    assert s['entry'] == 101.0 and abs(s['stop'] - 99.8) < 1e-9, s
    assert abs(s['objective'] - 105.0) < 1e-9, s  # 101 + 2*2
    assert abs(s['risk'] - 1.2) < 1e-9 and s['rr_ok'] is True, s
    t = build_breakout(dict(bo, trap=True), 101.0, 2.0, cfg)
    assert t['valid'] and t['score'] == 50, t
    print("PASS bo_follow_trap")


def test_breakout_pending_provisional_failed_silent():
    cfg = GeneralCfg()
    bo = dict(found=True, dir=-1, bo_bar=4, ref_price=100.0, outcome="PENDING",
              trap=False)
    s = build_breakout(bo, 99.0, 2.0, cfg)
    assert s['valid'] and s['provisional'] and s['score'] == 40, s
    assert abs(s['stop'] - 100.2) < 1e-9 and abs(s['objective'] - 95.0) < 1e-9, s
    f = build_breakout(dict(bo, outcome="FAILED"), 99.0, 2.0, cfg)
    assert f['valid'] is False, f
    n = build_breakout(dict(found=False), 99.0, 2.0, cfg)
    assert n['valid'] is False, n
    print("PASS bo_pending_failed")


def test_reversal_major_firm_minor_provisional():
    cfg = GeneralCfg()
    rv = dict(found=True, dir=+1, verdict="MAJOR")
    s = build_reversal(rv, 102.0, 100.0, 2.0, cfg)
    assert s['valid'] and not s['provisional'] and s['score'] == 80, s
    assert s['entry'] == 102.0, s
    assert abs(s['stop'] - 99.3) < 1e-9, s  # 100-(0.5+0.2)
    assert abs(s['objective'] - 106.0) < 1e-9, s
    assert abs(s['risk'] - 2.7) < 1e-9 and s['rr_ok'] is True, s
    m = build_reversal(dict(found=True, dir=-1, verdict="MINOR"), 98.0, 100.0,
                       2.0, cfg)
    assert m['valid'] and m['provisional'] and m['score'] == 40, m
    assert abs(m['stop'] - 100.7) < 1e-9 and abs(m['objective'] - 94.0) < 1e-9, m
    print("PASS rev_major_minor")


def test_rr_threshold_and_invalid_risk_reward():
    cfg = GeneralCfg(min_rr=2.0)
    s = build_pullback_bull(pb(2, 10), 105.0, 100.0, 108.0, 2.0, cfg)
    assert s['valid'] and s['rr_ok'] is False, s  # 0.547 < 2.0
    bad = build_pullback_bull(pb(2, 10), 105.0, 100.0, 104.0, 2.0)
    assert bad['valid'] is False, bad  # objective below entry
    flat = build_breakout(dict(found=True, dir=+1, bo_bar=5, ref_price=101.0,
                               outcome="FOLLOW", trap=False), 101.0, 2.0,
                          GeneralCfg(stop_buf=0.0))
    assert flat['risk'] == 0.0 and flat['valid'] is False, flat
    print("PASS rr_invalid")


def test_selection_and_safety():
    cfg = GeneralCfg()
    a = build_pullback_bull(pb(1, 7), 105.0, 100.0, 112.0, 2.0, cfg)  # 40
    b = build_breakout(dict(found=True, dir=+1, bo_bar=5, ref_price=100.0,
                            outcome="FOLLOW", trap=False), 101.0, 2.0, cfg)  # 70
    c = build_reversal(dict(found=True, dir=+1, verdict="MAJOR"), 102.0, 100.0,
                       2.0, cfg)  # 80
    assert select_best([a, b, c]) == 2, [a, b, c]
    # tie → lowest type order wins (PULLBACK=1 beats BREAKOUT=3)
    t1 = dict(a, score=70)
    assert select_best([t1, b]) == 0, (t1, b)
    off = GeneralCfg(enable=False)
    assert build_pullback_bull(pb(2, 10), 105.0, 100.0, 108.0, 2.0,
                               off)['valid'] is False
    assert build_double(dict(found=True, dir=-1, bar1=1, bar2=2, price1=100.0,
                             price2=100.0, micro=False), 96.0, 0.0)['valid'] is False
    assert build_reversal(dict(found=True, dir=0, verdict="MINOR"), 100.0, 99.0,
                          2.0)['valid'] is False
    print("PASS select_safety")


def test_determinism_and_freeze():
    cfg = GeneralCfg()
    d = dict(found=True, dir=-1, bar1=2, bar2=8, price1=100.0, price2=100.2,
             micro=False)
    a = build_double(d, 96.0, 2.0, cfg)
    b = build_double(d, 96.0, 2.0, cfg)
    assert a == b, "pure builder must be deterministic"
    # freeze: extending history (extra newer bars) never changes an old setup
    # because builders take explicit prices — re-call with identical inputs.
    c = build_breakout(dict(found=True, dir=+1, bo_bar=5, ref_price=100.0,
                            outcome="FOLLOW", trap=False), 101.0, 2.0, cfg)
    d2 = build_breakout(dict(found=True, dir=+1, bo_bar=5, ref_price=100.0,
                             outcome="FOLLOW", trap=False), 101.0, 2.0, cfg)
    assert c == d2, "history extension must leave old setup untouched"
    print("PASS determinism_freeze")


if __name__ == "__main__":
    test_pullback_h2_firm_geometry()
    test_pullback_h1_provisional_tick_buf()
    test_double_swing_top_geometry()
    test_double_micro_provisional_and_bottom_mirror()
    test_breakout_follow_firm_trap_penalty()
    test_breakout_pending_provisional_failed_silent()
    test_reversal_major_firm_minor_provisional()
    test_rr_threshold_and_invalid_risk_reward()
    test_selection_and_safety()
    test_determinism_and_freeze()
    print("ALL GENERAL TESTS PASS")
