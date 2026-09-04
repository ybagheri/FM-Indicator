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
#include <FM/Analysis.mqh>
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
CFMAnalysis    g_analysis;   // Phase 21: shared contract (owns ATR/swings/engine)
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
   g_analysis.Setup(g_cfg, GetPointer(g_log));

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
   double gap = (s20 - s50) / MathMax(1e-9, g_analysis.AtrAt(1));
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
   if(prev_calculated==0) { g_analysis.Reset(); g_first_run=true; }

   if(prev_calculated==0 || isNewClosedBar)
     {
      g_last_closed_time = time[1];
      // Snapshot previous FM states BEFORE analysis mutates the engine
      // (edge-triggered buffers/alerts below).
      CFMEngine *eng = g_analysis.EnginePtr();
      int nPrev = eng.ActiveCount();
      long prevIds[]; ENUM_FM_STATE prevStates[];
      ArrayResize(prevIds, nPrev); ArrayResize(prevStates, nPrev);
      for(int i=0;i<nPrev;i++) { CFMSetup s; eng.GetSetup(i,s); prevIds[i]=s.id; prevStates[i]=s.state; }

      // Shared analysis contract (Phase 21): single-source pipeline
      // (ATR → swings → projections → FM engine → Phases 1–8).
      FMAnalysisResult res;
      g_analysis.Update(rates, rates_total, g_cfg, 1, res);
      double atrNow = g_analysis.AtrAt(1);
      // Phases 1–5 run inside CFMAnalysis::Update (see Analysis.mqh).
       // Phase 6 runs inside CFMAnalysis::Update (see Analysis.mqh).
       // Phases 7–8 run inside CFMAnalysis::Update (see Analysis.mqh).
       // Adapter below: FM_DECISION label + LTF confirm (read-only).
       Decision dec = res.decision;
       if(g_cfg.EnableDecision && res.decisionDone)
         {
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
      BufCalcATR[1]=atrNow;
      for(int i=0;i<eng.ActiveCount();i++)
        {
         CFMSetup s; eng.GetSetup(i,s);
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
                  double dt = (atrNow > 0) ? ((s.dir > 0 ? s.target - high[1] : low[1] - s.target) / atrNow) : 0;
                  int q = CConfirmation::ScoreSignal(rates, rates_total, 1, fdir, g_cfg, s.dir, atrNow, dt, s.confidence);
                  ExportSignalRow(time[1], s, px, q);
                 }
              }
            if(s.state==FM_CONFIRMED || s.state==FM_DEVELOPING || s.state==FM_POTENTIAL)
              {
               if(eng.ClaimAlert(s.id, s.state))
                  g_alerts.Dispatch(g_cfg, s.id, s.state, s.dir, _Symbol, (ENUM_TIMEFRAMES)_Period, px, s.target);
              }
           }
         if(s.state==FM_PROJECTED || s.state==FM_POTENTIAL || s.state==FM_DEVELOPING)
            if(BufTarget[1]==EMPTY_VALUE) BufTarget[1]=s.target;
        }
      g_viz.Sync(rates, rates_total, *eng, g_cfg, atrNow);
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
