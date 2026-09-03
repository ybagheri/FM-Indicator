# FUTURE ROADMAP — FM Indicator

Phased, no premature implementation. Each item needs spec + tests first.

## v1.1 (correctness)
- MetaEditor compile + Strategy Tester visual run on majors/H1; screenshot log.
- Walk-forward review of inverse-MM anchor (failure-low − leg range is provisional).
- Follow-through edge case: signal on bar 1 with `RequireFollowThrough` (needs 1-bar delay path).

## v1.2 (families, still MVP-shaped)
- `CRangeHeightMM`, `CChannelMM`, `CGapMM` subclasses (reserved in ARCHITECTURE §6).
- Wedge/3-push counter as first-class exhaustion input (currently boolean proxy).
- Signal scoring (0–100) for display only, never auto-trading.

## v2 (research tooling)
- Historical signal export (CSV) + parameter sensitivity / Monte Carlo notes.
- Multi-timeframe context (higher-TF trend read-only overlay).
- Backtest support + performance metrics (max adverse/favorable excursion).

## v3 (EA foundation)
- Signal engine reuse (`CFMEngine::Active()` + DATA buffers) by an EA in a
  separate repo; indicator repo stays execution-free.
- Optimization framework + walk-forward analysis.

Non-goals for this repo: auto-trading, profitability claims, repainted-history
"perfect signals", per-tick CONFIRMED states.
