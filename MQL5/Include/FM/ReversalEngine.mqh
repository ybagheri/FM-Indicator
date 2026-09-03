//+------------------------------------------------------------------+
//| ReversalEngine.mqh : exhaustion report + pullback legs + MTR proxy |
//| Phase 5 of bar-by-bar engine (see docs/REVERSAL_ENGINE.md).        |
//| Stateless, closed bars only, read-only (DEBUG log; never gates FM).|
//| MT5 shifts: 0 = forming, >=1 closed, older = larger shift.         |
//+------------------------------------------------------------------+
#ifndef FM_REVERSALENGINE_MQH
#define FM_REVERSALENGINE_MQH
#include "Config.mqh"
#include "Defs.mqh"
#include "Confirmation.mqh"
#include "BreakoutEngine.mqh"

struct ExhaustionReport
  {
   bool              climax;
   bool              stall;
   int               pushes;       // raw PushCount (cap 6, MQL5 convention)
   bool              pushOK;
   bool              wedge;
   bool              overshoot;
   int               breadth;      // 0..5
  };

struct LegCount
  {
   bool              valid;
   int               legs;         // 0..3 (capped successive countertrend lows/highs)
   bool              deep;         // depth > 0.6
   double            depth;        // -1 when origin unknown
   int               anchorBar;    // MT5 shift of trend extreme
   int               extremeBar;   // MT5 shift of deepest countertrend extreme
  };

struct ReversalSignal
  {
   bool              found;        // verdict >= MINOR
   ENUM_REV_VERDICT  verdict;
   int               dir;          // reversal direction ±1
   bool              emaBreak;
   bool              retest;
   bool              boFollow;
   bool              pressureOK;
   int               pressN;
   int               score;        // 25 per leg, 0..100
   int               crossBar;     // MT5 shift of EMA cross (-1 when none)
  };

class CExhaustionAnalyzer
  {
public:
   // Backward push run ENDING at b toward older bars (larger shifts), cap 6.
   // Same close/high-low predicates as CConfirmation::PushCount, but the run
   // never extends newer-ward (v1 loop does for b>1 — preserved there).
   static int PushBack(const MqlRates &rates[], int count, int b, int dir)
     {
      if(b < 1 || b >= count) return 0;
      int n = 0;
      for(int i = b; i + 1 < count; i++)
        {
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

   // Wedge ending at b: pushes ≥ 3 with shrinking ranges toward older bars
   // (each ≤ prior ×1.05) or ≥4 pushes regardless. Needs 2 older bars.
   // Same predicates as CConfirmation::IsWedge WITHOUT its b<3 newest-bar
   // exclusion (v1 quirk — preserved in CConfirmation for compat).
   static bool WedgeAt(const MqlRates &rates[], int count, int b, int dir)
     {
      if(b < 1 || b + 2 >= count) return false;
      int n = PushBack(rates, count, b, dir);
      if(n < 3) return false;
      bool shrink = true;
      for(int i = b; i < b + n - 1 && i + 1 < count; i++)
        {
         double r0 = CConfirmation::Range(rates[i]);
         double r1 = CConfirmation::Range(rates[i+1]);
         if(r0 > r1 * 1.05) { shrink = false; break; }
        }
      return (shrink || n >= 4);
     }

   // Named components of SPEC §8 (backward predicates per §0 record, so
   // breadth>0 whenever ExhaustionAnyCfg(...) is true — tested in mirror).
   static ExhaustionReport Report(const MqlRates &rates[], int count, int b,
                                  int dir, double atr, const CFMConfig &cfg)
     {
      ExhaustionReport r;
      r.climax = false; r.stall = false; r.pushes = 0; r.pushOK = false;
      r.wedge = false; r.overshoot = false; r.breadth = 0;
      if(b < 1 || b >= count || atr <= 0) return r;
      MqlRates rb = rates[b];
      double rg = CConfirmation::Range(rb);
      r.climax = (rg >= 2.0 * atr);
      double upW = rb.high - MathMax(rb.close, rb.open);
      double loW = MathMin(rb.close, rb.open) - rb.low;
      r.stall = (rg < 0.5 * atr + _Point && upW > 0.4 * rg && loW > 0.4 * rg);
      r.pushes = PushBack(rates, count, b, dir);
      int mp = cfg.MinPushes;
      if(mp < 2) mp = 2;
      r.pushOK = (r.pushes >= mp);
      r.wedge = (cfg.UseWedgeExhaustion && WedgeAt(rates, count, b, dir));
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
         if(dir > 0)
            r.overshoot = (rb.high - MathMax(sma, hh - (hh - ll) * 0.2) > 0.3 * atr);
         else
            r.overshoot = (MathMin(sma, ll + (hh - ll) * 0.2) - rb.low > 0.3 * atr);
        }
      r.breadth = (r.climax ? 1 : 0) + (r.stall ? 1 : 0) + (r.pushOK ? 1 : 0)
                + (r.wedge ? 1 : 0) + (r.overshoot ? 1 : 0);
      return r;
     }

   static string Describe(const ExhaustionReport &r, int dir)
     {
      if(r.breadth <= 0) return "EXH none";
      string s = StringFormat("EXH %s n=%d", (dir > 0 ? "bull" : "bear"), r.breadth);
      if(r.climax) s += " climax";
      if(r.stall) s += " stall";
      if(r.pushOK) s += StringFormat(" pushes(%d)", r.pushes);
      if(r.wedge) s += " wedge";
      if(r.overshoot) s += " overshoot";
      return s;
     }
  };

class CLegCounter
  {
public:
   // Bull pullback legs: successive lower swing lows after the most recent
   // swing high (capped at 3). Confirmed swings only.
   static LegCount CountBull(const SwingPoint &sw[])
     {
      LegCount L;
      L.valid = false; L.legs = 0; L.deep = false; L.depth = -1;
      L.anchorBar = -1; L.extremeBar = -1;
      int n = ArraySize(sw);
      int a = -1;
      for(int i = n - 1; i >= 0; i--)
         if(sw[i].valid && sw[i].dir == +1) { a = i; break; }
      if(a < 0) return L;
      int o = -1;
      for(int i = a - 1; i >= 0; i--)
         if(sw[i].valid && sw[i].dir == -1) { o = i; break; }
      L.valid = true;
      L.anchorBar = sw[a].bar;
      double minLow = 0;
      bool first = true;
      int legs = 0;
      for(int i = a + 1; i < n; i++)
        {
         if(!sw[i].valid || sw[i].dir != -1) continue;
         if(first || sw[i].price < minLow)
           {
            minLow = sw[i].price;
            L.extremeBar = sw[i].bar;
            first = false;
            if(legs < 3) legs++;
           }
        }
      L.legs = (first ? 0 : legs);
      if(!first && o >= 0 && (sw[a].price - sw[o].price) > 0)
        {
         L.depth = (sw[a].price - minLow) / (sw[a].price - sw[o].price);
         L.deep = (L.depth > 0.6);
        }
      return L;
     }

   // Bear mirror: successive higher swing highs after the recent swing low.
   static LegCount CountBear(const SwingPoint &sw[])
     {
      LegCount L;
      L.valid = false; L.legs = 0; L.deep = false; L.depth = -1;
      L.anchorBar = -1; L.extremeBar = -1;
      int n = ArraySize(sw);
      int a = -1;
      for(int i = n - 1; i >= 0; i--)
         if(sw[i].valid && sw[i].dir == -1) { a = i; break; }
      if(a < 0) return L;
      int o = -1;
      for(int i = a - 1; i >= 0; i--)
         if(sw[i].valid && sw[i].dir == +1) { o = i; break; }
      L.valid = true;
      L.anchorBar = sw[a].bar;
      double maxHigh = 0;
      bool first = true;
      int legs = 0;
      for(int i = a + 1; i < n; i++)
        {
         if(!sw[i].valid || sw[i].dir != +1) continue;
         if(first || sw[i].price > maxHigh)
           {
            maxHigh = sw[i].price;
            L.extremeBar = sw[i].bar;
            first = false;
            if(legs < 3) legs++;
           }
        }
      L.legs = (first ? 0 : legs);
      if(!first && o >= 0 && (sw[o].price - sw[a].price) > 0)
        {
         L.depth = (maxHigh - sw[a].price) / (sw[o].price - sw[a].price);
         L.deep = (L.depth > 0.6);
        }
      return L;
     }

   static string Describe(const LegCount &L, int dir)
     {
      if(!L.valid || L.legs <= 0) return "LEGS none";
      return StringFormat("LEGS %s n=%d depth=%.2f%s", (dir > 0 ? "bull-PB" : "bear-PB"),
         L.legs, L.depth, (L.deep ? " DEEP" : ""));
     }
  };

class CMajorReversal
  {
public:
   // Oldest-seed EMA20 values for shifts [b .. b+K-1] (tail[0] = EMA at b).
   // Same convention as TrendGap's EMA20.
   static void EMA20Tail(const MqlRates &rates[], int count, int b, int K,
                         double &tail[])
     {
      ArrayResize(tail, K);
      for(int i = 0; i < K; i++) tail[i] = 0;
      if(b < 1 || b >= count) return;
      double k = 2.0 / 21.0;
      double e = rates[count-1].close;
      for(int i = count - 2; i >= b; i--)
        {
         e = rates[i].close * k + e * (1.0 - k);
         int slot = i - b;
         if(slot >= 0 && slot < K) tail[slot] = e;
        }
     }

   static int SideOf(double close, double ema, double tol)
     {
      if(close > ema + tol) return +1;
      if(close < ema - tol) return -1;
      return 0;
     }

   // MTR proxy at closed bar b toward revDir (see spec §4).
   static ReversalSignal Analyze(const MqlRates &rates[], int count, int b,
                                 double atr, const SwingPoint &sw[],
                                 const CFMConfig &cfg, int revDir)
     {
      ReversalSignal s;
      s.found = false; s.verdict = REV_NONE; s.dir = revDir;
      s.emaBreak = false; s.retest = false; s.boFollow = false;
      s.pressureOK = false; s.pressN = 0; s.score = 0; s.crossBar = -1;
      if(!cfg.EnableReversal) return s;
      if(b < 1 || b >= count || atr <= 0) return s;
      if(revDir != +1 && revDir != -1) return s;
      int K = cfg.RevLookback;
      if(K < 5) K = 5;
      if(K > 50) K = 50;
      if(count - b < K + 2) return s;
      double tol = cfg.RevRetestTolATRMult * atr;
      double tail[];
      EMA20Tail(rates, count, b, K, tail);
      if(SideOf(rates[b].close, tail[0], tol) != revDir) return s;
      s.emaBreak = true;
      for(int j = b + 1; j <= b + K - 1 && j < count; j++)
        {
         if(SideOf(rates[j].close, tail[j-b], tol) == -revDir)
           { s.crossBar = j; break; }
        }
      if(s.crossBar < 0) { s.emaBreak = false; return s; }
      // retest: dip to EMA after the cross, holding (no close-through)
      for(int j = b; j < s.crossBar && j < count; j++)
        {
         if(j < 1) continue;
         double e = tail[j-b];
         if(revDir > 0 && rates[j].low <= e + tol && rates[j].close > e - tol)
           { s.retest = true; break; }
         if(revDir < 0 && rates[j].high >= e - tol && rates[j].close < e + tol)
           { s.retest = true; break; }
        }
      BreakoutSignal bo = CBreakoutEngine::Analyze(rates, count, b, atr, sw, cfg);
      s.boFollow = (bo.found && bo.dir == revDir && bo.outcome == BO_FOLLOW_THROUGH);
      s.pressN = CExhaustionAnalyzer::PushBack(rates, count, b, revDir);
      int mp = cfg.RevMinPressure;
      if(mp < 3) mp = 3;
      if(mp > 10) mp = 10;
      s.pressureOK = (s.pressN >= mp);
      s.score = 25 * ((s.emaBreak ? 1 : 0) + (s.retest ? 1 : 0)
              + (s.boFollow ? 1 : 0) + (s.pressureOK ? 1 : 0));
      int n = (s.emaBreak ? 1 : 0) + (s.retest ? 1 : 0)
            + (s.boFollow ? 1 : 0) + (s.pressureOK ? 1 : 0);
      s.verdict = (n >= 4 ? REV_MAJOR : (n >= 1 ? REV_MINOR : REV_NONE));
      s.found = (s.verdict != REV_NONE);
      return s;
     }

   static string VerdictName(ENUM_REV_VERDICT v)
     {
      switch(v)
        {
         case REV_MAJOR: return "MAJOR";
         case REV_MINOR: return "MINOR";
         default:        return "NONE";
        }
     }

   static string Describe(const ReversalSignal &s)
     {
      if(!s.found) return "MTR none";
      return StringFormat("MTR %s %s score=%d EMA%s RET%s BO%s P%d(%s)", (s.dir > 0 ? "bull" : "bear"),
         VerdictName(s.verdict), s.score,
         (s.emaBreak ? "X" : "-"), (s.retest ? "OK" : "-"),
         (s.boFollow ? "FLW" : "-"), s.pressN, (s.pressureOK ? "OK" : "-"));
     }
  };

#endif
