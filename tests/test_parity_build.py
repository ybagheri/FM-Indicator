"""test_parity_build.py — Phase-3 builder equivalence (mirror of ParityDecision.mqh).

Checks CParityBuilder semantics against the pre-existing independent mirrors:
  1. universe = valid mapped catalog + FAILED_BO appended last, capped at 13.
  2. SINGLE/MULTI selection == strategy_registry.select over the same inputs.
  3. AUTO selection/final == strategy_registry.select_auto over the same inputs.
  4. autoFinal == -1 outside AUTO; determinism over randomized fixtures.
"""
import sys
import os
import random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strategy_registry import (select, select_auto, auto_final, map_type,
                               MODE_SINGLE, MODE_MULTI, MODE_AUTO,
                               STRAT_FM_FADE)
from parity_decision import build, MAX_CAND

TYPES = ["FM_FADE", "PULLBACK", "BREAKOUT", "REVERSAL", "DOUBLE", "BOGUS"]
STATES = ["BULL_TREND", "BEAR_CHANNEL", "TRADING_RANGE", "TRANSITION",
          "UNKNOWN", "BREAKOUT_MODE"]
TUN = {"trendBonus": 10, "provPenalty": 5, "rrBonus": 5, "rrLevel": 2.0}


def mk_setup(rng, i):
    return {"type": rng.choice(TYPES),
            "score": rng.randint(0, 100),
            "provisional": rng.random() < 0.4,
            "entry": round(1.0 + rng.random() + i * 1e-6, 6),
            "valid": rng.random() < 0.9,
            "dir": rng.choice([-1, 1]),
            "rMult": round(rng.uniform(0.2, 3.5), 3)}


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def raw_cands_for_select(catalog, fbo):
    """Inputs for the legacy select()/select_auto() mirrors."""
    raw = [dict(s) for s in catalog]
    if fbo is not None and fbo.get("valid", False):
        raw.append(dict(fbo, type="FAILED_BO"))
    return raw


def test_builder_matches_legacy():
    rng = random.Random(20260905)
    for trial in range(300):
        n = rng.randint(0, 8)
        catalog = [mk_setup(rng, i) for i in range(n)]
        fbo = None
        if rng.random() < 0.5:
            fbo = {"score": 55, "provisional": False,
                   "entry": round(1.5 + rng.random(), 6), "valid": True,
                   "dir": rng.choice([-1, 1]), "rMult": 2.0}
        mode = rng.choice([MODE_SINGLE, MODE_MULTI, MODE_AUTO])
        single = rng.randint(1, 6)
        uses = {s: rng.random() < 0.7 for s in range(1, 7)}
        state = rng.choice(STATES)
        state_valid = rng.random() < 0.9
        tuning = dict(TUN, trendBonus=rng.choice([0, 5, 10]),
                      rrLevel=rng.choice([1.0, 2.0]))
        got = build(catalog, fbo, mode, single, uses, state, state_valid,
                    tuning)
        # 1. universe shape
        exp_n = sum(1 for s in catalog
                    if s.get("valid") and map_type(s["type"]) != 0)
        if fbo is not None and fbo.get("valid"):
            exp_n += 1
        check("t%d count" % trial, got["candCount"] == min(exp_n, MAX_CAND))
        if fbo is not None and fbo.get("valid") and exp_n <= MAX_CAND:
            check("t%d fbo_last" % trial,
                  got["universe"][-1]["setup"] is fbo)
        # 2/3. selection vs legacy mirrors
        raw = raw_cands_for_select(catalog, fbo)
        if mode == MODE_AUTO:
            uses_a = dict(uses)
            ok, st, setup, final = select_auto(raw, state, state_valid,
                                               tuning, uses_a)
            check("t%d auto_trade" % trial, got["has_trade"] == ok)
            check("t%d auto_strat" % trial, got["strategy"] == st)
            check("t%d auto_final" % trial, got["autoFinal"] == final)
            if ok:
                check("t%d auto_setup" % trial,
                      got["setup"]["score"] == setup["score"]
                      and got["setup"]["entry"] == setup["entry"])
        else:
            ok, st, setup = select(raw, mode, single, uses)
            check("t%d sel_trade" % trial, got["has_trade"] == ok)
            check("t%d sel_strat" % trial, got["strategy"] == st)
            check("t%d sel_final" % trial, got["autoFinal"] == -1)
            if ok:
                check("t%d sel_setup" % trial,
                      got["setup"]["score"] == setup["score"]
                      and got["setup"]["entry"] == setup["entry"])


def test_empty_and_cap():
    got = build([], None, MODE_AUTO, STRAT_FM_FADE,
                {s: True for s in range(1, 7)}, "BULL_TREND", True, TUN)
    check("empty_no_trade",
          got["candCount"] == 0 and not got["has_trade"]
          and got["autoFinal"] == -1)
    big = [{"type": "PULLBACK", "score": 50, "provisional": False,
            "entry": 1.0 + i * 1e-6, "valid": True, "dir": 1, "rMult": 1.0}
           for i in range(20)]
    got = build(big, None, MODE_MULTI, STRAT_FM_FADE,
                {s: True for s in range(1, 7)}, "BULL_TREND", True, TUN)
    check("cap_13", got["candCount"] == MAX_CAND and got["has_trade"])
    # determinism
    a = build(big, None, MODE_AUTO, STRAT_FM_FADE,
              {s: True for s in range(1, 7)}, "BULL_TREND", True, TUN)
    b = build(big, None, MODE_AUTO, STRAT_FM_FADE,
              {s: True for s in range(1, 7)}, "BULL_TREND", True, TUN)
    check("determinism",
          a["strategy"] == b["strategy"] and a["autoFinal"] == b["autoFinal"])


if __name__ == "__main__":
    test_builder_matches_legacy()
    test_empty_and_cap()
    print("ALL PARITY-BUILD TESTS PASSED")
