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
                               decision_veto,
                               MODE_SINGLE, MODE_MULTI, MODE_AUTO)
from trade_intent import provisional_ok, chase_ok, side_ok

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


# --- Phase 5: veto + risk-RR + intent final-signal pipeline ---
# Mirrors FM_EA veto block + RiskManager::Check LOW_RR gate (strict, no eps,
# verbatim) + CTradeIntentBuilder gate order (provisional → chase → side),
# and the indicator projection (price = closed-bar close).

def detect_veto(has_trade, decision_done, reason_best):
    """Mirror of CParityBuilder::DetectVeto."""
    if not has_trade or not decision_done:
        return ""
    return decision_veto(reason_best)


def risk_rr_ok(setup, min_rr):
    """Mirror of the Check LOW_RR gate only (strict `<`, 0 = off)."""
    if min_rr > 0 and setup["rMult"] < min_rr:
        return (False, "LOW_RR")
    return (True, "")


def project_intent(setup, price, atr, trade_provisional, chase_mult):
    """Mirror of the From* gate chain. Returns (made, why, dir)."""
    ok, why = provisional_ok(setup["provisional"], trade_provisional)
    if not ok:
        return (False, "SKIP_" + why, 0)
    ok, why = chase_ok(setup["dir"], setup["entry"], price, atr, chase_mult)
    if not ok:
        return (False, "SKIP_" + why, 0)
    ok, why = side_ok(setup["dir"], setup["stop"], price)
    if not ok:
        return (False, "SKIP_" + why, 0)
    side = "BUY" if setup["dir"] > 0 else "SELL"
    return (True, "WOULD_" + side, setup["dir"])


def final_signal(has_trade, strategy, setup, reason_best, decision_done,
                 apply_veto, min_rr, price, atr, trade_provisional,
                 chase_mult):
    """Full pipeline mirror. Returns (action, why) with action in
    {BUY, SELL, NO_TRADE}. WAIT never blocks WOULD_ (EA gates only the five
    veto reasons + risk + intent) — locked here, not fixed, per spec §20."""
    veto = detect_veto(has_trade, decision_done, reason_best)
    if veto and apply_veto:
        return ("NO_TRADE", veto)
    if not has_trade:
        return ("NO_TRADE", "NO_SETUP")
    ok, why = risk_rr_ok(setup, min_rr)
    if not ok:
        return ("NO_TRADE", "SKIP_" + why)
    made, why, d = project_intent(setup, price, atr, trade_provisional,
                                  chase_mult)
    if made:
        return ("BUY" if d > 0 else "SELL", why)
    return ("NO_TRADE", why)


if __name__ == "__main__":
    print("mirror import OK")
