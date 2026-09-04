"""execution.py — mirror of CExecutionEngine validation/classification.

PreCheck order: MARKET_CLOSED -> LONG/SHORTONLY_VIOLATION -> HIGH_SPREAD ->
INVALID_VOLUME -> NO_QUOTES -> INVALID_STOPS -> MARGIN/MONEY.
Retcode: DONE/DONE_PARTIAL (+sent) == success, everything else classified.
"""
TRADE_MODE_DISABLED, TRADE_MODE_LONGONLY = 0, 1
TRADE_MODE_SHORTONLY, TRADE_MODE_CLOSEONLY, TRADE_MODE_FULL = 2, 3, 4

RETRYABLE = {"REQUOTE", "PRICE_CHANGED", "PRICE_OFF", "TIMEOUT"}


def direction_allowed(trade_mode, direction):
    if trade_mode in (TRADE_MODE_DISABLED, TRADE_MODE_CLOSEONLY):
        return (False, "MARKET_CLOSED")
    if direction > 0 and trade_mode == TRADE_MODE_SHORTONLY:
        return (False, "LONGONLY_VIOLATION")
    if direction < 0 and trade_mode == TRADE_MODE_LONGONLY:
        return (False, "SHORTONLY_VIOLATION")
    return (True, "")


def precheck(trade_mode, direction, volume, vmin, vmax, spread, max_spread,
             ref, sl, tp, min_dist, margin_free, margin_need):
    ok, why = direction_allowed(trade_mode, direction)
    if not ok:
        return why
    if max_spread > 0 and spread > max_spread:
        return "HIGH_SPREAD"
    if volume < vmin or volume > vmax:
        return "INVALID_VOLUME"
    if ref <= 0:
        return "NO_QUOTES"
    if sl > 0 and abs(ref - sl) < min_dist:
        return "INVALID_STOPS"
    if tp > 0 and abs(ref - tp) < min_dist:
        return "INVALID_STOPS"
    if margin_need > margin_free:
        return "NO_MONEY"
    return ""


def classify(sent, retcode):
    ok = sent and retcode in ("DONE", "DONE_PARTIAL")
    return (ok, retcode)


def is_retryable(retcode):
    return retcode in RETRYABLE


if __name__ == "__main__":
    print("mirror import OK")
