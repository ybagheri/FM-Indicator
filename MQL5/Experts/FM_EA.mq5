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
#include <FM/ParityDecision.mqh> // Phase 3: shared candidate/selection builder
#include <FM/RiskManager.mqh>
#include <FM/ExecutionEngine.mqh>  // Phase 25: constructed+configured, no calls yet
#include <FM/PositionManager.mqh>  // Phase 26: manage/BE/trail owned positions
#include <FM/TradeIntent.mqh>      // Phase 27+: selection → trade intent
#include <FM/TradeExplanation.mqh> // Phase 32: explainable decisions
#include <FM/SafetyManager.mqh>    // Phase 33: modes + kill-switches
#include <FM/PaperTrader.mqh>      // Phase 33: virtual fills
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
//--- trading modes + safety (Phase 33; default = safest)
input ENUM_FM_TRADE_MODE InpTradeMode      = TRADE_ANALYSIS_ONLY;
input string             InpLiveToken      = "";    // must equal TRADE_LIVE for live
//--- EXP-0002 apparatus (measurement only; default true = production logic)
input bool               InpApplyStructuralVeto = true;
input bool               InpEmergencyStop  = false;
input double             InpMaxDrawdownPct = 20.0;  // %, 0=off
input int                InpSessionStartH  = 0;     // server hour, start==end = always
input int                InpSessionEndH    = 24;
input bool               InpCloseOnHalt    = false;

CFMConfig         g_cfg;
CLogger           g_log;
CFMAnalysis       g_analysis;
CStrategyRegistry g_registry;
CRiskManager      g_risk;
CExecutionEngine  g_exec;
CPositionManager  g_pos;
CTradeIntentBuilder g_intent;
CSafetyManager    g_safety;
CPaperTrader      g_paper;
bool              g_haltLogged = false;
datetime          g_last_bar = 0;
long              g_bars = 0;
long              g_selCount[STRAT_COUNT];
long              g_riskOK = 0;
long              g_veto = 0;
long              g_vetoByReason[11];   // EXP-0002: indexed by ENUM_DECISION_REASON

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
   g_safety.Configure(InpTradeMode, InpLiveToken, InpEmergencyStop,
                      InpMaxDailyLoss, InpMaxDrawdownPct,
                      InpSessionStartH, InpSessionEndH, InpCloseOnHalt);
   g_paper.Configure(InpMaxOpenPos);
   PrintFormat("[FM_EA] mode=%s acctTradeMode=%d",
               CSafetyManager::ModeName(InpTradeMode),
               (int)AccountInfoInteger(ACCOUNT_TRADE_MODE));
   // Restart recovery: adopt already-open magic positions (logged, generic).
   PositionFix adopted[];
   int nAdopt = g_pos.Refresh(_Symbol, adopted);
   if(nAdopt > 0)
      PrintFormat("[FM_EA] adopted %d open position(s) on init", nAdopt);
   ArrayInitialize(g_selCount, 0);
   ArrayInitialize(g_vetoByReason, 0);
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
   string vr = "";
   for(int vi = 0; vi < 11; vi++)
      if(g_vetoByReason[vi] > 0)
         vr += StringFormat(" %s=%d", CDecisionEngine::ReasonName((ENUM_DECISION_REASON)vi), g_vetoByReason[vi]);
   PrintFormat("[FM_EA] vetoByReason:%s", vr);
   PaperStats ps;
   g_paper.Stats(ps);
   PrintFormat("[FM_EA] %s", g_paper.Summary());
  }

// Phase 35 — custom optimization criterion (§20). Composite over the
// COMPLETED test (tester statistics), NOT net profit alone:
//   score = PF_norm*0.35 + expectancyR*0.25 + activity*0.15 + ddPenalty
// where PF_norm = min(PF,3)/3, expectancyR = avg deal / mean risk (per
// Tester history), activity = min(trades,50)/50, ddPenalty =
// -(balanceDD% / 20) capped at -1. No-trade runs score ≤ 0 (never optimal).
// Formula documented in OPTIMIZATION_GUIDE.md §2.
double OnTester()
  {
   int deals = (int)TesterStatistics(STAT_DEALS);
   if(deals <= 0)
      return 0.0;
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double expProfit = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double initDep = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double balDDpct = 0.0;
   if(initDep > 0)
      balDDpct = TesterStatistics(STAT_BALANCEDD_PERCENT);
   double avgRisk = 0.0;
   HistorySelect(0, TimeCurrent() + 86400);
   double riskSum = 0.0;
   int riskN = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong dt = HistoryDealGetTicket(i);
      if(dt == 0)
         continue;
      if(HistoryDealGetInteger(dt, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(dt, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      double sl = HistoryDealGetDouble(dt, DEAL_SL);
      double open = HistoryDealGetDouble(dt, DEAL_PRICE);
      double vol = HistoryDealGetDouble(dt, DEAL_VOLUME);
      string sym = HistoryDealGetString(dt, DEAL_SYMBOL);
      if(sl <= 0 || vol <= 0)
         continue;
      double loss = 0.0;
      ENUM_ORDER_TYPE t = (sl < open ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(OrderCalcProfit(t, sym, vol, open, sl, loss))
        {
         riskSum += -loss;
         riskN++;
        }
     }
   if(riskN > 0)
      avgRisk = riskSum / riskN;
   double pfN = MathMin(pf, 3.0) / 3.0;
   double expR = (avgRisk > 0 ? expProfit / avgRisk : 0.0);
   expR = MathMax(-2.0, MathMin(2.0, expR)) / 2.0;   // → [-1,1]
   double act = MathMin((double)deals, 50.0) / 50.0;
   double ddPen = -MathMin(balDDpct / 20.0, 1.0);
   double score = 0.35 * pfN + 0.25 * expR + 0.15 * act + 0.25 * ddPen;
   PrintFormat("[FM_EA] OnTester deals=%d PF=%.2f exp=%.2f expR=%.2f dd=%.2f%% score=%.4f",
               deals, pf, expProfit, expR * 2.0, balDDpct, score);
   return score;
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

   // Phase 33: settle PAPER virtuals on the just-closed bar, then evaluate
   // safety for this bar (halt latches; session is a pause).
   string paperLog = "";
   g_paper.SettleBar(_Symbol, rates[1].high, rates[1].low, rates[1].time, paperLog);
   if(paperLog != "")
      PrintFormat("[FM_EA] %s %s", TimeToString(rates[1].time), paperLog);
   MqlDateTime hdt;
   TimeToStruct(rates[1].time, hdt);
   string safeWhy = "";
   bool safeGo = g_safety.Evaluate(AccountInfoDouble(ACCOUNT_EQUITY),
                                   g_risk.DailyPL(), hdt.hour, safeWhy);
   string haltReason = "";
   bool halted = g_safety.Halted(haltReason);
   if(halted && !g_haltLogged)
     {
      g_haltLogged = true;
      PrintFormat("[FM_EA] HALT %s", haltReason);
      if(g_safety.CloseOnHalt())
        {
         string clog = "";
         int nClosed = g_pos.CloseAll(_Symbol, clog);
         PrintFormat("[FM_EA] HALT_CLOSE n=%d %s", nClosed, clog);
        }
     }

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

   // Phase 3 parity: shared builder — identical universe (catalog +
   // FAILED_BO) and Select/SelectAuto as the Indicator (CParityBuilder).
   // Downstream (veto → risk → intent → execution) is untouched.
   AutoTuning at;
   at.trendBonus = InpAutoTrendBonus;
   at.provPenalty = InpAutoProvPenalty;
   at.rrBonus = InpAutoRRBonus;
   at.rrLevel = InpAutoRRLevel;
   FMParityDecision pd;
   CParityBuilder::Build(res, g_cfg, g_registry, InpStratMode, at, pd);
   StrategyCandidate cand[];
   ArrayResize(cand, pd.candCount);
   for(int pdi = 0; pdi < pd.candCount; pdi++)
      cand[pdi] = pd.candidates[pdi];
   int n = pd.candCount;
   StrategySelection sel = pd.selection;
   int autoFinal = pd.autoFinal;
   // Phase 31: Phase-8 structural vetoes apply in ALL modes.
   // EXP-0002 apparatus: InpApplyStructuralVeto=false counts vetoes but
   // proceeds (vetoWhy retained for alternate tagging + bypass log).
   string vetoWhy = "";
   ENUM_DECISION_REASON vetoDr = REASON_OK;
   if(sel.hasTrade && res.decisionDone)
     {
      ENUM_DECISION_REASON dr = res.decision.reason;
      if(dr == REASON_BARBWIRE || dr == REASON_MID_RANGE ||
         dr == REASON_CONFLICT || dr == REASON_NO_EDGE ||
         dr == REASON_TRAP_REPEAT)
        {
         vetoWhy = "DECISION_VETO_" + CDecisionEngine::ReasonName(dr);
         vetoDr = dr;
        }
     }
   bool vetoBypassed = false;
   if(sel.hasTrade && vetoWhy != "")
     {
      g_veto++;
      if((int)vetoDr >= 0 && (int)vetoDr < 11)
         g_vetoByReason[(int)vetoDr]++;
      if(!InpApplyStructuralVeto)
        {
         vetoBypassed = true;
         if(g_veto % 25 == 1)
            PrintFormat("[FM_EA] %s %s VETO_BYPASSED_%s",
                        TimeToString(res.barTime),
                        CStrategyRegistry::StrategyName(sel.strategy), vetoWhy);
        }
      else
        {
         if(g_veto % 25 == 1)
            PrintFormat("[FM_EA] %s %s veto=%s",
                        TimeToString(res.barTime),
                        CStrategyRegistry::StrategyName(sel.strategy), vetoWhy);
        }
     }
   // Production: skip on veto. EXP-0002 treatment: veto counted above,
   // bypass logged, selection proceeds (vetoWhy retained for tagging).
   if(sel.hasTrade && (vetoWhy == "" || vetoBypassed))
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
           {
            intentTxt = StringFormat("WOULD_%s %s",
                                     (ti.dir > 0 ? "BUY" : "SELL"), ti.note);
            // Phase 32: explanation record from engine data only.
            TradeExplanation ex;
            CTradeExplainer::Build(ti, res, rd, cand, vetoWhy, ex);
            PrintFormat("[FM_EA] EXPLAIN %s", CTradeExplainer::RenderText(ex));
            // Phase 33: mode execution (ANALYSIS_ONLY logs only).
            if(!safeGo)
               intentTxt += " HALT_" + safeWhy;
            else if(InpTradeMode == TRADE_PAPER)
              {
               string ctxName = CMarketState::StateName(res.mstate.state);
               if(g_paper.Open(_Symbol, ti, rd.volume, rd.riskMoney, px, res.barTime, ctxName))
                  intentTxt += StringFormat(" PAPER_OPEN ctx=%s", ctxName);
               else
                  intentTxt += " PAPER_FULL";
              }
            else if(InpTradeMode == TRADE_DEMO || InpTradeMode == TRADE_LIVE)
              {
               string allowWhy = "";
               if(!g_safety.RealOrdersAllowed(allowWhy))
                  intentTxt += " BLOCK_" + allowWhy;
               else
                 {
                  ExecResult er;
                  string cm = CPositionManager::MakeComment(ti.strategy, 0);
                  if(ti.dir > 0)
                     er = g_exec.Buy(_Symbol, rd.volume, ti.stop, ti.objective, cm);
                  else
                     er = g_exec.Sell(_Symbol, rd.volume, ti.stop, ti.objective, cm);
                  intentTxt += StringFormat(" EXEC_%s", er.reason);
                  if(er.ok)
                     g_risk.NotifyTradeOpened();
                 }
              }
           }
         else
            intentTxt = "SKIP_" + why;
        }
      PrintFormat("[FM_EA] %s %s %s entry=%s stop=%s obj=%s score=%d%s R=%.2f cands=%d final=%d sig=%d risk=%s vol=%.2f %s",
                  TimeToString(res.barTime),
                  (sel.setup.dir > 0 ? "BUY" : "SELL"),
                  CStrategyRegistry::StrategyName(sel.strategy),
                  DoubleToString(sel.setup.entry, _Digits),
                  DoubleToString(sel.setup.stop, _Digits),
                  DoubleToString(sel.setup.objective, _Digits),
                  sel.setup.score,
                  (sel.setup.provisional ? " PROV" : ""),
                  sel.setup.rMult, n, autoFinal, sel.setup.signalBar, rd.reason, rd.volume, intentTxt);
     }
   else if(g_bars % 500 == 0)
      PrintFormat("[FM_EA] %s NO_TRADE cands=%d (mode=%s)",
                  TimeToString(res.barTime), n,
                  CStrategyRegistry::ModeName(InpStratMode));
  }
//+------------------------------------------------------------------+
