//+------------------------------------------------------------------+
//| GeneralSetups.mqh : non-FM setup catalog — pullback/double/BO/MTR  |
//| Phase 7 of bar-by-bar engine (see docs/GENERAL_SETUPS.md).          |
//| Stateless, closed bars only, read-only (DEBUG log; never gates FM). |
//| MT5 shifts: 0 = forming, >=1 closed, older = larger shift.          |
//+------------------------------------------------------------------+
#ifndef FM_GENERALSETUPS_MQH
#define FM_GENERALSETUPS_MQH
#include "Config.mqh"
#include "Defs.mqh"
#include "PullbackPatterns.mqh"
#include "BreakoutEngine.mqh"
#include "ReversalEngine.mqh"

enum ENUM_SETUP_TYPE
  {
   SETUP_NONE=0,
   SETUP_TREND_PULLBACK=1,
   SETUP_DOUBLE=2,
   SETUP_BREAKOUT=3,
   SETUP_REVERSAL=4,
   SETUP_FM_FADE=5,   // Phase-6 FM plan converted for the Phase-8 contest (§5)
   SETUP_FAILED_BO=6  // Phase 28: EA-side failed-breakout fade (registry-built)
  };

struct GeneralSetup
  {
   bool              valid;
   ENUM_SETUP_TYPE   type;
   int               dir;          // ±1 trade direction
   double            entry;
   double            stop;
   double            objective;
   double            riskPts;
   double            rewardPts;
   double            rMult;
   bool              rrOK;         // report-only; veto is Phase 8
   bool              provisional;
   int               signalBar;    // MT5 shift of the signal/reference bar
   double            refPrice;     // structural reference (extreme/level/ref/EMA)
   int               score;        // 0..100 fixed proxy (never a probability)
  };

class CGeneralSetups
  {
public:
   static void InitNone(GeneralSetup &s)
     {
      s.valid=false; s.type=SETUP_NONE; s.dir=0;
      s.entry=0; s.stop=0; s.objective=0;
      s.riskPts=0; s.rewardPts=0; s.rMult=0;
      s.rrOK=false; s.provisional=true;
      s.signalBar=-1; s.refPrice=0; s.score=0;
     }

   static double MinRR(const CFMConfig &cfg)
     {
      double m=cfg.SetupMinRR;
      if(m<0.25) m=0.25;
      if(m>5.0) m=5.0;
      return m;
     }

   static void Finish(GeneralSetup &s, const CFMConfig &cfg)
     {
      if(s.rewardPts<=0 || s.riskPts<=0) { s.valid=false; return; }
      s.rMult=s.rewardPts/s.riskPts;
      s.rrOK=(s.rMult+1e-9>=MinRR(cfg));
      s.valid=true;
     }

   // TREND_PULLBACK from an already-detected H1/H2 (bull) signal.
   // sigHigh = H[sig]; pbStop = pullback low (pb.stop); winHigh = objective.
   static GeneralSetup FromPullbackBull(const PullbackSignal &pb, double sigHigh,
                                        double pbStop, double winHigh,
                                        double atr, const CFMConfig &cfg)
     {
      GeneralSetup s; InitNone(s);
      s.type=SETUP_TREND_PULLBACK; s.dir=+1;
      if(!cfg.EnableGeneralSetups) return s;
      if(!pb.found) return s;
      if(atr<=0) return s;
      double tick=cfg.GeneralTickProxyATRMult*atr;
      double buf=cfg.SetupStopBufATRMult*atr;
      s.entry=sigHigh+tick;
      s.stop=pbStop-buf;
      s.objective=winHigh;
      s.rewardPts=s.objective-s.entry;
      s.riskPts=s.entry-s.stop;
      s.provisional=(pb.legs<2);
      s.signalBar=pb.signalBar;
      s.refPrice=sigHigh;
      s.score=(pb.legs>=2 ? 70 : 40);
      Finish(s,cfg);
      return s;
     }

   // TREND_PULLBACK bear mirror (L1/L2).
   static GeneralSetup FromPullbackBear(const PullbackSignal &pb, double sigLow,
                                        double pbStop, double winLow,
                                        double atr, const CFMConfig &cfg)
     {
      GeneralSetup s; InitNone(s);
      s.type=SETUP_TREND_PULLBACK; s.dir=-1;
      if(!cfg.EnableGeneralSetups) return s;
      if(!pb.found) return s;
      if(atr<=0) return s;
      double tick=cfg.GeneralTickProxyATRMult*atr;
      double buf=cfg.SetupStopBufATRMult*atr;
      s.entry=sigLow-tick;
      s.stop=pbStop+buf;
      s.objective=winLow;
      s.rewardPts=s.entry-s.objective;
      s.riskPts=s.stop-s.entry;
      s.provisional=(pb.legs<2);
      s.signalBar=pb.signalBar;
      s.refPrice=sigLow;
      s.score=(pb.legs>=2 ? 70 : 40);
      Finish(s,cfg);
      return s;
     }

   // DOUBLE from an already-detected double + its trough price.
   static GeneralSetup FromDouble(const DoubleSignal &d, double trough,
                                  double atr, const CFMConfig &cfg)
     {
      GeneralSetup s; InitNone(s);
      s.type=SETUP_DOUBLE;
      if(!cfg.EnableGeneralSetups) return s;
      if(!d.found) return s;
      if(atr<=0) return s;
      if(d.dir!=+1 && d.dir!=-1) return s;
      double tol=cfg.DoubleTopTolATRMult*atr;
      double buf=cfg.SetupStopBufATRMult*atr;
      s.dir=d.dir;
      s.provisional=d.micro;
      s.signalBar=d.bar2;
      s.refPrice=d.price2;
      s.score=(d.micro ? 30 : 60);
      if(d.dir<0) // double top → short
        {
         double top=MathMax(d.price1,d.price2);
         s.entry=d.price2;
         s.stop=top+tol+buf;
         s.objective=trough;
         s.rewardPts=s.entry-s.objective;
         s.riskPts=s.stop-s.entry;
        }
      else // double bottom → long
        {
         double bot=MathMin(d.price1,d.price2);
         s.entry=d.price2;
         s.stop=bot-tol-buf;
         s.objective=trough;
         s.rewardPts=s.objective-s.entry;
         s.riskPts=s.entry-s.stop;
        }
      Finish(s,cfg);
      return s;
     }

   // BREAKOUT: FOLLOW (firm) or PENDING (provisional); FAILED/none → invalid.
   static GeneralSetup FromBreakout(const BreakoutSignal &bo, double closeB,
                                    double atr, const CFMConfig &cfg)
     {
      GeneralSetup s; InitNone(s);
      s.type=SETUP_BREAKOUT;
      if(!cfg.EnableGeneralSetups) return s;
      if(!bo.found) return s;
      if(atr<=0) return s;
      if(bo.dir!=+1 && bo.dir!=-1) return s;
      if(bo.outcome!=BO_FOLLOW_THROUGH && bo.outcome!=BO_PENDING) return s;
      double buf=cfg.SetupStopBufATRMult*atr;
      double objD=cfg.GeneralObjectiveATRMult*atr;
      s.dir=bo.dir;
      s.entry=closeB;
      s.signalBar=bo.boBar;
      s.refPrice=bo.refPrice;
      s.provisional=(bo.outcome==BO_PENDING);
      int base=(bo.outcome==BO_FOLLOW_THROUGH ? 70 : 40);
      if(bo.trapArmed) base-=20;
      if(base<0) base=0;
      s.score=base;
      if(bo.dir>0)
        {
         s.stop=bo.refPrice-buf;
         s.objective=s.entry+objD;
         s.rewardPts=s.objective-s.entry;
         s.riskPts=s.entry-s.stop;
        }
      else
        {
         s.stop=bo.refPrice+buf;
         s.objective=s.entry-objD;
         s.rewardPts=s.entry-s.objective;
         s.riskPts=s.stop-s.entry;
        }
      Finish(s,cfg);
      return s;
     }

   // REVERSAL: MINOR provisional, MAJOR firm. emaB = EMA20 at bar b.
   static GeneralSetup FromReversal(const ReversalSignal &rv, double closeB,
                                    double emaB, double atr, const CFMConfig &cfg)
     {
      GeneralSetup s; InitNone(s);
      s.type=SETUP_REVERSAL;
      if(!cfg.EnableGeneralSetups) return s;
      if(!rv.found) return s;
      if(atr<=0) return s;
      if(rv.dir!=+1 && rv.dir!=-1) return s;
      double buf=cfg.SetupStopBufATRMult*atr;
      double tolR=cfg.RevRetestTolATRMult*atr;
      double objD=cfg.GeneralObjectiveATRMult*atr;
      s.dir=rv.dir;
      s.entry=closeB;
      s.signalBar=-1;
      s.refPrice=emaB;
      s.provisional=(rv.verdict!=REV_MAJOR);
      s.score=(rv.verdict==REV_MAJOR ? 80 : 40);
      s.stop=emaB-rv.dir*(tolR+buf);
      s.objective=s.entry+rv.dir*objD;
      s.rewardPts=rv.dir*(s.objective-s.entry);
      s.riskPts=rv.dir*(s.entry-s.stop);
      Finish(s,cfg);
      return s;
     }

   // Hook-side selection: max score wins; ties → lowest type enum, then
   // lowest signalBar (most recent). Returns index into arr, or -1 if none.
   static int SelectBest(const GeneralSetup &arr[])
     {
      int best=-1;
      for(int i=0;i<ArraySize(arr);i++)
        {
         if(!arr[i].valid) continue;
         if(best<0) { best=i; continue; }
         if(arr[i].score>arr[best].score) { best=i; continue; }
         if(arr[i].score<arr[best].score) continue;
         if((int)arr[i].type<(int)arr[best].type) { best=i; continue; }
         if((int)arr[i].type>(int)arr[best].type) continue;
         if(arr[i].signalBar<arr[best].signalBar) best=i;
        }
      return best;
     }

   static string TypeName(ENUM_SETUP_TYPE t)
     {
      switch(t)
        {
         case SETUP_TREND_PULLBACK: return "PULLBACK";
         case SETUP_DOUBLE:         return "DOUBLE";
         case SETUP_BREAKOUT:       return "BREAKOUT";
         case SETUP_REVERSAL:       return "REVERSAL";
         case SETUP_FM_FADE:        return "FM_FADE";
         case SETUP_FAILED_BO:      return "FAILED_BO";
         default:                   return "NONE";
        }
     }

   static string Describe(const GeneralSetup &s)
     {
      if(!s.valid) return "GSETUP none";
      return StringFormat("GSETUP %s %s entry=%.5f stop=%.5f obj=%.5f R=%.2f score=%d%s%s",
         TypeName(s.type), (s.dir>0 ? "BUY" : "SELL"),
         s.entry, s.stop, s.objective, s.rMult, s.score,
         (s.rrOK ? " RRok" : " RRlow"), (s.provisional ? " PROV" : ""));
     }
  };

#endif
