"""reversal.py — Python mirror of docs/REVERSAL_ENGINE.md + ReversalEngine.mqh.

Indexing: oldest-first (index 0 = OLDEST). Detection consumes closed bars only;
`last_closed` is the newest closed index; analysis point `idx` (normally ==
last_closed) plays the MT5-shift-b role. Field-for-field identical semantics
to MQL5 (float tol 1e-9, ints/enums/bools exact).

Predicates follow MQL5/SPEC-§8 with backward (older-ward) push/wedge runs
(spec §0 honesty record); v1 `fm_engine.py` variants are untouched.
"""
from breakout import BOCfg, analyze as bo_analyze


class RevCfg:
    def __init__(self, lookback=10, retest_tol_atr=0.25, min_pressure=5,
                 enable=True, min_pushes=3, use_wedge=True,
                 bo_lookback=20, bo_tol_atr=0.10, bo_follow=5, bo_trap=20):
        self.lookback = lookback
        self.retest_tol_atr = retest_tol_atr
        self.min_pressure = min_pressure
        self.enable = enable
        self.min_pushes = min_pushes
        self.use_wedge = use_wedge
        self.bo_cfg = BOCfg(lookback=bo_lookback, tol_atr=bo_tol_atr,
                            follow_bars=bo_follow, trap_lookback=bo_trap)


def _range(r):
    return r['h'] - r['l'] or 1e-9


def push_back(bars, idx, last_closed, direction):
    """Backward push run ending at idx toward older bars, cap 6."""
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return 0
    n = 0
    i = idx
    while i >= 1 and i <= last_closed and i < len(bars):
        a, p = bars[i], bars[i - 1]
        if direction > 0:
            if not (a['c'] > p['c'] and a['h'] > p['h']):
                break
        else:
            if not (a['c'] < p['c'] and a['l'] < p['l']):
                break
        n += 1
        if n >= 6:
            break
        i -= 1
    return n


def wedge_at(bars, idx, last_closed, direction):
    """Wedge ending at idx (pushes≥3 + shrink ×1.05 older-ward, or ≥4)."""
    if idx - 2 < 0 or idx > last_closed or idx >= len(bars):
        return False
    n = push_back(bars, idx, last_closed, direction)
    if n < 3:
        return False
    shrink = all(_range(bars[i]) <= _range(bars[i - 1]) * 1.05
                 for i in range(idx, max(0, idx - n + 1), -1)
                 if i - 1 >= 0)
    return bool(shrink or n >= 4)


def exhaustion(bars, idx, last_closed, direction, atr, cfg=None):
    cfg = cfg or RevCfg()
    r = dict(climax=False, stall=False, pushes=0, pushOK=False,
             wedge=False, overshoot=False, breadth=0)
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return r
    if not atr or atr <= 0:
        return r
    b = bars[idx]
    rg = _range(b)
    r['climax'] = rg >= 2.0 * atr
    up_w = b['h'] - max(b['c'], b['o'])
    lo_w = min(b['c'], b['o']) - b['l']
    r['stall'] = rg < 0.5 * atr + 1e-9 and up_w > 0.4 * rg and lo_w > 0.4 * rg
    r['pushes'] = push_back(bars, idx, last_closed, direction)
    r['pushOK'] = r['pushes'] >= max(2, cfg.min_pushes)
    r['wedge'] = bool(cfg.use_wedge
                      and wedge_at(bars, idx, last_closed, direction))
    if idx - 19 >= 0:
        win = bars[idx - 19:idx + 1]
        sma = sum(x['c'] for x in win) / 20.0
        hh = max(x['h'] for x in win)
        ll = min(x['l'] for x in win)
        if direction > 0:
            r['overshoot'] = (b['h'] - max(sma, hh - (hh - ll) * 0.2)
                              > 0.3 * atr)
        else:
            r['overshoot'] = (min(sma, ll + (hh - ll) * 0.2) - b['l']
                              > 0.3 * atr)
    r['breadth'] = sum([r['climax'], r['stall'], r['pushOK'],
                        r['wedge'], r['overshoot']])
    return r


def leg_count(swings, direction):
    """Successive countertrend swing lows/highs after the trend extreme."""
    out = dict(valid=False, legs=0, deep=False, depth=-1.0,
               anchor=-1, extreme=-1)
    sw = [s for s in swings]
    want_anchor = +1 if direction > 0 else -1
    want_leg = -1 if direction > 0 else +1
    a = -1
    for i in range(len(sw) - 1, -1, -1):
        if sw[i].get('dir') == want_anchor:
            a = i
            break
    if a < 0:
        return out
    o = -1
    for i in range(a - 1, -1, -1):
        if sw[i].get('dir') == want_leg:
            o = i
            break
    out.update(valid=True, anchor=sw[a]['bar'])
    best = None
    legs = 0
    for i in range(a + 1, len(sw)):
        if sw[i].get('dir') != want_leg:
            continue
        if best is None or (sw[i]['price'] < best if direction > 0
                            else sw[i]['price'] > best):
            best = sw[i]['price']
            out['extreme'] = sw[i]['bar']
            if legs < 3:
                legs += 1
    if best is None:
        return out
    out['legs'] = legs
    if o >= 0:
        denom = ((sw[a]['price'] - sw[o]['price']) if direction > 0
                 else (sw[o]['price'] - sw[a]['price']))
        if denom > 0:
            out['depth'] = ((sw[a]['price'] - best) / denom if direction > 0
                            else (best - sw[a]['price']) / denom)
            out['deep'] = out['depth'] > 0.6
    return out


def _ema20_tail(bars, idx):
    e = bars[0]['c']
    k = 2.0 / 21.0
    tail = {}
    for i in range(1, idx + 1):
        e = bars[i]['c'] * k + e * (1.0 - k)
        tail[i] = e
    return tail


def _side(close, ema, tol):
    if close > ema + tol:
        return +1
    if close < ema - tol:
        return -1
    return 0


def mtr(bars, idx, last_closed, atr, swings=(), rev_dir=+1, cfg=None):
    cfg = cfg or RevCfg()
    swings = list(swings or [])
    s = dict(found=False, verdict="NONE", dir=rev_dir, ema_break=False,
             retest=False, bo_follow=False, pressure_ok=False, press_n=0,
             score=0, cross_bar=-1)
    if not cfg.enable:
        return s
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return s
    if not atr or atr <= 0:
        return s
    if rev_dir not in (+1, -1):
        return s
    K = min(50, max(5, cfg.lookback))
    if idx + 1 < K + 2:
        return s
    tol = cfg.retest_tol_atr * atr
    ema = _ema20_tail(bars, idx)
    if _side(bars[idx]['c'], ema[idx], tol) != rev_dir:
        return s
    s['ema_break'] = True
    for j in range(idx - 1, max(-1, idx - K), -1):
        if _side(bars[j]['c'], ema[j], tol) == -rev_dir:
            s['cross_bar'] = j
            break
    if s['cross_bar'] < 0:
        s['ema_break'] = False
        return s
    for j in range(s['cross_bar'] + 1, idx + 1):
        e = ema[j]
        if rev_dir > 0 and bars[j]['l'] <= e + tol and bars[j]['c'] > e - tol:
            s['retest'] = True
            break
        if rev_dir < 0 and bars[j]['h'] >= e - tol and bars[j]['c'] < e + tol:
            s['retest'] = True
            break
    bo = bo_analyze(bars, idx, last_closed, atr, swings, cfg.bo_cfg)
    s['bo_follow'] = bool(bo['found'] and bo['dir'] == rev_dir
                          and bo['outcome'] == "FOLLOW")
    s['press_n'] = push_back(bars, idx, last_closed, rev_dir)
    mp = min(10, max(3, cfg.min_pressure))
    s['pressure_ok'] = s['press_n'] >= mp
    n = sum([s['ema_break'], s['retest'], s['bo_follow'], s['pressure_ok']])
    s['score'] = 25 * n
    s['verdict'] = "MAJOR" if n >= 4 else ("MINOR" if n >= 1 else "NONE")
    s['found'] = s['verdict'] != "NONE"
    return s
