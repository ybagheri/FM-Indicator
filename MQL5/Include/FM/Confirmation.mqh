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

    // Consecutive pushes toward dir ending at b (first-class counter, v1.2).
    static int PushCount(const MqlRates &rates[], int count, int b, int dir)
      {
       if(b < 1 || b >= count) return 0;
       int n = 0;
       for(int i = b; i >= 1 && i < count; i--)
         {
          if(i + 1 >= count) break;
          if(dir > 0)
            {
             if(!(rates[i].close > rates[i+1].close && rates[i].high > rates[i+1].high)) break;
            }
          else
            {
             if(!(rates[i].close < rates[i+1].close && rates[i].low < rates[i+1].low)) break;
            }
          n++;
          if(n >= 6) break;
         }
       return n;
      }

    // Wedge/3-push exhaustion: >=3 pushes with shrinking ranges (each range
    // <= prior range) → buying/selling pressure fading into the target.
    static bool IsWedge(const MqlRates &rates[], int count, int b, int dir)
      {
       if(b < 3 || b + 2 >= count) return false;
       int n = PushCount(rates, count, b, dir);
       if(n < 3) return false;
       bool shrink = true;
       for(int i = b; i > b - n + 1 && i >= 1 && i + 1 < count; i--)
         {
          double r0 = Range(rates[i]), r1 = Range(rates[i+1]);
          if(r0 > r1 * 1.05) { shrink = false; break; }
         }
       return (shrink || n >= 4);
      }

    // Exhaustion/stall proxy OR-list (SPEC §8). dir = MM direction d.
    static bool ExhaustionAny(const MqlRates &rates[], int count, int b, int dir, double atr)
      {
       CFMConfig dflt;
       return ExhaustionAnyCfg(rates, count, b, dir, atr, dflt.MinPushes, true);
      }

    static bool ExhaustionAnyCfg(const MqlRates &rates[], int count, int b, int dir, double atr,
                                 int minPushes, bool useWedge)
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
       // 3) pushes (first-class counter, v1.2): PushCount >= minPushes
       bool pushes = (PushCount(rates, count, b, dir) >= (minPushes < 2 ? 2 : minPushes));
       // 3b) wedge variant (shrinking ranges into target)
       bool wedge = (useWedge && IsWedge(rates, count, b, dir));
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
         }
       return (climax || stall || pushes || wedge || over);
      }

    static bool IsSignalBar(const MqlRates &rates[], int count, int c, int fade_dir,
                            const CFMConfig &cfg)
      {
       // c = closed-bar shift (1 = newest closed). Prior bar c+1 must exist
       // for the optional engulf check; c==1 is the normal live case and MUST
       // be allowed (v1.1 fix: was c<2 which blocked all newest-bar signals).
       if(c < 1 || c + 1 >= count) return false;
      MqlRates r = rates[c], p = rates[c+1];
      double rg = Range(r);
      if(rg <= 0) return false;
      double body = Body(r);
      int dir = (r.close > r.open) ? +1 : (r.close < r.open ? -1 : 0);
      if(dir != fade_dir) return false;
      if(body / rg < cfg.MinBodyRatio) return false;
      double advWick = (fade_dir > 0) ? (r.high - r.close) : (r.close - r.low);
      // adverse wick vs fade direction (mirrors Python oracle): long fade wants
      // small upper wick (high-close); short fade wants small lower wick (close-low).
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

    // Signal quality score 0..100 (v1.2, display only — never auto-trades).
    // Components: body 0-20, wick 0-15, close position 0-15, engulf +10,
    // follow-through +10, exhaustion breadth 0-20, context 0-10.
    static int ScoreSignal(const MqlRates &rates[], int count, int c, int fade_dir,
                           const CFMConfig &cfg, int mm_dir, double atr,
                           double dist_to_target_atr, double ctx_conf)
      {
       if(c < 1 || c + 1 >= count || atr <= 0) return 0;
       MqlRates r = rates[c];
       double rg = Range(r);
       if(rg <= 0) return 0;
       double body = Body(r) / rg;                    // 0..1
       int score = (int)(MathMin(1.0, body) * 20.0);
       double adv = (fade_dir > 0) ? (r.high - r.close) / rg : (r.close - r.low) / rg;
       score += (int)((1.0 - MathMin(1.0, adv / 0.6)) * 15.0);
       double edge = (fade_dir > 0) ? (r.close - r.low) / rg : (r.high - r.close) / rg;
       score += (int)(MathMin(1.0, edge) * 15.0);
       if(cfg.RequireEngulf)
         {
          MqlRates p = rates[c+1];
          double pb = MathAbs(p.close - p.open);
          bool eng = (fade_dir > 0) ? (r.close > p.open && r.open < p.close) :
                                      (r.close < p.open && r.open > p.close);
          if(eng && Body(r) >= pb) score += 10;
         }
       else
          score += 5; // no engulf requirement: neutral half-credit
       if(FollowThrough(rates, count, c + 1 >= count ? c : c, fade_dir)) score += 5;
       if(c >= 2 && c - 1 >= 0)
         {
          // follow-through already printed on next bar: credit if current bar
          // itself closes beyond prior extreme (late-confirmation shape)
          MqlRates p = rates[c+1];
          if(fade_dir > 0 && r.close > p.high) score += 5;
          if(fade_dir < 0 && r.close < p.low) score += 5;
         }
       // exhaustion breadth at signal bar (toward MM dir)
       int hits = 0;
       double upW = r.high - MathMax(r.close, r.open);
       double loW = MathMin(r.close, r.open) - r.low;
       if(rg >= 2.0 * atr) hits++;
       if(rg < 0.5 * atr + _Point && upW > 0.4 * rg && loW > 0.4 * rg) hits++;
       if(PushCount(rates, count, c + 1, mm_dir) >= 2) hits++;
       if(IsWedge(rates, count, c + 1 >= count ? c : c + 1, mm_dir)) hits++;
       score += MathMin(4, hits) * 5; // 0..20
       score += (int)(MathMax(0.0, MathMin(1.0, ctx_conf)) * 10.0);
       double dt = MathAbs(dist_to_target_atr); // in ATR; 0=center → 10 pts
       score += (int)(MathMax(0.0, 1.0 - MathMin(1.0, dt / 0.5)) * 10.0);
       if(score < 0) score = 0;
       if(score > 100) score = 100;
       return score;
      }
  };

#endif
