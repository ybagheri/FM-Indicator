"""risk_manager.py — mirror of CRiskManager gate order + volume normalization.

Veto order (must match RiskManager.mqh::Check):
NO_SETUP -> LOW_RR -> HIGH_SPREAD -> DAILY_LOSS -> MAX_TRADES_DAY ->
CONSEC_LOSSES -> MAX_OPEN -> MAX_PER_SYMBOL -> OK.
"""
import math


def norm_vol(v, mn, mx, st):
    if st <= 0:
        st = 0.01
    v = math.floor(v / st) * st
    v = max(mn, min(mx, v))
    return round(v, 8)


def size_volume(risk_money, loss_per_lot, mn, mx, st):
    if risk_money <= 0 or loss_per_lot <= 0:
        return mn
    return norm_vol(risk_money / loss_per_lot, mn, mx, st)


def check(valid, r_mult, cfg, st):
    """cfg: dict(min_rr,max_spread,min...); st: dict(spread,daily_pl,
    trades,consec,open_n,sym_n). Returns (allowed, reason)."""
    if not valid:
        return (False, "NO_SETUP")
    if cfg.get("min_rr", 0) > 0 and r_mult < cfg["min_rr"]:
        return (False, "LOW_RR")
    if cfg.get("max_spread", 0) > 0 and st.get("spread", 0) > cfg["max_spread"]:
        return (False, "HIGH_SPREAD")
    if cfg.get("max_dl", 0) > 0 and st.get("daily_pl", 0) <= -cfg["max_dl"]:
        return (False, "DAILY_LOSS")
    if cfg.get("max_trades", 0) > 0 and st.get("trades", 0) >= cfg["max_trades"]:
        return (False, "MAX_TRADES_DAY")
    if cfg.get("max_consec", 0) > 0 and st.get("consec", 0) >= cfg["max_consec"]:
        return (False, "CONSEC_LOSSES")
    if cfg.get("max_open", 0) > 0 and st.get("open_n", 0) >= cfg["max_open"]:
        return (False, "MAX_OPEN")
    if cfg.get("max_sym", 0) > 0 and st.get("sym_n", 0) >= cfg["max_sym"]:
        return (False, "MAX_PER_SYMBOL")
    return (True, "OK")


class DayBook:
    """Mirror of OnNewDay/NotifyTradeClosed accounting."""

    def __init__(self):
        self.day = 0
        self.trades = 0
        self.pl = 0.0
        self.consec = 0

    def new_day(self, yyyymmdd):
        if yyyymmdd != self.day:
            self.day = yyyymmdd
            self.trades = 0
            self.pl = 0.0

    def closed(self, profit):
        self.trades += 1
        self.pl += profit
        self.consec = self.consec + 1 if profit < 0 else 0


if __name__ == "__main__":
    print("mirror import OK")
