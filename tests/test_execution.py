"""test_execution.py — Phase-25 execution suites (mirror)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from execution import (precheck, classify, is_retryable, TRADE_MODE_FULL,
                       TRADE_MODE_DISABLED, TRADE_MODE_LONGONLY,
                       TRADE_MODE_SHORTONLY, TRADE_MODE_CLOSEONLY)

BASE = dict(trade_mode=TRADE_MODE_FULL, direction=+1, volume=0.10,
            vmin=0.01, vmax=100.0, spread=20, max_spread=50, ref=1.1500,
            sl=1.1400, tp=1.1600, min_dist=0.0002, margin_free=10000.0,
            margin_need=35.0)


def P(**kw):
    d = dict(BASE)
    d.update(kw)
    return precheck(**d)


def check_n(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_precheck_gates():
    check_n("clear", P() == "")
    check_n("disabled", P(trade_mode=TRADE_MODE_DISABLED) == "MARKET_CLOSED")
    check_n("closeonly", P(trade_mode=TRADE_MODE_CLOSEONLY) == "MARKET_CLOSED")
    check_n("shortonly_blocks_buy",
            P(trade_mode=TRADE_MODE_SHORTONLY, direction=+1) == "LONGONLY_VIOLATION")
    check_n("shortonly_allows_sell",
            P(trade_mode=TRADE_MODE_SHORTONLY, direction=-1, sl=1.1600,
              tp=1.1400) == "")
    check_n("longonly_blocks_sell",
            P(trade_mode=TRADE_MODE_LONGONLY, direction=-1) == "SHORTONLY_VIOLATION")
    check_n("spread", P(spread=999) == "HIGH_SPREAD")
    check_n("volume_lo", P(volume=0.001) == "INVALID_VOLUME")
    check_n("volume_hi", P(volume=999.0) == "INVALID_VOLUME")
    check_n("no_quotes", P(ref=0.0) == "NO_QUOTES")
    check_n("sl_close", P(sl=1.14995) == "INVALID_STOPS")
    check_n("tp_close", P(tp=1.15005) == "INVALID_STOPS")
    check_n("no_money", P(margin_need=99999.0) == "NO_MONEY")
    # order: mode beats spread
    check_n("mode_first",
            P(trade_mode=TRADE_MODE_DISABLED, spread=999) == "MARKET_CLOSED")


def test_classify():
    check_n("done", classify(True, "DONE") == (True, "DONE"))
    check_n("partial", classify(True, "DONE_PARTIAL")[0] is True)
    check_n("sent_not_success", classify(True, "REJECT") == (False, "REJECT"))
    check_n("unsent_done", classify(False, "DONE") == (False, "DONE"))
    check_n("retry_requote", is_retryable("REQUOTE"))
    check_n("fatal_reject", not is_retryable("REJECT"))
    check_n("fatal_invalid_stops", not is_retryable("INVALID_STOPS"))


if __name__ == "__main__":
    test_precheck_gates()
    test_classify()
    print("ALL EXECUTION TESTS PASSED")
