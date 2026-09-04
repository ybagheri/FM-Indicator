//+------------------------------------------------------------------+
//| TradeExplanation.mqh : explainable decisions (Phase 32)             |
//| Every EA intent carries a TradeExplanation built ONLY from engine   |
//| data (no invented evidence). RenderText produces the §11 block.     |
//| Modify/close reasons attach in Phase 34 (live orders).              |
//+------------------------------------------------------------------+
#ifndef FM_TRADEEXPLANATION_MQH
#define FM_TRADEEXPLANATION_MQH

#include "Defs.mqh"
#include "GeneralSetups.mqh"
#include "MarketState.mqh"
#include "DecisionEngine.mqh"
#include "Analysis.mqh"
#include "StrategyRegistry.mqh"
#include "TradeIntent.mqh"
#include "RiskManager.mqh"

#define FM_EXPLAIN_MAX_ALT 11

struct AlternateSetup
  {
   ENUM_FM_STRATEGY  strategy;
   int               dir;
   int               score;
   string            rejectReason;  // DISABLED_BY_MODE | LOST_FINAL_<f> | <veto>
  };

struct TradeExplanation
  {
   datetime          barTime;
   ENUM_FM_STRATEGY  strategy;
   string            strategyName;
   string            contextName;   // state winner name
   int               contextScore;  // winner state share 0..100 (NOT a probability)
   int               setupScore;    // setup.score (context score)
   int               signalQuality; // FM: ScoreSignal; else -1 = N/A (catalog score only)
   string            entryReason;
   double            entryPrice;
   string            stopReason;
   double            stopPrice;
   string            targetReason;
   double            targetPrice;
   double            riskMoney;
   double            volume;
   double            rMult;
   AlternateSetup    alternates[FM_EXPLAIN_MAX_ALT];
   int               altCount;
   string            invalidation;
   string            decisionVeto;  // "" when none
  };

class CTradeExplainer
  {
private:
   static int        StateShare(const MarketState &m)
     {
      switch(m.state)
        {
         case MS_BULL_TREND:   return m.pctBullTrend;
         case MS_BEAR_TREND:   return m.pctBearTrend;
         case MS_BULL_CHANNEL: return m.pctBullChannel;
         case MS_BEAR_CHANNEL: return m.pctBearChannel;
         case MS_TRADING_RANGE:return m.pctRange;
         case MS_BREAKOUT_MODE:return m.pctBreakout;
         default:              return 0;
        }
     }

   static string     EntryReason(ENUM_FM_STRATEGY st, bool provisional)
     {
      string q = (provisional ? " (provisional: no second-leg/confirm evidence)" : " (firm)");
      switch(st)
        {
         case STRAT_FM_FADE:   return "Above/below FM signal-bar extreme at target zone" + q;
         case STRAT_PULLBACK:  return "Above/below pullback signal extreme (trend resumption)" + q;
         case STRAT_BREAKOUT:  return "Beyond breakout reference on follow-through" + q;
         case STRAT_REVERSAL:  return "MTR signal extreme after EMA-cross + retest" + q;
         case STRAT_DOUBLE:    return "Beyond double-trigger extreme" + q;
         case STRAT_FAILED_BO: return "Failed-level fade at next open" + q;
         default:              return "UNKNOWN";
        }
     }

public:
   // intent = winning intent; res = analysis; rd = risk record; cand[] =
   // full candidate list (for alternates); veto = DECISION_VETO_* or "".
   static void       Build(const TradeIntent &intent, const FMAnalysisResult &res,
                           const RiskDecision &rd, const StrategyCandidate &cand[],
                           string veto, TradeExplanation &ex)
     {
      ZeroMemory(ex);
      ex.barTime = res.barTime;
      ex.strategy = intent.strategy;
      ex.strategyName = CStrategyRegistry::StrategyName(intent.strategy);
      ex.contextName = CMarketState::StateName(res.mstate.state);
      ex.contextScore = (res.stateDone && res.mstate.valid) ? StateShare(res.mstate) : 0;
      ex.setupScore = intent.score;
      ex.signalQuality = (intent.strategy == STRAT_FM_FADE ? intent.score : -1);
      ex.entryReason = EntryReason(intent.strategy, intent.provisional);
      ex.entryPrice = intent.entry;
      ex.stopReason = "Structure + ATR buffer (" + intent.invalidation + ")";
      ex.stopPrice = intent.stop;
      ex.targetReason = "Structural magnet (B0 / window extreme / 2ATR measured)";
      ex.targetPrice = intent.objective;
      ex.riskMoney = rd.riskMoney;
      ex.volume = rd.volume;
      ex.rMult = intent.rMult;
      ex.altCount = 0;
      for(int i = 0; i < ArraySize(cand) && ex.altCount < FM_EXPLAIN_MAX_ALT; i++)
        {
         if(!cand[i].valid || cand[i].strategy == intent.strategy)
            continue;
         int k = ex.altCount++;
         ex.alternates[k].strategy = cand[i].strategy;
         ex.alternates[k].dir = cand[i].setup.dir;
         ex.alternates[k].score = cand[i].setup.score;
         if(!cand[i].enabled)
            ex.alternates[k].rejectReason = "DISABLED_BY_MODE";
         else if(veto != "")
            ex.alternates[k].rejectReason = veto;
         else
            ex.alternates[k].rejectReason = "LOST_SELECTION";
        }
      ex.invalidation = intent.invalidation;
      ex.decisionVeto = veto;
     }

   static string     RenderText(const TradeExplanation &ex)
     {
      string q = (ex.signalQuality >= 0 ? IntegerToString(ex.signalQuality)
                                        : "N/A (catalog score only)");
      string s = StringFormat(
         "WHY %s %s | ctx=%s(%d) setup=%d signal=%s entry=%s stop=%s tgt=%s R=%.2f vol=%.2f risk=%.2f | %s | inval=%s",
         (ex.strategy == STRAT_NONE ? "NO_TRADE" : CStrategyRegistry::StrategyName(ex.strategy)),
         TimeToString(ex.barTime), ex.contextName, ex.contextScore,
         ex.setupScore, q, DoubleToString(ex.entryPrice, 8),
         DoubleToString(ex.stopPrice, 8), DoubleToString(ex.targetPrice, 8),
         ex.rMult, ex.volume, ex.riskMoney, ex.entryReason, ex.invalidation);
      for(int i = 0; i < ex.altCount; i++)
         s += StringFormat(" | rej:%s(%s%d)=%s",
                           CStrategyRegistry::StrategyName(ex.alternates[i].strategy),
                           (ex.alternates[i].dir > 0 ? "B" : "S"),
                           ex.alternates[i].score, ex.alternates[i].rejectReason);
      if(ex.decisionVeto != "")
         s += " | " + ex.decisionVeto;
      return s;
     }
  };

#endif
