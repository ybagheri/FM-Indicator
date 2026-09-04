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
#include <FM/Inputs.mqh>       // shared analysis inputs (verbatim)

//--- EA inputs (Phase 23: selection + identity only; trading inputs later)
input ENUM_STRATEGY_MODE InpStratMode      = STRAT_MODE_AUTO;
input ENUM_FM_STRATEGY   InpSingleStrategy = STRAT_FM_FADE;
input bool               InpUseFM          = true;
input bool               InpUsePullback    = true;
input bool               InpUseBreakout    = true;
input bool               InpUseReversal    = true;
input bool               InpUseDouble      = true;
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

CFMConfig         g_cfg;
CLogger           g_log;
CFMAnalysis       g_analysis;
CStrategyRegistry g_registry;
CRiskManager      g_risk;
datetime          g_last_bar = 0;
long              g_bars = 0;
long              g_selCount[STRAT_COUNT];
long              g_riskOK = 0;

int OnInit()
  {
   FM_ApplyInputs(g_cfg);
   g_log.SetLevel(g_cfg.LogLevel);
   g_analysis.Setup(g_cfg, GetPointer(g_log));
   g_registry.Configure(InpStratMode, InpSingleStrategy,
                        InpUseFM, InpUsePullback, InpUseBreakout,
                        InpUseReversal, InpUseDouble);
   g_risk.Configure(InpLotMode, InpFixedLot, InpRiskPct, InpMoneyRisk,
                    InpMaxDailyLoss, InpMaxTradesDay, InpMaxOpenPos,
                    InpMaxPerSymbol, InpMaxConsecLoss, InpMaxSpreadPts,
                    InpRiskMinRR, InpMagic);
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
   PrintFormat("[FM_EA] done bars=%d riskOK=%d selections:%s reason=%d", g_bars, g_riskOK, s, reason);
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

   StrategyCandidate cand[];
   int n = g_registry.BuildCandidates(res, cand);
   StrategySelection sel = g_registry.Select(cand);
   if(sel.hasTrade)
     {
      g_selCount[sel.strategy]++;
      MqlDateTime dt;
      TimeToStruct(res.barTime, dt);
      int ymd = dt.year * 10000 + dt.mon * 100 + dt.day;
      int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      RiskDecision rd = g_risk.Check(_Symbol, sel.setup, spread, ymd);
      if(rd.allowed)
         g_riskOK++;
      PrintFormat("[FM_EA] %s %s %s entry=%s stop=%s obj=%s score=%d%s R=%.2f cands=%d risk=%s vol=%.2f",
                  TimeToString(res.barTime),
                  (sel.setup.dir > 0 ? "BUY" : "SELL"),
                  CStrategyRegistry::StrategyName(sel.strategy),
                  DoubleToString(sel.setup.entry, _Digits),
                  DoubleToString(sel.setup.stop, _Digits),
                  DoubleToString(sel.setup.objective, _Digits),
                  sel.setup.score,
                  (sel.setup.provisional ? " PROV" : ""),
                  sel.setup.rMult, n, rd.reason, rd.volume);
     }
   else if(g_bars % 500 == 0)
      PrintFormat("[FM_EA] %s NO_TRADE cands=%d (mode=%s)",
                  TimeToString(res.barTime), n,
                  CStrategyRegistry::ModeName(InpStratMode));
  }
//+------------------------------------------------------------------+
