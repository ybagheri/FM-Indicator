"""safety.py — mirror of CSafetyManager gates + CPaperTrader settlement.

Session: start==end -> always. Drawdown latches on peak. Emergency latches.
Paper: per-bar OHLC settle, SL-first ambiguity, R = profit/risk.
"""
ANALYSIS_ONLY, PAPER, DEMO, LIVE = 0, 1, 2, 3
ACCT_DEMO, ACCT_REAL = 0, 2  # simplified trade-mode classes


def session_open(start_h, end_h, hour):
    if start_h == end_h:
        return True
    if start_h < end_h:
        return start_h <= hour < end_h
    return hour >= start_h or hour < end_h


def real_orders_allowed(mode, acct, token):
    if mode == DEMO:
        return (False, "DEMO_MODE_ON_REAL_ACCOUNT") if acct == ACCT_REAL else (True, "")
    if mode == LIVE:
        if acct != ACCT_REAL:
            return (False, "LIVE_MODE_NEEDS_REAL_ACCOUNT")
        if token != "TRADE_LIVE":
            return (False, "LIVE_TOKEN_MISSING")
        return (True, "")
    return (False, "MODE_FORBIDS_ORDERS")


class Safety:
    """Mirror of Evaluate/Halt latch."""

    def __init__(self, max_dd_pct=20.0, max_dl=0.0, emergency=False):
        self.halted, self.reason = False, ""
        self.peak, self.init = 0.0, False
        self.max_dd, self.max_dl, self.emg = max_dd_pct, max_dl, emergency

    def evaluate(self, equity, daily_pl, session_ok):
        if self.halted:
            return (False, self.reason)
        if self.emg:
            self.halted, self.reason = True, "EMERGENCY_STOP"
            return (False, self.reason)
        if not self.init or equity > self.peak:
            self.peak, self.init = equity, True
        if self.max_dd > 0 and self.peak > 0:
            dd = (self.peak - equity) / self.peak * 100.0
            if dd >= self.max_dd:
                self.halted, self.reason = True, "MAX_DRAWDOWN"
                return (False, self.reason)
        if self.max_dl > 0 and daily_pl <= -self.max_dl:
            self.halted, self.reason = True, "MAX_DAILY_LOSS"
            return (False, self.reason)
        if not session_ok:
            return (False, "SESSION_CLOSED")
        return (True, "")


def settle(direction, entry, stop, obj, high, low):
    """Returns (closed, exit_px, how). SL-first on ambiguity."""
    hit_sl = (low <= stop) if direction > 0 else (high >= stop)
    hit_tp = (high >= obj) if direction > 0 else (low <= obj)
    if hit_sl:
        return (True, stop, "SL")
    if hit_tp:
        return (True, obj, "TP")
    return (False, 0.0, "")


if __name__ == "__main__":
    print("mirror import OK")
