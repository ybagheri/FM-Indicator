//+------------------------------------------------------------------+
//| SetupEngine.mqh : FM setup plans — entry/stop/target/R per setup   |
//| Phase 6 of bar-by-bar engine (see docs/SETUP_ENGINE.md).            |
//| Stateless, closed bars only, read-only (DEBUG log; never gates FM). |
//+------------------------------------------------------------------+
#ifndef FM_SETUPENGINE_MQH
#define FM_SETUPENGINE_MQH
#include "Config.mqh"
#include "Defs.mqh"

struct SetupPlan
  {
   bool              valid;        // scope + sanity (see spec §4)
   long              setupId;
   int               family;       // ENUM_MM_FAMILY passthrough
   int               fadeDir;      // ±1 (SELL −1 fades bull MM, BUY +1 fades bear)
   double            entry;        // signal-bar extreme (stop-order proxy)
   double            stop;         // structure + ATR buffer
   double            objective;    // B0 price (first structural magnet)
   double            riskPts;      // price distance entry→stop
   double            rewardPts;    // price distance entry→objective
   double            rMult;        // reward/risk
   bool              rrOK;         // rMult >= MinRR (report-only)
   bool              provisional;  // true for DEVELOPING, false for CONFIRMED
   double            invalidClose; // close beyond kills the setup
   int               signalShift;  // MT5 shift of the signal bar
  };

class CSetupPlanner
  {
public:
   // Pure plan from the signal bar + setup snapshot fields (spec §4).
   // sig = signal-bar rates (closed bar); mmDir = MM dir ±1 (NOT fade dir).
   static SetupPlan Plan(const MqlRates &sig, int mmDir, double target,
                         double b0Price, double atr, const CFMConfig &cfg,
                         long id, int family, bool confirmed, int sigShift)
     {
      SetupPlan p;
      p.valid=false; p.setupId=id; p.family=family;
      p.fadeDir=0; p.entry=0; p.stop=0; p.objective=b0Price;
      p.riskPts=0; p.rewardPts=0; p.rMult=0;
      p.rrOK=false; p.provisional=!confirmed;
      p.invalidClose=0; p.signalShift=sigShift;
      if(!cfg.EnableSetup) return p;
      if(mmDir!=+1 && mmDir!=-1) return p;
      if(atr<=0) return p;
      double tol=cfg.MMToleranceATRMult*atr;
      double buf=cfg.SetupStopBufATRMult*atr;
      double over=cfg.MaxOvershootATRMult*atr;
      double minRR=cfg.SetupMinRR;
      if(minRR<0.25) minRR=0.25;
      if(minRR>5.0) minRR=5.0;
      p.fadeDir=-mmDir;
      if(mmDir>0) // SELL fade of a bull MM
        {
         p.entry=sig.low;
         double structure=MathMax(sig.high, target+tol);
         p.stop=structure+buf;
         p.rewardPts=p.entry-b0Price;
         p.riskPts=p.stop-p.entry;
         p.invalidClose=target+over;
        }
      else // BUY fade of a bear MM
        {
         p.entry=sig.high;
         double structure=MathMin(sig.low, target-tol);
         p.stop=structure-buf;
         p.rewardPts=b0Price-p.entry;
         p.riskPts=p.entry-p.stop;
         p.invalidClose=target-over;
        }
      if(p.rewardPts<=0 || p.riskPts<=0) return p;
      p.rMult=p.rewardPts/p.riskPts;
      p.rrOK=(p.rMult+1e-9>=minRR);
      p.valid=true;
      return p;
     }

   static string SideName(int fadeDir)
     {
      return (fadeDir>0 ? "BUY" : "SELL");
     }

   static string Describe(const SetupPlan &p)
     {
      if(!p.valid) return "PLAN none";
      return StringFormat("PLAN #%d %s entry=%.5f stop=%.5f obj=%.5f R=%.2f%s%s",
         p.setupId, SideName(p.fadeDir), p.entry, p.stop, p.objective, p.rMult,
         (p.rrOK ? " RRok" : " RRlow"), (p.provisional ? " PROV" : ""));
     }
  };

#endif
