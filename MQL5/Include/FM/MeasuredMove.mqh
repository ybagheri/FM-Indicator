//+------------------------------------------------------------------+
//| MeasuredMove.mqh : leg validation + Leg1=Leg2 / inverse projection |
//+------------------------------------------------------------------+
#ifndef FM_MEASUREDMOVE_MQH
#define FM_MEASUREDMOVE_MQH
#include "Defs.mqh"
#include "Config.mqh"

struct LegInfo
  {
   SwingPoint        a0;
   SwingPoint        a1;
   int               dir;      // +1 bull, -1 bear
   double            range;
   int               bars;
  };

struct Projection
  {
   bool              valid;
   ENUM_MM_FAMILY    family;
   int               dir;
   SwingPoint        a0;
   SwingPoint        a1;
   SwingPoint        b0;
   double            mm_range;
   double            target;
   int               created_shift; // newest-closed shift at creation (=1 area)
   datetime          created_time;
  };

class CMeasuredMoveBase
  {
public:
   virtual bool Project(const SwingPoint &a0, const SwingPoint &a1, const SwingPoint &b0,
                        const CFMConfig &cfg, double atr_ref, Projection &out) { return false; }
  };

class CLegEqualityMM : public CMeasuredMoveBase
  {
public:
   virtual bool Project(const SwingPoint &a0, const SwingPoint &a1, const SwingPoint &b0,
                        const CFMConfig &cfg, double atr_ref, Projection &out) override
     {
      out.valid = false;
      int dir = 0;
      double mmr = 0;
      if(a0.dir==-1 && a1.dir==+1 && b0.dir==-1) { dir=+1; mmr = a1.price - a0.price; }
      else if(a0.dir==+1 && a1.dir==-1 && b0.dir==+1) { dir=-1; mmr = a0.price - a1.price; }
      else return false;
      if(mmr <= 0 || atr_ref <= 0) return false;
      int legBars = MathAbs(a1.bar - a0.bar);
      if(legBars < cfg.MinLegBars || legBars > cfg.MaxLegBars) return false;
      if(mmr < cfg.MinLegATRMult * atr_ref) return false;
      // pullback depth
      double depth = 0;
      if(dir > 0) depth = (a1.price - b0.price) / mmr;
      else        depth = (b0.price - a1.price) / mmr;
      if(depth < cfg.MinPullbackRatio || depth > cfg.MaxPullbackRatio) return false;
      int pbBars = MathAbs(b0.bar - a1.bar);
      if(pbBars < 0 || pbBars > cfg.MaxPullbackBars) return false;
      // chronological order: a0 older (larger shift) than a1 older than b0
      if(!(a0.bar > a1.bar && a1.bar > b0.bar)) return false;
      out.valid = true;
      out.family = MM_REGULAR;
      out.dir = dir;
      out.a0 = a0; out.a1 = a1; out.b0 = b0;
      out.mm_range = mmr;
      out.target = (dir > 0) ? b0.price + mmr : b0.price - mmr;
      return true;
     }
  };

// Failed-BO inverse: A1 extreme broken then reclaimed → opposite projection.
class CInverseMMHelper
  {
public:
   // Scan bars (b0.shift .. b0.shift-FailedBOBars) for break+reclaim of A1.
   // Returns true + fills out (bearish inverse shown; mirrors for bull leg).
   static bool TryInverse(const MqlRates &rates[], int count,
                          const LegInfo &leg, const CFMConfig &cfg,
                          double atr_ref, Projection &out)
     {
      out.valid = false;
      if(!cfg.EnableInverseMM || atr_ref <= 0) return false;
      // leg extreme price:
      double ext = (leg.dir > 0) ? leg.a1.price : leg.a1.price;
      // find failure excursion after a1.bar going toward newer bars (smaller shift)
      int from = leg.a1.bar - 1;
      int to = leg.a1.bar - cfg.FailedBOBars;
      if(from < 1) return false;
      if(to < 1) to = 1;
      if(leg.dir > 0)
        {
         // bull leg: look for close above ext then close back below ext
         double fhigh = 0; int flow = 0, failShift = -1;
         for(int s = from; s >= to; s--)
           {
            if(rates[s].high > fhigh) { fhigh = rates[s].high; flow = rates[s].low; }
            if(rates[s].close > ext)
              {
               // broken; now need reclaim within remaining window
               for(int t = s - 1; t >= to; t--)
                 {
                  if(rates[t].high > fhigh) { fhigh = rates[t].high; flow = rates[t].low; }
                  if(rates[t].close < ext) { failShift = t; break; }
                 }
               break;
              }
           }
         if(failShift < 0 || fhigh <= ext) return false;
         out.valid = true; out.family = MM_INVERSE; out.dir = -1;
         out.a0 = leg.a0; out.a1 = leg.a1;
         out.b0.bar = failShift; out.b0.price = fhigh; out.b0.dir = +1; out.b0.valid = true;
         out.mm_range = leg.range;
         out.target = flow - leg.range; // conservative: from failure low minus leg range
         if(out.target >= flow) return false;
         return true;
        }
      else
        {
         double flow = 0; int fhigh = 0; double fLow = 0; int failShift = -1;
         bool init = false;
         double flowLow = 0;
         for(int s = from; s >= to; s--)
           {
            if(!init || rates[s].low < flowLow) { flowLow = rates[s].low; init = true; }
            if(rates[s].close < ext)
              {
               for(int t = s - 1; t >= to; t--)
                 {
                  if(rates[t].low < flowLow) flowLow = rates[t].low;
                  if(rates[t].close > ext) { failShift = t; break; }
                 }
               break;
              }
           }
         if(failShift < 0 || !(flowLow < ext)) return false;
         // failure high = highest high of excursion
         double fHigh = rates[failShift].high;
         for(int s = from; s >= to; s--) if(rates[s].high > fHigh) fHigh = rates[s].high;
         out.valid = true; out.family = MM_INVERSE; out.dir = +1;
         out.a0 = leg.a0; out.a1 = leg.a1;
         out.b0.bar = failShift; out.b0.price = flowLow; out.b0.dir = -1; out.b0.valid = true;
         out.mm_range = leg.range;
         out.target = fHigh + leg.range;
         return true;
        }
     }
  };

#endif
