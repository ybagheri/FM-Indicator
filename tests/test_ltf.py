"""LTF confirmation tests (docs/MARKET_CONTEXT.md §5; v2 research tooling).
Run: python3 -m pytest tests/test_ltf.py -q
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
import fm_engine as F


def test_ltf_bias_geometry():
    assert F.ltf_bias([100.0] * 49) == 0, "need 50 closes"
    up = [100.0 + i * 0.5 for i in range(60)]
    assert F.ltf_bias(up) == +1, "rising LTF"
    dn = [130.0 - i * 0.5 for i in range(60)]
    assert F.ltf_bias(dn) == -1, "falling LTF"
    assert F.ltf_bias([100.0] * 60) == 0, "flat LTF neutral"
    # identical math to the HTF bias (shared TFBias helper in MQL5)
    assert F.ltf_bias(up) == F.mtf_bias(up), "LTF/HTF math must match"
    print("PASS ltf_bias")


def test_ltf_confirm_states():
    assert F.ltf_confirm(+1, +1) == "AGREE"
    assert F.ltf_confirm(-1, -1) == "AGREE"
    assert F.ltf_confirm(+1, -1) == "DISAGREE"
    assert F.ltf_confirm(-1, +1) == "DISAGREE"
    assert F.ltf_confirm(0, +1) == "NEUTRAL", "no bias → neutral"
    assert F.ltf_confirm(+1, 0) == "NEUTRAL", "no direction → neutral"
    assert F.ltf_confirm(0, 0) == "NEUTRAL"
    print("PASS ltf_confirm")


def test_ltf_pure_determinism():
    up = [100.0 + i * 0.5 for i in range(60)]
    assert F.ltf_bias(up) == F.ltf_bias(list(up)), "pure, no state"
    assert F.ltf_confirm(+1, -1) == F.ltf_confirm(+1, -1)
    print("PASS ltf_determinism")


if __name__ == "__main__":
    test_ltf_bias_geometry()
    test_ltf_confirm_states()
    test_ltf_pure_determinism()
    print("ALL LTF TESTS PASS")
