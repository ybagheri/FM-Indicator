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

// v1.2: trading-range height breakout. Range = HH-LL over RangeLookback bars
// ending at breakout bar `bo_shift` (newest-closed side). Bull breakout: close
// above range high → target = breakout close + range height. a0/a1 carry the
// range low/high bars for visualization; b0 = breakout bar.
class CRangeHeightMM
   {
public:
    static bool Project(const MqlRates &rates[], int count, int bo_shift,
                        const CFMConfig &cfg, double atr_ref, Projection &out)
      {
       out.valid = false;
       if(!cfg.EnableRangeMM || atr_ref <= 0) return false;
       int N = cfg.RangeLookback;
       if(bo_shift < 1 || bo_shift + N >= count) return false;
       double hh = rates[bo_shift+1].high, ll = rates[bo_shift+1].low;
       int hiBar = bo_shift+1, loBar = bo_shift+1;
       for(int i = bo_shift + 1; i <= bo_shift + N && i < count; i++)
         {
          if(rates[i].high > hh) { hh = rates[i].high; hiBar = i; }
          if(rates[i].low < ll) { ll = rates[i].low; loBar = i; }
         }
       double height = hh - ll;
       if(height < cfg.MinLegATRMult * atr_ref) return false;
       MqlRates bo = rates[bo_shift];
       if(bo.close > hh)
         {
          out.valid = true; out.family = MM_RANGE; out.dir = +1;
          out.a0.bar = loBar; out.a0.price = ll; out.a0.dir = -1; out.a0.valid = true;
          out.a1.bar = hiBar; out.a1.price = hh; out.a1.dir = +1; out.a1.valid = true;
          out.b0.bar = bo_shift; out.b0.price = hh; out.b0.dir = +1; out.b0.valid = true;
          out.mm_range = height; out.target = bo.close + height;
          return true;
         }
       if(bo.close < ll)
         {
          out.valid = true; out.family = MM_RANGE; out.dir = -1;
          out.a0.bar = hiBar; out.a0.price = hh; out.a0.dir = +1; out.a0.valid = true;
          out.a1.bar = loBar; out.a1.price = ll; out.a1.dir = -1; out.a1.valid = true;
          out.b0.bar = bo_shift; out.b0.price = ll; out.b0.dir = -1; out.b0.valid = true;
          out.mm_range = height; out.target = bo.close - height;
          return true;
         }
       return false;
      }
   };

// v1.2: channel continuation (shallow pullback). Same geometry as Leg1=Leg2
// but fires only when pullback depth is BELOW the regular minimum — i.e. a
// flag/channel that LegEquality rejects (default depth 0.02–0.15). Keeps the
// two families mutually exclusive by construction.
class CChannelMM : public CMeasuredMoveBase
   {
public:
    virtual bool Project(const SwingPoint &a0, const SwingPoint &a1, const SwingPoint &b0,
                         const CFMConfig &cfg, double atr_ref, Projection &out) override
      {
       out.valid = false;
       if(!cfg.EnableChannelMM) return false;
       int dir = 0;
       double mmr = 0;
       if(a0.dir==-1 && a1.dir==+1 && b0.dir==-1) { dir=+1; mmr = a1.price - a0.price; }
       else if(a0.dir==+1 && a1.dir==-1 && b0.dir==+1) { dir=-1; mmr = a0.price - a1.price; }
       else return false;
       if(mmr <= 0 || atr_ref <= 0) return false;
       int legBars = MathAbs(a1.bar - a0.bar);
       if(legBars < cfg.MinLegBars || legBars > cfg.MaxLegBars) return false;
       if(mmr < cfg.MinLegATRMult * atr_ref) return false;
       double depth = (dir > 0) ? (a1.price - b0.price) / mmr : (b0.price - a1.price) / mmr;
       // shallow-only band: [0.02, MinPullbackRatio). Regular owns >= MinPullbackRatio.
       if(depth < 0.02 || depth >= cfg.MinPullbackRatio) return false;
       int pbBars = MathAbs(b0.bar - a1.bar);
       if(pbBars < 0 || pbBars > cfg.MaxPullbackBars) return false;
       if(!(a0.bar > a1.bar && a1.bar > b0.bar)) return false;
       out.valid = true; out.family = MM_CHANNEL; out.dir = dir;
       out.a0 = a0; out.a1 = a1; out.b0 = b0;
       out.mm_range = mmr;
       out.target = (dir > 0) ? b0.price + mmr : b0.price - mmr;
       return true;
      }
   };

// v1.2: measuring-gap projection. Gap bar `g`: range >= MinGapATRMult×ATR,
// closes in extreme 25% toward dir, and gaps away from prior extreme
// (bull: low > prior high = micro gap; bear mirrors). mm_range = gap size
// (|close − prior extreme|), target = close + dir×range. Brooks: every trend
// bar is a BO/gap; the gap size is the measured impulse.
class CGapMM
   {
public:
    static bool Project(const MqlRates &rates[], int count, int g,
                        const CFMConfig &cfg, double atr_ref, Projection &out)
      {
       out.valid = false;
       if(!cfg.EnableGapMM || atr_ref <= 0) return false;
       if(g < 2 || g + 1 >= count) return false;
       MqlRates r = rates[g], p = rates[g+1];
       double rg = r.high - r.low;
       if(rg < cfg.MinGapATRMult * atr_ref || rg <= 0) return false;
       bool bullGap = (r.low > p.high) && ((r.close - r.low) / rg >= 0.75);
       bool bearGap = (r.high < p.low) && ((r.high - r.close) / rg >= 0.75);
       if(!bullGap && !bearGap) return false;
       double gapSize = bullGap ? (r.close - p.high) : (p.low - r.close);
       if(gapSize < 0.25 * atr_ref) return false;
       out.valid = true; out.family = MM_GAP;
       out.dir = bullGap ? +1 : -1;
       out.a0.bar = g + 1; out.a0.price = bullGap ? p.high : p.low;
       out.a0.dir = bullGap ? -1 : +1; out.a0.valid = true;
       out.a1.bar = g; out.a1.price = bullGap ? r.low : r.high;
       out.a1.dir = bullGap ? -1 : +1; out.a1.valid = true;
       out.b0.bar = g; out.b0.price = r.close;
       out.b0.dir = bullGap ? -1 : +1; out.b0.valid = true;
       out.mm_range = gapSize;
       out.target = r.close + out.dir * gapSize;
       return true;
      }
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
// v1.1 anchor review (walk-forward placeholder, no live data yet): anchor is
// the FAR SIDE of the failure-extreme bar — bull-inverse target = low of the
// failure-high bar minus leg range; bear-inverse mirrors (high of failure-low
// bar plus range). Symmetric, conservative, ATR-independent (range is ATR-
// gated at leg level). Flagged for walk-forward review once tester data exists.
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
         double fhigh = 0, flow = 0; int failShift = -1;
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
          // Bear leg (failed bear BO → bullish inverse). Symmetric to bull
          // branch (v1.1 anchor review): anchor = HIGH of the failure-LOW bar
          // (bar that printed the lowest low of the break+reclaim window),
          // target = anchor_high + leg_range. Conservative: measures from the
          // far side of the failure bar, not the excursion extreme.
          double failLow = 0; double anchorHigh = 0; int failShift = -1;
          int lowBar = -1;
          bool init = false;
          double lowPx = 0;
          for(int s = from; s >= to; s--)
            {
             if(!init || rates[s].low < lowPx) { lowPx = rates[s].low; lowBar = s; init = true; }
             if(rates[s].close < ext)
               {
                for(int t = s - 1; t >= to; t--)
                  {
                   if(rates[t].low < lowPx) { lowPx = rates[t].low; lowBar = t; }
                   if(rates[t].close > ext) { failShift = t; break; }
                  }
                break;
               }
            }
          if(failShift < 0 || !init || !(lowPx < ext) || lowBar < 1) return false;
          failLow = lowPx;
          anchorHigh = rates[lowBar].high;
          out.valid = true; out.family = MM_INVERSE; out.dir = +1;
          out.a0 = leg.a0; out.a1 = leg.a1;
          out.b0.bar = failShift; out.b0.price = failLow; out.b0.dir = -1; out.b0.valid = true;
          out.mm_range = leg.range;
          out.target = anchorHigh + leg.range;
          return true;
         }
     }
  };

#endif
