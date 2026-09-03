//+------------------------------------------------------------------+
//| BreakoutEngine.mqh : CBreakoutEngine — BO events + FOLLOW/FAILED   |
//|   lifecycle + second-leg trap flag (docs/BREAKOUT_ENGINE.md).      |
//| Generalizes v1 CInverseMMHelper beyond legs (detection only — emits |
//| NO targets). Stateless, closed bars only, read-only (DEBUG log).   |
//| MT5 shifts: 0 = forming, >=1 closed, older = larger shift.         |
//+------------------------------------------------------------------+
#ifndef FM_BREAKOUTENGINE_MQH
#define FM_BREAKOUTENGINE_MQH
#include "Config.mqh"
#include "Defs.mqh"

struct BreakoutSignal
  {
   bool              found;
   int               dir;          // +1 bull breakout, -1 bear breakout
   int               boBar;        // MT5 shift of the breakout bar k
   double            refPrice;     // reference level broken
   bool              refIsSwing;   // false = N-bar extreme, true = swing
   ENUM_BO_OUTCOME   outcome;      // PENDING / FOLLOW_THROUGH / FAILED
   bool              trapArmed;    // prior same-dir failure → second-leg trap risk
   int               decideBar;    // newest bar deciding outcome (-1 when PENDING)
  };

class CBreakoutEngine
  {
public:
   // N-bar reference over the N closed bars strictly older than k.
   // Needs >=10 such bars, else unavailable. Shifts [k+1 .. k+N].
   static bool NBarRef(const MqlRates &rates[], int count, int k, int N,
                       double &rh, double &rl)
     {
      rh = 0; rl = 0;
      int avail = 0;
      bool init = false;
      for(int i = k + 1; i <= k + N && i < count; i++)
        {
         if(!init) { rh = rates[i].high; rl = rates[i].low; init = true; }
         else
           {
            if(rates[i].high > rh) rh = rates[i].high;
            if(rates[i].low < rl) rl = rates[i].low;
           }
         avail++;
        }
      return (init && avail >= 10);
     }

   // Most recent confirmed swing high/low strictly older than k
   // (older = larger shift). hiOK/loOK independent.
   static void SwingRef(const SwingPoint &sw[], int k,
                        double &sh, double &sl, bool &hiOK, bool &loOK)
     {
      sh = 0; sl = 0; hiOK = false; loOK = false;
      int n = ArraySize(sw);
      for(int i = n - 1; i >= 0; i--)
        {
         if(!sw[i].valid || sw[i].bar <= k) continue;
         if(sw[i].dir == +1 && !hiOK) { sh = sw[i].price; hiOK = true; }
         if(sw[i].dir == -1 && !loOK) { sl = sw[i].price; loOK = true; }
         if(hiOK && loOK) break;
        }
     }

   // Breakout event at closed bar k. At most one direction can fire
   // (refHigh >= refLow); swing reference wins same-direction ties.
   // Returns +1 / -1 / 0.
   static int EventAt(const MqlRates &rates[], int count, int k, double tol,
                      const SwingPoint &sw[], const CFMConfig &cfg,
                      double &refPx, bool &isSwing)
     {
      refPx = 0; isSwing = false;
      if(k < 1 || k >= count) return 0;
      int N = cfg.BOLookback;
      if(N < 10) N = 10;
      double rh = 0, rl = 0;
      bool nbOK = NBarRef(rates, count, k, N, rh, rl);
      double sh = 0, sl = 0;
      bool hiOK = false, loOK = false;
      SwingRef(sw, k, sh, sl, hiOK, loOK);
      double c = rates[k].close;
      bool bullSw = (hiOK && c > sh + tol);
      bool bullNb = (nbOK && c > rh + tol);
      if(bullSw || bullNb)
        {
         if(bullSw) { refPx = sh; isSwing = true; }
         else { refPx = rh; isSwing = false; }
         return +1;
        }
      bool bearSw = (loOK && c < sl - tol);
      bool bearNb = (nbOK && c < rl - tol);
      if(bearSw || bearNb)
        {
         if(bearSw) { refPx = sl; isSwing = true; }
         else { refPx = rl; isSwing = false; }
         return -1;
        }
      return 0;
     }

   // Failed(m, refPx, dir): exists bar newer than m (down to stopShift,
   // inclusive) closing back past ref∓tol. Pure helper for trap scan.
   static bool FailedSince(const MqlRates &rates[], int count, int m,
                           int stopShift, double refPx, int dir, double tol,
                           int &failBar)
     {
      failBar = -1;
      for(int j = stopShift; j < m && j < count; j++)
        {
         if(j < 1) continue;
         if(dir > 0 && rates[j].close < refPx - tol) { failBar = j; break; }
         if(dir < 0 && rates[j].close > refPx + tol) { failBar = j; break; }
        }
      return (failBar >= 0);
     }

   // Main entry: active breakout at analysis bar b (b>=1). Most recent event
   // in [b .. b+FollowBars] wins; outcome from bars [b .. k-1].
   static BreakoutSignal Analyze(const MqlRates &rates[], int count, int b,
                                 double atr, const SwingPoint &sw[],
                                 const CFMConfig &cfg)
     {
      BreakoutSignal s;
      s.found = false; s.dir = 0; s.boBar = -1; s.refPrice = 0;
      s.refIsSwing = false; s.outcome = BO_NONE; s.trapArmed = false;
      s.decideBar = -1;
      if(!cfg.EnableBreakout) return s;
      if(b < 1 || b >= count) return s;
      if(atr <= 0) return s;
      double tol = cfg.BOToleranceATRMult * atr;
      int F = cfg.BOFollowBars;
      if(F < 1) F = 1;
      int T = cfg.BOTrapLookback;
      if(T < 5) T = 5;
      // active breakout: newest event first
      int k = -1;
      double refPx = 0;
      bool isSwing = false;
      int dir = 0;
      for(int kk = b; kk <= b + F && kk < count; kk++)
        {
         double rp = 0;
         bool sw2 = false;
         int d = EventAt(rates, count, kk, tol, sw, cfg, rp, sw2);
         if(d != 0) { k = kk; refPx = rp; isSwing = sw2; dir = d; break; }
        }
      if(k < 0) return s;
      s.found = true; s.dir = dir; s.boBar = k;
      s.refPrice = refPx; s.refIsSwing = isSwing;
      // outcome: FAILED precedence, then FOLLOW, else PENDING
      int failBar = -1;
      if(FailedSince(rates, count, k, b, refPx, dir, tol, failBar))
        {
         s.outcome = BO_FAILED; s.decideBar = failBar;
        }
      else
        {
         int folBar = -1;
         for(int j = b; j < k && j < count; j++)
           {
            if(j < 1) continue;
            if(dir > 0 && rates[j].close > refPx + tol) { folBar = j; break; }
            if(dir < 0 && rates[j].close < refPx - tol) { folBar = j; break; }
           }
         if(folBar >= 0) { s.outcome = BO_FOLLOW_THROUGH; s.decideBar = folBar; }
         else s.outcome = BO_PENDING;
        }
      // second-leg trap: older same-dir event m failing within [k .. m-1]
      for(int m = k + 1; m <= k + T && m < count; m++)
        {
         double rp = 0;
         bool sw2 = false;
         int d = EventAt(rates, count, m, tol, sw, cfg, rp, sw2);
         if(d != dir) continue;
         int fb = -1;
         if(FailedSince(rates, count, m, k, rp, dir, tol, fb))
           { s.trapArmed = true; break; }
        }
      return s;
     }

   static string OutcomeName(ENUM_BO_OUTCOME o)
     {
      switch(o)
        {
         case BO_PENDING:       return "PENDING";
         case BO_FOLLOW_THROUGH:return "FOLLOW";
         case BO_FAILED:        return "FAILED";
         default:               return "NONE";
        }
     }

   // Evidence-generated one-line summary (no generic text).
   static string Describe(const BreakoutSignal &s)
     {
      if(!s.found) return "BO none";
      return StringFormat("BO %s #%d>%.5f(%s) %s%s", (s.dir > 0 ? "bull" : "bear"),
         s.boBar, s.refPrice, (s.refIsSwing ? "SWING" : "NBAR"),
         OutcomeName(s.outcome), (s.trapArmed ? " [TRAP]" : ""));
     }
  };

#endif
