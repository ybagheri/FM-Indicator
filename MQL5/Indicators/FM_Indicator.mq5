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
input int    InpMTFTrendTFMinutes   = 0;      // v2 MTF overlay: 0=off, else higher-TF minutes
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

// v2 MTF overlay (read-only): higher-TF bias from 20/50 SMA on closed bars.
// Returns +1/-1/0; never affects the state machine (SPEC §7 LOG_ONLY).
int MTFBias()
  {
   if(InpMTFTrendTFMinutes <= 0) return 0;
   ENUM_TIMEFRAMES htf = (ENUM_TIMEFRAMES)InpMTFTrendTFMinutes;
   double c[];
   int need = 60;
   if(CopyClose(_Symbol, htf, 1, need, c) < need) return 0;
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
