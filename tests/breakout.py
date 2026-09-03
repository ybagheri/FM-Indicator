"""breakout.py — Python mirror of docs/BREAKOUT_ENGINE.md + BreakoutEngine.mqh.

Indexing: oldest-first (index 0 = OLDEST). Detection consumes closed bars only;
`last_closed` is the newest closed index; analysis point `idx` (normally ==
last_closed) plays the MT5-shift-b role. Field-for-field identical semantics
to MQL5 (float tol 1e-9, enums/bools exact).

MT5-shift ↔ oldest-first: shift s in a length-N series ↔ idx N-1-s. Newer bars
than shift k are [b..k-1] ↔ (k..idx]; the trap window [k..m-1] (m older than k)
↔ range(m+1, k+1).
"""


class BOCfg:
    def __init__(self, lookback=20, tol_atr=0.10, follow_bars=5,
                 trap_lookback=20, enable=True):
        self.lookback = lookback
        self.tol_atr = tol_atr
        self.follow_bars = follow_bars
        self.trap_lookback = trap_lookback
        self.enable = enable


def _none():
    return dict(found=False, dir=0, bo_bar=-1, ref=0.0, ref_swing=False,
                outcome="NONE", trap=False, decide_bar=-1)


def nbar_ref(bars, k, n):
    """(HH, LL) over the n bars strictly older than k; None if <10 bars."""
    lo = max(0, k - n)
    win = bars[lo:k]
    if len(win) < 10:
        return None
    return (max(b['h'] for b in win), min(b['l'] for b in win))


def swing_ref(swings, k):
    """Most-recent swing high/low strictly older than k: (sh, sl)."""
    sh = sl = None
    for s in swings:
        if s['bar'] >= k:
            continue
        if s.get('dir') == +1:
            sh = s['price']
        elif s.get('dir') == -1:
            sl = s['price']
    return sh, sl


def event_at(bars, k, last_closed, atr, swings, cfg):
    """Breakout event at bar k → (dir, ref, is_swing) or (0, 0.0, False)."""
    if k < 0 or k > last_closed or k >= len(bars):
        return 0, 0.0, False
    if not atr or atr <= 0:
        return 0, 0.0, False
    n = max(10, cfg.lookback)
    tol = cfg.tol_atr * atr
    nb = nbar_ref(bars, k, n)
    sh, sl = swing_ref(swings, k)
    c = bars[k]['c']
    if (sh is not None and c > sh + tol) or (nb is not None and c > nb[0] + tol):
        if sh is not None and c > sh + tol:
            return +1, sh, True
        return +1, nb[0], False
    if (sl is not None and c < sl - tol) or (nb is not None and c < nb[1] - tol):
        if sl is not None and c < sl - tol:
            return -1, sl, True
        return -1, nb[1], False
    return 0, 0.0, False


def _failed_since(bars, m, stop_idx, ref, direction, tol):
    """Newest j in (stop_idx..m) closing back past ref; -1 if none.

    Mirrors FailedSince over MT5 shifts [stopShift..m-1] (m older than stop).
    """
    for j in range(m - 1, stop_idx, -1):
        if direction > 0 and bars[j]['c'] < ref - tol:
            return j
        if direction < 0 and bars[j]['c'] > ref + tol:
            return j
    return -1


def analyze(bars, idx, last_closed, atr, swings=(), cfg=None):
    cfg = cfg or BOCfg()
    swings = list(swings or [])
    if not cfg.enable:
        return _none()
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return _none()
    if not atr or atr <= 0:
        return _none()
    tol = cfg.tol_atr * atr
    F = max(1, cfg.follow_bars)
    T = max(5, cfg.trap_lookback)
    k = -1
    for kk in range(idx, max(-1, idx - F - 1), -1):
        if kk < 0:
            continue
        d, rp, sw = event_at(bars, kk, last_closed, atr, swings, cfg)
        if d != 0:
            k, ref, is_sw, direction = kk, rp, sw, d
            break
    if k < 0:
        return _none()
    s = dict(found=True, dir=direction, bo_bar=k, ref=ref,
             ref_swing=is_sw, outcome="PENDING", trap=False, decide_bar=-1)
    fb = _failed_since(bars, idx + 1, k, ref, direction, tol)
    # scans j in (k..idx]: FAILED takes precedence over FOLLOW.
    if fb >= 0:
        s.update(outcome="FAILED", decide_bar=fb)
    else:
        for j in range(idx, k, -1):
            if direction > 0 and bars[j]['c'] > ref + tol:
                s.update(outcome="FOLLOW", decide_bar=j)
                break
            if direction < 0 and bars[j]['c'] < ref - tol:
                s.update(outcome="FOLLOW", decide_bar=j)
                break
    for m in range(max(0, k - T), k):
        if m > last_closed:
            continue
        d, rp, _sw = event_at(bars, m, last_closed, atr, swings, cfg)
        if d != direction:
            continue
        if _failed_since(bars, k + 1, m, rp, direction, tol) >= 0:
            # failure decided on bars [m+1..k] (MT5 [k..m-1]): before k.
            s['trap'] = True
            break
    return s
