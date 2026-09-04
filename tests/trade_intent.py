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


def fm_match(plans, fade_dir, entry):
    """plans: list of dicts(valid,fadeDir,entry,invalidClose)."""
    for p in plans:
        if p.get("valid") and p["fadeDir"] == fade_dir and p["entry"] == entry:
            return p["invalidClose"]
    return None


if __name__ == "__main__":
    print("mirror import OK")
