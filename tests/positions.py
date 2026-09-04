"""positions.py — mirror of CPositionManager pure logic.

Comment wire format: FM|<strategy>|<setupId>. BE/trail price math in points.
"""


def encode_comment(strategy, setup_id):
    return "FM|%d|%d" % (strategy, setup_id)


def parse_comment(c):
    parts = c.split("|")
    if len(parts) != 3 or parts[0] != "FM":
        return (False, 0, 0)
    try:
        st, sid = int(parts[1]), int(parts[2])
    except ValueError:
        return (False, 0, 0)
    if st <= 0 or st >= 6:
        return (False, 0, 0)
    return (True, st, sid)


def breakeven_sl(direction, entry, price, point, trigger_pts, offset_pts,
                 cur_sl):
    """Returns (send, new_sl). Mirrors MaybeBreakEven geometry."""
    if trigger_pts <= 0:
        return (False, 0.0)
    profit = (price - entry) / point if direction > 0 else (entry - price) / point
    if profit < trigger_pts:
        return (False, 0.0)
    be = entry + offset_pts * point if direction > 0 else entry - offset_pts * point
    if cur_sl > 0:
        if direction > 0 and cur_sl >= be - 0.5 * point:
            return (False, 0.0)
        if direction < 0 and cur_sl <= be + 0.5 * point:
            return (False, 0.0)
    return (True, be)


def trail_sl(direction, entry, price, point, cur_sl, start_pts, step_pts):
    """Returns (send, new_sl). Mirrors MaybeTrail geometry."""
    if start_pts <= 0 or step_pts <= 0:
        return (False, 0.0)
    profit = (price - entry) / point if direction > 0 else (entry - price) / point
    if profit < start_pts:
        return (False, 0.0)
    base = cur_sl if cur_sl > 0 else entry
    if direction > 0:
        want = price - start_pts * point
        if want > base + step_pts * point:
            return (True, want)
    else:
        want = price + start_pts * point
        if want < base - step_pts * point:
            return (True, want)
    return (False, 0.0)


if __name__ == "__main__":
    print("mirror import OK")
