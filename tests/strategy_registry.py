"""strategy_registry.py — 1:1 mirror of StrategyRegistry.mqh Select/filter rule.

Rule (Phase 22, documented to be replaced by Phase 31):
highest score among enabled+valid candidates; ties: firm beats provisional,
then lower strategy enum, then lower entry. Empty -> no trade.
"""
STRAT_NONE, STRAT_FM_FADE, STRAT_PULLBACK = 0, 1, 2
STRAT_BREAKOUT, STRAT_REVERSAL, STRAT_DOUBLE = 3, 4, 5
STRAT_FAILED_BO = 6
MODE_SINGLE, MODE_MULTI, MODE_AUTO = 0, 1, 2


def map_type(t):
    return {"FM_FADE": 1, "PULLBACK": 2, "BREAKOUT": 3,
            "REVERSAL": 4, "DOUBLE": 5, "FAILED_BO": 6}.get(t, 0)


def is_enabled(s, mode, single, uses):
    if s <= 0 or s >= 7:
        return False
    if mode == MODE_SINGLE:
        return s == single
    return bool(uses.get(s, False))


def select(cands, mode, single, uses):
    """cands: list of dicts(type,score,provisional,entry,valid).
    Returns (has_trade, strategy, setup-dict-or-None)."""
    best = None
    for c in cands:
        if not c.get("valid", False):
            continue
        st = map_type(c["type"])
        if st == 0 or not is_enabled(st, mode, single, uses):
            continue
        if best is None:
            best = (st, c)
            continue
        _, b = best
        if c["score"] != b["score"]:
            win = c["score"] > b["score"]
        elif c["provisional"] != b["provisional"]:
            win = b["provisional"] and not c["provisional"]
        elif st != best[0]:
            win = st < best[0]
        else:
            win = c["entry"] < b["entry"]
        if win:
            best = (st, c)
    if best is None:
        return (False, 0, None)
    return (True, best[0], best[1])


# --- Phase 31: AUTO conflict resolution (mirror of SelectAuto/AutoFinal) ---
# states: BULL_TREND/BULL_CHANNEL=+1, BEAR_*=-1, else 0 (no edge).
def context_dir(state):
    if state in ("BULL_TREND", "BULL_CHANNEL"):
        return +1
    if state in ("BEAR_TREND", "BEAR_CHANNEL"):
        return -1
    return 0


def auto_final(c, state, state_valid, tuning):
    f = c["score"]
    ctx = context_dir(state)
    if ctx != 0 and state_valid:
        f += tuning["trendBonus"] if c["dir"] == ctx else -tuning["trendBonus"]
    if c["provisional"]:
        f -= tuning["provPenalty"]
    if c["rMult"] + 1e-9 >= tuning["rrLevel"]:
        f += tuning["rrBonus"]
    return f


def select_auto(cands, state, state_valid, tuning, uses):
    best = None  # (final, strategy-enum, entry, cand)
    for c in cands:
        if not c.get("valid", False):
            continue
        st = map_type(c["type"])
        if st == 0 or not uses.get(st, False):
            continue
        f = auto_final(c, state, state_valid, tuning)
        key = (f, c["provisional"] is False, -st, -c["entry"])
        if best is None or key > best[0]:
            best = (key, st, c)
    if best is None:
        return (False, 0, None, -1)
    return (True, best[1], best[2], auto_final(best[2], state, state_valid,
                                              tuning))


# Phase-8 structural vetoes the EA applies in ALL modes (mirror of the
# EA veto block; score/RR/late vetoes live natively in risk/chase).
VETO_REASONS = {"BARBWIRE", "MID_RANGE", "CONFLICT", "NO_EDGE", "TRAP_REPEAT"}


def decision_veto(reason):
    return ("DECISION_VETO_" + reason) if reason in VETO_REASONS else ""


if __name__ == "__main__":
    print("mirror import OK")
