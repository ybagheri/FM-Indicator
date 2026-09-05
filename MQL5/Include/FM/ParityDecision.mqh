//+------------------------------------------------------------------+
//| ParityDecision.mqh : shared EA/Indicator decision contract (Phase 3)  |
//| Single source of truth for candidate evaluation + strategy selection.  |
//| EA and Indicator fill the SAME struct via CParityBuilder using the     |
//| SAME registry functions in the SAME order — no duplicated logic.       |
//| Veto/intent-projection fields are filled in Phase 5; candidates and    |
//| selection are filled from Phase 3 on. Never trades, no I/O.            |
//+------------------------------------------------------------------+
#ifndef FM_PARITYDECISION_MQH
#define FM_PARITYDECISION_MQH

#include "StrategyRegistry.mqh"
#include "DecisionEngine.mqh"

#define FM_PARITY_MAX_CAND 13   // FM_ANALYSIS_MAX_CAND (12) + FAILED_BO (1)

// Full per-closed-bar parity decision. Plain data only (no handles).
struct FMParityDecision
  {
   bool              valid;        // false = analysis invalid, nothing below usable
   datetime          barTime;      // res.barTime analyzed
   ENUM_STRATEGY_MODE mode;        // mode this decision was built under
   int               candCount;    // candidates[0..candCount)
   StrategyCandidate candidates[FM_PARITY_MAX_CAND];
   StrategySelection selection;    // registry Select/SelectAuto output
   int               autoFinal;    // SelectAuto final score (-1 when N/A / no trade)
   // Phase 5 fills (parity veto + closed-bar intent projection):
   Decision          decision;     // Decide() run on selection.setup (not on best)
   string            vetoWhy;      // "" or "DECISION_VETO_<reason>"
   string            intentWhy;    // "" or "WOULD_*" / "SKIP_*" projection
   int               intentDir;    // projected direction (±1, 0 when none)
  };

class CParityBuilder
  {
public:
   // EA candidate universe (FM_EA.mq5:275-285 order): catalog candidates plus
   // the registry-built FAILED_BO fade. Returns total count.
   static int        BuildUniverse(const FMAnalysisResult &res, const CFMConfig &cfg,
                                   CStrategyRegistry &reg, StrategyCandidate &out[])
     {
      int n = reg.BuildCandidates(res, out);
      StrategyCandidate fbo;
      if(reg.BuildFailedBO(res, cfg, fbo))
        {
         int m = ArraySize(out);
         ArrayResize(out, m + 1);
         out[m] = fbo;
         n = ArraySize(out);
        }
      return n;
     }

   // Full shared build: universe → Select/SelectAuto. Field-by-field init
   // (no ZeroMemory: struct owns strings). Output identical for EA and
   // Indicator given identical res/cfg/mode/tuning.
   static void       Build(const FMAnalysisResult &res, const CFMConfig &cfg,
                           CStrategyRegistry &reg, ENUM_STRATEGY_MODE mode,
                           const AutoTuning &t, FMParityDecision &out)
     {
      out.valid = false;
      out.barTime = res.barTime;
      out.mode = mode;
      out.candCount = 0;
      out.selection.hasTrade = false;
      out.selection.strategy = STRAT_NONE;
      CGeneralSetups::InitNone(out.selection.setup);
      out.autoFinal = -1;
      out.decision.action = DEC_NO_TRADE;
      out.decision.reason = REASON_NO_SETUP;
      out.decision.dir = 0;
      out.decision.setupType = SETUP_NONE;
      out.decision.entry = 0;
      out.decision.stop = 0;
      out.decision.objective = 0;
      out.decision.rMult = 0;
      out.decision.score = 0;
      out.vetoWhy = "";
      out.intentWhy = "";
      out.intentDir = 0;
      if(!res.valid)
         return;
      StrategyCandidate tmp[];
      int n = BuildUniverse(res, cfg, reg, tmp);
      for(int i = 0; i < n && out.candCount < FM_PARITY_MAX_CAND; i++)
        {
         out.candidates[out.candCount] = tmp[i];
         out.candCount++;
        }
      if(mode == STRAT_MODE_AUTO)
        {
         int finalOut = -1;
         out.selection = reg.SelectAuto(tmp, res, t, finalOut);
         out.autoFinal = finalOut;
        }
      else
         out.selection = reg.Select(tmp);
      out.valid = true;
     }
  };

#endif
