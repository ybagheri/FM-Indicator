"""decision.py — Python mirror of docs/DECISION_ENGINE.md + DecisionEngine.mqh.

Pure function of (candidate setup, context flags, ATR, cfg). No bar indexing:
callers resolve closed-bar values (hook concern); the math here is exact
(float tol 1e-9, enums as strings exact).
"""

ACTIONS = ("NO_TRADE", "WAIT", "BUY", "SELL")
REASONS = ("OK", "DISABLED", "NO_SETUP", "BARBWIRE", "MID_RANGE", "CONFLICT",
           "NO_EDGE", "LOW_SCORE", "LOW_RR", "LATE_ENTRY", "TRAP_REPEAT")


class DecisionCfg:
    def __init__(self, enable=True, min_score=40, max_late=0.50,
                 conflict_ppts=10, max_failed=2, min_rr=1.0):
        self.enable = enable
        self.min_score = min_score
        self.max_late = max_late
        self.conflict_ppts = conflict_ppts
        self.max_failed = max_failed
        self.min_rr = min_rr


def _clamp(v, lo, hi):
    return min(hi, max(lo, v))


def is_conflict(pct, pct_valid, conflict_ppts):
    if not pct_valid or pct is None:
        return False
    if sum(pct) != 100:
        return False
    order = sorted(range(len(pct)), key=lambda i: (-pct[i], i))
    gap = pct[order[0]] - pct[order[1]]
    return gap <= _clamp(conflict_ppts, 5, 30)


def is_late(setup, close, atr, max_late):
    if not setup.get('valid'):
        return False
    if not atr or atr <= 0:
        return False
    if setup.get('dir') == +1:
        return (close - setup['entry']) > max_late * atr
    if setup.get('dir') == -1:
        return (setup['entry'] - close) > max_late * atr
    return False


def decide(setup, ctx, atr, cfg=None):
    cfg = cfg or DecisionCfg()
    d = dict(action="NO_TRADE", reason="NO_SETUP", dir=setup.get('dir', 0),
             setup_type=setup.get('type', 'NONE'), entry=setup.get('entry', 0.0),
             stop=setup.get('stop', 0.0), objective=setup.get('objective', 0.0),
             r_mult=setup.get('r_mult', 0.0), score=setup.get('score', 0))
    min_score = _clamp(cfg.min_score, 0, 100)
    max_failed = _clamp(cfg.max_failed, 1, 5)
    if not cfg.enable:
        d['reason'] = "DISABLED"
        return d
    if not setup.get('valid'):
        d['reason'] = "NO_SETUP"
        return d
    if ctx.get('barbwire'):
        d['reason'] = "BARBWIRE"
        return d
    if ctx.get('mid_range'):
        d['reason'] = "MID_RANGE"
        return d
    if is_conflict(ctx.get('pct'), ctx.get('pct_valid', False),
                   cfg.conflict_ppts):
        d['reason'] = "CONFLICT"
        return d
    if ctx.get('state') in ("UNKNOWN", "TRANSITION"):
        d.update(action="WAIT", reason="NO_EDGE")
        return d
    if setup.get('score', 0) < min_score:
        d.update(action="WAIT", reason="LOW_SCORE")
        return d
    if not setup.get('rr_ok', False):
        d.update(action="WAIT", reason="LOW_RR")
        return d
    if is_late(setup, ctx.get('close', 0.0), atr, cfg.max_late):
        d.update(action="WAIT", reason="LATE_ENTRY")
        return d
    if ctx.get('fail_count', 0) >= max_failed and not ctx.get('has_follow'):
        d['reason'] = "TRAP_REPEAT"
        return d
    d['reason'] = "OK"
    if setup.get('dir') == +1:
        d['action'] = "BUY"
    elif setup.get('dir') == -1:
        d['action'] = "SELL"
    else:
        d.update(action="WAIT", reason="NO_SETUP")
    return d
