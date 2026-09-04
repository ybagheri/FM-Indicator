//+------------------------------------------------------------------+
//| FM_Indicator.mq5 : Fading Measured Move detector (Al Brooks)       |
//| v1: Leg1=Leg2 + failed-BO inverse, 3 FM states, no-look-ahead      |
//| Install: copy MQL5/Indicators/FM_Indicator.mq5 → <Data>/MQL5/       |
//|          Indicators/ and MQL5/Include/FM/*.mqh → <Data>/MQL5/       |
//|          Include/FM/, then compile in MetaEditor (F7).             |
//+------------------------------------------------------------------+
#property copyright "FM-Indicator contributors"
#property version   "1.30"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

//--- DATA buffers (EA-readable, frozen after close)
#property indicator_label1  "Target"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1
#property indicator_label2  "Potential"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_label3  "Developing"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrange
#property indicator_width3  2
#property indicator_label4  "Confirmed"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  3

#include <FM/Defs.mqh>
#include <FM/Config.mqh>
#include <FM/Logger.mqh>
#include <FM/MarketData.mqh>
#include <FM/ATR.mqh>
#include <FM/Swings.mqh>
#include <FM/BarAnalyzer.mqh>
#include <FM/PullbackPatterns.mqh>
#include <FM/MarketState.mqh>
#include <FM/BreakoutEngine.mqh>
#include <FM/ReversalEngine.mqh>
#include <FM/SetupEngine.mqh>
#include <FM/GeneralSetups.mqh>
#include <FM/DecisionEngine.mqh>
#include <FM/MeasuredMove.mqh>
#include <FM/FMEngine.mqh>
#include <FM/Visualizer.mqh>
#include <FM/Alerts.mqh>

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

//--- buffers
double BufTarget[];
double BufPotential[];
double BufDeveloping[];
double BufConfirmed[];
double BufCalcATR[];
double BufCalcSwing[];

//--- engine objects
CFMConfig      g_cfg;
CLogger        g_log;
CMarketData    g_md;
CATR           g_atr;
CSwingDetector g_swings;
CFMEngine      g_engine;
CVisualizer    g_viz;
CAlertManager  g_alerts;
datetime       g_last_closed_time = 0;
bool           g_first_run = true;

void ApplyInputsToConfig()
  {
   g_cfg.SwingK=InpSwingK; g_cfg.MinLegATRMult=InpMinLegATRMult;
   g_cfg.MinLegBars=InpMinLegBars; g_cfg.MaxLegBars=InpMaxLegBars;
   g_cfg.MinPullbackRatio=InpMinPullbackRatio; g_cfg.MaxPullbackRatio=InpMaxPullbackRatio;
   g_cfg.MaxPullbackBars=InpMaxPullbackBars;
   g_cfg.MMToleranceATRMult=InpMMToleranceATRMult;
   g_cfg.MaxOvershootATRMult=InpMaxOvershootATRMult;
   g_cfg.ApproachATRMult=InpApproachATRMult;
   g_cfg.SignalClosePct=InpSignalClosePct; g_cfg.MinBodyRatio=InpMinBodyRatio;
   g_cfg.MaxWickRatio=InpMaxWickRatio;
   g_cfg.RequireEngulf=InpRequireEngulf; g_cfg.RequireFollowThrough=InpRequireFollowThrough;
   g_cfg.EnableInverseMM=InpEnableInverseMM; g_cfg.FailedBOBars=InpFailedBOBars;
   g_cfg.EnableRangeMM=InpEnableRangeMM; g_cfg.RangeLookback=InpRangeLookback;
   g_cfg.EnableChannelMM=InpEnableChannelMM; g_cfg.EnableGapMM=InpEnableGapMM;
   g_cfg.MinGapATRMult=InpMinGapATRMult;
   g_cfg.MinPushes=InpMinPushes; g_cfg.UseWedgeExhaustion=InpUseWedgeExhaustion;
   g_cfg.ShowScore=InpShowScore;
   g_cfg.DojiMaxBodyRatio=InpDojiMaxBodyRatio; g_cfg.BigBarATRMult=InpBigBarATRMult;
   g_cfg.SmallBarATRMult=InpSmallBarATRMult; g_cfg.StrongClosePct=InpStrongClosePct;
   g_cfg.EnableBarAnalysis=InpEnableBarAnalysis;
   g_cfg.MinPullbackDepthATRMult=InpMinPullbackDepthATRMult;
   g_cfg.DoubleTopTolATRMult=InpDoubleTopTolATRMult;
   g_cfg.MaxDoubleBars=InpMaxDoubleBars;
   g_cfg.MinDoubleTroughATRMult=InpMinDoubleTroughATRMult;
   g_cfg.MicroDoubleBars=InpMicroDoubleBars;
   g_cfg.EnablePullbackPatterns=InpEnablePullbackPatterns;
   g_cfg.StateLookback=InpStateLookback; g_cfg.StateOverlapBars=InpStateOverlapBars;
   g_cfg.EnableMarketState=InpEnableMarketState;
   g_cfg.BOLookback=InpBOLookback; g_cfg.BOToleranceATRMult=InpBOToleranceATRMult;
   g_cfg.BOFollowBars=InpBOFollowBars; g_cfg.BOTrapLookback=InpBOTrapLookback;
   g_cfg.EnableBreakout=InpEnableBreakout;
   g_cfg.RevLookback=InpRevLookback;
   g_cfg.RevRetestTolATRMult=InpRevRetestTolATRMult;
   g_cfg.RevMinPressure=InpRevMinPressure;
   g_cfg.EnableReversal=InpEnableReversal;
   g_cfg.SetupStopBufATRMult=InpSetupStopBufATRMult;
   g_cfg.SetupMinRR=InpSetupMinRR;
   g_cfg.EnableSetup=InpEnableSetup;
   g_cfg.EnableGeneralSetups=InpEnableGeneralSetups;
   g_cfg.GeneralTickProxyATRMult=InpGeneralTickProxyATRMult;
   g_cfg.GeneralObjectiveATRMult=InpGeneralObjectiveATRMult;
   g_cfg.EnableDecision=InpEnableDecision;
   g_cfg.MinDecisionScore=InpMinDecisionScore;
   g_cfg.MaxLateEntryATRMult=InpMaxLateEntryATRMult;
   g_cfg.DecisionConflictPpts=InpDecisionConflictPpts;
   g_cfg.DecisionMaxFailedBO=InpDecisionMaxFailedBO;
   g_cfg.ContextFilter=InpContextFilterMode;
   g_cfg.PriceMode=InpPriceMode;
   g_cfg.MaxActiveSetups=InpMaxActiveSetups; g_cfg.MaxBarsForward=InpMaxBarsForward;
   g_cfg.UseIntrabarPotential=InpUseIntrabarPotential; g_cfg.AtrPeriod=InpAtrPeriod;
   g_cfg.ShowLegs=InpShowLegs; g_cfg.ShowPullbacks=InpShowPullbacks;
   g_cfg.ShowTargets=InpShowTargets; g_cfg.ShowZones=InpShowZones;
   g_cfg.AlertPotential=InpAlertPotential; g_cfg.AlertDeveloping=InpAlertDeveloping;
   g_cfg.AlertConfirmed=InpAlertConfirmed;
   g_cfg.UseSound=InpUseSound; g_cfg.UsePush=InpUsePush; g_cfg.UseMail=InpUseMail;
   g_cfg.SoundFile=InpSoundFile; g_cfg.LogLevel=InpLogLevel;
   if(!g_cfg.Validate()) Print("[FM] inputs clamped to valid ranges (see SPEC §1).");
  }

int OnInit()
  {
   ApplyInputsToConfig();
   g_log.SetLevel(g_cfg.LogLevel);
   g_atr.SetPeriod(g_cfg.AtrPeriod);
   g_swings.SetK(g_cfg.SwingK);
   g_engine.SetLogger(GetPointer(g_log));

   SetIndexBuffer(0, BufTarget, INDICATOR_DATA);
   SetIndexBuffer(1, BufPotential, INDICATOR_DATA);
   SetIndexBuffer(2, BufDeveloping, INDICATOR_DATA);
   SetIndexBuffer(3, BufConfirmed, INDICATOR_DATA);
   SetIndexBuffer(4, BufCalcATR, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, BufCalcSwing, INDICATOR_CALCULATIONS);
   for(int i=0;i<4;i++)
     {
      PlotIndexSetInteger(i, PLOT_ARROW, 159);
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
     }
   PlotIndexSetInteger(0, PLOT_ARROW, 158);
   ArraySetAsSeries(BufTarget, true);
   ArraySetAsSeries(BufPotential, true);
   ArraySetAsSeries(BufDeveloping, true);
   ArraySetAsSeries(BufConfirmed, true);
   ArraySetAsSeries(BufCalcATR, true);
   ArraySetAsSeries(BufCalcSwing, true);
   int begin = g_cfg.AtrPeriod + g_cfg.AtrWarmupExtra + 2*g_cfg.SwingK + 10;
   for(int i=0;i<4;i++) PlotIndexSetInteger(i, PLOT_DRAW_BEGIN, begin);
   g_log.Info("FM v1 init OK. Closed-bar discipline; no future-bar use.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_viz.DeleteAll();
  }

// v2 MTF/LTF overlays (read-only): SMA20/50-gap bias on another timeframe.
// Returns +1/-1/0; never affects the state machine (SPEC §7 LOG_ONLY).
// Shared helper (single formula source); MTFBias/LTFBias differ only by input.
int TFBias(int tfMinutes)
  {
   if(tfMinutes <= 0) return 0;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)tfMinutes;
   double c[];
   int need = 60;
   if(CopyClose(_Symbol, tf, 1, need, c) < need) return 0;
   double s20 = 0, s50 = 0;
   for(int i = 0; i < 20; i++) s20 += c[i];
   for(int i = 0; i < 50; i++) s50 += c[i];
   s20 /= 20.0; s50 /= 50.0;
   double rng = c[0];
   if(rng == 0) return 0;
   double gap = (s20 - s50) / MathMax(1e-9, g_atr.At(1));
   if(gap > 0.8) return +1;
   if(gap < -0.8) return -1;
   return 0;
  }

int MTFBias() { return TFBias(InpMTFTrendTFMinutes); }
int LTFBias() { return TFBias(InpLTFMinutes); }

// v2 research export: append one CSV row per CONFIRMED (closed-bar only).
void ExportSignalRow(datetime bt, const CFMSetup &s, double px, int score)
  {
   int h = FileOpen(InpCSVFile, FILE_CSV|FILE_READ|FILE_WRITE, ',');
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(FileSize(h) == 0)
      FileWrite(h, "time", "id", "family", "dir", "target", "price", "score", "symbol", "tf");
   FileWrite(h, TimeToString(bt, TIME_DATE|TIME_SECONDS), s.id, (int)s.family,
             s.dir, DoubleToString(s.target, _Digits), DoubleToString(px, _Digits),
             score, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
   FileClose(h);
  }

// Full-history incremental core: recompute confirmed structure on new closed
// bar; on tick-without-new-close only optional intrabar POTENTIAL preview.
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < g_cfg.AtrPeriod + 2*g_cfg.SwingK + 20) return(0);
   ArraySetAsSeries(time, true); ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   // Build series copy (series mode, [0]=forming)
   MqlRates rates[];
   ArrayResize(rates, rates_total);
   for(int i=0;i<rates_total;i++)
     {
      rates[i].time=time[i]; rates[i].open=open[i]; rates[i].high=high[i];
      rates[i].low=low[i]; rates[i].close=close[i];
      rates[i].tick_volume=tick_volume[i]; rates[i].real_volume=volume[i]; rates[i].spread=spread[i];
     }

   bool isNewClosedBar = (time[1] != g_last_closed_time);
   if(prev_calculated==0) { g_engine.Reset(); g_swings.Reset(); g_first_run=true; }

   if(prev_calculated==0 || isNewClosedBar)
     {
      g_last_closed_time = time[1];
      // ATR over full copy
      g_atr.Update(rates, rates_total);
      // Swings from confirmed bars only (newest closed shift = 1)
      g_swings.Update(rates, rates_total, 1, g_cfg.PriceMode);

      // Snapshot previous states for edge-triggered buffers/alerts
      int nPrev = g_engine.ActiveCount();
      long prevIds[]; ENUM_FM_STATE prevStates[];
      ArrayResize(prevIds, nPrev); ArrayResize(prevStates, nPrev);
      for(int i=0;i<nPrev;i++) { CFMSetup s; g_engine.GetSetup(i,s); prevIds[i]=s.id; prevStates[i]=s.state; }

      // Copy swings to plain array
      SwingPoint sw[]; ArrayResize(sw, g_swings.Count());
      for(int i=0;i<g_swings.Count();i++) g_swings.Get(i, sw[i]);

      g_engine.FormProjections(sw, rates, rates_total, g_cfg, g_atr, time[1]);
      g_engine.Update(rates, rates_total, 1, g_cfg, g_atr);
       // Phase 1 bar-by-bar analysis (read-only; never gates the state machine).
       if(g_cfg.EnableBarAnalysis)
         {
          BarFeatures bf = CBarAnalyzer::Analyze(rates, rates_total, 1, g_atr.At(1), g_cfg);
          g_log.Debug(CBarAnalyzer::Describe(bf, 1));
         }
       // Phase 2 pullback patterns (read-only; never gates the state machine).
       if(g_cfg.EnablePullbackPatterns)
         {
          int td = CPullbackPatterns::TrendDir(rates, rates_total, 1, g_atr.At(1), g_cfg);
          string pbMsg = StringFormat("PB trend=%d", td);
          if(td > 0)
            {
             PullbackSignal pb = CPullbackPatterns::DetectBull(rates, rates_total, 1, g_atr.At(1), g_cfg);
             if(pb.found) pbMsg += " " + CPullbackPatterns::DescribePB(pb, true);
            }
          else if(td < 0)
            {
             PullbackSignal pb = CPullbackPatterns::DetectBear(rates, rates_total, 1, g_atr.At(1), g_cfg);
             if(pb.found) pbMsg += " " + CPullbackPatterns::DescribePB(pb, false);
            }
          DoubleSignal dTop = CPullbackPatterns::FindDoubleTop(sw, g_atr.At(1), g_cfg);
          DoubleSignal dBot = CPullbackPatterns::FindDoubleBottom(sw, g_atr.At(1), g_cfg);
          if(dTop.found) pbMsg += " " + CPullbackPatterns::DescribeDouble(dTop);
          if(dBot.found) pbMsg += " " + CPullbackPatterns::DescribeDouble(dBot);
          DoubleSignal mTop = CPullbackPatterns::MicroDoubleTop(rates, rates_total, 1, g_atr.At(1), g_cfg);
          DoubleSignal mBot = CPullbackPatterns::MicroDoubleBottom(rates, rates_total, 1, g_atr.At(1), g_cfg);
          if(mTop.found) pbMsg += " " + CPullbackPatterns::DescribeDouble(mTop);
          if(mBot.found) pbMsg += " " + CPullbackPatterns::DescribeDouble(mBot);
          g_log.Debug(pbMsg);
         }
       // Phase 3 market-state engine (read-only; never gates the state machine).
       if(g_cfg.EnableMarketState)
         {
          MarketState ms = CMarketState::Analyze(rates, rates_total, 1, g_atr.At(1), g_cfg);
          g_log.Debug(CMarketState::Describe(ms, 1));
         }
       // Phase 4 breakout engine (read-only; never gates the state machine).
       if(g_cfg.EnableBreakout)
         {
          BreakoutSignal bo = CBreakoutEngine::Analyze(rates, rates_total, 1, g_atr.At(1), sw, g_cfg);
          if(bo.found) g_log.Debug(CBreakoutEngine::Describe(bo));
         }
       // Phase 5 reversal engine (read-only; never gates the state machine).
       if(g_cfg.EnableReversal)
         {
          ReversalSignal rvB = CMajorReversal::Analyze(rates, rates_total, 1, g_atr.At(1), sw, g_cfg, +1);
          ReversalSignal rvS = CMajorReversal::Analyze(rates, rates_total, 1, g_atr.At(1), sw, g_cfg, -1);
          if(rvB.found) g_log.Debug(CMajorReversal::Describe(rvB));
          if(rvS.found) g_log.Debug(CMajorReversal::Describe(rvS));
          ExhaustionReport exB = CExhaustionAnalyzer::Report(rates, rates_total, 1, +1, g_atr.At(1), g_cfg);
          ExhaustionReport exS = CExhaustionAnalyzer::Report(rates, rates_total, 1, -1, g_atr.At(1), g_cfg);
          if(exB.breadth > 0) g_log.Debug(CExhaustionAnalyzer::Describe(exB, +1));
          if(exS.breadth > 0) g_log.Debug(CExhaustionAnalyzer::Describe(exS, -1));
          LegCount lgB = CLegCounter::CountBull(sw);
          LegCount lgS = CLegCounter::CountBear(sw);
          if(lgB.valid && lgB.legs > 0) g_log.Debug(CLegCounter::Describe(lgB, +1));
          if(lgS.valid && lgS.legs > 0) g_log.Debug(CLegCounter::Describe(lgS, -1));
         }
       // Phase 6 FM setup plans (read-only; never gates the state machine).
       if(g_cfg.EnableSetup)
         {
          for(int i=0;i<g_engine.ActiveCount();i++)
            {
             CFMSetup s; if(!g_engine.GetSetup(i,s)) continue;
             if(s.state!=FM_DEVELOPING && s.state!=FM_CONFIRMED) continue;
             int sh=-1;
             for(int k=1;k<rates_total;k++)
               if(rates[k].time==s.signal_time) { sh=k; break; }
             if(sh<1) continue;
             SetupPlan pl=CSetupPlanner::Plan(rates[sh],s.dir,s.target,s.b0.price,
                g_atr.At(1),g_cfg,s.id,s.family,s.state==FM_CONFIRMED,sh);
              if(pl.valid) g_log.Debug(CSetupPlanner::Describe(pl));
             }
          }
       // Phase 7 general setup catalog (read-only; never gates the state machine).
       GeneralSetup genBest; CGeneralSetups::InitNone(genBest);
       bool haveGen=false;
       double atrNow7=g_atr.At(1);
       if(g_cfg.EnableGeneralSetups && atrNow7>0)
         {
          GeneralSetup cand[];
          ArrayResize(cand,0);
          int wEnd7=1+g_cfg.MaxPullbackBars;
          if(wEnd7>=rates_total) wEnd7=rates_total-1;
          int td7=CPullbackPatterns::TrendDir(rates,rates_total,1,atrNow7,g_cfg);
          if(td7>0)
            {
             PullbackSignal pbB=CPullbackPatterns::DetectBull(rates,rates_total,1,atrNow7,g_cfg);
             if(pbB.found && pbB.signalBar>=1 && pbB.signalBar<rates_total)
               {
                double winH=rates[1].high;
                for(int w=2;w<=wEnd7;w++) if(rates[w].high>winH) winH=rates[w].high;
                GeneralSetup g=CGeneralSetups::FromPullbackBull(pbB,rates[pbB.signalBar].high,pbB.stop,winH,atrNow7,g_cfg);
                if(g.valid) { int n=ArraySize(cand); ArrayResize(cand,n+1); cand[n]=g; g_log.Debug(CGeneralSetups::Describe(g)); }
               }
            }
          else if(td7<0)
            {
             PullbackSignal pbS=CPullbackPatterns::DetectBear(rates,rates_total,1,atrNow7,g_cfg);
             if(pbS.found && pbS.signalBar>=1 && pbS.signalBar<rates_total)
               {
                double winL=rates[1].low;
                for(int w=2;w<=wEnd7;w++) if(rates[w].low<winL) winL=rates[w].low;
                GeneralSetup g=CGeneralSetups::FromPullbackBear(pbS,rates[pbS.signalBar].low,pbS.stop,winL,atrNow7,g_cfg);
                if(g.valid) { int n=ArraySize(cand); ArrayResize(cand,n+1); cand[n]=g; g_log.Debug(CGeneralSetups::Describe(g)); }
               }
            }
          DoubleSignal darr[4];
          darr[0]=CPullbackPatterns::FindDoubleTop(sw,atrNow7,g_cfg);
          darr[1]=CPullbackPatterns::FindDoubleBottom(sw,atrNow7,g_cfg);
          darr[2]=CPullbackPatterns::MicroDoubleTop(rates,rates_total,1,atrNow7,g_cfg);
          darr[3]=CPullbackPatterns::MicroDoubleBottom(rates,rates_total,1,atrNow7,g_cfg);
          for(int di=0;di<4;di++)
            {
             if(!darr[di].found) continue;
             int b1=darr[di].bar1, b2=darr[di].bar2;
             if(b1<1||b2<1||b1>=rates_total||b2>=rates_total) continue;
             int lo=(b2<b1?b2:b1), hi=(b2<b1?b1:b2);
             double trough=0; bool tInit=false;
             for(int k=lo;k<=hi;k++)
               {
                double v=(darr[di].dir<0?rates[k].low:rates[k].high);
                if(!tInit) { trough=v; tInit=true; }
                else if(darr[di].dir<0) { if(v<trough) trough=v; }
                else { if(v>trough) trough=v; }
               }
             if(!tInit) continue;
             GeneralSetup g=CGeneralSetups::FromDouble(darr[di],trough,atrNow7,g_cfg);
             if(g.valid) { int n=ArraySize(cand); ArrayResize(cand,n+1); cand[n]=g; g_log.Debug(CGeneralSetups::Describe(g)); }
            }
          BreakoutSignal bo7=CBreakoutEngine::Analyze(rates,rates_total,1,atrNow7,sw,g_cfg);
          if(bo7.found)
            {
             GeneralSetup g=CGeneralSetups::FromBreakout(bo7,close[1],atrNow7,g_cfg);
             if(g.valid) { int n=ArraySize(cand); ArrayResize(cand,n+1); cand[n]=g; g_log.Debug(CGeneralSetups::Describe(g)); }
            }
          int revK=g_cfg.RevLookback;
          if(revK<5) revK=5;
          if(revK>50) revK=50;
          double emaTail[];
          CMajorReversal::EMA20Tail(rates,rates_total,1,revK,emaTail);
          if(ArraySize(emaTail)>0)
            {
             ReversalSignal rvB=CMajorReversal::Analyze(rates,rates_total,1,atrNow7,sw,g_cfg,+1);
             ReversalSignal rvS=CMajorReversal::Analyze(rates,rates_total,1,atrNow7,sw,g_cfg,-1);
             if(rvB.found)
               {
                GeneralSetup g=CGeneralSetups::FromReversal(rvB,close[1],emaTail[0],atrNow7,g_cfg);
                if(g.valid) { int n=ArraySize(cand); ArrayResize(cand,n+1); cand[n]=g; g_log.Debug(CGeneralSetups::Describe(g)); }
               }
             if(rvS.found)
               {
                GeneralSetup g=CGeneralSetups::FromReversal(rvS,close[1],emaTail[0],atrNow7,g_cfg);
                if(g.valid) { int n=ArraySize(cand); ArrayResize(cand,n+1); cand[n]=g; g_log.Debug(CGeneralSetups::Describe(g)); }
               }
            }
          int best7=CGeneralSetups::SelectBest(cand);
          if(best7>=0) { genBest=cand[best7]; haveGen=true; }
          // FM contest: best DEVELOPING/CONFIRMED plan joins with its ScoreSignal
          // and displaces the general best only on a strictly greater score.
          int fmScoreBest=-1;
          SetupPlan fmPlanBest; fmPlanBest.valid=false;
          for(int i=0;i<g_engine.ActiveCount();i++)
            {
             CFMSetup s; if(!g_engine.GetSetup(i,s)) continue;
             if(s.state!=FM_DEVELOPING && s.state!=FM_CONFIRMED) continue;
             int sh=-1;
             for(int k=1;k<rates_total;k++)
               if(rates[k].time==s.signal_time) { sh=k; break; }
             if(sh<1) continue;
             SetupPlan pl=CSetupPlanner::Plan(rates[sh],s.dir,s.target,s.b0.price,
                atrNow7,g_cfg,s.id,s.family,s.state==FM_CONFIRMED,sh);
             if(!pl.valid) continue;
             int fdir=-s.dir;
             double dtAtr=(s.dir>0?(s.target-high[1]):(low[1]-s.target))/atrNow7;
             int q=CConfirmation::ScoreSignal(rates,rates_total,1,fdir,g_cfg,s.dir,atrNow7,dtAtr,s.confidence);
             if(q>fmScoreBest) { fmScoreBest=q; fmPlanBest=pl; }
            }
          if(fmPlanBest.valid && (!haveGen || fmScoreBest>genBest.score))
            {
             GeneralSetup f; CGeneralSetups::InitNone(f);
             f.valid=true; f.type=SETUP_FM_FADE; f.dir=fmPlanBest.fadeDir;
             f.entry=fmPlanBest.entry; f.stop=fmPlanBest.stop;
             f.objective=fmPlanBest.objective;
             f.riskPts=fmPlanBest.riskPts; f.rewardPts=fmPlanBest.rewardPts;
             f.rMult=fmPlanBest.rMult; f.rrOK=fmPlanBest.rrOK;
             f.provisional=fmPlanBest.provisional;
             f.signalBar=fmPlanBest.signalShift; f.refPrice=fmPlanBest.entry;
             f.score=fmScoreBest;
             genBest=f; haveGen=true;
             g_log.Debug(CGeneralSetups::Describe(f));
            }
         }
       // Phase 8 decision engine (read-only; never gates the state machine).
       if(g_cfg.EnableDecision)
         {
          DecisionContext dctx;
          MarketState ms8=CMarketState::Analyze(rates,rates_total,1,atrNow7,g_cfg);
          dctx.state=ms8.state;
          dctx.pct[0]=ms8.pctBullTrend; dctx.pct[1]=ms8.pctBearTrend;
          dctx.pct[2]=ms8.pctBullChannel; dctx.pct[3]=ms8.pctBearChannel;
          dctx.pct[4]=ms8.pctRange; dctx.pct[5]=ms8.pctBreakout;
          dctx.pctValid=ms8.valid;
          BarFeatures bf8=CBarAnalyzer::Analyze(rates,rates_total,1,atrNow7,g_cfg);
          dctx.barbwire=(bf8.valid && bf8.barbwire);
          dctx.close=close[1];
          dctx.midRange=false;
          if(ms8.state==MS_TRADING_RANGE)
            {
             int L8=g_cfg.StateLookback;
             if(L8<10) L8=10;
             if(L8>=rates_total) L8=rates_total-1;
             double hh=rates[1].high, ll=rates[1].low;
             for(int w=2;w<=L8;w++)
               {
                if(rates[w].high>hh) hh=rates[w].high;
                if(rates[w].low<ll) ll=rates[w].low;
               }
             if(hh>ll)
               {
                double pos=(close[1]-ll)/(hh-ll);
                dctx.midRange=(pos>=1.0/3.0 && pos<=2.0/3.0);
               }
            }
          dctx.failCount=0; dctx.hasFollow=false;
          int scanN=20;
          if(scanN>=rates_total) scanN=rates_total-1;
          for(int j=1;j<=scanN;j++)
            {
             BreakoutSignal bj=CBreakoutEngine::Analyze(rates,rates_total,j,atrNow7,sw,g_cfg);
             if(!bj.found) continue;
             if(bj.outcome==BO_FAILED) dctx.failCount++;
             if(bj.outcome==BO_FOLLOW_THROUGH) dctx.hasFollow=true;
            }
          Decision dec=CDecisionEngine::Decide(genBest,dctx,atrNow7,g_cfg);
          g_log.Debug(CDecisionEngine::Describe(dec));
          color dc=(dec.action==DEC_BUY?clrLime:(dec.action==DEC_SELL?clrRed:(dec.action==DEC_WAIT?clrOrange:clrGray)));
          string dtxt=StringFormat("%s %s",CDecisionEngine::ActionName(dec.action),CDecisionEngine::ReasonName(dec.reason));
          if(ObjectFind(0,"FM_DECISION")<0) ObjectCreate(0,"FM_DECISION",OBJ_TEXT,0,time[1],close[1]);
          ObjectSetString(0,"FM_DECISION",OBJPROP_TEXT,dtxt);
          ObjectSetInteger(0,"FM_DECISION",OBJPROP_COLOR,dc);
          ObjectSetInteger(0,"FM_DECISION",OBJPROP_FONTSIZE,9);
          ObjectSetInteger(0,"FM_DECISION",OBJPROP_ANCHOR,ANCHOR_RIGHT);
          ObjectMove(0,"FM_DECISION",0,time[1],close[1]);
          // v2 LTF entry confirmation (read-only; never gates the state machine).
          if(InpLTFMinutes>0)
            {
             int ltfB=LTFBias();
             string lc=((ltfB==0||dec.dir==0)?"NEUTRAL":((ltfB==dec.dir)?"AGREE":"DISAGREE"));
             g_log.Info(StringFormat("LTF confirm=%s (LTF %d min bias=%d vs %s %s, LOG_ONLY)",
                lc,InpLTFMinutes,ltfB,CGeneralSetups::TypeName(dec.setupType),
                CDecisionEngine::ActionName(dec.action)));
            }
         }
      // v2 MTF overlay (read-only annotation; never gates the state machine).
      if(InpMTFTrendTFMinutes > 0)
         g_log.Info(StringFormat("MTF bias=%d (HTF %d min, LOG_ONLY)", MTFBias(), InpMTFTrendTFMinutes));

      // Write DATA buffers at shift 1 (the just-closed bar). Never rewrite older
      // shifts here → freeze guarantee (history built bar-by-bar identically).
      BufTarget[1] = EMPTY_VALUE; BufPotential[1]=EMPTY_VALUE;
      BufDeveloping[1]=EMPTY_VALUE; BufConfirmed[1]=EMPTY_VALUE;
      BufCalcATR[1]=g_atr.At(1);
      for(int i=0;i<g_engine.ActiveCount();i++)
        {
         CFMSetup s; g_engine.GetSetup(i,s);
         // find prev state
         ENUM_FM_STATE ps = FM_PROJECTED;
         for(int k=0;k<nPrev;k++) if(prevIds[k]==s.id) { ps=prevStates[k]; break; }
         bool isNew = true;
         for(int k=0;k<nPrev;k++) if(prevIds[k]==s.id) { isNew=false; break; }
         if(isNew && s.state==FM_PROJECTED)
           {
            // mark target existence at B0 bar for chart archaeology (shift of b0)
            // (informational; does not move afterwards)
           }
         if(s.state!=ps) // edge transition on this closed bar
           {
            double px = close[1];
            if(s.state==FM_POTENTIAL) BufPotential[1]=px;
            else if(s.state==FM_DEVELOPING) BufDeveloping[1]=px;
            else if(s.state==FM_CONFIRMED)
              {
               BufConfirmed[1]=px;
               if(InpExportCSV)
                 {
                  int fdir = -s.dir;
                  double dt = (g_atr.At(1) > 0) ? ((s.dir > 0 ? s.target - high[1] : low[1] - s.target) / g_atr.At(1)) : 0;
                  int q = CConfirmation::ScoreSignal(rates, rates_total, 1, fdir, g_cfg, s.dir, g_atr.At(1), dt, s.confidence);
                  ExportSignalRow(time[1], s, px, q);
                 }
              }
            if(s.state==FM_CONFIRMED || s.state==FM_DEVELOPING || s.state==FM_POTENTIAL)
              {
               if(g_engine.ClaimAlert(s.id, s.state))
                  g_alerts.Dispatch(g_cfg, s.id, s.state, s.dir, _Symbol, (ENUM_TIMEFRAMES)_Period, px, s.target);
              }
           }
         if(s.state==FM_PROJECTED || s.state==FM_POTENTIAL || s.state==FM_DEVELOPING)
            if(BufTarget[1]==EMPTY_VALUE) BufTarget[1]=s.target;
        }
      g_viz.Sync(rates, rates_total, g_engine, g_cfg, g_atr.At(1));
      g_first_run=false;
      return(rates_total);
     }

   // Tick without new close: optional intrabar POTENTIAL preview only.
   if(g_cfg.UseIntrabarPotential && !g_first_run)
     {
      // preview only — never writes DEVELOPING/CONFIRMED, never alerts twice
      // (implemented as visual nudge; state machine untouched)
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
