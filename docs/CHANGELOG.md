# CHANGELOG — EA/Indicator parity project

Format: one entry per phase; EA trading behavior is unchanged throughout
(spec §20) unless stated.

## Phase 0 — audit EA and indicator parity

- Added `docs/INDICATOR_EA_PARITY_AUDIT.md`: architecture, strategy/mode/veto/
  input/phase parity matrices, mismatch list M1–M10, phased plan.
- Re-attached the working tree to `origin/main` (local copy had no `.git`;
  content was identical to tip `7de04ce`); fixed remote URL case.
- Baseline: all 16 Python suites green.

## Phase 1 — synchronize analysis and inputs

- `FM_Indicator.mq5`: 15 decision-affecting EA selection inputs mirrored with
  identical defaults (`InpStratMode/SingleStrategy`, 6× `InpUse*`, 4×
  `InpAuto*`, `InpApplyStructuralVeto`, `InpTradeProvisional`,
  `InpChaseATRMult`); `CStrategyRegistry` included + configured as in the EA.
- Analysis path untouched (byte-identical by construction).

## Phase 2 — synchronize strategy registry

- Indicator builds the EA candidate universe (`BuildCandidates` + registry
  `BuildFailedBO`) per closed bar with a DEBUG census. FAILED_BO needs only
  `res`+`cfg` — evaluable in indicator context, no isolation required.

## Phase 3 — synchronize candidate evaluation

- New shared contract `MQL5/Include/FM/ParityDecision.mqh` (`FMParityDecision`
  + `CParityBuilder::BuildUniverse/Build`): one code path for universe +
  `Select`/`SelectAuto` in both programs.
- `FM_EA.mq5` refactored onto the builder (mechanical, outputs identical);
  indicator fills `g_parity` from it.
- New mirrors `tests/parity_decision.py`, `tests/test_parity_build.py`
  (builder == legacy selection over 300 randomized trials × modes).

## Phase 4 — synchronize strategy selection modes

- Indicator `Decide()` runs on the registry selection (not score-max `best`);
  `FM_DECISION` label shows `action reason MODE STRAT [f=]`; SINGLE/MULTI/AUTO
  semantics now match the EA exactly.

## Phase 5 — synchronize veto and final signals

- Shared `CParityBuilder::DetectVeto` (EA refactored onto it, outputs
  identical); indicator mirrors veto + `LOW_RR` risk projection (strict,
  verbatim `Check`) + closed-bar intent projection (`From*` at `dctx.close`).
- `FM_DECISION` now shows the EA-mirror final: `BUY`/`SELL` (= EA `WOULD_*`)
  or `NO_TRADE` + `DECISION_VETO_*` / `SKIP_*` / `NO_SETUP`; `PARITY` DEBUG line.
- Locked as-is (documented, not fixed): WAIT never blocks `WOULD_`; `rrOK`
  epsilon vs strict risk gate; live-tick chase/side proxy divergence.
- New `tests/test_parity_final.py` (spec cases A–G).

## Phase 6 — add indicator visualization and diagnostics

- `FM_PARITY` detail label (`DEC/VETO/INTENT`, WAIT-visible, toggle
  `InpShowParityLabel`), `FM_P_ENTRY/STOP/TP` selection lines (toggle
  `InpShowParityLevels`, never stale), `InpDiagnosticMode` DEBUG dashboard.
- New `docs/INDICATOR_REFERENCE.md` (inputs, labels, buffers, diagnostics,
  signal meanings, known limitations).

## Phase 7 — add EA-indicator parity tests

- Indicator `InpExportParityCSV` writes per-bar `FM_parity.csv` under a
  normative column contract (`BAR,…,RESULT` via the comparator).
- New `tests/parity_compare.py` (EA-log parser incl. veto-quiet synthesis,
  CSV reader, bar-joined comparator) + `tests/test_parity_harness.py`
  (case H determinism/append-stability, case I tuning/mask sensitivity,
  contract + parser + comparator tests).
- New `docs/EA_INDICATOR_PARITY_TESTING.md` (mirror + MT5-log workflows,
  mismatch reading guide). MT5 comparison run itself requires a terminal
  (operator step).

## Phase 8 — complete documentation and release preparation

- `README.md` (EA + mirror framing, install, presets note, status, doc links),
  `docs/CURRENT_STATE.md` (supersession note), `docs/TESTING.md` (parity
  oracles), this changelog.
- Known remaining work: MetaEditor compile + Strategy Tester runs + first live
  Workflow-B comparison (no terminal in this environment); per-historical-bar
  parity visualization (DEBUG/CSV only for now).
