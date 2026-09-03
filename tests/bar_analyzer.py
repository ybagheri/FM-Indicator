"""bar_analyzer.py — Python mirror of docs/BAR_BY_BAR_ENGINE.md + BarAnalyzer.mqh.

Indexing: oldest-first (index 0 = OLDEST). Detection consumes closed bars only;
`last_closed` is the newest closed index. Field-for-field identical semantics
to MQL5 (float tol 1e-9, booleans exact). MQL5 MT5-shift b maps to
oldest-first idx = (N-1) - b for a series copy of length N.
"""
from dataclasses import dataclass


@dataclass
class BarCfg:
    doji_max_body: float = 0.15
    big_bar_atr: float = 2.0
    small_bar_atr: float = 0.5
    strong_close_pct: float = 0.70
    min_body: float = 0.30
    overlap_ratio: float = 0.50
    barbwire_bars: int = 5
    barbwire_min_overlap: int = 3
    pressure_lookback: int = 10


def _range(r):
    rg = r['h'] - r['l']
    return rg if rg > 0 else 1e-9


def _body(r):
    return abs(r['c'] - r['o'])


def _dir(r):
    if r['c'] > r['o']:
        return +1
    if r['c'] < r['o']:
        return -1
    return 0


def pair_overlap(a, b):
    ra, rb = a['h'] - a['l'], b['h'] - b['l']
    m = min(ra, rb)
    if m <= 0:
        return 0.0
    top = min(max(a['c'], a['o']), max(b['c'], b['o']))
    bot = max(min(a['c'], a['o']), min(b['c'], b['o']))
    ov = top - bot
    return ov / m if ov > 0 else 0.0


def run_count(bars, idx, last_closed, cfg):
    if idx < 0 or idx > last_closed:
        return 0
    d0 = _dir(bars[idx])
    if d0 == 0:
        return 0
    n = 0
    for i in range(idx, -1, -1):
        if i > last_closed:
            continue
        if _dir(bars[i]) != d0:
            break
        n += 1
        if n >= 20:
            break
    return n if d0 > 0 else -n


def inside_run(bars, idx, last_closed):
    if idx <= 0 or idx > last_closed:
        return 0
    n = 0
    for i in range(idx, 0, -1):
        if i > last_closed:
            continue
        ins = bars[i]['h'] <= bars[i-1]['h'] and bars[i]['l'] >= bars[i-1]['l']
        if not ins:
            break
        n += 1
    return n


def bar_analyze(bars, idx, last_closed, atr, cfg=None):
    cfg = cfg or BarCfg()
    f = dict(valid=False, dir=0, range=0.0, body=0.0, body_ratio=0.0,
             close_pos=0.5, upper_tail=0.0, lower_tail=0.0,
             upper_ratio=0.0, lower_ratio=0.0, is_doji=False,
             is_big=False, is_small=False, is_strong_bull=False,
             is_strong_bear=False, is_inside=False, is_outside=False,
             overlap=0.0, gap_up=False, gap_down=False, consecutive=0,
             ii_count=0, pressure_bull=0, pressure_bear=0,
             barbwire=False, tightening=False, label="NONE")
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return f
    r = bars[idx]
    rg = _range(r)
    body = _body(r)
    br = body / rg
    cp = (r['c'] - r['l']) / rg
    d = _dir(r)
    up_t = r['h'] - max(r['c'], r['o'])
    lo_t = min(r['c'], r['o']) - r['l']
    f.update(valid=True, dir=d, range=rg, body=body, body_ratio=br,
             close_pos=cp, upper_tail=up_t, lower_tail=lo_t,
             upper_ratio=up_t / rg, lower_ratio=lo_t / rg,
             is_doji=br < cfg.doji_max_body)
    if atr and atr > 0:
        f['is_big'] = rg >= cfg.big_bar_atr * atr
        f['is_small'] = rg < cfg.small_bar_atr * atr
    f['is_strong_bull'] = d > 0 and cp >= cfg.strong_close_pct and br >= cfg.min_body
    f['is_strong_bear'] = d < 0 and (1.0 - cp) >= cfg.strong_close_pct and br >= cfg.min_body
    if idx - 1 >= 0:
        p = bars[idx-1]
        f['is_inside'] = r['h'] <= p['h'] and r['l'] >= p['l']
        f['is_outside'] = (r['h'] >= p['h'] and r['l'] <= p['l']
                           and (r['h'] > p['h'] or r['l'] < p['l']))
        f['overlap'] = pair_overlap(r, p)
        f['gap_up'] = r['l'] > p['h']
        f['gap_down'] = r['h'] < p['l']
    c = run_count(bars, idx, last_closed, cfg)
    if f['is_doji']:
        c = 0
    f['consecutive'] = c
    f['ii_count'] = inside_run(bars, idx, last_closed)
    L = max(1, cfg.pressure_lookback)
    pb = pe = 0
    for i in range(idx, max(-1, idx - L), -1):
        if i < 0 or i > last_closed:
            continue
        rr = bars[i]
        rrg = _range(rr)
        dd = _dir(rr)
        ccp = (rr['c'] - rr['l']) / rrg
        bbr = _body(rr) / rrg
        if dd > 0 and ccp >= cfg.strong_close_pct and bbr >= cfg.min_body:
            pb += 1
        if dd < 0 and (1.0 - ccp) >= cfg.strong_close_pct and bbr >= cfg.min_body:
            pe += 1
    f['pressure_bull'], f['pressure_bear'] = pb, pe
    W = max(3, cfg.barbwire_bars)
    ovn, any_doji = 0, False
    for i in range(idx, max(-1, idx - W), -1):
        if i <= 0 or i > last_closed:
            continue
        if pair_overlap(bars[i], bars[i-1]) >= cfg.overlap_ratio:
            ovn += 1
        rr = _range(bars[i])
        if _body(bars[i]) / rr < cfg.doji_max_body:
            any_doji = True
    tail = idx - W
    if 0 <= tail <= last_closed:
        rr = _range(bars[tail])
        if _body(bars[tail]) / rr < cfg.doji_max_body:
            any_doji = True
    f['barbwire'] = ovn >= cfg.barbwire_min_overlap and any_doji
    if idx - 5 >= 0:
        w = sorted(bars[i]['h'] - bars[i]['l'] for i in range(idx-4, idx))
        med = (w[1] + w[2]) * 0.5
        f['tightening'] = (bars[idx]['h'] - bars[idx]['l']) < med
    if f['is_strong_bull']:
        f['label'] = "STRONG_BULL"
    elif f['is_strong_bear']:
        f['label'] = "STRONG_BEAR"
    elif f['ii_count'] >= 2:
        f['label'] = "II%d" % f['ii_count']
    elif f['is_big']:
        f['label'] = "BIG"
    elif f['is_doji']:
        f['label'] = "DOJI"
    elif f['is_outside']:
        f['label'] = "OUTSIDE"
    elif f['is_inside']:
        f['label'] = "INSIDE"
    elif f['gap_up'] or f['gap_down']:
        f['label'] = "GAP"
    else:
        f['label'] = "BAR"
    return f
