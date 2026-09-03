"""fm_engine.py — Python 1:1 mirror of docs/SYSTEMATIC_SPECIFICATION.md.

Bar indexing: index 0 = OLDEST, index N-1 = NEWEST (opposite of MT5 series).
Detection consumes closed bars only; the newest bar in `feed_step` is the
just-closed bar. Used as test oracle: MQL5 engine must match on identical
synthetic series.
"""
from dataclasses import dataclass, field

PROJECTED, POTENTIAL, DEVELOPING, CONFIRMED, INVALIDATED, COMPLETED = (
    "PROJECTED", "POTENTIAL", "DEVELOPING", "CONFIRMED", "INVALIDATED", "COMPLETED")


@dataclass
class Cfg:
    swing_k: int = 3
    min_leg_atr: float = 1.0
    min_leg_bars: int = 3
    max_leg_bars: int = 100
    min_pb: float = 0.15
    max_pb: float = 0.90
    max_pb_bars: int = 50
    tol_atr: float = 0.25
    over_atr: float = 0.50
    approach_atr: float = 1.0
    close_pct: float = 0.50
    min_body: float = 0.30
    max_wick: float = 0.60
    require_engulf: bool = False
    require_ft: bool = False
    enable_inverse: bool = True
    failed_bo_bars: int = 5
    max_active: int = 20
    max_fwd: int = 100


def wilder_atr(bars, period=14):
    """bars: list of dicts o/h/l/c oldest-first. Returns list aligned."""
    n = len(bars)
    atr = [0.0] * n
    tr = [0.0] * n
    for i in range(n):
        if i == 0:
            tr[i] = bars[i]['h'] - bars[i]['l']
        else:
            tr[i] = max(bars[i]['h'] - bars[i]['l'],
                        abs(bars[i]['h'] - bars[i-1]['c']),
                        abs(bars[i]['l'] - bars[i-1]['c']))
    if n < period + 1:
        return atr
    atr[n - period - 1] = sum(tr[n-period:]) / period
    for i in range(n - period - 2, -1, -1):
        atr[i] = (atr[i+1] * (period-1) + tr[i]) / period
    # convert to oldest-first forward fill: recompute forward (equivalent)
    # simpler forward Wilder:
    atr2 = [0.0]*n
    atr2[period] = sum(tr[1:period+1]) / period
    for i in range(period+1, n):
        atr2[i] = (atr2[i-1]*(period-1) + tr[i]) / period
    return atr2


def confirmed_swings(bars, k, last_closed_idx, use_close=False):
    """Return swings confirmed as of last_closed_idx (inclusive newest closed).
    A swing at s requires s+k <= last_closed_idx.
    use_close=True mirrors InpPriceMode=CLOSE (line chart)."""
    def pxH(b): return b['c'] if use_close else b['h']
    def pxL(b): return b['c'] if use_close else b['l']
    sw = []
    for s in range(k, last_closed_idx - k + 1):
        if s < 1 or s + k >= len(bars):
            continue
        # closed bars only: s-k..s+k must be <= last_closed_idx
        if s + k > last_closed_idx:
            continue
        hi = all(pxH(bars[j]) <= pxH(bars[s]) for j in range(s-k, s+k+1) if j != s)
        lo = all(pxL(bars[j]) >= pxL(bars[s]) for j in range(s-k, s+k+1) if j != s)
        if hi:
            # earliest-wins tie-break
            if any(pxH(bars[j]) == pxH(bars[s]) for j in range(s+1, s+k+1)):
                hi = False
        if lo:
            if any(pxL(bars[j]) == pxL(bars[s]) for j in range(s+1, s+k+1)):
                lo = False
        if hi:
            sw.append({'bar': s, 'price': pxH(bars[s]), 'dir': +1})
        elif lo:
            sw.append({'bar': s, 'price': pxL(bars[s]), 'dir': -1})
    return sw


def body(r): return abs(r['c'] - r['o'])
def brange(r): return max(r['h'] - r['l'], 1e-9)


def exhaustion_any(bars, b, direction, atr):
    if b < 1 or b >= len(bars) or atr <= 0:
        return False
    r = bars[b]
    rg = brange(r)
    climax = rg >= 2.0 * atr
    up_w = r['h'] - max(r['c'], r['o'])
    lo_w = min(r['c'], r['o']) - r['l']
    stall = rg < 0.5 * atr and up_w > 0.4 * rg and lo_w > 0.4 * rg
    pushes = False
    if b - 3 >= -1 and b >= 2:
        if direction > 0:
            pushes = (bars[b]['c'] > bars[b-1]['c'] > bars[b-2]['c'] and
                      bars[b]['h'] > bars[b-1]['h'] > bars[b-2]['h'])
        else:
            pushes = (bars[b]['c'] < bars[b-1]['c'] < bars[b-2]['c'] and
                      bars[b]['l'] < bars[b-1]['l'] < bars[b-2]['l'])
    return bool(climax or stall or pushes)


def is_signal_bar(bars, c, fade_dir, cfg):
    if c < 1 or c >= len(bars):
        return False
    r, p = bars[c], bars[c-1]
    rg = brange(r)
    b = body(r)
    d = +1 if r['c'] > r['o'] else (-1 if r['c'] < r['o'] else 0)
    if d != fade_dir:
        return False
    if b / rg < cfg.min_body:
        return False
    adv = (r['h'] - r['c']) if fade_dir > 0 else (r['c'] - r['l'])
    if adv / rg > cfg.max_wick:
        return False
    edge = (r['c'] - r['l']) / rg if fade_dir > 0 else (r['h'] - r['c']) / rg
    if edge < 1.0 - cfg.close_pct:
        return False
    if cfg.require_engulf:
        pb = abs(p['c'] - p['o'])
        eng = (r['c'] > p['o'] and r['o'] < p['c']) if fade_dir > 0 else (r['c'] < p['o'] and r['o'] > p['c'])
        if not (eng and b >= pb):
            return False
    return True


@dataclass
class Setup:
    id: int
    dir: int
    a0: dict
    a1: dict
    b0: dict
    mm_range: float
    target: float
    state: str = PROJECTED
    age: int = 0
    state_age: int = 0
    alerted: set = field(default_factory=set)


class Engine:
    def __init__(self, cfg=None):
        self.cfg = cfg or Cfg()
        self.setups = []
        self.next_id = 1

    def form(self, swings, last_idx, atr):
        cfg = self.cfg
        # recent triples
        for i in range(max(0, len(swings)-8), len(swings)-2):
            a0, a1, b0 = swings[i], swings[i+1], swings[i+2]
            proj = self._regular(a0, a1, b0, atr)
            if proj and not self._dup(proj):
                self.setups.append(Setup(self.next_id, proj['dir'], a0, a1, b0,
                                         proj['mm'], proj['target']))
                self.next_id += 1
        self.setups = self.setups[-cfg.max_active:]

    def _regular(self, a0, a1, b0, atr):
        cfg = self.cfg
        d, mm = 0, 0.0
        if a0['dir'] == -1 and a1['dir'] == +1 and b0['dir'] == -1:
            d, mm = +1, a1['price'] - a0['price']
        elif a0['dir'] == +1 and a1['dir'] == -1 and b0['dir'] == +1:
            d, mm = -1, a0['price'] - a1['price']
        else:
            return None
        if mm <= 0 or atr <= 0:
            return None
        lb = abs(a1['bar'] - a0['bar'])
        if not (cfg.min_leg_bars <= lb <= cfg.max_leg_bars):
            return None
        if mm < cfg.min_leg_atr * atr:
            return None
        depth = ((a1['price'] - b0['price']) / mm) if d > 0 else ((b0['price'] - a1['price']) / mm)
        if not (cfg.min_pb <= depth <= cfg.max_pb):
            return None
        if abs(b0['bar'] - a1['bar']) > cfg.max_pb_bars:
            return None
        if not (a0['bar'] < a1['bar'] < b0['bar']):
            return None
        t = b0['price'] + mm if d > 0 else b0['price'] - mm
        return {'dir': d, 'mm': mm, 'target': t}

    def _dup(self, proj):
        return any(s.dir == proj['dir'] and abs(s.target - proj['target']) < 1e-9
                   and s.state != INVALIDATED for s in self.setups)

    def update(self, bars, b, atr, use_close=False):
        cfg = self.cfg
        tol, app, over = cfg.tol_atr*atr, cfg.approach_atr*atr, cfg.over_atr*atr
        for s in self.setups:
            if s.state in (INVALIDATED, COMPLETED):
                continue
            s.age += 1
            s.state_age += 1
            if s.age > cfg.max_fwd:
                s.state = INVALIDATED
                continue
            bar = bars[b]
            ext = bar['c'] if use_close else (bar['h'] if s.dir > 0 else bar['l'])
            dist = (s.target - ext) if s.dir > 0 else (ext - s.target)
            ov = (bar['c'] - s.target) if s.dir > 0 else (s.target - bar['c'])
            if ov > over:
                s.state = INVALIDATED
                continue
            if s.state == PROJECTED:
                if 0 <= dist <= app:
                    s.state, s.state_age = POTENTIAL, 0
            elif s.state == POTENTIAL:
                if abs(ext - s.target) <= tol and exhaustion_any(bars, b, s.dir, atr):
                    s.state, s.state_age = DEVELOPING, 0
            elif s.state == DEVELOPING:
                f = -s.dir
                if abs(ext - s.target) <= tol and is_signal_bar(bars, b, f, cfg):
                    if cfg.require_ft:
                        pass  # wait: need next bar; handled by caller stepping
                    else:
                        s.state, s.state_age = CONFIRMED, 0
                elif abs(ext - s.target) > tol + app:
                    s.state, s.state_age = POTENTIAL, 0
            elif s.state == CONFIRMED:
                s.state = COMPLETED
