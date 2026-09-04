# CURRENT STATE — Phase-20 audit (2026-09-04, HEAD `7009511`)

> Verified by inspection this session (git + SHA256 + re-run tests + agent
> logs). Nothing below is carried over on trust. Labels per project rule:
> UNIT TEST vs MT5 BACKTEST vs NOT TESTED.

## Current Git Commit

- HEAD: `7009511` "test: record Strategy Tester smoke runs (EURUSD H1+M1,
  0 errors)", branch `main`, tracking `origin/main`, working tree CLEAN.
- 22 commits total. Last three: smoke-run records (`7009511`), warning-43
  fix (`eeabb48`), prior main (`6af0a4f`).
- No `reports/` directory. No EA in repo. No screenshots committed
  (forbidden by `.gitignore`).

## Indicator Status

- `MQL5/Indicators/FM_Indicator.mq5` v1.30 + 20 headers under
  `MQL5/Include/FM/`. Provenance verified: SHA256 of all 21 repo files ==
  terminal data-folder copies (Alpari MT5_2 `...AF19ECCF...`).
- MetaEditor compile (build 6090): **0 errors, 0 warnings** (warning-43
  `flow int→double` fixed in `eeabb48`, re-verified).
- Behavior: FM state machine
  `PROJECTED→POTENTIAL→DEVELOPING→CONFIRMED→COMPLETED (→INVALIDATED)`,
  max one transition per closed bar; Phases 1–8 layers read-only
  (DEBUG logs + `FM_DECISION` label), never gating FM; DATA buffers
  `Target/Potential/Developing/Confirmed` frozen at issuing bar.

## EA Status

- **No EA exists in the repo.** The only EA on record is `FM_SmokeTest.mq5`
  v1.00, which lives SOLELY in the terminal `MQL5/Experts/` folder: attaches
  the indicator via `iCustom` (defaults) and reads the 4 DATA buffers per
  new bar. It places no orders. It must NOT be committed here (indicator
  repo stays execution-free; the trading EA belongs to Phase 23+ design).

## Analysis Engine Status (all DONE, read-only unless noted)

| Layer | MQL5 | Mirror | Tests |
|---|---|---|---|
| v1 core FM (swings/legs/MM/states/buffers/viz/alerts) | `Swings/MeasuredMove/FMEngine/Visualizer/Alerts` | `fm_engine.py` | 19 |
| v1.1 fixes (FT delay, newest-bar signal, symmetric inv anchor) | `Confirmation/MeasuredMove` | same | incl. |
| v1.2 families + wedge + score | `MeasuredMove/Confirmation` | same | incl. |
| v2 research (MTF/LTF/CSV/MAE-MFE/backtest) | indicator hooks | same | 3 LTF |
| Phase 1 bars | `BarAnalyzer` | `bar_analyzer.py` | 7 |
| Phase 2 pullbacks/doubles | `PullbackPatterns` | `pullback_patterns.py` | 10 |
| Phase 3 market state | `MarketState` (+`Context`) | `market_state.py` | 9 |
| Phase 4 breakout/trap | `BreakoutEngine` | `breakout.py` | 9 |
| Phase 5 reversal/exhaustion/MTR | `ReversalEngine` | `reversal.py` | 10 |
| Phase 6 FM setup plans | `SetupEngine` | `setup_engine.py` | 10 |
| Phase 7 general catalog + best | `GeneralSetups` | `general_setups.py` | 10 |
| Phase 8 decision + reasons | `DecisionEngine` | `decision.py` | 10 |
| **Total UNIT TEST** | | | **97, all pass (re-run 2026-09-04)** |

Reuse surface for the EA (already exists, no refactor needed to START):
`CFMEngine::ActiveSnapshots(FMSetupSnapshot[])` + `GetSetup/ActiveCount`,
`CGeneralSetups::SelectBest`, `CSetupPlanner::Plan`, `CDecisionEngine::Decide`,
DATA buffers. Gap: orchestration (rates copy → ATR → 8 layers → projections)
currently lives inline in the indicator's `OnCalculate`; an EA would duplicate
that sequence. → Phase 21: extract a shared `CFMAnalysis` facade (MINIMUM
refactor, indicator behavior byte-identical, mirror-tested).

## Testing Status

- UNIT TEST: 97/97 pass (re-run this session).
- MT5 BACKTEST (smoke only, no orders): 2 runs, both pass, 0 errors —
  detail in `docs/MT5_TESTING_STATUS.md`.
- NOT TESTED: visual chart behavior, repaint-vs-history comparison,
  CSV walk-forward, calibration, optimization, multi-symbol/TF, any live/demo.

## Known Bugs

- None open. Last bug (warning-43 narrowing) fixed and verified.
- Flaky infra (not product): local test agent died once mid-run
  (`MetaTester 5 stopped`); recovered by terminal restart. `ShutdownTerminal`
  did not close the terminal; killed manually.

## Known Limitations (see `LIMITATIONS.md`)

Inverse-MM anchor unvalidated; BO/reversal objectives are fixed `2.0×ATR`
proxies; context/MTF/LTF/decision read-only by design; per-bar tags log-only;
no `CSupportResistanceEngine` class (swings+range+BO+targets serve as S/R);
scores are NOT probabilities; no statistical validation.

## Completed Phases

Phase 0 audit, Phase 1–8 bar-by-bar engine, v1/v1.1/v1.2/v2, MT5 compile 0/0,
MT5 smoke runs (H1+M1). Docs: full §31 set + `ROADMAP.md`.

## Incomplete Phases

Visual tester run, walk-forward, v3 EA (now superseded by this EA track:
Phases 21+), calibration, advanced MTF, ML (not planned).

## Recommended Next Phase

**Phase 21 — Shared Analysis Contract**: extract `CFMAnalysis` facade from
`OnCalculate` (indicator calls it; behavior unchanged; UNIT TEST parity),
then Phase 22 strategy registry, Phase 23 EA skeleton (ANALYSIS_ONLY first).

## EA Gap Analysis (no refactor without stated reason)

- Current design: `FM_Indicator.mq5::OnCalculate` owns the pipeline
  (rates copy → `CATR` → 8 read-only layers → swings → projections →
  `CFMEngine::Update` → buffers → viz → alerts). All engines are stateless
  static calls except `CSwingDetector`/`CFMEngine`/`CATR`/`CMarketData`.
- Problem: an EA `#include`-ing the headers must re-implement that exact
  call order + new-bar gating; two copies of orchestration will drift.
- Why refactor is necessary: single-source orchestration is the precondition
  for §5 (one engine, three adapters). Nothing else requires refactoring:
  engines, enums (`Defs.mqh`), snapshots, scores, and the decision layer are
  directly consumable.
- Proposed design (MINIMUM change): new `MQL5/Include/FM/Analysis.mqh`
  `class CFMAnalysis` with ` bool Update(const MqlRates &rates[], int total,
  CFMConfig &cfg, …) ` returning a result struct (swings, state, BO, MTR,
  FM snapshots, general-best, decision). Indicator's `OnCalculate` becomes a
  thin adapter (build rates → call → write buffers/viz/alerts). EA adapter
  (Phase 23) calls the same `Update` per new closed bar, then risk/execution.
- Migration plan: (1) move code verbatim, no logic edits; (2) Python mirror
  unchanged (already mirrors each layer); (3) prove byte-identical behavior:
  MT5 smoke-run edge counts (T-001/T-002) must reproduce exactly + 97 UNIT
  TESTS pass + 0/0 compile.
- Risk: LOW (mechanical move, verified by reproduction). Rejected alternative:
  EA-via-`iCustom` buffers only — keeps logic single-sourced but hides
  context/setup/reasons the EA must explain (§11); buffers stay as the
  third (Research/EA-light) adapter, not the primary one.

## Next Phases (tail of repo roadmap; full detail → `ROADMAP.md` in Phase 21)

- Phase 21: shared contract (`Analysis.mqh`), indicator as adapter, parity proof.
- Phase 22: strategy registry (ONLY genuinely implemented: FM fade, MM-continuation
  via general catalog, pullback H1/H2, BO follow/pending, failed-BO inverse,
  MTR major/minor, doubles) + SINGLE/MULTI/AUTO mode skeleton (ANALYSIS_ONLY).
- Phase 23: EA skeleton — new-bar gating, trade explanation records, no orders.
