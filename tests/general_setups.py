"""general_setups.py — Python mirror of docs/GENERAL_SETUPS.md + GeneralSetups.mqh.

Indexing: oldest-first (index 0 = OLDEST). Builders consume already-detected
signals plus explicit prices; hook-side window/EMA resolution is caller input
so the math stays pure and exactly mirrorable (float tol 1e-9).
"""


class GeneralCfg:
    def __init__(self, enable=True, tick_proxy=0.05, obj_mult=2.0,
                 stop_buf=0.10, min_rr=1.0, double_tol=0.25, retest_tol=0.25):
        self.enable = enable
        self.tick_proxy = tick_proxy
        self.obj_mult = obj_mult
        self.stop_buf = stop_buf
        self.min_rr = min_rr
        self.double_tol = double_tol
        self.retest_tol = retest_tol


def _none(setup_type="NONE"):
    return dict(valid=False, type=setup_type, dir=0, entry=0.0, stop=0.0,
                objective=0.0, risk=0.0, reward=0.0, r_mult=0.0, rr_ok=False,
                provisional=True, signal_bar=-1, ref_price=0.0, score=0)


def _finish(s, cfg):
    if s['reward'] <= 0 or s['risk'] <= 0:
        s['valid'] = False
        return s
    s['r_mult'] = s['reward'] / s['risk']
    s['rr_ok'] = s['r_mult'] + 1e-9 >= min(5.0, max(0.25, cfg.min_rr))
    s['valid'] = True
    return s


def build_pullback_bull(pb, sig_high, pb_stop, win_high, atr, cfg=None):
    cfg = cfg or GeneralCfg()
    s = _none("PULLBACK")
    s.update(dir=+1, ref_price=float(sig_high), signal_bar=pb.get('signal_bar', -1))
    if not cfg.enable or not pb.get('found'):
        return s
    if not atr or atr <= 0:
        return s
    tick = cfg.tick_proxy * atr
    buf = cfg.stop_buf * atr
    s['entry'] = float(sig_high) + tick
    s['stop'] = float(pb_stop) - buf
    s['objective'] = float(win_high)
    s['reward'] = s['objective'] - s['entry']
    s['risk'] = s['entry'] - s['stop']
    s['provisional'] = pb.get('legs', 1) < 2
    s['score'] = 70 if pb.get('legs', 1) >= 2 else 40
    return _finish(s, cfg)


def build_pullback_bear(pb, sig_low, pb_stop, win_low, atr, cfg=None):
    cfg = cfg or GeneralCfg()
    s = _none("PULLBACK")
    s.update(dir=-1, ref_price=float(sig_low), signal_bar=pb.get('signal_bar', -1))
    if not cfg.enable or not pb.get('found'):
        return s
    if not atr or atr <= 0:
        return s
    tick = cfg.tick_proxy * atr
    buf = cfg.stop_buf * atr
    s['entry'] = float(sig_low) - tick
    s['stop'] = float(pb_stop) + buf
    s['objective'] = float(win_low)
    s['reward'] = s['entry'] - s['objective']
    s['risk'] = s['stop'] - s['entry']
    s['provisional'] = pb.get('legs', 1) < 2
    s['score'] = 70 if pb.get('legs', 1) >= 2 else 40
    return _finish(s, cfg)


def build_double(d, trough, atr, cfg=None):
    cfg = cfg or GeneralCfg()
    s = _none("DOUBLE")
    if not cfg.enable or not d.get('found'):
        return s
    if not atr or atr <= 0:
        return s
    if d.get('dir') not in (+1, -1):
        return s
    tol = cfg.double_tol * atr
    buf = cfg.stop_buf * atr
    s['dir'] = d['dir']
    s['provisional'] = bool(d.get('micro', False))
    s['signal_bar'] = d.get('bar2', -1)
    s['ref_price'] = float(d['price2'])
    s['score'] = 30 if d.get('micro', False) else 60
    if d['dir'] < 0:  # double top → short
        top = max(d['price1'], d['price2'])
        s['entry'] = float(d['price2'])
        s['stop'] = top + tol + buf
        s['objective'] = float(trough)
        s['reward'] = s['entry'] - s['objective']
        s['risk'] = s['stop'] - s['entry']
    else:  # double bottom → long
        bot = min(d['price1'], d['price2'])
        s['entry'] = float(d['price2'])
        s['stop'] = bot - tol - buf
        s['objective'] = float(trough)
        s['reward'] = s['objective'] - s['entry']
        s['risk'] = s['entry'] - s['stop']
    return _finish(s, cfg)


def build_breakout(bo, close_b, atr, cfg=None):
    cfg = cfg or GeneralCfg()
    s = _none("BREAKOUT")
    if not cfg.enable or not bo.get('found'):
        return s
    if not atr or atr <= 0:
        return s
    if bo.get('dir') not in (+1, -1):
        return s
    if bo.get('outcome') not in ("FOLLOW", "PENDING"):
        return s
    buf = cfg.stop_buf * atr
    obj_d = cfg.obj_mult * atr
    s['dir'] = bo['dir']
    s['entry'] = float(close_b)
    s['signal_bar'] = bo.get('bo_bar', -1)
    s['ref_price'] = float(bo.get('ref_price', 0.0))
    s['provisional'] = bo['outcome'] == "PENDING"
    base = 70 if bo['outcome'] == "FOLLOW" else 40
    if bo.get('trap', False):
        base -= 20
    s['score'] = max(0, base)
    if bo['dir'] > 0:
        s['stop'] = s['ref_price'] - buf
        s['objective'] = s['entry'] + obj_d
        s['reward'] = s['objective'] - s['entry']
        s['risk'] = s['entry'] - s['stop']
    else:
        s['stop'] = s['ref_price'] + buf
        s['objective'] = s['entry'] - obj_d
        s['reward'] = s['entry'] - s['objective']
        s['risk'] = s['stop'] - s['entry']
    return _finish(s, cfg)


def build_reversal(rv, close_b, ema_b, atr, cfg=None):
    cfg = cfg or GeneralCfg()
    s = _none("REVERSAL")
    if not cfg.enable or not rv.get('found'):
        return s
    if not atr or atr <= 0:
        return s
    if rv.get('dir') not in (+1, -1):
        return s
    buf = cfg.stop_buf * atr
    tol_r = cfg.retest_tol * atr
    obj_d = cfg.obj_mult * atr
    s['dir'] = rv['dir']
    s['entry'] = float(close_b)
    s['signal_bar'] = -1
    s['ref_price'] = float(ema_b)
    s['provisional'] = rv.get('verdict') != "MAJOR"
    s['score'] = 80 if rv.get('verdict') == "MAJOR" else 40
    s['stop'] = float(ema_b) - rv['dir'] * (tol_r + buf)
    s['objective'] = s['entry'] + rv['dir'] * obj_d
    s['reward'] = rv['dir'] * (s['objective'] - s['entry'])
    s['risk'] = rv['dir'] * (s['entry'] - s['stop'])
    return _finish(s, cfg)


_TYPE_ORDER = {"PULLBACK": 1, "DOUBLE": 2, "BREAKOUT": 3, "REVERSAL": 4,
               "FM_FADE": 5}


def select_best(setups):
    """Hook-side selection: max score; ties → lowest type order, then lowest
    (most recent, oldest-first largest) ... mirror of MQL5 SelectBest.

    NOTE on signal_bar tie-break: MQL5 uses MT5 shifts (most recent = lowest
    shift); oldest-first uses most recent = largest index. To stay identical
    under the index mapping (shift = last_closed - idx), the mirror compares
    most-recent-wins via the largest idx. MQL5 `signalBar < best` (smaller
    shift = newer) ↔ mirror `signal_bar > best` (larger idx = newer).
    """
    best = -1
    for i, s in enumerate(setups):
        if not s.get('valid'):
            continue
        if best < 0:
            best = i
            continue
        if s['score'] > setups[best]['score']:
            best = i
            continue
        if s['score'] < setups[best]['score']:
            continue
        if _TYPE_ORDER.get(s['type'], 99) < _TYPE_ORDER.get(setups[best]['type'], 99):
            best = i
            continue
        if _TYPE_ORDER.get(s['type'], 99) > _TYPE_ORDER.get(setups[best]['type'], 99):
            continue
        if s.get('signal_bar', -1) > setups[best].get('signal_bar', -1):
            best = i
    return best
