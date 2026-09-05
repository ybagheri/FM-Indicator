# EA ↔ Indicator Parity Testing (Phase 7)

Deterministic methodology for proving (or diagnosing) behavioral equivalence.
Two workflows share one result contract.

## 1. Result contract

Every compared bar emits exactly:

```text
BAR, EA_SIGNAL, IND_SIGNAL, EA_STRATEGY, IND_STRATEGY,
EA_SCORE, IND_SCORE, EA_RR, IND_RR, EA_VETO, IND_VETO, RESULT
```

`RESULT` is `MATCH` or the first mismatch in column order:
`MISMATCH_SIGNAL → _STRATEGY → _SCORE → _RR → _VETO`.
RR compares with tolerance `5e-3` (EA log prints `R=%.2f`, CSV stores 4 decimals).

## 2. Workflow A — Python mirrors (runs anywhere, CI-friendly)

```bash
python tests/test_parity_build.py    # Phase-3 builder equivalence (300 randomized trials × modes)
python tests/test_parity_final.py    # cases A–G final-signal semantics
python tests/test_parity_harness.py  # case H determinism + append-stability,
                                     # case I tuning/enable-mask sensitivity,
                                     # CSV contract, EA-log parser, comparator
```

Plus the 16 pre-existing engine suites (`tests/test_*.py`), all green.

Case map: A BUY / B SELL / C veto (+bypass) / D insufficient RR (+boundary
`rMult == minRR` strict gate) / E provisional gating / F chase + wrong-side +
documented close-vs-live divergence / G no-setup + WAIT-does-not-block /
H determinism + history-append stability / I AUTO-tuning + enable-mask flips.
Every case asserts EA path == indicator path at equal prices.

## 3. Workflow B — MT5 logs (Windows terminal required)

Preconditions (see `docs/BACKTESTING_GUIDE.md`): identical symbol, timeframe,
date range, history data, and input values on both sides; EA in
`TRADE_ANALYSIS_ONLY` or `TRADE_PAPER` (no live orders needed for parity);
indicator with `InpExportParityCSV=true` (+ `LOG_DEBUG` for `REGISTRY/PARITY/
DIAG` lines); same strategy mode + enable mask + AUTO tuning + veto flag.

1. Run the EA (Strategy Tester or chart) over range R; save the Experts log.
2. Run the indicator over the same range R; collect `MQL5/Files/FM_parity.csv`.
3. Parse + compare (stdlib only):

```bash
python -c "
from tests.parity_compare import parse_ea_log, read_ind_csv, compare
ea, _ = parse_ea_log(open('ea_tester.log').read())
ind = read_ind_csv(open('FM_parity.csv').read())
rep = compare(ea, ind)
bad = [r for r in rep if r['RESULT'] != 'MATCH']
print(len(rep), 'bars,', len(bad), 'mismatches')
for r in bad[:50]: print(r)
"
```

4. Every mismatch is diagnosable: the bar's `DIAG` dashboard (candidates +
scores + selection + veto + intent) vs the EA's `[FM_EA] …` + `EXPLAIN …` lines.

## 4. Reading mismatches

- `MISMATCH_SIGNAL` with `SKIP_LATE_ENTRY`/`SKIP_WRONG_SIDE` on the EA side only:
  expected live-tick divergence (EA gates at next-tick Ask/Bid, indicator
  projects at the closed-bar close). Confirm the bar was fast; not a bug.
- `MISMATCH_VETO`: veto trigger differs — check inputs (`InpApplyStructuralVeto`,
  state/BO inputs) and history depth (trap-repeat scans 20 bars).
- `MISMATCH_STRATEGY/SCORE/RR`: check mode, enable mask, AUTO tuning, and that
  both sides loaded the same `.set` preset (presets bind by name in both).
- EA-missing bars with an indicator veto row: normal (vetoed selections print no
  EA selection line); the harness synthesizes the EA side as vetoed NO_TRADE and
  expects `MATCH` on equal veto reasons. EA veto census lines print every 25th
  veto — absence of a veto line for an isolated vetoed bar is expected.
- Account-dependent EA rejections (`HIGH_SPREAD`, `MAX_*`, `HALT_*`, `BLOCK_*`,
  `EXEC_*`) have no indicator counterpart by design (§6 of
  `docs/INDICATOR_REFERENCE.md`); compare the analytical `WOULD_*`/`SKIP_*`
  core, and review execution suffixes separately.

## 5. What this environment verified

All Workflow-A suites pass (19/19 files). Workflow B was specified and its
parser/comparator tested on synthetic logs, but no MetaEditor/terminal exists
in this Linux environment — the first real MT5 comparison run is an explicit
operator step (see `docs/BACKTESTING_GUIDE.md` for the terminal procedure).
