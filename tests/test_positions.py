"""test_positions.py — Phase-26 position suites (mirror)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from positions import encode_comment, parse_comment, breakeven_sl, trail_sl


def check_n(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_comment_codec():
    check_n("roundtrip", parse_comment(encode_comment(2, 481)) == (True, 2, 481))
    check_n("foreign", parse_comment("Grid #12")[0] is False)
    check_n("bad_strat", parse_comment("FM|9|1")[0] is False)
    check_n("bad_shape", parse_comment("FM|2")[0] is False)
    check_n("non_numeric", parse_comment("FM|x|1")[0] is False)


def test_breakeven():
    ok, sl = breakeven_sl(+1, 1.1500, 1.1540, 0.00001, 300, 20, 0.0)
    check_n("be_buy", ok and abs(sl - 1.1502) < 1e-9)
    ok, _ = breakeven_sl(+1, 1.1500, 1.1520, 0.00001, 300, 20, 0.0)
    check_n("be_early", not ok)
    ok, _ = breakeven_sl(+1, 1.1500, 1.1540, 0.00001, 300, 20, 1.1502)
    check_n("be_already", not ok)
    ok, sl = breakeven_sl(-1, 1.1500, 1.1460, 0.00001, 300, 20, 0.0)
    check_n("be_sell", ok and abs(sl - 1.1498) < 1e-9)
    ok, _ = breakeven_sl(+1, 1.1500, 1.1600, 0.00001, 0, 20, 0.0)
    check_n("be_disabled", not ok)


def test_trail():
    ok, sl = trail_sl(+1, 1.1500, 1.1560, 0.00001, 0.0, 300, 50)
    check_n("trail_buy", ok and abs(sl - 1.1530) < 1e-9)
    ok, _ = trail_sl(+1, 1.1500, 1.1520, 0.00001, 0.0, 300, 50)
    check_n("trail_early", not ok)
    ok, _ = trail_sl(+1, 1.1500, 1.1560, 0.00001, 1.1529, 300, 50)
    check_n("trail_step_gate", not ok)  # want 1.1530 vs base 1.1529 < step
    ok, _ = trail_sl(+1, 1.1500, 1.1560, 0.00001, 1.1520, 300, 50)
    check_n("trail_ratchet", ok)
    ok, sl = trail_sl(-1, 1.1500, 1.1440, 0.00001, 0.0, 300, 50)
    check_n("trail_sell", ok and abs(sl - 1.1470) < 1e-9)


if __name__ == "__main__":
    test_comment_codec()
    test_breakeven()
    test_trail()
    print("ALL POSITION TESTS PASSED")
