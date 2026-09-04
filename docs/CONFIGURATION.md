# CONFIGURATION — inputs, groups, presets (normative defaults = Balanced)

> Companion to `SYSTEMATIC_SPECIFICATION.md` (§1 table), `FM_Indicator.mq5`
> (input declarations), `Presets/*.set`. All Brooks-discretionary choices are
> `Inp*` inputs. Invalid values are clamped in `CFMConfig::Validate()`.

## 1. Groups (as ordered in the indicator Inputs dialog)

| Group | Inputs | Defaults |
|---|---|---|
| Swings/Legs | `InpSwingK`, `InpMinLegATRMult`, `InpMinLegBars`, `InpMaxLegBars` | 3, 1.0, 3, 100 |
| Pullback/MM | `InpMinPullbackRatio`, `InpMaxPullbackRatio`, `InpMaxPullbackBars` | 0.15, 0.90, 50 |
| FM zone | `InpApproachATRMult`, `InpMMToleranceATRMult`, `InpMaxOvershootATRMult` | 1.0, 0.25, 0.50 |
| Signal bar | `InpSignalClosePct`, `InpMinBodyRatio`, `InpMaxWickRatio`, `InpRequireEngulf`, `InpRequireFollowThrough` | 0.50, 0.30, 0.60, false, false |
| Families | `InpEnableInverseMM`, `InpFailedBOBars`, `InpEnableRangeMM`, `InpRangeLookback`, `InpEnableChannelMM`, `InpEnableGapMM`, `InpMinGapATRMult` | true, 5, false, 50, false, false, 1.0 |
| Exhaustion/Score | `InpMinPushes`, `InpUseWedgeExhaustion`, `InpShowScore` | 3, true, true |
| Phase 1 bars | `InpDojiMaxBodyRatio`, `InpBigBarATRMult`, `InpSmallBarATRMult`, `InpStrongClosePct`, `InpEnableBarAnalysis` | 0.15, 2.0, 0.5, 0.70, true |
| Phase 2 pullbacks | `InpMinPullbackDepthATRMult`, `InpDoubleTopTolATRMult`, `InpMaxDoubleBars`, `InpMinDoubleTroughATRMult`, `InpMicroDoubleBars`, `InpEnablePullbackPatterns` | 0.50, 0.25, 20, 0.50, 5, true |
| Phase 3 state | `InpStateLookback`, `InpStateOverlapBars`, `InpEnableMarketState` | 20, 10, true |
| Phase 4 breakout | `InpBOLookback`, `InpBOToleranceATRMult`, `InpBOFollowBars`, `InpBOTrapLookback`, `InpEnableBreakout` | 20, 0.10, 5, 20, true |
| Phase 5 reversal | `InpRevLookback`, `InpRevRetestTolATRMult`, `InpRevMinPressure`, `InpEnableReversal` | 10, 0.25, 5, true |
| Phase 6 setup | `InpSetupStopBufATRMult`, `InpSetupMinRR`, `InpEnableSetup` | 0.10, 1.0, true |
| Phase 7 general | `InpEnableGeneralSetups`, `InpGeneralTickProxyATRMult`, `InpGeneralObjectiveATRMult` | true, 0.05, 2.0 |
| Phase 8 decision | `InpEnableDecision`, `InpMinDecisionScore`, `InpMaxLateEntryATRMult`, `InpDecisionConflictPpts`, `InpDecisionMaxFailedBO` | true, 40, 0.50, 10, 2 |
| Research (v2) | `InpMTFTrendTFMinutes`, `InpLTFMinutes`, `InpExportCSV`, `InpCSVFile` | 0, 0, false, FM_signals.csv |
| Context/price | `InpContextFilterMode`, `InpPriceMode` | LOG_ONLY, High/Low |
| Engine caps | `InpMaxActiveSetups`, `InpMaxBarsForward`, `InpUseIntrabarPotential`, `InpAtrPeriod` | 20, 100, false, 14 |
| Viz/alerts/log | `InpShowLegs/Pullbacks/Targets/Zones`, `InpAlertPotential/Developing/Confirmed`, `InpUseSound/Push/Mail`, `InpSoundFile`, `InpLogLevel` | true×4, true×3, false×3, alert.wav, INFO |

Full table + clamp rules: SPEC §1. Phase input tables: `BAR_BY_BAR_ENGINE.md`,
`PULLBACK_PATTERNS.md`, `MARKET_STATE.md`, `BREAKOUT_ENGINE.md`,
`REVERSAL_ENGINE.md`, `SETUP_ENGINE.md`, `GENERAL_SETUPS.md`,
`DECISION_ENGINE.md`.

## 2. Presets (`Presets/`, load via Inputs → Load)

- **Balanced** (SPEC defaults above). Start here.
- **Conservative**: `SwingK` 4, `MinLegATR` 1.5, tol 0.20, approach 0.75,
  `MinBody` 0.40, `FollowThrough` true — fewer, stricter setups.
- **Aggressive**: `SwingK` 2, `MinLegATR` 0.75, tol 0.35, approach 1.5,
  `MinBody` 0.25 — more, looser setups.
- **M1-Scalp**: for noisy M1 (e.g. EURUSD).
- **Line-Chart**: `InpPriceMode=Close` — swings/legs/targets on closes.
- **Families**: all MM families ON (research only).

## 3. Guidance

- Tune ONE group at a time; keep families OFF unless researching them.
- `LOG_ONLY` context first; `DEMOTE`/`VETO` only after walk-forward.
- Phase 1–8 toggles are read-only layer switches — disabling one only
  silences its DEBUG lines, never changes FM states.
