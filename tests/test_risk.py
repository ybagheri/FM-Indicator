"""test_risk.py — Phase-24 risk suites (mirror of RiskManager.mqh)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from risk_manager import check, norm_vol, size_volume, DayBook

CFG = {"min_rr": 1.0, "max_spread": 50, "max_dl": 200.0, "max_trades": 5,
       "max_consec": 3, "max_open": 1, "max_sym": 1}
ST = {"spread": 20, "daily_pl": 0.0, "trades": 0, "consec": 0,
      "open_n": 0, "sym_n": 0}


def check_n(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_gate_order():
    check_n("ok", check(True, 2.0, CFG, dict(ST)) == (True, "OK"))
    check_n("no_setup", check(False, 9.0, CFG, dict(ST))[1] == "NO_SETUP")
    check_n("low_rr", check(True, 0.5, CFG, dict(ST))[1] == "LOW_RR")
    s = dict(ST, spread=999)
    check_n("high_spread", check(True, 2.0, CFG, s)[1] == "HIGH_SPREAD")
    s = dict(ST, daily_pl=-250.0)
    check_n("daily_loss", check(True, 2.0, CFG, s)[1] == "DAILY_LOSS")
    s = dict(ST, trades=5)
    check_n("max_trades", check(True, 2.0, CFG, s)[1] == "MAX_TRADES_DAY")
    s = dict(ST, consec=3)
    check_n("consec", check(True, 2.0, CFG, s)[1] == "CONSEC_LOSSES")
    s = dict(ST, open_n=1)
    check_n("max_open", check(True, 2.0, CFG, s)[1] == "MAX_OPEN")
    s = dict(ST, sym_n=1)
    check_n("max_sym", check(True, 2.0, CFG, s)[1] == "MAX_PER_SYMBOL")
    # priority: RR beats spread when both bad
    s = dict(ST, spread=999)
    check_n("rr_first", check(True, 0.5, CFG, s)[1] == "LOW_RR")


def test_volume_norm():
    check_n("floor_step", norm_vol(0.137, 0.01, 100.0, 0.01) == 0.13)
    check_n("clamp_min", norm_vol(0.001, 0.01, 100.0, 0.01) == 0.01)
    check_n("clamp_max", norm_vol(500.0, 0.01, 100.0, 0.01) == 100.0)
    check_n("sized", size_volume(100.0, 50.0, 0.01, 100.0, 0.01) == 2.0)
    # risk budget <= 0 must mean "do not trade", NOT the minimum lot
    check_n("zero_risk_rejects", size_volume(0.0, 50.0, 0.01, 100.0, 0.01) == 0.0)
    check_n("neg_risk_rejects", size_volume(-5.0, 50.0, 0.01, 100.0, 0.01) == 0.0)
    # IEEE-754 floor regression: 0.29/0.01 == 28.999999999999996
    check_n("fp_029", norm_vol(0.29, 0.01, 100.0, 0.01) == 0.29)
    check_n("fp_057", norm_vol(0.57, 0.01, 100.0, 0.01) == 0.57)
    check_n("fp_115", norm_vol(1.15, 0.01, 100.0, 0.01) == 1.15)


def test_daybook():
    b = DayBook()
    b.new_day(20251103)
    b.opened(); b.closed(-50.0)
    b.opened(); b.closed(-30.0)
    # one open + one close == ONE trade (was double-counted as 2)
    check_n("consec2", b.consec == 2 and b.trades == 2 and b.pl == -80.0)
    b.opened(); b.closed(10.0)
    check_n("win_resets", b.consec == 0 and b.trades == 3)
    b.new_day(20251103)
    check_n("same_day_keeps", b.trades == 3)
    # InpMaxTradesDay=5 must allow exactly 5 open/close trades
    c = DayBook(); c.new_day(20251105)
    for _ in range(4):
        c.opened(); c.closed(1.0)
    check_n("fifth_trade_allowed", check(True, 2.0, CFG, dict(ST, trades=c.trades))[1] == "OK")
    c.opened(); c.closed(1.0)
    check_n("sixth_trade_blocked", check(True, 2.0, CFG, dict(ST, trades=c.trades))[1] == "MAX_TRADES_DAY")
    b.new_day(20251104)
    check_n("rollover_resets", b.trades == 0 and b.pl == 0.0)


if __name__ == "__main__":
    test_gate_order()
    test_volume_norm()
    test_daybook()
    print("ALL RISK TESTS PASSED")
