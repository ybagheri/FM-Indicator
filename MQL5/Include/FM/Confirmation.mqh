//+------------------------------------------------------------------+
//| Confirmation.mqh : ExhaustionAny + SignalBar (pure functions)       |
//+------------------------------------------------------------------+
#ifndef FM_CONFIRMATION_MQH
#define FM_CONFIRMATION_MQH
#include "Config.mqh"

class CConfirmation
  {
public:
   static double Body(const MqlRates &r) { return MathAbs(r.close - r.open); }
   static double Range(const MqlRates &r)
     {
      double rg = r.high - r.low;
      return (rg <= 0 ? _Point : rg);
     }

   // Exhaustion/stall proxy OR-list (SPEC §8). dir = MM direction d.
   static bool ExhaustionAny(const MqlRates &rates[], int count, int b, int dir, double atr)
     {
      if(b < 1 || b >= count || atr <= 0) return false;
      MqlRates r = rates[b];
      double rg = Range(r);
      // 1) climax
      bool climax = (rg >= 2.0 * atr);
      // 2) stall/doji with two-sided wicks
      double body = Body(r);
      double upW = r.high - MathMax(r.close, r.open);
      double loW = MathMin(r.close, r.open) - r.low;
      bool stall = (rg < 0.5 * atr + _Point && upW > 0.4 * rg && loW > 0.4 * rg);
      // 3) 3 pushes
      bool pushes = false;
      if(b + 2 < count)
        {
         if(dir > 0)
            pushes = (rates[b].close > rates[b+1].close && rates[b+1].close > rates[b+2].close &&
                      rates[b].high > rates[b+1].high && rates[b+1].high > rates[b+2].high);
         else
            pushes = (rates[b].close < rates[b+1].close && rates[b+1].close < rates[b+2].close &&
                      rates[b].low < rates[b+1].low && rates[b+1].low < rates[b+2].low);
        }
      // 4) channel overshoot: close beyond 20-bar SMA ± 0.3 ATR extreme proxy
      bool over = false;
      if(b + 20 < count)
        {
         double sum = 0;
         double hh = rates[b].high, ll = rates[b].low;
         for(int i = b; i < b + 20; i++)
           {
            sum += rates[i].close;
            if(rates[i].high > hh) hh = rates[i].high;
            if(rates[i].low < ll) ll = rates[i].low;
           }
         double sma = sum / 20.0;
         if(dir > 0) over = (r.high - MathMax(sma, hh - (hh - ll) * 0.2) > 0.3 * atr);
         else        over = (MathMin(sma, ll + (hh - ll) * 0.2) - r.low > 0.3 * atr);
         // simpler equivalent: extreme beyond recent extreme + 0.3 ATR
         if(dir > 0) over = over || (r.high > hh - (hh - ll) * 0.0 + 0.3 * atr * 0 + 0); // keep deterministic
        }
      return (climax || stall || pushes || over);
     }

   static bool IsSignalBar(const MqlRates &rates[], int count, int c, int fade_dir,
                           const CFMConfig &cfg)
     {
      if(c < 2 || c >= count) return false;
      MqlRates r = rates[c], p = rates[c+1];
      double rg = Range(r);
      if(rg <= 0) return false;
      double body = Body(r);
      int dir = (r.close > r.open) ? +1 : (r.close < r.open ? -1 : 0);
      if(dir != fade_dir) return false;
      if(body / rg < cfg.MinBodyRatio) return false;
      double advWick = (fade_dir > 0) ? (r.high - r.close) : (r.close - r.low);
      // for bearish fade (fade_dir=-1): adverse wick = close-low? No: adverse = upper wick
      // fade bull (buying fade, f=+1): want close near high → adverse = high-close. Correct above.
      // fade bear (f=-1): adverse = close-low? Actually want close near low → adverse = close-low? No:
      // close near low ⇒ lower wick small ⇒ adverse wick = r.close - r.low. Fix:
      if(fade_dir < 0) advWick = r.close - r.low;
      if(advWick / rg > cfg.MaxWickRatio) return false;
      double edge = (fade_dir > 0) ? (r.close - r.low) / rg : (r.high - r.close) / rg;
      // close must be in extreme SignalClosePct toward fade dir:
      // bull fade: (close-low)/rg >= 1-ClosePct ; bear fade: (high-close)/rg >= 1-ClosePct
      double need = 1.0 - cfg.SignalClosePct;
      if(edge < need) return false;
      if(cfg.RequireEngulf)
        {
         double pb = MathAbs(p.close - p.open);
         bool engulf = (fade_dir > 0) ? (r.close > p.open && r.open < p.close) :
                                        (r.close < p.open && r.open > p.close);
         if(!engulf || body < pb) return false;
        }
      return true;
     }

   static bool FollowThrough(const MqlRates &rates[], int count, int sig, int fade_dir)
     {
      if(sig < 2 || sig >= count) return false; // need bar sig-1 (newer) to exist & be closed
      MqlRates s = rates[sig], n = rates[sig-1];
      if(fade_dir > 0) return (n.close > s.high);
      return (n.close < s.low);
     }
  };

#endif
