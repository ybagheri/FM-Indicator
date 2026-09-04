"""Decision-engine tests (docs/DECISION_ENGINE.md).
Run: python3 -m pytest tests/test_decision.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from decision import DecisionCfg, decide


def setup(dir=+1, score=70, rr_ok=True, entry=100.0, r_mult=2.0,
          valid=True, stype="REVERSAL"):
    return dict(valid=valid, type=stype, dir=dir, entry=entry, stop=99.0,
                objective=102.0, risk=1.0, reward=2.0, r_mult=r_mult,
                rr_ok=rr_ok, provisional=False, signal_bar=1, ref_price=99.5,
                score=score)


def ctx(state="BULL_TREND", pct=None, mid=False, bw=False, close=100.0,
        fails=0, follow=False):
    return dict(state=state,
                pct=pct or [45, 12, 20, 5, 12, 6], pct_valid=True,
                mid_range=mid, barbwire=bw, close=close,
                fail_count=fails, has_follow=follow)


def test_clean_buy_sell_passthrough():
    d = decide(setup(+1), ctx(close=100.0), 2.0)
    assert (d['action'], d['reason']) == ("BUY", "OK"), d
    d = decide(setup(-1, stype="PULLBACK"), ctx(close=100.0), 2.0)
    assert (d['action'], d['reason']) == ("SELL", "OK"), d
    assert d['setup_type'] == "PULLBACK" and d['dir'] == -1, d
    print("PASS passthrough")


def test_disabled_and_no_setup():
    d = decide(setup(), ctx(), 2.0, DecisionCfg(enable=False))
    assert (d['action'], d['reason']) == ("NO_TRADE", "DISABLED"), d
    d = decide(setup(valid=False), ctx(), 2.0)
    assert (d['action'], d['reason']) == ("NO_TRADE", "NO_SETUP"), d
    print("PASS disabled_nosetup")


def test_structural_vetoes_barbwire_midrange():
    d = decide(setup(), ctx(bw=True, mid=True), 2.0)
    assert (d['action'], d['reason']) == ("NO_TRADE", "BARBWIRE"), d
    d = decide(setup(), ctx(mid=True), 2.0)
    assert (d['action'], d['reason']) == ("NO_TRADE", "MID_RANGE"), d
    print("PASS structural")


def test_conflict_veto_and_unknown_guard_transition_order():
    d = decide(setup(), ctx(pct=[30, 29, 20, 10, 6, 5]), 2.0)  # gap 1
    assert (d['action'], d['reason']) == ("NO_TRADE", "CONFLICT"), d
    d = decide(setup(), ctx(pct=[45, 12, 20, 5, 12, 6]), 2.0)  # gap 25
    assert d['reason'] == "OK", d
    # UNKNOWN pcts (all 0, sum != 100) never conflict → falls to NO_EDGE
    u = dict(ctx(), state="UNKNOWN", pct=[0] * 6, pct_valid=False)
    d = decide(setup(), u, 2.0)
    assert (d['action'], d['reason']) == ("WAIT", "NO_EDGE"), d
    # split-state TRANSITION still reports CONFLICT (conflict precedes NO_EDGE)
    t = dict(ctx(pct=[30, 29, 20, 10, 6, 5]), state="TRANSITION")
    d = decide(setup(), t, 2.0)
    assert (d['action'], d['reason']) == ("NO_TRADE", "CONFLICT"), d
    # clean TRANSITION → NO_EDGE
    d = decide(setup(), ctx(state="TRANSITION"), 2.0)
    assert (d['action'], d['reason']) == ("WAIT", "NO_EDGE"), d
    print("PASS conflict_edge")


def test_low_score_and_low_rr_waits():
    d = decide(setup(score=39), ctx(), 2.0)
    assert (d['action'], d['reason']) == ("WAIT", "LOW_SCORE"), d
    d = decide(setup(score=40), ctx(), 2.0)
    assert d['reason'] == "OK", d  # boundary earns a direction
    d = decide(setup(rr_ok=False, r_mult=0.5), ctx(), 2.0)
    assert (d['action'], d['reason']) == ("WAIT", "LOW_RR"), d
    print("PASS score_rr")


def test_late_chase_veto_both_sides():
    d = decide(setup(+1, entry=100.0), ctx(close=101.5), 2.0)  # +1.5 > 1.0
    assert (d['action'], d['reason']) == ("WAIT", "LATE_ENTRY"), d
    d = decide(setup(+1, entry=100.0), ctx(close=100.5), 2.0)  # +0.5 ok
    assert d['reason'] == "OK", d
    d = decide(setup(-1, entry=100.0), ctx(close=98.5), 2.0)
    assert (d['action'], d['reason']) == ("WAIT", "LATE_ENTRY"), d
    d = decide(setup(-1, entry=100.0), ctx(close=99.5), 2.0)
    assert d['reason'] == "OK", d
    print("PASS late")


def test_trap_repeat_veto_and_follow_rescue():
    d = decide(setup(), ctx(fails=2, follow=False), 2.0)
    assert (d['action'], d['reason']) == ("NO_TRADE", "TRAP_REPEAT"), d
    d = decide(setup(), ctx(fails=2, follow=True), 2.0)
    assert d['reason'] == "OK", d  # follow-through rescues
    d = decide(setup(), ctx(fails=1, follow=False), 2.0)
    assert d['reason'] == "OK", d  # below threshold
    print("PASS trap")


def test_priority_order():
    # barbwire beats mid-range/conflict/score (after enable/setup)
    c = ctx(bw=True, mid=True, pct=[30, 29, 20, 10, 6, 5])
    d = decide(setup(score=10, rr_ok=False), c, 2.0)
    assert d['reason'] == "BARBWIRE", d
    # mid-range beats conflict
    c = ctx(mid=True, pct=[30, 29, 20, 10, 6, 5])
    d = decide(setup(), c, 2.0)
    assert d['reason'] == "MID_RANGE", d
    # score beats RR beats late beats trap
    d = decide(setup(score=10, rr_ok=False), ctx(close=110.0, fails=5), 2.0)
    assert d['reason'] == "LOW_SCORE", d
    print("PASS priority")


def test_zero_atr_late_guard():
    # atr<=0 must not crash and must not false-late; trap window still works
    d = decide(setup(+1, entry=100.0), ctx(close=150.0), 0.0)
    assert d['reason'] == "OK", d
    print("PASS zero_atr")


def test_determinism_and_freeze():
    s, c = setup(), ctx()
    assert decide(s, c, 2.0) == decide(s, c, 2.0), "pure decide deterministic"
    # freeze: pure inputs — history extension is irrelevant by construction;
    # identical inputs re-decided identically.
    assert decide(dict(s), dict(c), 2.0) == decide(s, c, 2.0)
    print("PASS determinism_freeze")


if __name__ == "__main__":
    test_clean_buy_sell_passthrough()
    test_disabled_and_no_setup()
    test_structural_vetoes_barbwire_midrange()
    test_conflict_veto_and_unknown_guard_transition_order()
    test_low_score_and_low_rr_waits()
    test_late_chase_veto_both_sides()
    test_trap_repeat_veto_and_follow_rescue()
    test_priority_order()
    test_zero_atr_late_guard()
    test_determinism_and_freeze()
    print("ALL DECISION TESTS PASS")
