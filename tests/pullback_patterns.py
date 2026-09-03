"""pullback_patterns.py — Python mirror of docs/PULLBACK_PATTERNS.md + PullbackPatterns.mqh.

Indexing: oldest-first (index 0 = OLDEST). Detection consumes closed bars only;
`last_closed` is the newest closed index; analysis point `idx` (normally ==
last_closed) plays the MT5-shift-b role. Field-for-field identical semantics
to MQL5 (float tol 1e-9, booleans exact).

Entry note: MQL5 records entry = extreme +/- _Point (one tick). The mirror has
no tick grid, so it returns `ref` (the extreme price) plus `stop`; MQL5 parity
holds on (found, legs, signal/anchor bars, stop) exactly, entry by construction.
"""

from dataclasses import dataclass


@dataclass
class PVCfg:
    min_pullback_depth_atr: float = 0.50
    double_tol_atr: float = 0.25
    max_double_bars: int = 20
    min_double_trough_atr: float = 0.50
    micro_double_bars: int = 5
    max_pullback_bars: int = 50  # reuses the FM pullback window (spec §3 note)
    enable: bool = True


def _none_pullback():
    return dict(found=False, legs=0, signal=-1, anchor=-1, ref=0.0, stop=0.0)


def _none_double(direction):
    return dict(found=False, dir=direction, bar1=-1, bar2=-1,
                price1=0.0, price2=0.0, micro=False)


def trend_dir(bars, idx, last_closed, atr, cfg=None):
    """EMA20/EMA50 gap on closes ending at idx. Needs 50+ closes, else 0."""
    cfg = cfg or PVCfg()
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return 0
    if not atr or atr <= 0:
        return 0
    if idx + 1 < 50:
        return 0
    k20, k50 = 2.0 / 21.0, 2.0 / 51.0
    e20 = e50 = bars[0]['c']
    for i in range(1, idx + 1):
        e20 = bars[i]['c'] * k20 + e20 * (1.0 - k20)
        e50 = bars[i]['c'] * k50 + e50 * (1.0 - k50)
    gap = (e20 - e50) / atr
    if gap > 0.4:
        return +1
    if gap < -0.4:
        return -1
    return 0


def detect_bull(bars, idx, last_closed, atr, cfg=None):
    """H1/H2 bull pullback. Returns dict(found, legs, signal, anchor, ref, stop)."""
    cfg = cfg or PVCfg()
    s = _none_pullback()
    if not cfg.enable:
        return s
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return s
    if not atr or atr <= 0:
        return s
    if trend_dir(bars, idx, last_closed, atr, cfg) != +1:
        return s
    w0 = max(0, idx - cfg.max_pullback_bars)
    if w0 + 1 > idx:
        return s
    mxh = max(b['h'] for b in bars[w0:idx + 1])
    mnl = min(b['l'] for b in bars[w0:idx + 1])
    if mxh - mnl < cfg.min_pullback_depth_atr * atr:
        return s
    h1 = -1
    for i in range(w0 + 1, idx + 1):
        if bars[i]['h'] > bars[i - 1]['h']:
            h1 = i
            break
    if h1 < 0:
        return s
    low_at = min(b['l'] for b in bars[w0:h1 + 1])
    # second leg: oldest bar newer than h1 with a lower low (spec "exists j").
    jlow = -1
    for j in range(h1 + 1, idx + 1):
        if bars[j]['l'] < low_at:
            jlow = j
            break
    if jlow < 0:
        return dict(found=True, legs=1, signal=h1, anchor=h1,
                    ref=bars[h1]['h'], stop=mnl)
    h2 = -1
    for k in range(jlow + 1, idx + 1):
        if bars[k]['h'] > bars[k - 1]['h']:
            h2 = k
            break
    if h2 < 0:
        return dict(found=True, legs=1, signal=h1, anchor=h1,
                    ref=bars[h1]['h'], stop=mnl)
    return dict(found=True, legs=2, signal=h2, anchor=h1,
                ref=bars[h2]['h'], stop=mnl)


def detect_bear(bars, idx, last_closed, atr, cfg=None):
    """L1/L2 bear mirror of detect_bull."""
    cfg = cfg or PVCfg()
    s = _none_pullback()
    if not cfg.enable:
        return s
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return s
    if not atr or atr <= 0:
        return s
    if trend_dir(bars, idx, last_closed, atr, cfg) != -1:
        return s
    w0 = max(0, idx - cfg.max_pullback_bars)
    if w0 + 1 > idx:
        return s
    mxh = max(b['h'] for b in bars[w0:idx + 1])
    mnl = min(b['l'] for b in bars[w0:idx + 1])
    if mxh - mnl < cfg.min_pullback_depth_atr * atr:
        return s
    l1 = -1
    for i in range(w0 + 1, idx + 1):
        if bars[i]['l'] < bars[i - 1]['l']:
            l1 = i
            break
    if l1 < 0:
        return s
    high_at = max(b['h'] for b in bars[w0:l1 + 1])
    jhigh = -1
    for j in range(l1 + 1, idx + 1):
        if bars[j]['h'] > high_at:
            jhigh = j
            break
    if jhigh < 0:
        return dict(found=True, legs=1, signal=l1, anchor=l1,
                    ref=bars[l1]['l'], stop=mxh)
    l2 = -1
    for k in range(jhigh + 1, idx + 1):
        if bars[k]['l'] < bars[k - 1]['l']:
            l2 = k
            break
    if l2 < 0:
        return dict(found=True, legs=1, signal=l1, anchor=l1,
                    ref=bars[l1]['l'], stop=mxh)
    return dict(found=True, legs=2, signal=l2, anchor=l1,
                ref=bars[l2]['l'], stop=mxh)


def find_double_top(swings, atr, cfg=None):
    """Double top on confirmed swings (oldest-first). Most-recent pair wins."""
    cfg = cfg or PVCfg()
    d = _none_double(-1)
    if not cfg.enable:
        return d
    if not atr or atr <= 0:
        return d
    n = len(swings)
    tol = cfg.double_tol_atr * atr
    need = cfg.min_double_trough_atr * atr
    for j in range(n - 1, -1, -1):
        if swings[j].get('dir') != +1:
            continue
        for i in range(j - 1, -1, -1):
            if swings[i].get('dir') != +1:
                continue
            if abs(swings[j]['price'] - swings[i]['price']) > tol:
                continue
            if swings[j]['bar'] - swings[i]['bar'] > cfg.max_double_bars:
                continue
            base = min(swings[i]['price'], swings[j]['price'])
            ok = any(swings[k].get('dir') == -1
                     and base - swings[k]['price'] >= need
                     for k in range(i + 1, j))
            if not ok:
                continue
            return dict(found=True, dir=-1, bar1=swings[i]['bar'],
                        bar2=swings[j]['bar'], price1=swings[i]['price'],
                        price2=swings[j]['price'], micro=False)
    return d


def find_double_bottom(swings, atr, cfg=None):
    """Double bottom mirror on swing lows + intervening high."""
    cfg = cfg or PVCfg()
    d = _none_double(+1)
    if not cfg.enable:
        return d
    if not atr or atr <= 0:
        return d
    n = len(swings)
    tol = cfg.double_tol_atr * atr
    need = cfg.min_double_trough_atr * atr
    for j in range(n - 1, -1, -1):
        if swings[j].get('dir') != -1:
            continue
        for i in range(j - 1, -1, -1):
            if swings[i].get('dir') != -1:
                continue
            if abs(swings[j]['price'] - swings[i]['price']) > tol:
                continue
            if swings[j]['bar'] - swings[i]['bar'] > cfg.max_double_bars:
                continue
            base = max(swings[i]['price'], swings[j]['price'])
            ok = any(swings[k].get('dir') == +1
                     and swings[k]['price'] - base >= need
                     for k in range(i + 1, j))
            if not ok:
                continue
            return dict(found=True, dir=+1, bar1=swings[i]['bar'],
                        bar2=swings[j]['bar'], price1=swings[i]['price'],
                        price2=swings[j]['price'], micro=False)
    return d


def micro_double_top(bars, idx, last_closed, atr, cfg=None):
    """Micro double top on raw bar highs; trough requirement halved."""
    cfg = cfg or PVCfg()
    d = _none_double(-1)
    d['micro'] = True
    if not cfg.enable:
        return d
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return d
    if not atr or atr <= 0:
        return d
    w = max(3, cfg.micro_double_bars)
    w0 = max(0, idx - w + 1)
    if idx - w0 + 1 < 3:
        return d
    tol = cfg.double_tol_atr * atr
    need = cfg.min_double_trough_atr * atr * 0.5
    for j in range(idx, w0 - 1, -1):
        for i in range(j - 1, w0 - 1, -1):
            if abs(bars[j]['h'] - bars[i]['h']) > tol:
                continue
            if j - i > cfg.max_double_bars:
                continue
            base = min(bars[i]['h'], bars[j]['h'])
            if any(base - bars[k]['l'] >= need for k in range(i + 1, j)):
                return dict(found=True, dir=-1, bar1=i, bar2=j,
                            price1=bars[i]['h'], price2=bars[j]['h'],
                            micro=True)
    return d


def micro_double_bottom(bars, idx, last_closed, atr, cfg=None):
    """Micro double bottom mirror on raw bar lows."""
    cfg = cfg or PVCfg()
    d = _none_double(+1)
    d['micro'] = True
    if not cfg.enable:
        return d
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return d
    if not atr or atr <= 0:
        return d
    w = max(3, cfg.micro_double_bars)
    w0 = max(0, idx - w + 1)
    if idx - w0 + 1 < 3:
        return d
    tol = cfg.double_tol_atr * atr
    need = cfg.min_double_trough_atr * atr * 0.5
    for j in range(idx, w0 - 1, -1):
        for i in range(j - 1, w0 - 1, -1):
            if abs(bars[j]['l'] - bars[i]['l']) > tol:
                continue
            if j - i > cfg.max_double_bars:
                continue
            base = max(bars[i]['l'], bars[j]['l'])
            if any(bars[k]['h'] - base >= need for k in range(i + 1, j)):
                return dict(found=True, dir=+1, bar1=i, bar2=j,
                            price1=bars[i]['l'], price2=bars[j]['l'],
                            micro=True)
    return d
