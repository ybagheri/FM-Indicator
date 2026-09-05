"""parity_decision.py — 1:1 mirror of ParityDecision.mqh CParityBuilder.

Build order (must match MQL5 exactly):
  universe = mapped catalog entries (valid, known type) + FAILED_BO appended
  selection = SelectAuto (AUTO) else Select (SINGLE/MULTI)
Universe entries: {"strategy": enum, "setup": dict, "enabled": bool}.
Setup dicts: {type,score,provisional,entry,valid,dir,rMult}.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strategy_registry import (map_type, is_enabled, auto_final,
                               MODE_SINGLE, MODE_MULTI, MODE_AUTO)

MAX_CAND = 13  # FM_PARITY_MAX_CAND


def build_universe(catalog, fbo, uses, mode, single):
    out = []
    for s in catalog:
        if not s.get("valid", False):
            continue
        st = map_type(s["type"])
        if st == 0:
            continue
        out.append({"strategy": st, "setup": s,
                    "enabled": is_enabled(st, mode, single, uses)})
    if fbo is not None and fbo.get("valid", False):
        st = map_type("FAILED_BO")
        if st != 0:
            out.append({"strategy": st, "setup": fbo,
                        "enabled": is_enabled(st, mode, single, uses)})
    return out[:MAX_CAND]


def _select_universe(uni):
    """Mirror of CStrategyRegistry::Select over universe entries."""
    best = None
    for u in uni:
        s = u["setup"]
        if not u["enabled"] or not s.get("valid", False):
            continue
        if best is None:
            best = u
            continue
        a, b = s, best["setup"]
        if a["score"] != b["score"]:
            win = a["score"] > b["score"]
        elif a["provisional"] != b["provisional"]:
            win = b["provisional"] and not a["provisional"]
        elif u["strategy"] != best["strategy"]:
            win = u["strategy"] < best["strategy"]
        else:
            win = a["entry"] < b["entry"]
        if win:
            best = u
    if best is None:
        return (False, 0, None)
    return (True, best["strategy"], best["setup"])


def _select_auto_universe(uni, state, state_valid, tuning):
    """Mirror of CStrategyRegistry::SelectAuto over universe entries."""
    best = None
    best_final = -1000000
    for u in uni:
        s = u["setup"]
        if not u["enabled"] or not s.get("valid", False):
            continue
        f = auto_final(s, state, state_valid, tuning)
        if best is None or f != best_final:
            win = best is None or f > best_final
        elif s["provisional"] != best["setup"]["provisional"]:
            win = best["setup"]["provisional"] and not s["provisional"]
        elif u["strategy"] != best["strategy"]:
            win = u["strategy"] < best["strategy"]
        else:
            win = s["entry"] < best["setup"]["entry"]
        if win:
            best = u
            best_final = f
    if best is None:
        return (False, 0, None, -1)
    return (True, best["strategy"], best["setup"], best_final)


def build(catalog, fbo, mode, single, uses, state, state_valid, tuning):
    uni = build_universe(catalog, fbo, uses, mode, single)
    if mode == MODE_AUTO:
        ok, st, setup, final = _select_auto_universe(uni, state,
                                                     state_valid, tuning)
    else:
        ok, st, setup = _select_universe(uni)
        final = -1
    return {"valid": True, "candCount": len(uni), "universe": uni,
            "has_trade": ok, "strategy": st, "setup": setup,
            "autoFinal": final}


if __name__ == "__main__":
    print("mirror import OK")
