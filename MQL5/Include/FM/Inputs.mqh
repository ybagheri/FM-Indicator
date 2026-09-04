//+------------------------------------------------------------------+
//| Inputs.mqh : shared analysis inputs (Phase 23)                      |
//| SINGLE SOURCE for Indicator AND EA analysis inputs. Names, order and|
//| defaults are VERBATIM from FM_Indicator.mq5 (SPEC §1 Balanced).     |
//| .set presets bind by NAME, so they keep loading in both programs.   |
//+------------------------------------------------------------------+
#ifndef FM_INPUTS_MQH
#define FM_INPUTS_MQH
#include "Config.mqh"
#include "Defs.mqh"

//--- inputs (SPEC §1 Balanced defaults)
input int    InpSwingK              = 3;
input double InpMinLegATRMult       = 1.0;
input int    InpMinLegBars          = 3;
input int    InpMaxLegBars          = 100;
input double InpMinPullbackRatio    = 0.15;
input double InpMaxPullbackRatio    = 0.90;
input int    InpMaxPullbackBars     = 50;
input double InpMMToleranceATRMult  = 0.25;
input double InpMaxOvershootATRMult = 0.50;
input double InpApproachATRMult     = 1.0;
input double InpSignalClosePct      = 0.50;
input double InpMinBodyRatio        = 0.30;
input double InpMaxWickRatio        = 0.60;
input bool   InpRequireEngulf       = false;
input bool   InpRequireFollowThrough= false;
input bool   InpEnableInverseMM     = true;
input int    InpFailedBOBars        = 5;
input bool   InpEnableRangeMM       = false;  // v1.2 range-height breakout family
input int    InpRangeLookback       = 50;
input bool   InpEnableChannelMM     = false;  // v1.2 shallow-pullback channel family
input bool   InpEnableGapMM         = false;  // v1.2 measuring-gap family
input double InpMinGapATRMult       = 1.0;
input int    InpMinPushes           = 3;      // v1.2 exhaustion push threshold 2..5
input bool   InpUseWedgeExhaustion  = true;
input bool   InpShowScore           = true;   // v1.2 display-only S=0..100
input double InpDojiMaxBodyRatio    = 0.15;   // Phase 1 bar engine: doji threshold
input double InpBigBarATRMult       = 2.0;    // Phase 1: big-bar threshold
input double InpSmallBarATRMult     = 0.5;    // Phase 1: small-bar threshold
input double InpStrongClosePct      = 0.70;   // Phase 1: strong-close threshold
input bool   InpEnableBarAnalysis   = true;   // Phase 1: bar-by-bar analyzer (read-only)
input double InpMinPullbackDepthATRMult = 0.50; // Phase 2: pullback window range gate (xATR)
input double InpDoubleTopTolATRMult  = 0.25;  // Phase 2: double-top/bottom tolerance (xATR)
input int    InpMaxDoubleBars        = 20;    // Phase 2: max bars between double extremes
input double InpMinDoubleTroughATRMult = 0.50; // Phase 2: min trough separation (xATR)
input int    InpMicroDoubleBars      = 5;     // Phase 2: micro-double window (newest closed bars)
input bool   InpEnablePullbackPatterns = true; // Phase 2: pullback/double layer (read-only)
input int    InpStateLookback        = 20;    // Phase 3: range-height window (bars)
input int    InpStateOverlapBars     = 10;    // Phase 3: body-overlap window (bars)
input bool   InpEnableMarketState    = true;  // Phase 3: market-state engine (read-only)
input int    InpBOLookback          = 20;    // Phase 4: Donchian reference window (bars)
input double InpBOToleranceATRMult  = 0.10;  // Phase 4: close must clear ref by this xATR
input int    InpBOFollowBars        = 5;     // Phase 4: active-breakout window (bars)
input int    InpBOTrapLookback      = 20;    // Phase 4: prior-failure scan (bars)
input bool   InpEnableBreakout      = true;  // Phase 4: breakout/trap engine (read-only)
input int    InpRevLookback         = 10;    // Phase 5: MTR cross/retest window (bars)
input double InpRevRetestTolATRMult = 0.25;  // Phase 5: EMA touch band (xATR)
input int    InpRevMinPressure      = 5;     // Phase 5: pushes for MTR pressure leg
input bool   InpEnableReversal      = true;  // Phase 5: reversal engine (read-only)
input double InpSetupStopBufATRMult = 0.10;  // Phase 6: stop buffer beyond structure (xATR)
input double InpSetupMinRR          = 1.0;   // Phase 6: R flag threshold (report-only)
input bool   InpEnableSetup         = true;  // Phase 6: FM setup plans (read-only)
input bool   InpEnableGeneralSetups = true;  // Phase 7: non-FM setup catalog (read-only)
input double InpGeneralTickProxyATRMult = 0.05; // Phase 7: pullback entry beyond extreme (xATR)
input double InpGeneralObjectiveATRMult = 2.0;  // Phase 7: BO/reversal objective (xATR)
input bool   InpEnableDecision      = true;  // Phase 8: BUY/SELL/WAIT/NO_TRADE + reasons (read-only)
input int    InpMinDecisionScore    = 40;    // Phase 8: min setup score for a direction
input double InpMaxLateEntryATRMult = 0.50;  // Phase 8: chase veto past entry (xATR)
input int    InpDecisionConflictPpts= 10;    // Phase 8: top-two state pct gap = conflict
input int    InpDecisionMaxFailedBO = 2;     // Phase 8: failed-BO trap-repeat threshold
input int    InpMTFTrendTFMinutes   = 0;      // v2 MTF overlay: 0=off, else higher-TF minutes
input int    InpLTFMinutes            = 0;      // v2 LTF confirm: 0=off, else lower-TF minutes (LOG_ONLY)
input bool   InpExportCSV           = false;  // v2: write signals CSV on new CONFIRMED
input string InpCSVFile             = "FM_signals.csv";
input ENUM_CTX_FILTER InpContextFilterMode = CTX_LOG_ONLY;
input ENUM_FM_PRICE_MODE InpPriceMode = FM_PRICE_HIGHLOW; // High/Low (candles) or Close (line chart)
input int    InpMaxActiveSetups     = 20;
input int    InpMaxBarsForward      = 100;
input bool   InpUseIntrabarPotential= false;
input int    InpAtrPeriod           = 14;
input bool   InpShowLegs            = true;
input bool   InpShowPullbacks       = true;
input bool   InpShowTargets         = true;
input bool   InpShowZones           = true;
input bool   InpAlertPotential      = true;
input bool   InpAlertDeveloping     = true;
input bool   InpAlertConfirmed      = true;
input bool   InpUseSound            = false;
input bool   InpUsePush             = false;
input bool   InpUseMail             = false;
input string InpSoundFile           = "alert.wav";
input ENUM_LOG_LEVEL InpLogLevel    = LOG_INFO;

// Shared applier (moved verbatim from FM_Indicator.mq5).
void FM_ApplyInputs(CFMConfig &cfg)
  {
   cfg.SwingK=InpSwingK; cfg.MinLegATRMult=InpMinLegATRMult;
   cfg.MinLegBars=InpMinLegBars; cfg.MaxLegBars=InpMaxLegBars;
   cfg.MinPullbackRatio=InpMinPullbackRatio; cfg.MaxPullbackRatio=InpMaxPullbackRatio;
   cfg.MaxPullbackBars=InpMaxPullbackBars;
   cfg.MMToleranceATRMult=InpMMToleranceATRMult;
   cfg.MaxOvershootATRMult=InpMaxOvershootATRMult;
   cfg.ApproachATRMult=InpApproachATRMult;
   cfg.SignalClosePct=InpSignalClosePct; cfg.MinBodyRatio=InpMinBodyRatio;
   cfg.MaxWickRatio=InpMaxWickRatio;
   cfg.RequireEngulf=InpRequireEngulf; cfg.RequireFollowThrough=InpRequireFollowThrough;
   cfg.EnableInverseMM=InpEnableInverseMM; cfg.FailedBOBars=InpFailedBOBars;
   cfg.EnableRangeMM=InpEnableRangeMM; cfg.RangeLookback=InpRangeLookback;
   cfg.EnableChannelMM=InpEnableChannelMM; cfg.EnableGapMM=InpEnableGapMM;
   cfg.MinGapATRMult=InpMinGapATRMult;
   cfg.MinPushes=InpMinPushes; cfg.UseWedgeExhaustion=InpUseWedgeExhaustion;
   cfg.ShowScore=InpShowScore;
   cfg.DojiMaxBodyRatio=InpDojiMaxBodyRatio; cfg.BigBarATRMult=InpBigBarATRMult;
   cfg.SmallBarATRMult=InpSmallBarATRMult; cfg.StrongClosePct=InpStrongClosePct;
   cfg.EnableBarAnalysis=InpEnableBarAnalysis;
   cfg.MinPullbackDepthATRMult=InpMinPullbackDepthATRMult;
   cfg.DoubleTopTolATRMult=InpDoubleTopTolATRMult;
   cfg.MaxDoubleBars=InpMaxDoubleBars;
   cfg.MinDoubleTroughATRMult=InpMinDoubleTroughATRMult;
   cfg.MicroDoubleBars=InpMicroDoubleBars;
   cfg.EnablePullbackPatterns=InpEnablePullbackPatterns;
   cfg.StateLookback=InpStateLookback; cfg.StateOverlapBars=InpStateOverlapBars;
   cfg.EnableMarketState=InpEnableMarketState;
   cfg.BOLookback=InpBOLookback; cfg.BOToleranceATRMult=InpBOToleranceATRMult;
   cfg.BOFollowBars=InpBOFollowBars; cfg.BOTrapLookback=InpBOTrapLookback;
   cfg.EnableBreakout=InpEnableBreakout;
   cfg.RevLookback=InpRevLookback;
   cfg.RevRetestTolATRMult=InpRevRetestTolATRMult;
   cfg.RevMinPressure=InpRevMinPressure;
   cfg.EnableReversal=InpEnableReversal;
   cfg.SetupStopBufATRMult=InpSetupStopBufATRMult;
   cfg.SetupMinRR=InpSetupMinRR;
   cfg.EnableSetup=InpEnableSetup;
   cfg.EnableGeneralSetups=InpEnableGeneralSetups;
   cfg.GeneralTickProxyATRMult=InpGeneralTickProxyATRMult;
   cfg.GeneralObjectiveATRMult=InpGeneralObjectiveATRMult;
   cfg.EnableDecision=InpEnableDecision;
   cfg.MinDecisionScore=InpMinDecisionScore;
   cfg.MaxLateEntryATRMult=InpMaxLateEntryATRMult;
   cfg.DecisionConflictPpts=InpDecisionConflictPpts;
   cfg.DecisionMaxFailedBO=InpDecisionMaxFailedBO;
   cfg.ContextFilter=InpContextFilterMode;
   cfg.PriceMode=InpPriceMode;
   cfg.MaxActiveSetups=InpMaxActiveSetups; cfg.MaxBarsForward=InpMaxBarsForward;
   cfg.UseIntrabarPotential=InpUseIntrabarPotential; cfg.AtrPeriod=InpAtrPeriod;
   cfg.ShowLegs=InpShowLegs; cfg.ShowPullbacks=InpShowPullbacks;
   cfg.ShowTargets=InpShowTargets; cfg.ShowZones=InpShowZones;
   cfg.AlertPotential=InpAlertPotential; cfg.AlertDeveloping=InpAlertDeveloping;
   cfg.AlertConfirmed=InpAlertConfirmed;
   cfg.UseSound=InpUseSound; cfg.UsePush=InpUsePush; cfg.UseMail=InpUseMail;
   cfg.SoundFile=InpSoundFile; cfg.LogLevel=InpLogLevel;
   if(!cfg.Validate()) Print("[FM] inputs clamped to valid ranges (see SPEC §1).");
  }

#endif
