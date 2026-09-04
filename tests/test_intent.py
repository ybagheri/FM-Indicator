"""test_intent.py — Phase-27 intent suites (mirror of TradeIntent.mqh)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trade_intent import (permits, provisional_ok, chase_ok, fm_match,
                          failedbo_geometry, STRAT_FM_FADE, STRAT_PULLBACK,
                          STRAT_BREAKOUT, STRAT_REVERSAL, STRAT_DOUBLE,
                          STRAT_FAILED_BO)


def check_n(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_permits():
    check_n("fm_be_only", permits(STRAT_FM_FADE) == (True, False, False))
    check_n("pb_trails", permits(STRAT_PULLBACK) == (True, True, False))
    check_n("bo_trails", permits(STRAT_BREAKOUT) == (True, True, False))
    check_n("mtr_be_only", permits(STRAT_REVERSAL) == (True, False, False))
    check_n("dbl_be_only", permits(STRAT_DOUBLE) == (True, False, False))
    check_n("permits_fbo", permits(STRAT_FAILED_BO) == (True, False, False))


def test_provisional():
    check_n("firm_passes", provisional_ok(False, False)[0])
    check_n("prov_blocked", provisional_ok(True, False) == (False, "PROVISIONAL_OFF"))
    check_n("prov_allowed", provisional_ok(True, True)[0])


def test_chase():
    check_n("buy_clean", chase_ok(+1, 1.1500, 1.1500, 0.0010)[0])
    check_n("buy_late", chase_ok(+1, 1.1500, 1.1506, 0.0010) == (False, "LATE_ENTRY"))
    check_n("buy_boundary", chase_ok(+1, 1.1500, 1.1505, 0.0010)[0])
    check_n("sell_late", chase_ok(-1, 1.1500, 1.1494, 0.0010) == (False, "LATE_ENTRY"))
    check_n("zero_atr_safe", chase_ok(+1, 1.1500, 9.9999, 0.0)[0])


def test_fm_match():
    plans = [{"valid": True, "fadeDir": -1, "entry": 1.1600,
              "invalidClose": 1.1610},
             {"valid": True, "fadeDir": +1, "entry": 1.1400,
              "invalidClose": 1.1390}]
    check_n("match", fm_match(plans, -1, 1.1600) == 1.1610)
    check_n("dir_miss", fm_match(plans, +1, 1.1600) is None)
    check_n("entry_miss", fm_match(plans, -1, 1.1601) is None)
    check_n("empty", fm_match([], -1, 1.1600) is None)


def test_failedbo_geometry():
    s = failedbo_geometry(+1, 1.1600, 0.0010)
    check_n("fbo_sell", s["dir"] == -1 and s["entry"] == 1.1600)
    check_n("fbo_stop", abs(s["stop"] - 1.16035) < 1e-9)
    check_n("fbo_obj", abs(s["objective"] - 1.15800) < 1e-9)
    check_n("fbo_score55", s["score"] == 55 and not s["provisional"])
    check_n("fbo_rr", abs(s["rMult"] - 2.0 / 0.35) < 1e-9 and s["rrOK"])
    m = failedbo_geometry(-1, 1.1400, 0.0010)
    check_n("fbo_buy_mirror", m["dir"] == +1 and m["stop"] < m["entry"] < m["objective"])
    check_n("fbo_bad_dir", failedbo_geometry(0, 1.16, 0.001) is None)
    check_n("fbo_zero_atr", failedbo_geometry(+1, 1.16, 0.0) is None)


if __name__ == "__main__":
    test_permits()
    test_provisional()
    test_chase()
    test_fm_match()
    test_failedbo_geometry()
    print("ALL INTENT TESTS PASSED")
