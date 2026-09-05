# INDICATOR ↔ EA PARITY AUDIT — Phase 0 (2026-09-05)

> Inspected locally at `E:\FM-Indicator` + remote `https://github.com/ybagheri/FM-indicator`.
> No assumptions from filenames alone — every claim below was read in code.
> Do not start implementation until this audit is reviewed.

## 0. Repo / Git status (important anomaly)

- Local `E:\FM-Indicator` is **NOT a git repository** (no `.git/`; verified with
  PortableGit 2.49.0 `git status` → `fatal: not a git repository`).
  `git` is not on PATH; only `C:\Users\bagheri\Downloads\PortableGit-2.49.0-64-bit.7z\bin\git.exe` exists.
- Remote GitHub `ybagheri/FM-indicator` (`main`) shows **50 commits**, README describes an
  **indicator-only v1.30** project ("No EA in repo", "v3 EA in a separate repo").
- Local tree **already contains a full EA** (`MQL5/Experts/FM_EA.mq5` v1.00 +
  `StrategyRegistry/RiskManager/ExecutionEngine/PositionManager/TradeIntent/
  TradeExplanation/SafetyManager/PaperTrader.mqh`, `docs/EA_ARCHITECTURE.md`,
  `docs/STRATEGY_CATALOG.md`, `docs/TRADE_DECISION_SPECIFICATION.md`,
  `Presets/FM_EA_Auto_Baseline.set`, `reports/T-014..T-020*.htm`).
  `docs/CURRENT_STATE.md` (HEAD `7009511`, 2026-09-04) still says "No EA exists in the repo".
- Conclusion: **local is ahead of remote and ahead of its own docs**.
  There is uncommitted, unpushed EA work (Phases 21–35 by file headers) with no git history
  to inspect. Before Phase 1, the operator must decide: `git init + add remote +
  fetch/reconcile` vs fresh clone then copy EA files in. **Do NOT `git init` blindly
  over divergent histories; fetch remote first and diff.**
- SSH/push readiness: `C:\Windows\System32\OpenSSH\` exists on PATH but no key/host
  verification was performed in this phase. Push is **BLOCKED until git+SSH verified**.
- Baseline tests (this phase, `python tests/test_*.py` directly — no pytest in
  embedded Python 3.13.12): **all 16 suites PASS**
  (bar, breakout, decision, execution, fm, general, intent, ltf, positions,
  pullback, registry, reversal, risk, safety, setup, state).

## 1. Architecture (as built)

```
Shared single-source layers (Indicator AND EA consume identically)
  Defs / Config / Logger / ATR / Swings / MeasuredMove / FMEngine
  BarAnalyzer(Ph1) / PullbackPatterns(Ph2) / MarketState+Context(Ph3)
  BreakoutEngine(Ph4) / ReversalEngine(Ph5) / SetupEngine(Ph6)
  GeneralSetups(Ph7: catalog + SelectBest + Finish/RR) / Confirmation(score)
  DecisionEngine(Ph8: BUY/SELL/WAIT/NO_TRADE + 11 reasons)
  Analysis.mqh CFMAnalysis::Update(rates,count,cfg,shift=1,res)  ← Phase-21 facade
        │  fills FMAnalysisResult: atr/bar/pb/state/bo/rev/fmPlans[20]/
        │  best+candidates[12]+generalDone / dctx+decision+decisionDone
        ├─ Indicator adapter (FM_Indicator.mq5 v1.30): new-closed-bar gate,
        │  Update(shift=1), FM_DECISION label, DATA buffers 0-3 frozen at
        │  shift 1, Visualizer FM_<id>_*, Alerts, MTF/LTF LOG_ONLY, CSV export.
        └─ EA adapter (FM_EA.mq5 v1.00): new-closed-bar gate (iTime(0) change,
           CopyRates need=max(HistoryBars,500), require ≥500),
           Update(shift=1) → StrategyRegistry → structural veto →
           RiskManager.Check → TradeIntent.From* → SafetyManager/Paper/Execution.
```

Good news: Phases 1–8 engines + `CFMAnalysis` + `Inputs.mqh`/`Config.mqh` are genuinely
shared. No rewrite needed there.

## 2. Strategy coverage

EA (`StrategyRegistry.mqh:17-27`, `FM_EA.mq5:358-369`, `TradeIntent.mqh:133-285`):

| ID | Name | Source | EA status |
|----|------|--------|-----------|
| 1 | FM_FADE | SETUP_FM_FADE (all MM families) | YES |
| 2 | PULLBACK | SETUP_TREND_PULLBACK H1/H2/L1/L2 | YES |
| 3 | BREAKOUT | SETUP_BREAKOUT FOLLOW firm / PENDING prov | YES |
| 4 | REVERSAL_MTR | SETUP_REVERSAL MAJOR firm / MINOR prov | YES |
| 5 | DOUBLE | SETUP_DOUBLE swing firm / micro prov | YES |
| 6 | FAILED_BO | registry-built fade (Phase 28, score 55, entry=failed level) | YES |

Indicator (`Analysis.mqh:248-491`): catalog emits PULLBACK / DOUBLE / BREAKOUT /
REVERSAL / FM_FADE (FM joins catalog even when not winning, `460-490`) and picks
`SelectBest` (score-max). **It never builds FAILED_BO** (no `BuildFailedBO` call;
`BreakoutSignal FAILED` is silent by design in `BreakoutEngine.mqh:4-5`).
Indicator also has **no `ENUM_FM_STRATEGY`, no mode filter** — every valid catalog
entry competes.

Gap G1 (HIGH): Indicator cannot produce FAILED_BO; EA can. Any failed-BO bar diverges.

## 3. Mode semantics (SINGLE / MULTI / AUTO)

- EA: `ENUM_STRATEGY_MODE SINGLE/MULTI/AUTO` (`StrategyRegistry.mqh:29-34`).
  `Configure(mode,single,useFM,usePB,useBO,useRev,useDbl,useFailedBO)` (`FM_EA.mq5:101-103`).
  `SINGLE/MULTI → Select()` raw-score-max (firm>prov, enum order, entry tiebreak,
  `192-229`); `AUTO → SelectAuto()` final-score (`231-303`, see §5).
- Indicator: **no mode inputs, no registry include** (grep: `StrategyRegistry/
  SelectAuto/InpStratMode/InpSingleStrategy` match EA-side files only).
  It always behaves like "MULTI-all-enabled score-max on `best`" — closest to EA MULTI
  with all `Use*=true`, but even that differs (see G2/G3).

Gap G2 (HIGH): SINGLE and AUTO have no indicator equivalent. MULTI matches only when
all strategies enabled AND no FAILED_BO AND tie-breaks coincide.

## 4. AUTO algorithm (exact EA sequence — indicator does NOT do this)

`StrategyRegistry.mqh:236-303` + `FM_EA.mq5:288-298` + `TRADE_DECISION_SPECIFICATION.md:17-29`:

1. `BuildCandidates(res)` from `res.candidates` (skip invalid/NONE) + `BuildFailedBO` append.
2. Drop `!valid || !enabled || !setup.valid`.
3. `AutoFinal = score + (ctxDir!=0 && mstate.valid ? ±trendBonus : 0) − (prov ? provPenalty : 0) + (rMult≥rrLevel ? rrBonus : 0)`; defaults `10/5/5/2.0`.
   `ContextDir`: BULL_TREND/BULL_CHANNEL→+1, BEAR_TREND/BEAR_CHANNEL→−1, else 0.
4. Rank by final desc; ties → firm beats provisional → lower strategy enum → lower entry.
5. Structural veto AFTER selection (EA, all modes — see §6).
6. Risk → intent gates → execution/mode gate.

Indicator `SelectBest` (`GeneralSetups`): raw `score` max; ties lowest setup-type enum then
lowest signalBar. **No trend bonus/penalty/RR bonus, no enable mask, no FAILED_BO.**
AUTO parity = 0% today by construction.

## 5. Candidate evaluation parity (per-strategy geometry/score — SHARED, good)

All formulas live in shared `GeneralSetups.mqh` / `SetupEngine.mqh` / `Confirmation.mqh`
consumed via `Analysis.mqh`; EA does not recompute them. Spot-checked parity:
PULLBACK `legs≥2?70:40`, DOUBLE `micro?30:60`, BREAKOUT `FOLLOW 70 / PENDING 40 − trap 20`,
REVERSAL `MAJOR 80 / MINOR 40`, FAILED_BO fixed 55, FM_FADE `ScoreSignal 0..100`
(body/wick/close/engulf/FT/exhaustion/context/distance). `Finish`: `rMult=reward/risk`,
`rrOK = rMult+1e-9 ≥ clamp(SetupMinRR,0.25,5.0)` (default 1.0).
**No action needed here** beyond keeping the single source.

## 6. Veto / safety / final-signal parity (the biggest behavioral gap)

Phase-8 `DecisionEngine.Decide` priority (shared code, `DecisionEngine.mqh:99-130`):
`DISABLED → NO_SETUP → BARBWIRE → MID_RANGE → CONFLICT → NO_EDGE(WAIT) →
LOW_SCORE(WAIT) → LOW_RR(WAIT) → LATE_ENTRY(WAIT) → TRAP_REPEAT → OK→BUY/SELL`.
Indicator applies this to its own `res.best` and shows it in `FM_DECISION`
(`FM_Indicator.mq5:199-209`). Fine.

EA adds three layers the indicator lacks:

- (a) **Registry-level structural veto** (`FM_EA.mq5:299-339`, all modes): if
  `sel.hasTrade && res.decisionDone && reason ∈ {BARBWIRE, MID_RANGE, CONFLICT,
  NO_EDGE, TRAP_REPEAT}` → `DECISION_VETO_<reason>`, counted in `g_veto /
  g_vetoByReason[11]`, selection skipped (production) or bypass-counted
  (`InpApplyStructuralVeto=false`, EXP-0002 apparatus). Note LOW_SCORE/LOW_RR/
  LATE_ENTRY do NOT veto at this layer (they stay WAIT semantics inside the decision).
  The indicator has **no `InpApplyStructuralVeto`, no veto counters, no BYPASS path** —
  and because its `best ≠ sel` in general, even the veto trigger differs.
- (b) **RiskManager.Check** (`EA_ARCHITECTURE.md:78-81`, `FM_EA.mq5:346`):
  `NO_SETUP → LOW_RR → HIGH_SPREAD → DAILY_LOSS → MAX_TRADES_DAY → CONSEC_LOSSES →
  MAX_OPEN → MAX_PER_SYMBOL → OK`. No indicator equivalent (correctly execution-side,
  except LOW_RR which duplicates the decision rule — document, don't mirror fills).
- (c) **TradeIntent gates** (`TradeIntent.mqh:58-100`, `FM_EA.mq5:408-409`):
  `PROVISIONAL_OFF (InpTradeProvisional=false default) / LATE_ENTRY (chase 0.50 ATR,
  mirrors Phase-8 late) / WRONG_SIDE (Phase-41 fix: BUY needs price>stop, SELL price<stop)
  / NOT_FM/.../STALE → SKIP_why`, plus `Permits`: BE always, trail only PULLBACK/
  BREAKOUT, no partials. Plus SafetyManager halts/session/mode gates
  (`ANALYSIS_ONLY/PAPER/DEMO/LIVE`, emergency/drawdown/daily-loss latches).
  These use **live Ask/Bid at the next tick** (`FM_EA.mq5:353-354`) — inherently
  non-mirrorable tick-for-tick in a closed-bar indicator; the indicator must model the
  *closed-bar projection* (entry/stop/objective/validity) and label execution-only
  gates as such rather than fake them.

Gap G3 (HIGH): final-signal parity fails whenever (i) selection differs, (ii) veto
applies to one side's pick only, (iii) intent/risk gates fire (PROVISIONAL_OFF and
LATE_ENTRY are the frequent ones — cf. reports `T-015 SINGLE_PB 0 trades (51 LATE +
18 PROV_OFF)`).

## 7. Input parity

Shared analysis inputs: **PARITY OK**. `Inputs.mqh:13-93` is the single source, included
verbatim by both programs (`FM_Indicator.mq5:52`, `FM_EA.mq5:24`), applied by
`FM_ApplyInputs` (`96-154`) into `CFMConfig` (`Config.mqh:11-105`, Balanced preset
`109-142`, `Validate()` clamps `165-243`). `.set` presets bind by name so they load in both.

Decision-affecting inputs **missing from the indicator** (all default-sensitive):

| EA input | Default | Effect | Indicator |
|----------|---------|--------|-----------|
| InpStratMode / InpSingleStrategy | AUTO / FM_FADE | selection universe | MISSING |
| InpUseFM/Pullback/Breakout/Reversal/Double/FailedBO | all true | enable mask | MISSING |
| InpAutoTrendBonus/ProvPenalty/RRBonus/RRLevel | 10/5/5/2.0 | AUTO ranking | MISSING |
| InpApplyStructuralVeto | true | veto bypass apparatus | MISSING |
| InpTradeProvisional / InpChaseATRMult / InpMaxHoldBars | false / 0.50 / 5 | intent gates | MISSING (analysis has MaxLateEntryATRMult 0.50 + SetupMinRR, but not the intent side) |
| InpRiskMinRR (+ full RiskManager block) | 1.0 (+ caps) | risk veto | MISSING by design (execution) — but LOW_RR overlap must be documented |
| InpTradeMode/Safety block | ANALYSIS_ONLY… | halts/session | MISSING by design |

Display-only inputs (ShowScore/Legs/alerts/CSV/LogLevel): shared, no parity impact.
Execution-only (lots, magic, slippage, BE/trail,5727 magic/history): correctly EA-only;
`maxHoldBars` is copied into intent but expiry is downstream — document, don't mirror fills.

Gap G4 (HIGH): any AUTO/registry/veto parity test run with non-default EA selection
inputs has no indicator knob to match. Fix = Phase 1 indicator inputs (mirror) with
identical defaults, EA-execution-only stays EA-only with a documented list.

## 8. Analysis-phase parity matrix

| Component | EA | Ind | Shared impl | Same inputs | Same timing | Same result |
|-----------|:--:|:---:|:-----------:|:-----------:|:-----------:|:-----------:|
| ATR/Swings/Projections/FMEngine core + 5 MM families | YES | YES | YES (`Analysis.mqh:119-128`) | YES | YES shift 1 | YES (assumed; needs closed-bar proof test) |
| Ph1 bars | YES | YES | YES | YES | YES | YES (read-only both) |
| Ph2 pullbacks/doubles | YES | YES | YES | YES | YES | YES |
| Ph3 market state | YES | YES | YES | YES | YES | YES |
| Ph4 breakout/trap | YES | YES | YES | YES | YES | YES |
| Ph5 reversal/MTR | YES | YES | YES | YES | YES | YES |
| Ph6 FM plans | YES | YES | YES | YES | YES | YES |
| Ph7 catalog (PB/DBL/BO/REV/FM) | YES | YES | YES | YES | YES | YES |
| Ph7 FAILED_BO candidate | YES (`BuildFailedBO`) | NO | — | — | — | **NO (G1)** |
| Ph7 best-pick (`SelectBest` vs registry) | registry | `SelectBest` | NO (different code) | n/a | YES | **NO (G2/G3)** |
| Ph8 Decide on own pick | YES (on `sel.setup` via res.decision*) | YES (on `best`) | YES code | YES | YES | diverges when pick differs |
| SINGLE/MULTI/AUTO modes | YES | NO | NO | NO | — | **NO (G2)** |
| Structural veto + bypass | YES (EA layer) | NO | NO | NO | — | **NO (G3)** |
| Risk/Intent/Safety gates | YES | NO | — | — | live-tick vs close | **NO by design (document)** |
| Closed-bar discipline | YES (`iTime(0)` new-bar, `Update(shift=1)`, need≥500) | YES (`time[1]` new-bar, `Update(shift=1)`, buffers frozen) | same contract | — | equivalent, **history depth differs** (EA 1500/≥500 vs ind full-chart; ATR/swing warmup edge — needs test H) | TBD verify |

* EA reuses `res.decision` (computed on indicator-style `best`) only as the veto
signal, then applies it to the registry selection — a deliberate but divergence-prone
coupling; parity work must decide: veto-per-selection vs veto-on-best (recommend:
compute decision per selected candidate in the shared engine, Phase 5).

## 9. Timing / repaint contract (both claim closed-bar; verify, don't trust)

- EA: `OnTick` returns unless `iTime(0)` changed (`FM_EA.mq5:208-211`); analyzes
  `rates[1]` (just-closed); settle/manage on `rates[1]` (`233-237`).
- Indicator: `OnCalculate` full recompute only on `time[1]` change or first run
  (`FM_Indicator.mq5:176-193`); buffers written at shift 1 only, never rewrite older
  (`224-226`); state snapshots pre-mutation for edge triggers (`184-188`); max one
  transition per setup per bar (`FMEngine.mqh:196-198`); bar-0 intrabar POTENTIAL
  preview only when `InpUseIntrabarPotential` (default false), never DEV/CONF (`272-278`).
- Both honor shift≥1; both document freeze. Open verification items: EA 500-bar minimum
  vs indicator `AtrPeriod+2*SwingK+20` minimum + `PLOT_DRAW_BEGIN`; EA fixed 1500-bar
  window vs indicator full history (engine state evolution may differ on long histories);
  `CopyRates` series orientation handled in both (`ArraySetAsSeries(true)`).
  Test H (historical stability) must prove byte-identical decisions bar-by-bar.

## 10. Visualization / diagnostics (indicator behind EA explainability)

- Indicator today: FM state objects (`FM_<id>_LEG/PB/TGT/ZONE/LABEL/ARROW`),
  4 DATA buffers + ATR/swing calc buffers, single `FM_DECISION` label
  (`BUY lime/SELL red/WAIT orange/else gray`), DEBUG logs per phase, score in labels,
  CSV per CONFIRMED. No candidate list, no registry pick, no veto reason, no RR/entry
  overlay for non-FM strategies, no structured per-bar dump.
- EA today: `[FM_EA]` log lines per selection (strategy/entry/stop/obj/score/PROV/
  R/cands/final/sig/risk/vol/intent), `EXPLAIN` records (`TradeExplanation.mqh`),
  veto census + `vetoByReason[11]`, PAPER fills, `OnTester` composite (Phase 35).
- Gap G5 (MEDIUM): no indicator diagnostic mode exposing candidates/selection/veto/
  intent-projection per bar → parity mismatches are not diagnosable from the chart.
  Fix = Phase 6 (configurable viz + DEBUG diagnostic block + optional CSV parity row).

## 11. Testing status

- Python mirrors: 16/16 suites pass (this phase, direct-run, no pytest).
- MT5: reports `T-014 AUTO DEMO 3tr 0/3 −353.49`, `T-015 SINGLE_PB 0tr`,
  `T-016 SINGLE_DBL 4tr 1/3 −37.44`, `T-020 XAUUSD AUTO 10tr 5/5 +158.32`,
  `T-018 IS 1tr −99`, `T-019 OOS 5tr +487.82` — EA-side only; **no EA↔Indicator
  parity test exists** (no BAR/EA_SIGNAL/IND_SIGNAL… CSV, no cases A–I).
- Established methodology to preserve: PAPER mode, AUTO/all-strategies, Balanced,
  EURUSD H1 primary + XAUUSD mirror, safety/veto controls (`PAPER_FORWARD_TEST_PLAN.md`,
  `BACKTESTING_GUIDE.md`). Parity work must plug into it, not replace it.

## 12. Exact mismatch list (normative for Phases 1–7)

1. M1 Indicator lacks FAILED_BO evaluation (EA `BuildFailedBO`). — Phase 2.
2. M2 Indicator lacks SINGLE/MULTI/AUTO + enable mask + AUTO tuning. — Phases 1+4.
3. M3 Indicator `SelectBest` ≠ EA `Select`/`SelectAuto` (different ranking + tiebreaks). — Phase 4.
4. M4 EA structural-veto layer (+ bypass + census) has no indicator counterpart. — Phase 5.
5. M5 Intent gates (PROVISIONAL_OFF/LATE_ENTRY/WRONG_SIDE/STALE) + risk/safety gates
   have no indicator projection. — Phase 5 (model closed-bar projection; document
   live-tick remainder as known limitation).
6. M6 Decision-affecting EA inputs missing from indicator (see §7 table). — Phase 1.
7. M7 No shared decision/result contract exposing candidates+selection+veto+intent
   per bar (EA logs strings; indicator shows one label). — Phase 3.
8. M8 No parity test harness / cases A–I / CSV contract. — Phase 7.
9. M9 Docs claim "no EA in repo" (`CURRENT_STATE.md`, README) — stale; update in Phase 8.
10. M10 No git linkage locally; push blocked. — operator action before Phase-1 commit.

## 13. Implementation plan (phased, smallest diffs first, no EA behavior changes)

- Phase 1 — Input + analysis parity: add EA-selection inputs to indicator with
  identical defaults (mode/single/6×Use/AUTO×4/ApplyVeto/TradeProvisional/Chase);
  route through `FM_ApplyInputs`-adjacent applier (no duplication of analysis inputs);
  prove `CFMAnalysis` byte-identical (test H script). No strategy-logic edits.
- Phase 2 — Registry parity: indicator includes `StrategyRegistry.mqh` (already
  depends only on shared headers — no cycle beyond `Analysis.mqh`, verified);
  add `BuildFailedBO` candidate to indicator path (or shared catalog — prefer shared,
  EA behavior unchanged since geometry identical).
- Phase 3 — Candidate/result contract: shared `ParityDecision` struct (candidates,
  selection, final scores, veto, intent-projection, bar time); EA and indicator fill
  the same struct from the same functions.
- Phase 4 — Mode parity: indicator `Select`/`SelectAuto` via the same registry
  object; AUTO formula untouched (defaults 10/5/5/2.0); tiebreaks verbatim.
- Phase 5 — Veto/safety/final-signal: shared veto helper (decision-per-selection);
  indicator models PROVISIONAL_OFF + closed-bar LATE projection + WRONG_SIDE static
  check; risk fills/safety halts stay EA-only, explicitly listed.
- Phase 6 — Viz + diagnostics: candidate/strategy/veto/RR/score overlays (toggles),
  `InpDiagnosticMode` DEBUG block + parity CSV row writer.
- Phase 7 — Parity harness: Python + MQL5-log-driven `BAR,EA_SIG,IND_SIG,EA_STRAT,
  IND_STRAT,…,RESULT` comparator + cases A–I fixtures.
- Phase 8 — Docs/release: refresh README/CURRENT_STATE/architecture/strategy/
  input/testing docs, changelog, clean-compile proof.

Rule: do NOT retune thresholds/scores/veto/entry/SL/TP (spec §20). Any EA bug found
→ document, minimal fix, impact test, never silent.

## 14. STOP condition for Phase 0

Audit complete. **Do not write implementation code until §10 git linkage + SSH push
path are resolved and this audit is accepted.** Next action is operator decision on
git reconciliation, then Phase-1 commit separately per the required commit strategy.
