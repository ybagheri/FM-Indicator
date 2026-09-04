"""trade_intent.py — mirror of CTradeIntentBuilder pure rules.

Permits table, chase guard (Phase-8 late rule twin), FM plan matching.
Phases 28-30 extend with per-strategy geometry (mirrored here as added).
"""
STRAT_FM_FADE, STRAT_PULLBACK, STRAT_BREAKOUT = 1, 2, 3
STRAT_REVERSAL, STRAT_DOUBLE, STRAT_FAILED_BO = 4, 5, 6


def permits(strategy):
    be, trail, partial = True, False, False
    if strategy in (STRAT_PULLBACK, STRAT_BREAKOUT):
        trail = True
    return (be, trail, partial)


def provisional_ok(provisional, trade_provisional):
    if provisional and not trade_provisional:
        return (False, "PROVISIONAL_OFF")
    return (True, "")


def chase_ok(direction, entry, price, atr, mult=0.5):
    if atr <= 0:
        return (True, "")
    beyond = ((price - entry) if direction > 0 else (entry - price)) / atr
    if beyond > mult + 1e-9:
        return (False, "LATE_ENTRY")
    return (True, "")


def side_ok(direction, stop, price):
    """Mirror of GateSide: fill must not invert risk."""
    if direction > 0:
        return (True, "") if price > stop else (False, "WRONG_SIDE")
    return (True, "") if price < stop else (False, "WRONG_SIDE")


def fm_match(plans, fade_dir, entry):
    """plans: list of dicts(valid,fadeDir,entry,invalidClose)."""
    for p in plans:
        if p.get("valid") and p["fadeDir"] == fade_dir and p["entry"] == entry:
            return p["invalidClose"]
    return None


def failedbo_geometry(bo_dir, ref, atr, stop_buf_mult=0.10, tol_mult=0.25,
                      obj_mult=2.0, min_rr=1.0):
    """Mirror of BuildFailedBO geometry. Returns setup dict or None."""
    if bo_dir not in (+1, -1) or atr <= 0:
        return None
    buf = (stop_buf_mult + tol_mult) * atr
    obj_d = obj_mult * atr
    if buf <= 0 or obj_d <= 0:
        return None
    entry = ref
    stop = ref + buf if bo_dir > 0 else ref - buf
    obj = ref - obj_d if bo_dir > 0 else ref + obj_d
    risk, reward = abs(entry - stop), abs(entry - obj)
    if risk <= 0 or reward <= 0:
        return None
    r = reward / risk
    return {"type": "FAILED_BO", "dir": -bo_dir, "entry": entry,
            "stop": stop, "objective": obj, "risk": risk, "reward": reward,
            "rMult": r, "rrOK": r + 1e-9 >= min_rr, "score": 55,
            "provisional": False, "valid": True}


def explain_alternates(cands, winner_strategy, veto):
    """Mirror of CTradeExplainer::Build alternate loop (cap 11)."""
    alts = []
    for c in cands:
        if not c.get("valid", False) or c.get("strategy") == winner_strategy:
            continue
        if not c.get("enabled", False):
            reason = "DISABLED_BY_MODE"
        elif veto:
            reason = veto
        else:
            reason = "LOST_SELECTION"
        alts.append({"strategy": c["strategy"], "dir": c.get("dir", 0),
                     "score": c.get("score", 0), "reason": reason})
        if len(alts) >= 11:
            break
    return alts


if __name__ == "__main__":
    print("mirror import OK")
