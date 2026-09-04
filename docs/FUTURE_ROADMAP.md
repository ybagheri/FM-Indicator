# FUTURE ROADMAP — FM Indicator → Brooks-style bar-by-bar engine

## Status (read this first)

Implementation in this repo is COMPLETE: v1 core, v1.1 fixes, v1.2 families,
v2 research tooling, bar-by-bar Phases 0–8, and the LTF confirm overlay —
97 Python mirror tests, all passing. Nothing below adds indicator features;
every remaining item is validation or execution. Work through
`Next moves (ordered)` top to bottom; each item names its owner, its
acceptance check, and what it unblocks.

## Next moves (ordered)

1. **MetaEditor compile (owner: human on Windows; unblocks everything).**
   Copy `MQL5/Indicators/FM_Indicator.mq5` + `MQL5/Include/FM/*.mqh` to the
   terminal, compile (F7). Accept: 0 errors, 0 warnings; attach to a chart,
   confirm objects draw. Linux CI cannot do this (no `metaeditor.exe`/`wine`;
   it runs the Python mirror + delimiter scan instead).
2. **Strategy Tester visual run (owner: human; unblocks 3).** Run majors/H1
   (plus M1 with `FM-M1-Scalp.set`), keep a screenshot log. Accept: no
   runtime errors, DEBUG logs show bar/pullback/state/BO/MTR/plan/decision
   lines, `FM_DECISION` label updates per closed bar.
3. **Walk-forward review (owner: human/analyst; unblocks any live use).**
   Enable `InpExportCSV` in tester runs (`FM-Families.set` for per-family
   data), review MAE/MFE per family via `backtest_run`, then parameter
   sensitivity / Monte Carlo notes. Accept: written review noting whether the
   inverse-MM anchor (§5 SPEC, weakest point) and the `2.0×ATR` BO/reversal
   objectives survive contact with real data. NOTHING in this repo may be
   called validated before this step.
4. **v3 EA (owner: separate repo; blocked on 3).** Reuse
   `CFMEngine::ActiveSnapshots()` + DATA buffers; optimization framework +
   walk-forward analysis live there. This indicator repo stays
   execution-free — no orders, no auto-trading PRs accepted here.

## Version map (three numbering axes — do not confuse them)

- **Indicator `#property version` (currently 1.30):** the MT5 program
  version stamped in `FM_Indicator.mq5`. Cosmetic release counter.
- **SPEC generations v1 / v1.1 / v1.2 / v2:** capability layers of the FM
  core (`SYSTEMATIC_SPECIFICATION.md`): v1 Leg1=Leg2 + inverse + states;
  v1.1 correctness fixes; v1.2 families + wedge + score; v2 research tooling
  (MTF/LTF/CSV/MAE-MFE/backtest).
- **Phases 0–8:** the bar-by-bar expansion track (this file): Phase 0 audit,
  Phase 1 bar foundation, Phases 2–6 pullback/state/BO/MTR/FM-plan engines,
  Phase 7 general catalog, Phase 8 decision engine.

## Phase 0 (audit) — DONE
- [x] Repo/history/code/docs audit (v1.2+v2 preserved, committed `206501b`).

## Phase 1 (bar-by-bar foundation) — DONE (this milestone)
- [x] `BROOKS_CONCEPTS.md` knowledge base (Brooks vs proxy vs implementation).
- [x] `BAR_BY_BAR_ENGINE.md` normative spec + `MARKET_CONTEXT.md` plan.
- [x] `CBarAnalyzer` (MQL5, pure/read-only) + `bar_analyzer.py` mirror + 7 tests.
- [x] Read-only indicator hook (DEBUG log, never gates FM state machine).

## v1.1 (correctness) — DONE
- [x] Follow-through 1-bar delay path (signal on newest bar never confirms
  same-bar with `RequireFollowThrough`).
- [x] `IsSignalBar` newest-bar fix (was `c<2`, now `c>=1`).
- [x] Inverse-MM anchor made symmetric (far side of failure bar, both legs).
- [ ] MetaEditor compile + Strategy Tester visual run on majors/H1 (user-side);
  screenshot log.

## v1.2 (families) — DONE (code + mirror + tests; live review pending)
- [x] `CRangeHeightMM`, `CChannelMM`, `CGapMM` (flag-gated, default OFF).
- [x] Wedge/3-push as first-class exhaustion (`InpMinPushes`, `InpUseWedgeExhaustion`).
- [x] Signal scoring 0–100 display-only (`InpShowScore`, `S=` in labels).
- [ ] Walk-forward review per family (MAE/MFE via CSV/backtest) on real data.

## v2 (research tooling) — DONE (tooling; analysis pending)
- [x] Historical signal export (CSV) + `backtest_run` + MAE/MFE harness.
- [x] Multi-timeframe read-only overlay (`InpMTFTrendTFMinutes`, LOG_ONLY).
- [x] Lower-TF entry confirmation (`InpLTFMinutes` + `LTFBias` via shared
  `TFBias` helper + AGREE/DISAGREE/NEUTRAL vs Phase-8 direction, LOG_ONLY) +
  mirror (`ltf_bias`/`ltf_confirm`) + 3 tests.
- [x] EA foundation: `CFMEngine::ActiveSnapshots()` + DATA buffers.
- [ ] Parameter sensitivity / Monte Carlo notes from exported data.

## v3 (EA foundation, separate repo)
- Signal engine reuse (`CFMEngine::ActiveSnapshots()` + DATA buffers) by an EA
  in a separate repo; indicator repo stays execution-free.
- Optimization framework + walk-forward analysis.

## Phases 2–8 (bar-by-bar expansion, planned)
- [x] Phase 2: H1/H2/L1/L2 pullback counter + doubles (DT/DB) on confirmed swings
  (`PULLBACK_PATTERNS.md` + `PullbackPatterns.mqh` + mirror + 10 tests, read-only hook).
- [x] Phase 3: market-state engine (TREND/CHANNEL/RANGE/BREAKOUT_MODE scores)
  (`MARKET_STATE.md` + `MarketState.mqh` + mirror + 9 tests, read-only hook).
- [x] Phase 4: breakout + generalized failed-breakout/trap engine
  (`BREAKOUT_ENGINE.md` + `BreakoutEngine.mqh` + mirror + 9 tests, read-only hook).
- [x] Phase 5: pullback/reversal/MTR + dedicated exhaustion analyzer
  (`REVERSAL_ENGINE.md` + `ReversalEngine.mqh` + mirror + 10 tests, read-only hook).
- [x] Phase 6: FM as setup-engine module (entry/stop/target/R per setup)
  (`SETUP_ENGINE.md` + `SetupEngine.mqh` + mirror + 10 tests, read-only hook).
- [x] Phase 7: general setup catalog — trend-pullback (H1/H2/L1/L2), swing +
  micro doubles, breakout FOLLOW/PENDING, MTR MINOR/MAJOR — with
  entry/stop/objective/R/score + best-candidate contest incl. FM plans
  (`GENERAL_SETUPS.md` + `GeneralSetups.mqh` + mirror + 10 tests, read-only hook).
- [x] Phase 8: decision engine (BUY/SELL/WAIT/NO_TRADE + machine-checkable
  reasons per the §4 no-trade doctrine) + `FM_DECISION` label
  (`DECISION_ENGINE.md` + `DecisionEngine.mqh` + mirror + 10 tests,
  read-only hook; never gates FM, never trades).

Bar-by-bar expansion Phases 1–8 COMPLETE (97 Python tests, all pass).
Stale-doc audit post-Phase-8: RESEARCH row 4, PULLBACK §6, MARKET_CONTEXT §3,
MARKET_STATE §7, CONCEPTS H1/H2 corrected to built-status (records retained).
Remaining: MetaEditor compile + Strategy Tester visual run (user-side);
walk-forward/parameter review from exported CSV data; v3 EA in a separate
repo (this indicator repo stays execution-free).

Non-goals for this repo: auto-trading, profitability claims, repainted-history
"perfect signals", per-tick CONFIRMED states.
