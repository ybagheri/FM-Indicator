"""setup_engine.py — Python mirror of docs/SETUP_ENGINE.md + SetupEngine.mqh.

Pure function of (signal-bar OHLC, MM dir, target, B0, ATR, cfg).
Indexing: signal bar passed explicitly as a dict; hook-side time→shift
resolution is not part of the planner and not mirrored.
"""


class SetupCfg:
    def __init__(self, stop_buf=0.10, min_rr=1.0, enable=True,
                 tol_mult=0.25, over_mult=0.50):
        self.stop_buf = stop_buf
        self.min_rr = min_rr
        self.enable = enable
        self.tol_mult = tol_mult
        self.over_mult = over_mult


def _invalid(setup_id=0, family="REGULAR", provisional=True, shift=-1):
    return dict(valid=False, setup_id=setup_id, family=family, fade_dir=0,
                entry=0.0, stop=0.0, objective=0.0, risk=0.0, reward=0.0,
                r_mult=0.0, rr_ok=False, provisional=provisional,
                invalid_close=0.0, signal_shift=shift)


def plan(sig, mm_dir, target, b0, atr, setup_id=0, family="REGULAR",
         confirmed=True, shift=1, cfg=None):
    """FM setup plan (spec §4). sig: {'o','h','l','c'} of the signal bar."""
    cfg = cfg or SetupCfg()
    p = _invalid(setup_id, family, not confirmed, shift)
    p.update(objective=float(b0))
    if not cfg.enable:
        return p
    if mm_dir not in (+1, -1):
        return p
    if not atr or atr <= 0:
        return p
    tol = cfg.tol_mult * atr
    buf = cfg.stop_buf * atr
    over = cfg.over_mult * atr
    min_rr = min(5.0, max(0.25, cfg.min_rr))
    p['fade_dir'] = -mm_dir
    if mm_dir > 0:  # SELL fade of a bull MM
        p['entry'] = float(sig['l'])
        struct = max(sig['h'], target + tol)
        p['stop'] = struct + buf
        p['reward'] = p['entry'] - float(b0)
        p['risk'] = p['stop'] - p['entry']
        p['invalid_close'] = target + over
    else:  # BUY fade of a bear MM
        p['entry'] = float(sig['h'])
        struct = min(sig['l'], target - tol)
        p['stop'] = struct - buf
        p['reward'] = float(b0) - p['entry']
        p['risk'] = p['entry'] - p['stop']
        p['invalid_close'] = target - over
    if p['reward'] <= 0 or p['risk'] <= 0:
        return p
    p['r_mult'] = p['reward'] / p['risk']
    p['rr_ok'] = p['r_mult'] + 1e-9 >= min_rr
    p['valid'] = True
    return p
