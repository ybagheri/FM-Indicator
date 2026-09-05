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
#include <FM/StrategyRegistry.mqh>  // Phase 1: parity — mode/single/enable/AUTO types + registry
#include <FM/ParityDecision.mqh>    // Phase 3: parity — shared candidate/selection builder
#include <FM/TradeIntent.mqh>       // Phase 5: parity — closed-bar intent projection

#include <FM/Inputs.mqh>     // Phase 23: shared analysis inputs (verbatim)

//--- parity inputs (Phase 1: decision-affecting EA selection inputs mirrored
//--- with IDENTICAL defaults; see FM_EA.mq5:27-34,62-71. NOT in Inputs.mqh:
//--- that file is shared verbatim, and the EA already defines these inputs —
//--- duplicating them there would break the EA build with redefinitions.
//--- .set presets bind by NAME, so EA presets drive these too.)
input ENUM_STRATEGY_MODE InpStratMode       = STRAT_MODE_AUTO;
input ENUM_FM_STRATEGY   InpSingleStrategy  = STRAT_FM_FADE;
input bool               InpUseFM           = true;
input bool               InpUsePullback     = true;
input bool               InpUseBreakout     = true;
input bool               InpUseReversal     = true;
input bool               InpUseDouble       = true;
input bool               InpUseFailedBO     = true;
input int                InpAutoTrendBonus  = 10;
input int                InpAutoProvPenalty = 5;
input int                InpAutoRRBonus     = 5;
input double             InpAutoRRLevel     = 2.0;
input bool               InpApplyStructuralVeto = true;  // EXP-0002 apparatus
input bool               InpTradeProvisional    = false; // intent gate (Phase 5)
input double             InpChaseATRMult        = 0.50;  // intent chase (Phase 5)
input double             InpRiskMinRR           = 1.0;   // risk LOW_RR projection, 0=off (Phase 5)
input int                InpMaxHoldBars         = 5;     // intent max-hold projection (Phase 5)

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
CStrategyRegistry g_registry; // Phase 1: parity — configured, selection wired in Phase 4
FMParityDecision g_parity;       // Phase 3: parity — shared builder output (universe+selection)
CTradeIntentBuilder g_indIntent; // Phase 5: parity — closed-bar intent projection
datetime       g_last_closed_time = 0;
bool           g_first_run = true;

void ApplyInputsToConfig() { FM_ApplyInputs(g_cfg); }  // shared (Inputs.mqh)

int OnInit()
  {
   ApplyInputsToConfig();
   g_log.SetLevel(g_cfg.LogLevel);
   g_analysis.Setup(g_cfg, GetPointer(g_log));
   // Phase 1 parity: same registry configuration call as FM_EA.mq5:101-103.
   // Selection itself is wired in Phase 4; analysis path unchanged (byte-identical).
   g_registry.Configure(InpStratMode, InpSingleStrategy,
                        InpUseFM, InpUsePullback, InpUseBreakout,
                        InpUseReversal, InpUseDouble, InpUseFailedBO);
   // Phase 5 parity: same intent configuration as FM_EA.mq5:112.
   g_indIntent.Configure(InpTradeProvisional, InpMaxHoldBars, InpChaseATRMult);

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
       // Phase 3 parity: shared builder — the same universe + Select/SelectAuto
       // the EA evaluates (CParityBuilder::Build). Selection display wired in
       // Phase 4; Decide/veto/intent fields filled in Phase 5.
       AutoTuning indTune;
       indTune.trendBonus = InpAutoTrendBonus;
       indTune.provPenalty = InpAutoProvPenalty;
       indTune.rrBonus = InpAutoRRBonus;
       indTune.rrLevel = InpAutoRRLevel;
       CParityBuilder::Build(res, g_cfg, g_registry, InpStratMode, indTune, g_parity);
       int nIndCand = g_parity.candCount;
       string indCensus = "";
       for(int cci = 0; cci < g_parity.candCount; cci++)
          indCensus += StringFormat(" %s/%d%s",
             CStrategyRegistry::StrategyName(g_parity.candidates[cci].strategy),
             g_parity.candidates[cci].setup.score,
             (g_parity.candidates[cci].setup.provisional ? "P" : ""));
       g_log.Debug(StringFormat("REGISTRY cands=%d:%s", nIndCand, indCensus));
      // Phases 1–5 run inside CFMAnalysis::Update (see Analysis.mqh).
       // Phase 6 runs inside CFMAnalysis::Update (see Analysis.mqh).
       // Phases 7–8 run inside CFMAnalysis::Update (see Analysis.mqh).
       // Phase 4 parity: Decide on the REGISTRY selection (the same
       // Select/SelectAuto output the EA trades off), not on the score-max
       // best. SINGLE/MULTI/AUTO semantics therefore match the EA exactly.
       Decision dec;
       dec.action = DEC_NO_TRADE; dec.reason = REASON_NO_SETUP; dec.dir = 0;
       dec.setupType = SETUP_NONE; dec.entry = 0; dec.stop = 0;
       dec.objective = 0; dec.rMult = 0; dec.score = 0;
       if(g_cfg.EnableDecision && res.decisionDone && g_parity.selection.hasTrade)
          dec = CDecisionEngine::Decide(g_parity.selection.setup, res.dctx, res.atr, g_cfg);
       else if(!g_cfg.EnableDecision)
          dec.reason = REASON_DISABLED;
       g_parity.decision = dec;
       // Phase 5 parity: EA final-signal pipeline mirrored at the closed bar —
       // veto (shared DetectVeto, same best-based coupling as the EA) →
       // risk LOW_RR projection (Check order/gate, strict, verbatim) →
       // intent projection at the closed-bar close (EA uses next-tick Ask/Bid;
       // live-tick chase/side divergence is expected and documented).
       ENUM_DECISION_REASON indVetoDr = REASON_OK;
       CParityBuilder::DetectVeto(res, g_parity.selection, g_parity.vetoWhy, indVetoDr);
       bool indVetoApplied = (g_parity.vetoWhy != "" && InpApplyStructuralVeto);
       string indRiskWhy = "";
       if(!indVetoApplied && g_parity.selection.hasTrade && InpRiskMinRR > 0 &&
          g_parity.selection.setup.rMult < InpRiskMinRR)
          indRiskWhy = "LOW_RR";
       TradeIntent indTI;
       string indSkip = "";
       bool indMade = false;
       if(!indVetoApplied && g_parity.selection.hasTrade && indRiskWhy == "")
         {
          double indPx = res.dctx.close;
          ENUM_FM_STRATEGY iss = g_parity.selection.strategy;
          GeneralSetup ssel = g_parity.selection.setup;
          if(iss == STRAT_FM_FADE)
             indMade = g_indIntent.FromFM(ssel, res, indPx, indSkip, indTI);
          else if(iss == STRAT_FAILED_BO)
             indMade = g_indIntent.FromFailedBO(ssel, indPx, res.atr, indSkip, indTI);
          else if(iss == STRAT_PULLBACK)
             indMade = g_indIntent.FromPullback(ssel, indPx, res.atr, indSkip, indTI);
          else if(iss == STRAT_BREAKOUT)
             indMade = g_indIntent.FromBreakout(ssel, indPx, res.atr, indSkip, indTI);
          else if(iss == STRAT_REVERSAL)
             indMade = g_indIntent.FromReversal(ssel, indPx, res.atr, indSkip, indTI);
          else if(iss == STRAT_DOUBLE)
             indMade = g_indIntent.FromDouble(ssel, indPx, res.atr, indSkip, indTI);
          else
             indSkip = "NO_STRATEGY";
         }
       string finAct;
       string finWhy;
       if(indVetoApplied)
         { finAct = "NO_TRADE"; finWhy = g_parity.vetoWhy; }
       else if(!g_parity.selection.hasTrade)
         { finAct = "NO_TRADE"; finWhy = "NO_SETUP"; }
       else if(indRiskWhy != "")
         { finAct = "NO_TRADE"; finWhy = "SKIP_" + indRiskWhy; }
       else if(indMade)
         {
          finAct = (indTI.dir > 0 ? "BUY" : "SELL");
          finWhy = StringFormat("R=%.2f", indTI.rMult);
          g_parity.intentWhy = StringFormat("WOULD_%s", finAct);
          g_parity.intentDir = indTI.dir;
         }
       else
         {
          finAct = "NO_TRADE"; finWhy = "SKIP_" + indSkip;
          g_parity.intentWhy = "SKIP_" + indSkip;
          g_parity.intentDir = 0;
         }
       g_log.Debug(StringFormat("PARITY final=%s %s dec=%s/%s veto=%s intent=%s",
          finAct, CStrategyRegistry::StrategyName(g_parity.selection.strategy),
          CDecisionEngine::ActionName(dec.action), CDecisionEngine::ReasonName(dec.reason),
          (g_parity.vetoWhy == "" ? "-" : g_parity.vetoWhy),
          (g_parity.intentWhy == "" ? "-" : g_parity.intentWhy)));
       // Adapter below: FM_DECISION label + LTF confirm (read-only).
       if(g_cfg.EnableDecision && res.decisionDone)
         {
          color dc=((finAct == "BUY") ? clrLime : ((finAct == "SELL") ? clrRed : clrGray));
          string stratTxt = CStrategyRegistry::StrategyName(g_parity.selection.strategy);
          string modeTxt = CStrategyRegistry::ModeName(InpStratMode);
          string finTxt = ((InpStratMode == STRAT_MODE_AUTO && g_parity.autoFinal >= 0)
                           ? StringFormat(" f=%d", g_parity.autoFinal) : "");
          string dtxt=StringFormat("%s %s %s %s%s",finAct,finWhy,modeTxt,stratTxt,finTxt);
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
