"""market_state.py — Python mirror of docs/MARKET_STATE.md + MarketState.mqh.

Indexing: oldest-first (index 0 = OLDEST). Detection consumes closed bars only;
`last_closed` is the newest closed index; analysis point `idx` (normally ==
last_closed) plays the MT5-shift-b role. Field-for-field identical semantics
to MQL5 (float tol 1e-9, pcts exact ints summing to 100, winner exact).
"""
import math

from bar_analyzer import pair_overlap


STATES = ["BULL_TREND", "BEAR_TREND", "BULL_CHANNEL",
          "BEAR_CHANNEL", "TRADING_RANGE", "BREAKOUT_MODE"]


class StateCfg:
    def __init__(self, state_lookback=20, state_overlap_bars=10, enable=True,
                 strong_close_pct=0.70, min_body=0.30, overlap_ratio=0.50,
                 pressure_lookback=10):
        self.state_lookback = state_lookback
        self.state_overlap_bars = state_overlap_bars
        self.enable = enable
        self.strong_close_pct = strong_close_pct
        self.min_body = min_body
        self.overlap_ratio = overlap_ratio
        self.pressure_lookback = pressure_lookback


def _unknown():
    return dict(valid=False, state="UNKNOWN", pct=[0] * 6,
                trend=0.0, range=0.0, chop=0.0, pressure=0.0,
                tight=False, max_raw=0.0)


def _clamp01(x):
    return min(max(x, 0.0), 1.0)


def _clamp11(x):
    return min(max(x, -1.0), 1.0)


def trend_gap(bars, idx):
    """Raw EMA20−EMA50 gap over closes[0..idx]; <50 closes → 0.0."""
    if idx < 0 or idx >= len(bars):
        return 0.0
    if idx + 1 < 50:
        return 0.0
    k20, k50 = 2.0 / 21.0, 2.0 / 51.0
    e20 = e50 = bars[0]['c']
    for i in range(1, idx + 1):
        e20 = bars[i]['c'] * k20 + e20 * (1.0 - k20)
        e50 = bars[i]['c'] * k50 + e50 * (1.0 - k50)
    return e20 - e50


def _tightening(bars, idx, last_closed):
    # Same predicate as CBarAnalyzer tightening: range[idx] < median of the
    # 4 older closed bars; needs 5 bars (idx >= 4), else False.
    if idx < 4 or idx > last_closed or idx >= len(bars):
        return False
    w = sorted(bars[i]['h'] - bars[i]['l'] for i in range(idx - 4, idx))
    med = (w[1] + w[2]) * 0.5
    return (bars[idx]['h'] - bars[idx]['l']) < med


def _pressure(bars, idx, last_closed, cfg):
    L = max(1, cfg.pressure_lookback)
    pb = pe = 0
    for i in range(idx, max(-1, idx - L), -1):
        if i < 0 or i > last_closed or i >= len(bars):
            continue
        r = bars[i]
        rg = r['h'] - r['l'] or 1e-9
        dd = 1 if r['c'] > r['o'] else (-1 if r['c'] < r['o'] else 0)
        cp = (r['c'] - r['l']) / rg
        br = abs(r['c'] - r['o']) / rg
        if dd > 0 and cp >= cfg.strong_close_pct and br >= cfg.min_body:
            pb += 1
        if dd < 0 and (1.0 - cp) >= cfg.strong_close_pct and br >= cfg.min_body:
            pe += 1
    return pb, pe


def analyze(bars, idx, last_closed, atr, cfg=None):
    cfg = cfg or StateCfg()
    if not cfg.enable:
        return _unknown()
    if idx < 0 or idx > last_closed or idx >= len(bars):
        return _unknown()
    if not atr or atr <= 0:
        return _unknown()
    L = max(10, cfg.state_lookback)
    W = max(5, cfg.state_overlap_bars)
    if idx + 1 < max(L + 1, W + 1, 6):
        return _unknown()

    ts = _clamp11(trend_gap(bars, idx) / atr / 2.0)
    w0 = max(0, idx - L + 1)
    rs = (max(b['h'] for b in bars[w0:idx + 1])
          - min(b['l'] for b in bars[w0:idx + 1])) / atr
    o0 = max(0, idx - W + 1)
    pairs = [i for i in range(o0 + 1, idx + 1)]
    chop = (sum(1 for i in pairs
                if pair_overlap(bars[i], bars[i - 1]) >= cfg.overlap_ratio)
            / len(pairs)) if pairs else 0.0
    pb, pe = _pressure(bars, idx, last_closed, cfg)
    PL = max(1, cfg.pressure_lookback)
    pr = (pb - pe) / PL
    tight = _tightening(bars, idx, last_closed)

    bull_t, bear_t = _clamp01(ts), _clamp01(-ts)
    bull_p, bear_p = _clamp01(pr), _clamp01(-pr)
    expand = _clamp01((rs - 3.0) / 3.0)
    compact = _clamp01((6.0 - rs) / 4.0)
    balance = 1.0 - abs(pr)
    raws = [bull_t + bull_p + expand,
            bear_t + bear_p + expand,
            bull_t + chop + compact,
            bear_t + chop + compact,
            compact + chop + balance,
            (1.0 if tight else 0.0) + compact + chop]
    out = _unknown()
    out.update(valid=True, trend=ts, range=rs, chop=chop,
               pressure=pr, tight=tight)
    s = sum(raws)
    if s <= 0:
        out['state'] = "TRANSITION"
        return out
    exact = [r / s * 100.0 for r in raws]
    pct = [int(math.floor(e)) for e in exact]
    frac = [e - p for e, p in zip(exact, pct)]
    for _ in range(100 - sum(pct)):
        bi = max(range(6), key=lambda i: (frac[i], -i))
        pct[bi] += 1
        frac[bi] = -1.0
    bi = max(range(6), key=lambda i: (raws[i], -i))
    out.update(pct=pct, max_raw=raws[bi],
               state=STATES[bi] if raws[bi] >= 1.0 else "TRANSITION")
    return out
