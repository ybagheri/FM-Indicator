"""test_grid_math.py — mirror of FM_Ilan_GridEA.mq5 basket break-even + commission/swap
sign convention (v2.01).  Conventions: `adj` is a signed MONEY ADJUSTMENT to basket profit
(negative = cost): commission is subtracted, swap (already signed, negative when paid) is added.
required_move = -adj / money_per_price  -> costs push the break-even price AGAINST the basket."""


def basket_be(direction, positions, commission_per_lot, tick_value, tick_size, spread=0.0):
    vol = sum(v for v, _p, _s in positions)
    w_open = sum(v * p for v, p, _s in positions) / vol
    adj = sum(-v * commission_per_lot + sw for v, _p, sw in positions)
    mpp = vol * tick_value / tick_size
    move = -adj / mpp
    return (w_open + move + spread) if direction == "BUY" else (w_open - move - spread)


def floating_with_costs(profit, positions, commission_per_lot):
    return profit + sum(-v * commission_per_lot + sw for v, _p, sw in positions)


def check_n(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    assert cond, name


def test_be():
    pos = [(1.0, 1.1000, 0.0)]
    # 1 lot EURUSD: 100000 per 1.0 price -> $12 commission == 0.00012
    tick_value, tick_size = 1.0, 0.00001          # $1 per 0.00001 per lot
    be = basket_be("BUY", pos, 12.0, tick_value, tick_size)
    check_n("buy_commission_raises_be", abs(be - (1.1000 + 12.0 / 100000.0)) < 1e-9)
    be = basket_be("SELL", pos, 12.0, tick_value, tick_size)
    check_n("sell_commission_lowers_be", abs(be - (1.1000 - 12.0 / 100000.0)) < 1e-9)
    paid = [(1.0, 1.1000, -3.0)]                    # swap PAID (negative)
    be_paid = basket_be("BUY", paid, 12.0, tick_value, tick_size)
    be_free = basket_be("BUY", pos, 12.0, tick_value, tick_size)
    check_n("paid_swap_raises_buy_be", be_paid > be_free)
    # at the computed BE the net result (profit - costs) is ~0
    price_move = be_paid - 1.1000
    gross = price_move * 100000.0
    check_n("net_zero_at_be", abs(floating_with_costs(gross, paid, 12.0)) < 1e-6)


def test_floating():
    pos = [(2.0, 1.1, 0.0)]
    check_n("commission_reduces_profit", floating_with_costs(0.0, pos, 12.0) == -24.0)


if __name__ == "__main__":
    test_be()
    test_floating()
    print("ALL GRID-MATH TESTS PASSED")
