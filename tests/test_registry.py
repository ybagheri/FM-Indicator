"""test_registry.py — Phase-22 registry suites (mirror of StrategyRegistry.mqh)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strategy_registry import (select, map_type, MODE_SINGLE, MODE_MULTI,
                               MODE_AUTO, STRAT_FM_FADE, STRAT_PULLBACK,
                               STRAT_BREAKOUT)

USES_ALL = {1: True, 2: True, 3: True, 4: True, 5: True}


def C(t, score, prov=False, entry=1.0, valid=True):
    return {"type": t, "score": score, "provisional": prov,
            "entry": entry, "valid": valid}


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_single_filter():
    cands = [C("PULLBACK", 84), C("FM_FADE", 41)]
    ok, st, _ = select(cands, MODE_SINGLE, STRAT_FM_FADE, USES_ALL)
    check("single_fm_only", ok and st == STRAT_FM_FADE)
    ok, st, _ = select(cands, MODE_SINGLE, STRAT_PULLBACK, USES_ALL)
    check("single_pb_only", ok and st == STRAT_PULLBACK)


def test_multi_filter():
    uses = {1: True, 2: False, 3: True, 4: False, 5: False}
    cands = [C("PULLBACK", 84), C("BREAKOUT", 76), C("FM_FADE", 41)]
    ok, st, s = select(cands, MODE_MULTI, STRAT_FM_FADE, uses)
    check("multi_max_enabled", ok and st == STRAT_BREAKOUT and s["score"] == 76)


def test_auto_max():
    cands = [C("PULLBACK", 84), C("BREAKOUT", 76), C("FM_FADE", 41),
             C("REVERSAL", 38)]
    ok, st, _ = select(cands, MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    check("auto_pullback84", ok and st == STRAT_PULLBACK)


def test_tiebreaks():
    cands = [C("BREAKOUT", 70, prov=True, entry=1.0),
             C("PULLBACK", 70, prov=False, entry=2.0)]
    ok, st, _ = select(cands, MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    check("tie_firm_wins", ok and st == STRAT_PULLBACK)
    cands = [C("BREAKOUT", 70, entry=1.0), C("PULLBACK", 70, entry=2.0)]
    ok, st, _ = select(cands, MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    check("tie_enum_order", ok and st == STRAT_PULLBACK)  # 2 < 3
    cands = [C("PULLBACK", 70, entry=2.0), C("PULLBACK", 70, entry=1.0)]
    ok, st, s = select(cands, MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    check("tie_lower_entry", ok and s["entry"] == 1.0)
    check("map_unknown_none", map_type("NOPE") == 0)


def test_empty_no_trade():
    ok, st, s = select([], MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    check("empty_no_trade", (not ok) and st == 0 and s is None)
    cands = [C("PULLBACK", 84, valid=False), C("FM_FADE", 41)]
    uses = {1: False, 2: False, 3: False, 4: False, 5: False}
    ok, _, _ = select(cands, MODE_MULTI, STRAT_FM_FADE, uses)
    check("all_disabled_no_trade", not ok)
    # determinism: repeat call identical
    cands = [C("PULLBACK", 84), C("BREAKOUT", 76)]
    r1 = select(cands, MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    r2 = select(cands, MODE_AUTO, STRAT_FM_FADE, USES_ALL)
    check("determinism", r1 == r2)


if __name__ == "__main__":
    test_single_filter()
    test_multi_filter()
    test_auto_max()
    test_tiebreaks()
    test_empty_no_trade()
    print("ALL REGISTRY TESTS PASSED")
