"""test_parity_final.py — Phase-5 final-signal parity (mirror level).

EA path (price = next-tick Ask/Bid) vs indicator path (price = closed-bar
close) through the SAME pipeline: veto → risk-RR → intent gates.
Cases A–G per spec §18 (H–I live in the Phase-7 harness).

Locks two EA behaviors as-is (spec §20, not bugs to fix here):
  * LOW_SCORE/WAIT never blocks WOULD_ (only the five veto reasons gate).
  * Risk LOW_RR is strict `<` while setup rrOK carries +1e-9 epsilon, so the
    band [minRR-1e-9, minRR) is rrOK=true yet risk-rejected — mirrored exactly.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parity_decision import final_signal


def S(score=80, prov=False, entry=1.1000, stop=1.0980, r=2.1, d=1):
    return {"score": score, "provisional": prov, "entry": entry,
            "stop": stop, "rMult": r, "dir": d, "valid": True}


def ea(has_trade=True, strat=2, setup=None, reason="OK", done=True,
       veto=True, rr=1.0, price=1.1000, atr=0.0020, prov=False, chase=0.50):
    return final_signal(has_trade, strat, setup or S(), reason, done,
                        veto, rr, price, atr, prov, chase)


def ind(has_trade=True, strat=2, setup=None, reason="OK", done=True,
        veto=True, rr=1.0, close=1.1000, atr=0.0020, prov=False, chase=0.50):
    return final_signal(has_trade, strat, setup or S(), reason, done,
                        veto, rr, close, atr, prov, chase)


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_case_a_buy():
    a = ea(setup=S(d=1, entry=1.1000, stop=1.0980))
    b = ind(setup=S(d=1, entry=1.1000, stop=1.0980), close=1.1000)
    check("A_buy_ea", a == ("BUY", "WOULD_BUY"))
    check("A_buy_parity", a == b)


def test_case_b_sell():
    s = S(d=-1, entry=1.1000, stop=1.1020)
    a = ea(strat=3, setup=s, price=1.1000)
    b = ind(strat=3, setup=s, close=1.1000)
    check("B_sell_ea", a == ("SELL", "WOULD_SELL"))
    check("B_sell_parity", a == b)


def test_case_c_veto():
    a = ea(reason="BARBWIRE")
    b = ind(reason="BARBWIRE")
    check("C_veto", a == ("NO_TRADE", "DECISION_VETO_BARBWIRE") and a == b)
    for r in ("MID_RANGE", "CONFLICT", "NO_EDGE", "TRAP_REPEAT"):
        check("C_veto_" + r, ea(reason=r) == ("NO_TRADE", "DECISION_VETO_" + r))
    for r in ("OK", "LOW_SCORE", "LOW_RR", "LATE_ENTRY"):
        check("C_nonveto_" + r, ea(reason=r)[0] == "BUY")
    c = ea(reason="CONFLICT", veto=False)  # EXP-0002 bypass proceeds
    check("C_bypass", c == ("BUY", "WOULD_BUY"))


def test_case_d_low_rr():
    a = ea(setup=S(r=0.8), price=1.1000)
    check("D_lowrr", a == ("NO_TRADE", "SKIP_LOW_RR"))
    check("D_lowrr_parity", a == ind(setup=S(r=0.8), close=1.1000))
    check("D_boundary_strict", ea(setup=S(r=1.0)) == ("BUY", "WOULD_BUY"))
    check("D_rr_off", ea(setup=S(r=0.2), rr=0.0)[0] == "BUY")


def test_case_e_provisional():
    a = ea(setup=S(prov=True), prov=False)
    check("E_prov_off", a == ("NO_TRADE", "SKIP_PROVISIONAL_OFF"))
    check("E_prov_parity", a == ind(setup=S(prov=True), close=1.1000,
                                   prov=False))
    check("E_prov_on", ea(setup=S(prov=True), prov=True)[0] == "BUY")


def test_case_f_chase_side():
    s = S(d=1, entry=1.1000, stop=1.0980)
    check("F_late", ea(setup=s, price=1.1000 + 0.6 * 0.0020)
          == ("NO_TRADE", "SKIP_LATE_ENTRY"))
    check("F_at_limit_ok",
          ea(setup=s, price=1.1000 + 0.5 * 0.0020)[0] == "BUY")
    check("F_wrong_side",
          ea(setup=s, price=1.0970) == ("NO_TRADE", "SKIP_WRONG_SIDE"))
    # documented live-tick divergence: close inside chase, live Ask beyond it
    e = ea(setup=s, price=1.1000 + 0.6 * 0.0020)
    i = ind(setup=s, close=1.1000)
    check("F_proxy_divergence_documented",
          e == ("NO_TRADE", "SKIP_LATE_ENTRY") and i[0] == "BUY")


def test_case_g_wait_nosetup():
    check("G_no_setup", ea(has_trade=False) == ("NO_TRADE", "NO_SETUP"))
    check("G_no_veto_without_trade",
          ea(has_trade=False, reason="BARBWIRE")
          == ("NO_TRADE", "NO_SETUP"))
    # WAIT/LOW_SCORE does NOT block WOULD_ (EA behavior, locked)
    check("G_lowscore_still_would",
          ea(reason="LOW_SCORE") == ("BUY", "WOULD_BUY"))
    check("G_wait_parity",
          ea(reason="LOW_SCORE") == ind(reason="LOW_SCORE"))


def test_epsilon_band_documented():
    # rrOK epsilon (+1e-9) vs strict risk gate: band member is rrOK yet rejected.
    r = 1.0 - 5e-10
    rr_ok = r + 1e-9 >= 1.0
    act, _ = ea(setup=S(r=r))
    check("eps_band", rr_ok and act == "NO_TRADE")


if __name__ == "__main__":
    test_case_a_buy()
    test_case_b_sell()
    test_case_c_veto()
    test_case_d_low_rr()
    test_case_e_provisional()
    test_case_f_chase_side()
    test_case_g_wait_nosetup()
    test_epsilon_band_documented()
    print("ALL PARITY-FINAL TESTS PASSED")
