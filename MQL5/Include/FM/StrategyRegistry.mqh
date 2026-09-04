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
   STRAT_COUNT=6
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
                               bool useRev, bool useDbl)
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

   // Deterministic selection under the configured mode. Phase-22 rule:
   // highest setup score among enabled+valid candidates; ties broken by
   // lower ENUM_FM_STRATEGY value, then lower entry price. Provisional
   // setups are eligible but lose ties to firm ones. Richer context-aware
   // conflict resolution arrives in Phase 31; the rule is NOT changed
   // silently — Phase 31 documents and replaces this section.
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
         const GeneralSetup &a = cand[i].setup;
         const GeneralSetup &b = cand[bestIdx].setup;
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

   static string     StrategyName(ENUM_FM_STRATEGY s)
     {
      switch(s)
        {
         case STRAT_FM_FADE:  return "FM_FADE";
         case STRAT_PULLBACK: return "PULLBACK";
         case STRAT_BREAKOUT: return "BREAKOUT";
         case STRAT_REVERSAL: return "REVERSAL_MTR";
         case STRAT_DOUBLE:   return "DOUBLE";
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
