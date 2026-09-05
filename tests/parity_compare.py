"""parity_compare.py — Phase-7 EA<->Indicator parity harness (stdlib only).

Column contract (normative — mirrors ExportParityRow FileWrite order):
  HEADER = bar,ind_signal,ind_why,mode,strategy,score,r_mult,auto_final,
           veto,intent,dec_action,dec_reason

Workflows:
  MIRROR: rows come from the python mirrors (parity_decision.final_signal).
  MT5:    EA rows parsed from Strategy Tester `[FM_EA]` log lines
          (parse_ea_log); indicator rows read from FM_parity.csv
          (read_ind_csv); compare() joins on BAR and reports per-column
          RESULT. See docs/EA_INDICATOR_PARITY_TESTING.md.
"""
import csv
import io
import re

HEADER = ["bar", "ind_signal", "ind_why", "mode", "strategy", "score",
          "r_mult", "auto_final", "veto", "intent", "dec_action",
          "dec_reason"]

RESULT_HEADER = ["BAR", "EA_SIGNAL", "IND_SIGNAL", "EA_STRATEGY",
                 "IND_STRATEGY", "EA_SCORE", "IND_SCORE", "EA_RR",
                 "IND_RR", "EA_VETO", "IND_VETO", "RESULT"]

EA_LINE = re.compile(
    r"\[FM_EA\] (\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) (BUY|SELL) (\w+) "
    r"entry=(\S+) stop=(\S+) obj=(\S+) score=(\d+)( PROV)? R=(\S+) "
    r"cands=(\d+) final=(-?\d+) sig=(-?\d+) risk=(\S+) vol=(\S+) ?(.*)")

EA_VETO = re.compile(
    r"\[FM_EA\] (\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) (\w+) veto=(DECISION_VETO_\w+)")


def ea_signal_from_tail(direction, tail):
    """Analytical EA signal from the intent tail (halt/block suffixes describe
    execution gating, not the analytical decision — recorded, not compared)."""
    tok = tail.strip().split(" ")[0] if tail.strip() else ""
    if tok == "WOULD_BUY":
        return ("BUY", tok)
    if tok == "WOULD_SELL":
        return ("SELL", tok)
    if tok.startswith("SKIP_"):
        return ("NO_TRADE", tok)
    if tok == "INTENT_PENDING_PHASE":
        return ("NO_TRADE", "RISK_REJECT")
    return ("NO_TRADE", tok if tok else "UNKNOWN_TAIL")


def parse_ea_log(text):
    """Returns (rows_by_bar, veto_by_bar). Rows carry RESULT_HEADER EA_* fields."""
    rows = {}
    vetos = {}
    for m in EA_VETO.finditer(text):
        vetos[m.group(1)] = m.group(3)
    for m in EA_LINE.finditer(text):
        (bar, direction, strat, _e, _s, _o, score, _prov, rmult, _cands,
         final, _sig, risk, _vol, tail) = m.groups()
        sig, why = ea_signal_from_tail(direction, tail)
        if why == "RISK_REJECT":
            why = "RISK_" + risk
        rows[bar] = {"BAR": bar, "EA_SIGNAL": sig,
                     "EA_STRATEGY": strat if sig != "NO_TRADE" else strat,
                     "EA_SCORE": int(score), "EA_RR": float(rmult),
                     "EA_VETO": vetos.get(bar, "-"),
                     "EA_WHY": why, "EA_FINAL": int(final)}
    # Veto-quiet bars: a vetoed selection prints no selection line (only the
    # sparse veto census). Synthesize the EA side as vetoed NO_TRADE so the
    # comparator can verify the indicator shows the same veto.
    for bar, veto in vetos.items():
        if bar not in rows:
            rows[bar] = {"BAR": bar, "EA_SIGNAL": "NO_TRADE",
                         "EA_STRATEGY": "?", "EA_SCORE": "?",
                         "EA_RR": "?", "EA_VETO": veto,
                         "EA_WHY": veto, "EA_FINAL": -1}
    return rows, vetos


def read_ind_csv(text):
    """Parse FM_parity.csv content. Returns dict bar -> row."""
    rows = {}
    rdr = csv.DictReader(io.StringIO(text))
    for r in rdr:
        rows[r["bar"]] = r
    return rows


def _eq_rr(a, b, tol=5e-3):
    try:
        return abs(float(a) - float(b)) <= tol
    except (TypeError, ValueError):
        return str(a) == str(b)


def compare(ea_rows, ind_rows):
    """Join on BAR. Returns list of RESULT_HEADER dicts, sorted by BAR."""
    out = []
    for bar in sorted(set(ea_rows) | set(ind_rows)):
        e = ea_rows.get(bar, {})
        i = ind_rows.get(bar, {})
        r = {"BAR": bar,
             "EA_SIGNAL": e.get("EA_SIGNAL", "?"),
             "IND_SIGNAL": i.get("ind_signal", "?"),
             "EA_STRATEGY": e.get("EA_STRATEGY", "?"),
             "IND_STRATEGY": i.get("strategy", "?"),
             "EA_SCORE": e.get("EA_SCORE", "?"),
             "IND_SCORE": i.get("score", "?"),
             "EA_RR": e.get("EA_RR", "?"),
             "IND_RR": i.get("r_mult", "?"),
             "EA_VETO": e.get("EA_VETO", "?"),
             "IND_VETO": i.get("veto", "?"),
             "RESULT": "MATCH"}
        if (r["EA_SIGNAL"] == "NO_TRADE" and r["IND_SIGNAL"] == "NO_TRADE"
                and r["EA_VETO"] == r["IND_VETO"]
                and r["EA_VETO"] not in ("?", "-")):
            # veto-quiet agreement (EA prints no selection line when vetoed)
            pass
        elif r["EA_SIGNAL"] != r["IND_SIGNAL"]:
            r["RESULT"] = "MISMATCH_SIGNAL"
        elif (r["EA_SIGNAL"] == "NO_TRADE" and r["IND_SIGNAL"] == "NO_TRADE"
                and r["EA_VETO"] != r["IND_VETO"]
                and (r["EA_VETO"] not in ("?", "-")
                     or r["IND_VETO"] not in ("?", "-"))):
            r["RESULT"] = "MISMATCH_VETO"
        elif r["EA_STRATEGY"] != r["IND_STRATEGY"]:
            r["RESULT"] = "MISMATCH_STRATEGY"
        elif str(r["EA_SCORE"]) != str(r["IND_SCORE"]):
            r["RESULT"] = "MISMATCH_SCORE"
        elif not _eq_rr(r["EA_RR"], r["IND_RR"]):
            r["RESULT"] = "MISMATCH_RR"
        elif r["EA_VETO"] != r["IND_VETO"]:
            r["RESULT"] = "MISMATCH_VETO"
        out.append(r)
    return out


def format_parity_row(bar, signal, why, mode, strategy, has_trade, score,
                      r_mult, auto_final, veto, intent, dec_action,
                      dec_reason):
    """Mirror of ExportParityRow field order/defaults ("-" markers, -1 score
    when no trade). Returns HEADER-ordered dict."""
    return {"bar": bar, "ind_signal": signal, "ind_why": why, "mode": mode,
            "strategy": strategy,
            "score": score if has_trade else -1,
            "r_mult": r_mult if has_trade else 0.0,
            "auto_final": auto_final, "veto": veto if veto else "-",
            "intent": intent if intent else "-",
            "dec_action": dec_action, "dec_reason": dec_reason}


def rows_to_csv(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=HEADER)
    w.writeheader()
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


if __name__ == "__main__":
    print("harness import OK")
