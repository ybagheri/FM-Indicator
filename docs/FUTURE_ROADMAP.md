# FUTURE ROADMAP — FM Indicator

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
- [x] EA foundation: `CFMEngine::ActiveSnapshots()` + DATA buffers.
- [ ] Parameter sensitivity / Monte Carlo notes from exported data.

## v3 (EA foundation, separate repo)
- Signal engine reuse (`CFMEngine::ActiveSnapshots()` + DATA buffers) by an EA
  in a separate repo; indicator repo stays execution-free.
- Optimization framework + walk-forward analysis.

Non-goals for this repo: auto-trading, profitability claims, repainted-history
"perfect signals", per-tick CONFIRMED states.
