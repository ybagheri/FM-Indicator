//+------------------------------------------------------------------+
//| FM_EA.mq5 : Al Brooks-inspired Price Action EA (Phase 23)          |
//| ANALYSIS_ONLY skeleton: consumes the SHARED engine (CFMAnalysis +  |
//| CStrategyRegistry), logs decisions, places NO orders. Execution,   |
//| risk and position layers arrive in Phases 24–26.                   |
//| Non-repainting: closed bars only (shift>=1), one analysis per bar.  |
//+------------------------------------------------------------------+
#property copyright "FM-Indicator contributors"
#property version   "1.00"
#property strict

#include <FM/Config.mqh>
#include <FM/Defs.mqh>
#include <FM/Logger.mqh>
#include <FM/Analysis.mqh>
#include <FM/StrategyRegistry.mqh>
#include <FM/RiskManager.mqh>
#include <FM/ExecutionEngine.mqh>  // Phase 25: constructed+configured, no calls yet
#include <FM/PositionManager.mqh>  // Phase 26: manage/BE/trail owned positions
#include <FM/TradeIntent.mqh>      // Phase 27+: selection → trade intent
#include <FM/Inputs.mqh>       // shared analysis inputs (verbatim)

//--- EA inputs (Phase 23: selection + identity only; trading inputs later)
input ENUM_STRATEGY_MODE InpStratMode      = STRAT_MODE_AUTO;
input ENUM_FM_STRATEGY   InpSingleStrategy = STRAT_FM_FADE;
input bool               InpUseFM          = true;
input bool               InpUsePullback    = true;
input bool               InpUseBreakout    = true;
input bool               InpUseReversal    = true;
input bool               InpUseDouble      = true;
input bool               InpUseFailedBO    = true;   // Phase 28
input long               InpMagic          = 20260904;
input int                InpHistoryBars    = 1500;
//--- risk inputs (Phase 24; sizing + caps, still ANALYSIS_ONLY)
input ENUM_LOT_MODE      InpLotMode        = LOT_RISK_PCT;
input double             InpFixedLot       = 0.10;
input double             InpRiskPct        = 1.0;
input double             InpMoneyRisk      = 100.0;
input double             InpMaxDailyLoss   = 0.0;   // money, 0=off
input int                InpMaxTradesDay   = 5;     // 0=off
input int                InpMaxOpenPos     = 1;     // 0=off
input int                InpMaxPerSymbol   = 1;     // 0=off
input int                InpMaxConsecLoss  = 3;     // 0=off
input int                InpMaxSpreadPts   = 50;    // points, 0=off
input double             InpRiskMinRR      = 1.0;   // 0=off
//--- execution inputs (Phase 25: configured only; orders need Phase 33 mode)
input int                InpSlippagePts    = 10;
//--- position inputs (Phase 26; strategy-permits refined in Phases 27-30)
input bool               InpUseTrailing    = false;
input int                InpTrailStartPts  = 300;
input int                InpTrailStepPts   = 50;
input bool               InpUseBreakEven   = true;
input int                InpBETriggerPts   = 300;
input int                InpBEOffsetPts    = 20;
//--- intent inputs (Phases 27–30; entries still need Phase 33 mode)
input bool               InpTradeProvisional = false;
input int                InpMaxHoldBars    = 5;
input double             InpChaseATRMult   = 0.50;
//--- AUTO tuning (Phase 31)
input int                InpAutoTrendBonus = 10;
input int                InpAutoProvPenalty = 5;
input int                InpAutoRRBonus    = 5;
input double             InpAutoRRLevel    = 2.0;

CFMConfig         g_cfg;
CLogger           g_log;
CFMAnalysis       g_analysis;
CStrategyRegistry g_registry;
CRiskManager      g_risk;
CExecutionEngine  g_exec;
CPositionManager  g_pos;
CTradeIntentBuilder g_intent;
datetime          g_last_bar = 0;
long              g_bars = 0;
long              g_selCount[STRAT_COUNT];
long              g_riskOK = 0;
long              g_veto = 0;

int OnInit()
  {
   FM_ApplyInputs(g_cfg);
   g_log.SetLevel(g_cfg.LogLevel);
   g_analysis.Setup(g_cfg, GetPointer(g_log));
   g_registry.Configure(InpStratMode, InpSingleStrategy,
                        InpUseFM, InpUsePullback, InpUseBreakout,
                        InpUseReversal, InpUseDouble, InpUseFailedBO);
   g_risk.Configure(InpLotMode, InpFixedLot, InpRiskPct, InpMoneyRisk,
                    InpMaxDailyLoss, InpMaxTradesDay, InpMaxOpenPos,
                    InpMaxPerSymbol, InpMaxConsecLoss, InpMaxSpreadPts,
                    InpRiskMinRR, InpMagic);
   g_exec.Configure(InpMagic, InpSlippagePts, InpMaxSpreadPts);
   g_pos.Configure(InpMagic, InpSlippagePts, InpUseTrailing, InpTrailStartPts,
                   InpTrailStepPts, InpUseBreakEven, InpBETriggerPts,
                   InpBEOffsetPts);
   g_intent.Configure(InpTradeProvisional, InpMaxHoldBars, InpChaseATRMult);
   // Restart recovery: adopt already-open magic positions (logged, generic).
   PositionFix adopted[];
   int nAdopt = g_pos.Refresh(_Symbol, adopted);
   if(nAdopt > 0)
      PrintFormat("[FM_EA] adopted %d open position(s) on init", nAdopt);
   ArrayInitialize(g_selCount, 0);
   PrintFormat("[FM_EA] init OK mode=%s magic=%d history=%d (ANALYSIS_ONLY, no orders)",
               CStrategyRegistry::ModeName(InpStratMode), InpMagic, InpHistoryBars);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   string s = "";
   for(int i = 1; i < STRAT_COUNT; i++)
      s += StringFormat(" %s=%d", CStrategyRegistry::StrategyName((ENUM_FM_STRATEGY)i), g_selCount[i]);
   PrintFormat("[FM_EA] done bars=%d riskOK=%d veto=%d selections:%s reason=%d", g_bars, g_riskOK, g_veto, s, reason);
  }

void OnTick()
  {
   datetime bt0 = iTime(_Symbol, _Period, 0);
   if(bt0 == 0 || bt0 == g_last_bar)
      return;                       // new closed bar only (non-repainting)
   g_last_bar = bt0;

   int need = InpHistoryBars;
   if(need < 500)
      need = 500;
   MqlRates rates[];
   int got = CopyRates(_Symbol, _Period, 0, need, rates);
   if(got < 500)
      return;                       // warming up
   ArraySetAsSeries(rates, true);
   int count = ArraySize(rates);
   if(count < 2)
      return;

   FMAnalysisResult res;
   if(!g_analysis.Update(rates, count, g_cfg, 1, res))
      return;
   g_bars++;

   // Phase 26: manage owned positions (BE/trail; strategy-permits are all-true
   // until Phases 27–30 attach per-strategy rules) + closed-deal accounting.
   PositionFix mine[];
   g_pos.Refresh(_Symbol, mine);
   for(int i = 0; i < ArraySize(mine); i++)
     {
      ModifyResult mr;
      if(g_pos.MaybeBreakEven(mine[i], true, mr) && mr.ok)
         PrintFormat("[FM_EA] BE #%d %s", mine[i].ticket, mr.reason);
      if(g_pos.MaybeTrail(mine[i], true, mr) && mr.ok)
         PrintFormat("[FM_EA] TRAIL #%d %s", mine[i].ticket, mr.reason);
     }
   double closedProfits[];
   int nClosed = g_pos.ScanClosedDeals(closedProfits);
   for(int i = 0; i < nClosed; i++)
     {
      g_risk.NotifyTradeClosed(closedProfits[i]);
      PrintFormat("[FM_EA] closed profit=%.2f", closedProfits[i]);
     }

   StrategyCandidate cand[];
   int n = g_registry.BuildCandidates(res, cand);
   // Phase 28: failed-BO candidate joins the catalog.
   StrategyCandidate fbo;
   if(g_registry.BuildFailedBO(res, g_cfg, fbo))
     {
      int m = ArraySize(cand);
      ArrayResize(cand, m + 1);
      cand[m] = fbo;
      n = ArraySize(cand);
     }
   StrategySelection sel;
   int autoFinal = -1;
   if(InpStratMode == STRAT_MODE_AUTO)
     {
      AutoTuning at;
      at.trendBonus = InpAutoTrendBonus;
      at.provPenalty = InpAutoProvPenalty;
      at.rrBonus = InpAutoRRBonus;
      at.rrLevel = InpAutoRRLevel;
      sel = g_registry.SelectAuto(cand, res, at, autoFinal);
     }
   else
      sel = g_registry.Select(cand);
   // Phase 31: Phase-8 structural vetoes apply in ALL modes.
   string vetoWhy = "";
   if(sel.hasTrade && res.decisionDone)
     {
      ENUM_DECISION_REASON dr = res.decision.reason;
      if(dr == REASON_BARBWIRE || dr == REASON_MID_RANGE ||
         dr == REASON_CONFLICT || dr == REASON_NO_EDGE ||
         dr == REASON_TRAP_REPEAT)
         vetoWhy = "DECISION_VETO_" + CDecisionEngine::ReasonName(dr);
     }
   if(sel.hasTrade && vetoWhy != "")
     {
      g_veto++;
      if(g_veto % 25 == 1)
         PrintFormat("[FM_EA] %s %s veto=%s",
                     TimeToString(res.barTime),
                     CStrategyRegistry::StrategyName(sel.strategy), vetoWhy);
     }
   else if(sel.hasTrade)
     {
      g_selCount[sel.strategy]++;
      MqlDateTime dt;
      TimeToStruct(res.barTime, dt);
      int ymd = dt.year * 10000 + dt.mon * 100 + dt.day;
      int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      RiskDecision rd = g_risk.Check(_Symbol, sel.setup, spread, ymd);
      if(rd.allowed)
         g_riskOK++;
      // Phase 27–30: all strategy intents (entries still need Phase 33).
      string intentTxt = "INTENT_PENDING_PHASE";
      if(rd.allowed && sel.strategy != STRAT_NONE)
        {
         double px = (sel.setup.dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_BID));
         TradeIntent ti;
         string why = "";
         bool made = false;
         if(sel.strategy == STRAT_FM_FADE)
            made = g_intent.FromFM(sel.setup, res, px, why, ti);
         else if(sel.strategy == STRAT_FAILED_BO)
            made = g_intent.FromFailedBO(sel.setup, px, res.atr, why, ti);
         else if(sel.strategy == STRAT_PULLBACK)
            made = g_intent.FromPullback(sel.setup, px, res.atr, why, ti);
         else if(sel.strategy == STRAT_BREAKOUT)
            made = g_intent.FromBreakout(sel.setup, px, res.atr, why, ti);
         else if(sel.strategy == STRAT_REVERSAL)
            made = g_intent.FromReversal(sel.setup, px, res.atr, why, ti);
         else if(sel.strategy == STRAT_DOUBLE)
            made = g_intent.FromDouble(sel.setup, px, res.atr, why, ti);
         if(made)
            intentTxt = StringFormat("WOULD_%s %s",
                                     (ti.dir > 0 ? "BUY" : "SELL"), ti.note);
         else
            intentTxt = "SKIP_" + why;
        }
      PrintFormat("[FM_EA] %s %s %s entry=%s stop=%s obj=%s score=%d%s R=%.2f cands=%d final=%d risk=%s vol=%.2f %s",
                  TimeToString(res.barTime),
                  (sel.setup.dir > 0 ? "BUY" : "SELL"),
                  CStrategyRegistry::StrategyName(sel.strategy),
                  DoubleToString(sel.setup.entry, _Digits),
                  DoubleToString(sel.setup.stop, _Digits),
                  DoubleToString(sel.setup.objective, _Digits),
                  sel.setup.score,
                  (sel.setup.provisional ? " PROV" : ""),
                  sel.setup.rMult, n, autoFinal, rd.reason, rd.volume, intentTxt);
     }
   else if(g_bars % 500 == 0)
      PrintFormat("[FM_EA] %s NO_TRADE cands=%d (mode=%s)",
                  TimeToString(res.barTime), n,
                  CStrategyRegistry::ModeName(InpStratMode));
  }
//+------------------------------------------------------------------+
