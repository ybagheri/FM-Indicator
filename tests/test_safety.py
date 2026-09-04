"""test_safety.py — Phase-33 safety + paper suites (mirror)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from safety import (session_open, real_orders_allowed, Safety, settle,
                    ANALYSIS_ONLY, PAPER, DEMO, LIVE, ACCT_DEMO, ACCT_REAL)


def check_n(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_modes():
    check_n("analysis_never", real_orders_allowed(ANALYSIS_ONLY, ACCT_DEMO, "")[0] is False)
    check_n("paper_never", real_orders_allowed(PAPER, ACCT_DEMO, "")[0] is False)
    check_n("demo_ok", real_orders_allowed(DEMO, ACCT_DEMO, "") == (True, ""))
    check_n("demo_blocks_real",
            real_orders_allowed(DEMO, ACCT_REAL, "")[1] == "DEMO_MODE_ON_REAL_ACCOUNT")
    check_n("live_needs_real",
            real_orders_allowed(LIVE, ACCT_DEMO, "TRADE_LIVE")[1] == "LIVE_MODE_NEEDS_REAL_ACCOUNT")
    check_n("live_needs_token",
            real_orders_allowed(LIVE, ACCT_REAL, "")[1] == "LIVE_TOKEN_MISSING")
    check_n("live_ok", real_orders_allowed(LIVE, ACCT_REAL, "TRADE_LIVE")[0] is True)


def test_session():
    check_n("always", session_open(0, 24, 3) and session_open(5, 5, 22))
    check_n("inside", session_open(8, 18, 12))
    check_n("outside", not session_open(8, 18, 20))
    check_n("edge_end", not session_open(8, 18, 18))
    check_n("overnight_in", session_open(20, 4, 23) and session_open(20, 4, 2))
    check_n("overnight_out", not session_open(20, 4, 12))


def test_latches():
    s = Safety(max_dd_pct=10.0)
    check_n("go", s.evaluate(10000.0, 0.0, True)[0])
    ok, why = s.evaluate(8900.0, 0.0, True)
    check_n("dd_halt", (not ok) and why == "MAX_DRAWDOWN")
    check_n("dd_latches", s.evaluate(20000.0, 0.0, True)[0] is False)
    s = Safety(max_dl=200.0)
    s.evaluate(10000.0, 0.0, True)
    check_n("dl_halt", s.evaluate(9900.0, -250.0, True)[1] == "MAX_DAILY_LOSS")
    s = Safety(emergency=True)
    check_n("emg", s.evaluate(10000.0, 0.0, True)[1] == "EMERGENCY_STOP")
    s = Safety()
    check_n("session_pause", s.evaluate(10000.0, 0.0, False) == (False, "SESSION_CLOSED"))
    check_n("session_no_latch", s.evaluate(10000.0, 0.0, True)[0] is True)


def test_settle():
    check_n("buy_tp", settle(+1, 1.15, 1.14, 1.16, 1.1610, 1.1450) == (True, 1.16, "TP"))
    check_n("buy_sl", settle(+1, 1.15, 1.14, 1.16, 1.1550, 1.1390) == (True, 1.14, "SL"))
    check_n("sl_first", settle(+1, 1.15, 1.14, 1.16, 1.1700, 1.1300) == (True, 1.14, "SL"))
    check_n("sell_tp", settle(-1, 1.15, 1.16, 1.14, 1.1550, 1.1390) == (True, 1.14, "TP"))
    check_n("hold", settle(+1, 1.15, 1.14, 1.16, 1.1550, 1.1450) == (False, 0.0, ""))


if __name__ == "__main__":
    test_modes()
    test_session()
    test_latches()
    test_settle()
    print("ALL SAFETY TESTS PASSED")
