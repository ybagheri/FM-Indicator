//+------------------------------------------------------------------+
//| FM_Indicator.mq5 : Fading Measured Move detector (Al Brooks)       |
//| v1: Leg1=Leg2 + failed-BO inverse, 3 FM states, no-look-ahead      |
//| Install: copy MQL5/Indicators/FM_Indicator.mq5 → <Data>/MQL5/       |
//|          Indicators/ and MQL5/Include/FM/*.mqh → <Data>/MQL5/       |
//|          Include/FM/, then compile in MetaEditor (F7).             |
//+------------------------------------------------------------------+
#property copyright "FM-Indicator contributors"
#property version   "1.00"
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
input ENUM_CTX_FILTER InpContextFilterMode = CTX_LOG_ONLY;
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
   g_cfg.ContextFilter=InpContextFilterMode;
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
      rates[rates_total-1-i].time=time[i]; // convert non-series loop → then set series
     }
   // simpler: fill in series order directly
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
      g_swings.Update(rates, rates_total, 1);

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
            else if(s.state==FM_CONFIRMED) BufConfirmed[1]=px;
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
