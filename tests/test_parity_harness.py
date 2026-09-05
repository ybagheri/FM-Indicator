"""test_parity_harness.py — Phase-7 harness tests (cases H + I, contract, parser).

Case map (spec §18): A–G covered in test_parity_final.py (final-signal
semantics); here H (historical stability) + I (input parity) plus the CSV
column contract, the EA-log parser, and the comparator itself.
"""
import sys
import os
import random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parity_decision import build, final_signal
from parity_compare import (HEADER, RESULT_HEADER, parse_ea_log,
                            read_ind_csv, compare, format_parity_row,
                            rows_to_csv)
from strategy_registry import MODE_SINGLE, MODE_MULTI, MODE_AUTO

TUN = {"trendBonus": 10, "provPenalty": 5, "rrBonus": 5, "rrLevel": 2.0}
USES_ALL = {s: True for s in range(1, 7)}


def S(t, score, prov=False, entry=1.1, d=1, r=2.0):
    return {"type": t, "score": score, "provisional": prov, "entry": entry,
            "stop": entry - 0.002 * d, "valid": True, "dir": d,
            "rMult": r}


def ea_ind_final(catalog, fbo, mode, single, uses, state, tuning, price,
                 reason="OK", veto=True, rr=1.0, prov=False, chase=0.50):
    """Both program paths through the shared pipeline (EA price vs close)."""
    b = build(catalog, fbo, mode, single, uses, state, True, tuning)
    kw = dict(reason_best=reason, decision_done=True, apply_veto=veto,
              min_rr=rr, atr=0.002, trade_provisional=prov, chase_mult=chase)
    e = final_signal(b["has_trade"], b["strategy"], b["setup"] or
                     {"provisional": False, "dir": 0, "entry": 0, "stop": 0,
                      "rMult": 0}, price=price, **kw) if b["has_trade"] \
        else ("NO_TRADE", "NO_SETUP")
    i = final_signal(b["has_trade"], b["strategy"], b["setup"] or
                     {"provisional": False, "dir": 0, "entry": 0, "stop": 0,
                      "rMult": 0}, price=price, **kw) if b["has_trade"] \
        else ("NO_TRADE", "NO_SETUP")
    return e, i, b


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_h1_determinism():
    rng = random.Random(777)
    seen = []
    for trial in range(200):
        catalog = [S(rng.choice(["FM_FADE", "PULLBACK", "BREAKOUT",
                                 "REVERSAL", "DOUBLE"]),
                     rng.randint(0, 100), rng.random() < 0.4,
                     1.0 + rng.random(), rng.choice([-1, 1]),
                     round(rng.uniform(0.2, 3.5), 3))
                   for _ in range(rng.randint(0, 5))]
        mode = rng.choice([MODE_SINGLE, MODE_MULTI, MODE_AUTO])
        e, i, b = ea_ind_final(catalog, None, mode, rng.randint(1, 6),
                               USES_ALL, "BULL_TREND", TUN, 1.05)
        seen.append((b["strategy"], b["autoFinal"], e, i))
    rng2 = random.Random(777)
    for trial in range(200):
        catalog = [S(rng2.choice(["FM_FADE", "PULLBACK", "BREAKOUT",
                                  "REVERSAL", "DOUBLE"]),
                     rng2.randint(0, 100), rng2.random() < 0.4,
                     1.0 + rng2.random(), rng2.choice([-1, 1]),
                     round(rng2.uniform(0.2, 3.5), 3))
                   for _ in range(rng2.randint(0, 5))]
        mode = rng2.choice([MODE_SINGLE, MODE_MULTI, MODE_AUTO])
        e, i, b = ea_ind_final(catalog, None, mode, rng2.randint(1, 6),
                               USES_ALL, "BULL_TREND", TUN, 1.05)
        check("h1_det_%d" % trial,
              (b["strategy"], b["autoFinal"], e, i) == seen[trial])


def test_h2_append_stability():
    """Closed-bar decisions are pure functions of their own bar: appending
    future bars never rewrites history (locks the anti-repainting contract)."""
    rng = random.Random(4242)
    bars = []
    for _ in range(12):
        bars.append([S(rng.choice(["FM_FADE", "PULLBACK", "DOUBLE"]),
                       rng.randint(30, 95), False, 1.0 + rng.random(),
                       1, 2.0)])
    first_pass = [ea_ind_final(b, None, MODE_AUTO, 1, USES_ALL,
                               "BULL_TREND", TUN, 1.05)[:2] for b in bars]
    bars.extend([[S("BREAKOUT", 99, False, 1.5, -1, 3.0)]])
    second_pass = [ea_ind_final(b, None, MODE_AUTO, 1, USES_ALL,
                                "BULL_TREND", TUN, 1.05)[:2] for b in bars[:12]]
    check("h2_history_frozen", first_pass == second_pass)


def test_i1_tuning_sensitivity():
    conflict = [S("PULLBACK", 84, False, 1.1000, 1, 2.5),
                S("BREAKOUT", 76, False, 1.1010, -1, 2.5)]
    e1, i1, b1 = ea_ind_final(conflict, None, MODE_AUTO, 1, USES_ALL,
                              "BULL_TREND", TUN, 1.1005)
    flat = dict(TUN, trendBonus=0, provPenalty=0, rrBonus=0)
    e2, i2, b2 = ea_ind_final(conflict, None, MODE_AUTO, 1, USES_ALL,
                              "BULL_TREND", flat, 1.1005)
    check("i1_tuned_picks_aligned",
          b1["strategy"] == 2 and e1 == i1)       # PULLBACK 84+10 wins
    check("i1_flat_picks_raw_max",
          b2["strategy"] == 2 and e2 == i2)       # still PULLBACK on raw 84
    rev = dict(TUN, trendBonus=10)
    e3, i3, b3 = ea_ind_final(conflict, None, MODE_AUTO, 1, USES_ALL,
                              "BEAR_TREND", rev, 1.1005)
    check("i1_bear_flips_to_breakout",
          b3["strategy"] == 3 and e3 == i3)       # 76+10=86 > 84-10=74
    check("i1_paths_equal", e1 == i1 and e2 == i2 and e3 == i3)


def test_i2_enable_mask():
    cands = [S("PULLBACK", 84, False, 1.1000, 1, 2.5),
             S("BREAKOUT", 76, False, 1.1010, -1, 2.5)]
    uses = dict(USES_ALL)
    uses[2] = False  # PULLBACK disabled
    e, i, b = ea_ind_final(cands, None, MODE_MULTI, 1, uses,
                           "BULL_TREND", TUN, 1.1005)
    check("i2_mask_applies", b["strategy"] == 3 and e == i)
    e, i, b = ea_ind_final(cands, None, MODE_SINGLE, 2, USES_ALL,
                           "BULL_TREND", TUN, 1.1005)
    check("i2_single", b["strategy"] == 2 and e == i)


def test_csv_contract():
    check("header_contract", HEADER == ["bar", "ind_signal", "ind_why",
                                        "mode", "strategy", "score",
                                        "r_mult", "auto_final", "veto",
                                        "intent", "dec_action", "dec_reason"])
    row = format_parity_row("2026.09.05 14:00", "BUY", "R=2.10", "AUTO",
                            "PULLBACK", True, 84, 2.1, 94, "", "WOULD_BUY",
                            "BUY", "OK")
    check("row_keys", list(row.keys()) == HEADER)
    check("row_defaults",
          format_parity_row("b", "NO_TRADE", "NO_SETUP", "AUTO", "NONE",
                            False, 0, 0.0, -1, "", "",
                            "NO_TRADE", "NO_SETUP")["score"] == -1)
    csv_text = rows_to_csv([row])
    back = read_ind_csv(csv_text)
    check("csv_roundtrip", back["2026.09.05 14:00"]["strategy"] == "PULLBACK")


def test_parser_and_comparator():
    log = ("[FM_EA] 2026.09.05 14:00 BUY PULLBACK entry=1.10000 stop=1.09800 "
           "obj=1.10420 score=84 R=2.10 cands=3 final=94 sig=12 risk=OK "
           "vol=0.10 WOULD_BUY FM fade BUY score=84 R=2.10\n"
           "[FM_EA] 2026.09.05 15:00 SELL BREAKOUT entry=1.10200 stop=1.10400 "
           "obj=1.09800 score=76 R=2.00 cands=2 final=86 sig=9 risk=OK "
           "vol=0.10 SKIP_LATE_ENTRY\n"
           "[FM_EA] 2026.09.05 16:00 DOUBLE veto=DECISION_VETO_CONFLICT\n")
    ea_rows, _ = parse_ea_log(log)
    check("parse_count", len(ea_rows) == 3)
    check("parse_would",
          ea_rows["2026.09.05 14:00"]["EA_SIGNAL"] == "BUY")
    check("parse_skip",
          ea_rows["2026.09.05 15:00"]["EA_SIGNAL"] == "NO_TRADE")
    check("parse_veto",
          ea_rows["2026.09.05 16:00"]["EA_VETO"] == "DECISION_VETO_CONFLICT")
    check("parse_veto_quiet",
          ea_rows["2026.09.05 16:00"]["EA_SIGNAL"] == "NO_TRADE")
    ind = {
        "2026.09.05 14:00": {"bar": "2026.09.05 14:00",
                             "ind_signal": "BUY", "strategy": "PULLBACK",
                             "score": "84", "r_mult": "2.10",
                             "veto": "-", "intent": "WOULD_BUY"},
        "2026.09.05 15:00": {"bar": "2026.09.05 15:00",
                             "ind_signal": "NO_TRADE",
                             "strategy": "BREAKOUT", "score": "76",
                             "r_mult": "2.00", "veto": "-",
                             "intent": "SKIP_LATE_ENTRY"},
        "2026.09.05 16:00": {"bar": "2026.09.05 16:00",
                             "ind_signal": "NO_TRADE",
                             "strategy": "DOUBLE", "score": "60",
                             "r_mult": "2.00",
                             "veto": "DECISION_VETO_CONFLICT",
                             "intent": "-"},
    }
    rep = compare(ea_rows, ind)
    check("compare_all_match", all(r["RESULT"] == "MATCH" for r in rep))
    check("result_header", list(rep[0].keys()) == RESULT_HEADER)
    bad = dict(ind)
    bad["2026.09.05 14:00"] = dict(bad["2026.09.05 14:00"],
                                   ind_signal="SELL")
    rep2 = compare(ea_rows, bad)
    check("compare_flags_signal",
          [r["RESULT"] for r in rep2 if r["BAR"] == "2026.09.05 14:00"]
          == ["MISMATCH_SIGNAL"])
    bad2 = dict(ind)
    bad2["2026.09.05 16:00"] = dict(bad2["2026.09.05 16:00"], veto="-")
    rep3 = compare(ea_rows, bad2)
    check("compare_flags_veto",
          [r["RESULT"] for r in rep3 if r["BAR"] == "2026.09.05 16:00"]
          == ["MISMATCH_VETO"])


if __name__ == "__main__":
    test_h1_determinism()
    test_h2_append_stability()
    test_i1_tuning_sensitivity()
    test_i2_enable_mask()
    test_csv_contract()
    test_parser_and_comparator()
    print("ALL PARITY-HARNESS TESTS PASSED")
