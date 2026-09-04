//+------------------------------------------------------------------+
//| StrategyRegistry.mqh : strategy selection (Phase 22)                |
//| ONLY genuinely-implemented strategies (built from FMAnalysisResult). |
//| Modes: SINGLE / MULTI / AUTO. Deterministic, no orders, no I/O.     |
//| Conflict resolution beyond score-max lives in Phase 31 (AUTO).      |
//| FAILED_BO as a separate strategy is deferred to Phase 28 (needs     |
//| inverse-family plumbing in the trade intent; see EA_ARCHITECTURE).  |
//+------------------------------------------------------------------+
#ifndef FM_STRATEGYREGISTRY_MQH
#define FM_STRATEGYREGISTRY_MQH

#include "Config.mqh"
#include "Defs.mqh"
#include "GeneralSetups.mqh"
#include "Analysis.mqh"

enum ENUM_FM_STRATEGY
  {
   STRAT_NONE=0,
   STRAT_FM_FADE=1,    // SETUP_FM_FADE (all MM families; family in fmPlans)
   STRAT_PULLBACK=2,   // SETUP_TREND_PULLBACK (H1/H2/L1/L2)
   STRAT_BREAKOUT=3,   // SETUP_BREAKOUT (FOLLOW firm / PENDING provisional)
   STRAT_REVERSAL=4,   // SETUP_REVERSAL (MTR MAJOR firm / MINOR provisional)
   STRAT_DOUBLE=5,     // SETUP_DOUBLE (swing firm / micro provisional)
   STRAT_FAILED_BO=6,  // SETUP_FAILED_BO (Phase 28: registry-built fade)
   STRAT_COUNT=7
  };

enum ENUM_STRATEGY_MODE
  {
   STRAT_MODE_SINGLE=0,
   STRAT_MODE_MULTI=1,
   STRAT_MODE_AUTO=2
  };

struct StrategyCandidate
  {
   bool              valid;
   ENUM_FM_STRATEGY  strategy;
   GeneralSetup      setup;     // concrete entry/stop/objective/score
   bool              enabled;   // passes the mode filter
  };

struct StrategySelection
  {
   bool              hasTrade;  // false = NO TRADE under current mode/filter
   ENUM_FM_STRATEGY  strategy;
   GeneralSetup      setup;
  };

// Phase 31: AUTO tuning (context-aware conflict resolution). All bonuses are
// additive score points, documented in TRADE_DECISION_SPECIFICATION.md.
struct AutoTuning
  {
   int               trendBonus;   // ± for alignment with state winner
   int               provPenalty;  // extra provisional caution
   int               rrBonus;      // reward for rMult >= rrLevel
   double            rrLevel;
  };

class CStrategyRegistry
  {
private:
   ENUM_STRATEGY_MODE m_mode;
   ENUM_FM_STRATEGY  m_single;
   bool              m_use[STRAT_COUNT];

   static ENUM_FM_STRATEGY MapType(ENUM_SETUP_TYPE t)
     {
      switch(t)
        {
         case SETUP_FM_FADE:        return STRAT_FM_FADE;
         case SETUP_TREND_PULLBACK: return STRAT_PULLBACK;
         case SETUP_BREAKOUT:       return STRAT_BREAKOUT;
         case SETUP_REVERSAL:       return STRAT_REVERSAL;
         case SETUP_DOUBLE:         return STRAT_DOUBLE;
         case SETUP_FAILED_BO:      return STRAT_FAILED_BO;
         default:                   return STRAT_NONE;
        }
     }

public:
                     CStrategyRegistry()
     {
      m_mode = STRAT_MODE_AUTO;
      m_single = STRAT_FM_FADE;
      for(int i = 0; i < STRAT_COUNT; i++)
         m_use[i] = true;
      m_use[STRAT_NONE] = false;
     }

   void              Configure(ENUM_STRATEGY_MODE mode, ENUM_FM_STRATEGY single,
                               bool useFM, bool usePB, bool useBO,
                               bool useRev, bool useDbl, bool useFailedBO)
     {
      m_mode = mode;
      m_single = single;
      for(int i = 0; i < STRAT_COUNT; i++)
         m_use[i] = false;
      m_use[STRAT_FM_FADE] = useFM;
      m_use[STRAT_PULLBACK] = usePB;
      m_use[STRAT_BREAKOUT] = useBO;
      m_use[STRAT_REVERSAL] = useRev;
      m_use[STRAT_DOUBLE] = useDbl;
      m_use[STRAT_FAILED_BO] = useFailedBO;
     }

   // Strategy enable-query (EA inputs call this; never invents strategies).
   bool              IsEnabled(ENUM_FM_STRATEGY s) const
     {
      if(s <= STRAT_NONE || s >= STRAT_COUNT)
         return false;
      if(m_mode == STRAT_MODE_SINGLE)
         return (s == m_single);
      return m_use[s];
     }

   // Build one candidate per catalog entry with a known strategy mapping.
   // Returns candidate count (0 = NO TRADE under any mode).
   int               BuildCandidates(const FMAnalysisResult &res, StrategyCandidate &out[])
     {
      ArrayResize(out, 0);
      if(!res.valid || !res.generalDone)
         return 0;
      for(int i = 0; i < res.candCount; i++)
        {
         if(!res.candidates[i].valid)
            continue;
         ENUM_FM_STRATEGY st = MapType(res.candidates[i].type);
         if(st == STRAT_NONE)
            continue;
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n].valid = true;
         out[n].strategy = st;
         out[n].setup = res.candidates[i];
         out[n].enabled = IsEnabled(st);
        }
      return ArraySize(out);
     }

   // Phase 28 — failed-breakout fade candidate, built from the BreakoutSignal
   // (the catalog emits no target for failures by design). Geometry (proxy,
   // see STRATEGY_CATALOG.md): fade dir opposite the failed BO; entry at the
   // failed level; stop beyond it by (stopBuf+tol)×ATR; objective 2.0×ATR
   // measured (FromBreakout convention); score 55 (failure confirmed,
   // reversal unconfirmed: between PENDING 40 and FOLLOW 70).
   bool              BuildFailedBO(const FMAnalysisResult &res, const CFMConfig &cfg,
                                   StrategyCandidate &out)
     {
      out.valid = false;
      out.enabled = false;
      if(!res.valid || !res.boDone || !res.breakout.found)
         return false;
      if(res.breakout.outcome != BO_FAILED)
         return false;
      if(res.atr <= 0)
         return false;
      int bdir = res.breakout.dir;
      if(bdir != +1 && bdir != -1)
         return false;
      double ref = res.breakout.refPrice;
      double buf = (cfg.SetupStopBufATRMult + cfg.MMToleranceATRMult) * res.atr;
      double objD = cfg.GeneralObjectiveATRMult * res.atr;
      if(buf <= 0 || objD <= 0)
         return false;
      GeneralSetup g;
      CGeneralSetups::InitNone(g);
      g.type = SETUP_FAILED_BO;
      g.dir = -bdir;
      g.entry = ref;
      g.stop = ref + (bdir > 0 ? buf : -buf);
      g.objective = ref - (bdir > 0 ? objD : -objD);
      g.riskPts = MathAbs(g.entry - g.stop);
      g.rewardPts = MathAbs(g.entry - g.objective);
      g.provisional = false;
      g.signalBar = res.breakout.boBar;
      g.refPrice = ref;
      g.score = 55;
      CGeneralSetups::Finish(g, cfg);
      if(!g.valid)
         return false;
      out.valid = true;
      out.strategy = STRAT_FAILED_BO;
      out.setup = g;
      out.enabled = IsEnabled(STRAT_FAILED_BO);
      return true;
     }

   // SINGLE/MULTI selection (Phase-22 score-max rule, unchanged).
   // AUTO mode uses SelectAuto (Phase 31) instead.
   StrategySelection Select(const StrategyCandidate &cand[]) const
     {
      StrategySelection sel;
      sel.hasTrade = false;
      sel.strategy = STRAT_NONE;
      CGeneralSetups::InitNone(sel.setup);
      int bestIdx = -1;
      for(int i = 0; i < ArraySize(cand); i++)
        {
         if(!cand[i].valid || !cand[i].enabled || !cand[i].setup.valid)
            continue;
         if(bestIdx < 0)
           {
            bestIdx = i;
            continue;
           }
         GeneralSetup a = cand[i].setup;
         GeneralSetup b = cand[bestIdx].setup;
         bool aWins = false;
         if(a.score != b.score)
            aWins = (a.score > b.score);
         else if(a.provisional != b.provisional)
            aWins = (b.provisional && !a.provisional);
         else if(cand[i].strategy != cand[bestIdx].strategy)
            aWins = (cand[i].strategy < cand[bestIdx].strategy);
         else
            aWins = (a.entry < b.entry);
         if(aWins)
            bestIdx = i;
        }
      if(bestIdx >= 0)
        {
         sel.hasTrade = true;
         sel.strategy = cand[bestIdx].strategy;
         sel.setup = cand[bestIdx].setup;
        }
      return sel;
     }

   // Phase 31 — AUTO final score: setup score + context alignment
   // (±trendBonus vs state-winner direction) − provPenalty (provisional) +
   // rrBonus (rMult ≥ rrLevel). Structural vetoes (barbwire/mid-range/
   // conflict/no-edge/trap) belong to the Phase-8 decision and are applied
   // by the EA (DECISION_VETO_*), not here.
   static int        ContextDir(ENUM_MARKET_STATE st)
     {
      if(st == MS_BULL_TREND || st == MS_BULL_CHANNEL)
         return +1;
      if(st == MS_BEAR_TREND || st == MS_BEAR_CHANNEL)
         return -1;
      return 0;   // RANGE/BREAKOUT_MODE/TRANSITION/UNKNOWN: no directional edge
     }

   int               AutoFinal(const StrategyCandidate &c,
                               const FMAnalysisResult &res,
                               const AutoTuning &t) const
     {
      int f = c.setup.score;
      int ctx = ContextDir(res.mstate.state);
      if(ctx != 0 && res.mstate.valid)
         f += (c.setup.dir == ctx ? t.trendBonus : -t.trendBonus);
      if(c.setup.provisional)
         f -= t.provPenalty;
      if(c.setup.rMult + 1e-9 >= t.rrLevel)
         f += t.rrBonus;
      return f;
     }

   // Phase-31 AUTO selection. Replaces the Phase-22 score-max rule (which
   // remains for SINGLE/MULTI via Select). Deterministic: max final score;
   // ties → firm beats provisional → lower strategy enum → lower entry.
   // Returns final score via finalOut (-1 when no trade).
   StrategySelection SelectAuto(const StrategyCandidate &cand[],
                                const FMAnalysisResult &res,
                                const AutoTuning &t, int &finalOut) const
     {
      StrategySelection sel;
      sel.hasTrade = false;
      sel.strategy = STRAT_NONE;
      CGeneralSetups::InitNone(sel.setup);
      finalOut = -1;
      int bestIdx = -1;
      int bestFinal = -1000000;
      for(int i = 0; i < ArraySize(cand); i++)
        {
         if(!cand[i].valid || !cand[i].enabled || !cand[i].setup.valid)
            continue;
         int f = AutoFinal(cand[i], res, t);
         bool wins = false;
         if(bestIdx < 0 || f != bestFinal)
            wins = (bestIdx < 0 || f > bestFinal);
         else if(cand[i].setup.provisional != cand[bestIdx].setup.provisional)
            wins = (cand[bestIdx].setup.provisional && !cand[i].setup.provisional);
         else if(cand[i].strategy != cand[bestIdx].strategy)
            wins = (cand[i].strategy < cand[bestIdx].strategy);
         else
            wins = (cand[i].setup.entry < cand[bestIdx].setup.entry);
         if(wins)
           {
            bestIdx = i;
            bestFinal = f;
           }
        }
      if(bestIdx >= 0)
        {
         sel.hasTrade = true;
         sel.strategy = cand[bestIdx].strategy;
         sel.setup = cand[bestIdx].setup;
         finalOut = bestFinal;
        }
      return sel;
     }

   static string     StrategyName(ENUM_FM_STRATEGY s)
     {
      switch(s)
        {
         case STRAT_FM_FADE:  return "FM_FADE";
         case STRAT_PULLBACK: return "PULLBACK";
         case STRAT_BREAKOUT: return "BREAKOUT";
         case STRAT_REVERSAL: return "REVERSAL_MTR";
         case STRAT_DOUBLE:   return "DOUBLE";
         case STRAT_FAILED_BO: return "FAILED_BO";
         default:             return "NONE";
        }
     }

   static string     ModeName(ENUM_STRATEGY_MODE m)
     {
      switch(m)
        {
         case STRAT_MODE_SINGLE: return "SINGLE";
         case STRAT_MODE_MULTI:  return "MULTI";
         case STRAT_MODE_AUTO:   return "AUTO";
         default:                return "?";
        }
     }
  };

#endif
