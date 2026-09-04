# ROADMAP — master phases 0–19 → repo status (index)

> Detailed plan + version map + ordered next moves live in
> `FUTURE_ROADMAP.md` (normative for sequencing). This file is the
> master-prompt (§35) index: each requested phase → where it stands here.
> No profitability claims. No further indicator features are planned here —
> remaining work is validation + execution (separate v3 repo).

| Master phase | Repo status |
|---|---|
| 0 audit + research | DONE (`RESEARCH.md`, `BROOKS_CONCEPTS.md`, arch 20 commits) |
| 1 knowledge / spec | DONE (`SYSTEMATIC_SPECIFICATION.md` + 8 layer specs) |
| 2 bar-by-bar analyzer | DONE Phase 1 (`BarAnalyzer.mqh` + mirror + 7 tests, read-only) |
| 3 market context engine | DONE Phase 3 (`MarketState.mqh` + `Context.mqh` + mirror + 9 tests, read-only) |
| 4 trend / range / breakout | DONE Phases 3–4 (`MarketState` + `BreakoutEngine` + mirrors, read-only) |
| 5 pullback / reversal / patterns | DONE Phases 2+5 (`PullbackPatterns` + `ReversalEngine` + mirrors, read-only) |
| 6 measured move + FM | DONE v1/v1.1/v1.2 core (`MeasuredMove` + `FMEngine`, 19 tests) |
| 7 trade setup engine | DONE Phases 6–7 (`SetupEngine` + `GeneralSetups` + mirrors, read-only) |
| 8 buy/sell/wait decision | DONE Phase 8 (`DecisionEngine` BUY/SELL/WAIT/NO_TRADE + reasons, read-only) |
| 9 visualization | DONE (`Visualizer.mqh` + `FM_DECISION` label + toggles; per-bar tags log-only by design) |
| 10 alerts | DONE (`Alerts.mqh`, per-state + throttle) |
| 11 non-repaint validation | DONE contract + suites (`NON_REPAINTING.md`); human tester run pending (`VALIDATION.md` §2.1) |
| 12 synthetic testing | DONE 97 suites (`TESTING.md`) |
| 13 historical validation | PENDING walk-forward from CSVs (`VALIDATION.md` §2.2, owner human/analyst) |
| 14 performance | DONE new-closed-bar only; incremental `OnCalculate` |
| 15 Strategy Tester integration | PENDING visual run (`VALIDATION.md` §2.1, owner human) |
| 16 optional EA | v3 SEPARATE REPO (blocked on 13/15; reuse `ActiveSnapshots()` + buffers) |
| 17 statistical calibration | FUTURE, gated on 13 (scores stay scores until then) |
| 18 advanced MTF | v2 HTF overlay + LTF confirm DONE read-only (LOG_ONLY); deeper MTF future |
| 19 ML research | NOT PLANNED beyond feature export (CSV + MAE/MFE); deterministic engine stays |

Master docs (§31) → files: `RESEARCH.md`, `BROOKS_CONCEPTS.md`,
`SYSTEMATIC_SPECIFICATION.md`, `BAR_BY_BAR_ENGINE.md`, `MARKET_CONTEXT.md`,
`SETUP_ENGINE.md`, `FM_ENGINE.md`, `SIGNAL_SCORING.md`, `NON_REPAINTING.md`,
`ARCHITECTURE.md`, `TESTING.md`, `VALIDATION.md`, `LIMITATIONS.md`,
`CONFIGURATION.md`, `USER_GUIDE.md`, this file. Layer specs:
`PULLBACK_PATTERNS.md`, `MARKET_STATE.md`, `BREAKOUT_ENGINE.md`,
`REVERSAL_ENGINE.md`, `GENERAL_SETUPS.md`, `DECISION_ENGINE.md`.
Detail: `FUTURE_ROADMAP.md`.
