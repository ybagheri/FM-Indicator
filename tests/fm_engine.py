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
    # v1.2
    enable_range: bool = False
    range_lookback: int = 50
    enable_channel: bool = False
    enable_gap: bool = False
    min_gap_atr: float = 1.0
    min_pushes: int = 3
    use_wedge: bool = True


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


def exhaustion_any(bars, b, direction, atr, min_pushes=3, use_wedge=True):
    if b < 1 or b >= len(bars) or atr <= 0:
        return False
    r = bars[b]
    rg = brange(r)
    climax = rg >= 2.0 * atr
    up_w = r['h'] - max(r['c'], r['o'])
    lo_w = min(r['c'], r['o']) - r['l']
    stall = rg < 0.5 * atr and up_w > 0.4 * rg and lo_w > 0.4 * rg
    pushes = push_count(bars, b, direction) >= max(2, min_pushes)
    wedge = is_wedge(bars, b, direction) if use_wedge else False
    # 4) channel overshoot: extreme beyond 20-bar SMA band by > 0.3 ATR
    # (mirrors MQL5 CConfirmation::ExhaustionAny §8.4; needs 20 older bars)
    over = False
    if b >= 20:
        window = bars[b-19:b+1]
        sma = sum(x['c'] for x in window) / 20.0
        if direction > 0:
            over = (r['h'] - sma) > 0.3 * atr and r['h'] == max(x['h'] for x in window)
        else:
            over = (sma - r['l']) > 0.3 * atr and r['l'] == min(x['l'] for x in window)
    return bool(climax or stall or pushes or wedge or over)


def push_count(bars, b, direction):
    """Consecutive closes (+higher highs / lower lows) toward direction, ending at b."""
    n = 0
    i = b
    while i >= 1:
        if direction > 0:
            if not (bars[i]['c'] > bars[i-1]['c'] and bars[i]['h'] > bars[i-1]['h']):
                break
        else:
            if not (bars[i]['c'] < bars[i-1]['c'] and bars[i]['l'] < bars[i-1]['l']):
                break
        n += 1
        i -= 1
    return n


def follow_through(bars, sig, fade_dir):
    """Next (newer) closed bar closes beyond signal extreme toward fade dir."""
    if sig < 0 or sig + 1 >= len(bars):
        return False
    s, n = bars[sig], bars[sig+1]
    if fade_dir > 0:
        return n['c'] > s['h']
    return n['c'] < s['l']


def is_wedge(bars, b, direction):
    if b < 3:
        return False
    n = push_count(bars, b, direction)
    if n < 3:
        return False
    shrink = all(brange(bars[i]) <= brange(bars[i-1]) * 1.05
                 for i in range(b - n + 2, b + 1))
    return bool(shrink or n >= 4)


def score_signal(bars, c, fade_dir, cfg, mm_dir, atr, dist_atr, conf):
    """0..100 display-only score (mirrors MQL5 ScoreSignal)."""
    if c < 1 or c >= len(bars) or atr <= 0:
        return 0
    r = bars[c]
    rg = brange(r)
    if rg <= 0:
        return 0
    body_n = abs(r['c'] - r['o']) / rg
    score = int(min(1.0, body_n) * 20)
    adv = ((r['h'] - r['c']) if fade_dir > 0 else (r['c'] - r['l'])) / rg
    score += int((1.0 - min(1.0, adv / 0.6)) * 15)
    edge = ((r['c'] - r['l']) if fade_dir > 0 else (r['h'] - r['c'])) / rg
    score += int(min(1.0, edge) * 15)
    score += 5  # no-engulf neutral credit (engulf path adds full 10 in MQL5)
    if fade_dir > 0 and r['c'] > bars[c-1]['h']:
        score += 5
    if fade_dir < 0 and r['c'] < bars[c-1]['l']:
        score += 5
    hits = 0
    up_w = r['h'] - max(r['c'], r['o'])
    lo_w = min(r['c'], r['o']) - r['l']
    if rg >= 2.0 * atr:
        hits += 1
    if rg < 0.5 * atr and up_w > 0.4 * rg and lo_w > 0.4 * rg:
        hits += 1
    if push_count(bars, c, mm_dir) >= 2:
        hits += 1
    if is_wedge(bars, c, mm_dir):
        hits += 1
    score += min(4, hits) * 5
    score += int(max(0.0, min(1.0, conf)) * 10)
    score += int(max(0.0, 1.0 - min(1.0, abs(dist_atr) / 0.5)) * 10)
    return max(0, min(100, score))


def range_projection(bars, bo, cfg, atr):
    """v1.2 range-height breakout at newest closed index bo (oldest-first)."""
    if not cfg.enable_range or atr <= 0:
        return None
    N = cfg.range_lookback
    if bo < 1 or bo - N < 0:
        return None
    window = bars[bo-N:bo]  # N closed bars before breakout
    hh = max(x['h'] for x in window)
    ll = min(x['l'] for x in window)
    height = hh - ll
    if height < cfg.min_leg_atr * atr:
        return None
    r = bars[bo]
    if r['c'] > hh:
        return {'dir': +1, 'mm': height, 'target': r['c'] + height, 'family': 'RANGE'}
    if r['c'] < ll:
        return {'dir': -1, 'mm': height, 'target': r['c'] - height, 'family': 'RANGE'}
    return None


def channel_projection(a0, a1, b0, cfg, atr):
    """v1.2 shallow-pullback channel (depth below regular minimum)."""
    if not cfg.enable_channel:
        return None
    d, mm = 0, 0.0
    if a0['dir'] == -1 and a1['dir'] == +1 and b0['dir'] == -1:
        d, mm = +1, a1['price'] - a0['price']
    elif a0['dir'] == +1 and a1['dir'] == -1 and b0['dir'] == +1:
        d, mm = -1, a0['price'] - a1['price']
    else:
        return None
    if mm <= 0 or atr <= 0 or mm < cfg.min_leg_atr * atr:
        return None
    depth = ((a1['price'] - b0['price']) / mm) if d > 0 else ((b0['price'] - a1['price']) / mm)
    if not (0.02 <= depth < cfg.min_pb):
        return None
    t = b0['price'] + mm if d > 0 else b0['price'] - mm
    return {'dir': d, 'mm': mm, 'target': t, 'family': 'CHANNEL'}


def gap_projection(bars, g, cfg, atr):
    """v1.2 measuring-gap projection at closed index g."""
    if not cfg.enable_gap or atr <= 0:
        return None
    if g < 1 or g >= len(bars):
        return None
    r, p = bars[g], bars[g-1]
    rg = max(r['h'] - r['l'], 1e-9)
    if rg < cfg.min_gap_atr * atr:
        return None
    bull = r['l'] > p['h'] and (r['c'] - r['l']) / rg >= 0.75
    bear = r['h'] < p['l'] and (r['h'] - r['c']) / rg >= 0.75
    if not bull and not bear:
        return None
    gap = (r['c'] - p['h']) if bull else (p['l'] - r['c'])
    if gap < 0.25 * atr:
        return None
    d = +1 if bull else -1
    return {'dir': d, 'mm': gap, 'target': r['c'] + d * gap, 'family': 'GAP'}


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
    family: str = 'REGULAR'


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
                                         proj['mm'], proj['target'],
                                         family=proj.get('family', 'REGULAR')))
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
        return {'dir': d, 'mm': mm, 'target': t, 'family': 'REGULAR'}

    def _dup(self, proj):
        pf = proj.get('family', 'REGULAR')
        return any(s.dir == proj['dir'] and abs(s.target - proj['target']) < 1e-9
                   and getattr(s, 'family', 'REGULAR') == pf
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
                if abs(ext - s.target) <= tol and exhaustion_any(
                        bars, b, s.dir, atr, cfg.min_pushes, cfg.use_wedge):
                    s.state, s.state_age = DEVELOPING, 0
            elif s.state == DEVELOPING:
                f = -s.dir
                if abs(ext - s.target) <= tol and is_signal_bar(bars, b, f, cfg):
                    if cfg.require_ft:
                        pass  # v1.1: signal on newest bar must wait one bar (see below)
                    else:
                        s.state, s.state_age = CONFIRMED, 0
                # v1.1 delayed follow-through: signal was on previous closed bar
                # (b-1), current bar b closes beyond its extreme. Covers the
                # "signal on bar 1 with RequireFollowThrough" edge: confirmation
                # always lands exactly one closed bar after the signal.
                if s.state == DEVELOPING and cfg.require_ft and b >= 1:
                    pb = b - 1
                    pext = bars[pb]['c'] if use_close else (
                        bars[pb]['h'] if s.dir > 0 else bars[pb]['l'])
                    if (abs(pext - s.target) <= 2 * tol
                            and is_signal_bar(bars, pb, f, cfg)
                            and follow_through(bars, pb, f)):
                        s.state, s.state_age = CONFIRMED, 0
                if s.state == DEVELOPING and abs(ext - s.target) > tol + app:
                    s.state, s.state_age = POTENTIAL, 0
            elif s.state == CONFIRMED:
                s.state = COMPLETED


# ---- v2 research tooling: MTF bias, MAE/MFE, CSV export, backtest ----

def mtf_bias(htf_closes):
    """Read-only higher-TF bias from 20/50 SMA gap (mirrors MQL5 MTFBias).
    Returns +1/-1/0; never affects detection."""
    if len(htf_closes) < 50:
        return 0
    s20 = sum(htf_closes[-20:]) / 20.0
    s50 = sum(htf_closes[-50:]) / 50.0
    gap = s20 - s50
    # ATR-normalization happens caller-side; use relative gap here:
    scale = max(1e-9, abs(s50) * 0.001)
    if gap / scale > 0.8:
        return +1
    if gap / scale < -0.8:
        return -1
    return 0


def mae_mfe(bars, entry_idx, entry_px, fade_dir, horizon=20):
    """Max adverse / favorable excursion (in price) after entry bar.
    fade_dir: trade direction (opposite the MM). No profit claims — pure
    excursion measurement for walk-forward review."""
    mae, mfe = 0.0, 0.0
    for i in range(entry_idx + 1, min(len(bars), entry_idx + 1 + horizon)):
        b = bars[i]
        if fade_dir > 0:  # long: adverse = entry - low, favorable = high - entry
            mae = max(mae, entry_px - b['l'])
            mfe = max(mfe, b['h'] - entry_px)
        else:             # short
            mae = max(mae, b['h'] - entry_px)
            mfe = max(mfe, entry_px - b['l'])
    return {'mae': mae, 'mfe': mfe, 'horizon': horizon}


def export_signals_csv(path, rows):
    """rows: list of dicts with keys time,id,family,dir,target,price,score,symbol,tf."""
    import csv
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=["time", "id", "family", "dir", "target",
                                          "price", "score", "symbol", "tf"])
        w.writeheader()
        w.writerows(rows)


def backtest_run(bars, cfg=None, atr_period=14, horizon=20, use_close=False):
    """Bar-by-bar engine run over oldest-first bars. Returns signal rows with
    MAE/MFE measured from the CONFIRMED close. Deterministic; for research
    review only, not a profitability backtest."""
    cfg = cfg or Cfg()
    eng = Engine(cfg)
    rows = []
    atrs = wilder_atr(bars, atr_period)
    for b in range(len(bars)):
        atr = atrs[b]
        if atr <= 0:
            continue
        sw = confirmed_swings(bars, cfg.swing_k, b, use_close)
        # form regular + channel on swing triples (mirrors MQL5 FormProjections)
        for i in range(max(0, len(sw) - 8), len(sw) - 2):
            a0, a1, b0 = sw[i], sw[i+1], sw[i+2]
            for proj in (eng._regular(a0, a1, b0, atr),
                         channel_projection(a0, a1, b0, cfg, atr)):
                if proj and not eng._dup(proj):
                    eng.setups.append(Setup(eng.next_id, proj['dir'], a0, a1, b0,
                                            proj['mm'], proj['target'],
                                            family=proj.get('family', 'REGULAR')))
                    eng.next_id += 1
        # range + gap on newest bar
        for proj in (range_projection(bars, b, cfg, atr),
                     gap_projection(bars, b, cfg, atr)):
            if proj and not eng._dup(proj):
                z = {'bar': b, 'price': bars[b]['c'], 'dir': 0}
                eng.setups.append(Setup(eng.next_id, proj['dir'], z, z, z,
                                        proj['mm'], proj['target'],
                                        family=proj.get('family', 'MM')))
                eng.next_id += 1
        before = {s.id: s.state for s in eng.setups}
        eng.update(bars, b, atr, use_close)
        for s in eng.setups:
            if before.get(s.id) != CONFIRMED and s.state == CONFIRMED:
                f = -s.dir
                entry = bars[b]['c']
                ex = mae_mfe(bars, b, entry, f, horizon)
                q = score_signal(bars, b, f, cfg, s.dir, atr,
                                 abs(entry - s.target) / max(atr, 1e-9), 0.5)
                rows.append({'time': b, 'id': s.id,
                             'family': getattr(s, 'family', 'MM'), 'dir': f,
                             'target': round(s.target, 5), 'price': round(entry, 5),
                             'score': q, 'mae': round(ex['mae'], 5),
                             'mfe': round(ex['mfe'], 5)})
    return rows
