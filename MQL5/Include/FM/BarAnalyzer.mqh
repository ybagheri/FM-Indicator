//+------------------------------------------------------------------+
//| BarAnalyzer.mqh : CBarAnalyzer — pure per-closed-bar PA features   |
//| Phase 1 of bar-by-bar engine (see docs/BAR_BY_BAR_ENGINE.md).      |
//| Stateless, no future bars, no alerts/objects. Closed bars only.    |
//+------------------------------------------------------------------+
#ifndef FM_BARANALYZER_MQH
#define FM_BARANALYZER_MQH
#include "Config.mqh"

struct BarFeatures
  {
   bool              valid;          // false for shift 0 / out of range
   int               dir;            // +1 bull, -1 bear, 0 tick-exact flat
   double            range;
   double            body;
   double            bodyRatio;      // body/range
   double            closePos;       // (close-low)/range
   double            upperTail;
   double            lowerTail;
   double            upperRatio;
   double            lowerRatio;
   bool              isDoji;
   bool              isBig;
   bool              isSmall;
   bool              isStrongBull;
   bool              isStrongBear;
   bool              isInside;
   bool              isOutside;
   double            overlap;        // 0..1 vs prior closed bar
   bool              gapUp;
   bool              gapDown;
   int               consecutive;    // signed run toward dir (doji resets)
   int               iiCount;        // trailing inside-bar run ending here
   int               pressureBull;   // strong-bull count in lookback window
   int               pressureBear;
   bool              barbwire;
   bool              tightening;
   string            label;          // STRONG_BULL/STRONG_BEAR/BIG/DOJI/INSIDE/...
  };

class CBarAnalyzer
  {
public:
   static double BarRange(const MqlRates &r)
     {
      double rg = r.high - r.low;
      return (rg <= 0 ? _Point : rg);
     }

   static double BarBody(const MqlRates &r) { return MathAbs(r.close - r.open); }

   // Pairwise body overlap ratio vs prior closed bar (MT5 shift: prior = b+1).
   static double PairOverlap(const MqlRates &a, const MqlRates &b)
     {
      double ra = a.high - a.low, rb = b.high - b.low;
      double m = MathMin(ra, rb);
      if(m <= 0) return 0.0;
      double top = MathMin(MathMax(a.close, a.open), MathMax(b.close, b.open));
      double bot = MathMax(MathMin(a.close, a.open), MathMin(b.close, b.open));
      double ov = top - bot;
      if(ov <= 0) return 0.0;
      return ov / m;
     }

   static bool IsStrongClose(const MqlRates &r, double rg, int dir, const CFMConfig &cfg)
     {
      if(dir > 0) return ((r.close - r.low) / rg >= cfg.StrongClosePct);
      if(dir < 0) return ((r.high - r.close) / rg >= cfg.StrongClosePct);
      return false;
     }

   static int RunCount(const MqlRates &rates[], int count, int b, const CFMConfig &cfg)
     {
      // Signed consecutive run ending at b; dojis reset (Brooks: pause, not flip).
      if(b < 1 || b >= count) return 0;
      int d0 = BarDir(rates[b], cfg);
      if(d0 == 0) return 0;
      int n = 0;
      for(int i = b; i >= 1 && i < count; i--)
        {
         int d = BarDir(rates[i], cfg);
         if(d != d0) break;
         n++;
         if(n >= 20) break;
        }
      return (d0 > 0 ? n : -n);
     }

   static int BarDir(const MqlRates &r, const CFMConfig &cfg)
     {
      if(r.close > r.open) return +1;
      if(r.close < r.open) return -1;
      return 0; // tick-exact flat only; near-zero bodies keep sign → doji pause
     }

   static int InsideRun(const MqlRates &rates[], int count, int b)
     {
      if(b < 1 || b + 1 >= count) return 0;
      int n = 0;
      for(int i = b; i >= 1 && i + 1 < count; i--)
        {
         bool ins = (rates[i].high <= rates[i+1].high && rates[i].low >= rates[i+1].low);
         if(!ins) break;
         n++;
        }
      return n;
     }

   static void WindowStats(const MqlRates &rates[], int count, int b, double atr,
                           const CFMConfig &cfg, int &pBull, int &pBear,
                           bool &barbwire, bool &tightening)
     {
      pBull = 0; pBear = 0; barbwire = false; tightening = false;
      if(b < 1 || b >= count) return;
      int L = cfg.PressureLookback;
      if(L < 1) L = 1;
      for(int i = b; i > b - L && i >= 1 && i < count; i--)
        {
         double rg = BarRange(rates[i]);
         int d = BarDir(rates[i], cfg);
         double cp = (rates[i].close - rates[i].low) / rg;
         double br = BarBody(rates[i]) / rg;
         if(d > 0 && cp >= cfg.StrongClosePct && br >= cfg.MinBodyRatio) pBull++;
         if(d < 0 && (1.0 - cp) >= cfg.StrongClosePct && br >= cfg.MinBodyRatio) pBear++;
        }
      // barbwire: overlapping pairs + a doji inside the window
      int W = cfg.BarbwireBars;
      if(W < 3) W = 3;
      int ovn = 0; bool anyDoji = false;
      for(int i = b; i > b - W && i >= 1 && i + 1 < count; i--)
        {
         if(PairOverlap(rates[i], rates[i+1]) >= cfg.OverlapRatio) ovn++;
         double rg = BarRange(rates[i]);
         if(BarBody(rates[i]) / rg < cfg.DojiMaxBodyRatio) anyDoji = true;
        }
      // include oldest window bar for doji scan
      int tail = b - W;
      if(tail >= 1 && tail < count)
        {
         double rg = BarRange(rates[tail]);
         if(BarBody(rates[tail]) / rg < cfg.DojiMaxBodyRatio) anyDoji = true;
        }
      barbwire = (ovn >= cfg.BarbwireMinOverlap && anyDoji);
      // tightening: current range below median of previous 4 closed bars
      if(b + 4 < count)
        {
         double w[4];
         for(int k = 0; k < 4; k++) w[k] = rates[b+1+k].high - rates[b+1+k].low;
         // median of 4 = mean of middle two after sort
         for(int x = 0; x < 3; x++)
            for(int y = x + 1; y < 4; y++)
               if(w[y] < w[x]) { double t = w[x]; w[x] = w[y]; w[y] = t; }
         double med = (w[1] + w[2]) * 0.5;
         double cur = rates[b].high - rates[b].low;
         tightening = (cur < med);
        }
     }

   // Main entry: analyze closed-bar shift b (b>=1). b==0 → valid=false.
   static BarFeatures Analyze(const MqlRates &rates[], int count, int b,
                              double atr, const CFMConfig &cfg)
     {
      BarFeatures f;
      f.valid = false; f.dir = 0; f.range = 0; f.body = 0; f.bodyRatio = 0;
      f.closePos = 0.5; f.upperTail = 0; f.lowerTail = 0; f.upperRatio = 0;
      f.lowerRatio = 0; f.isDoji = false; f.isBig = false; f.isSmall = false;
      f.isStrongBull = false; f.isStrongBear = false; f.isInside = false;
      f.isOutside = false; f.overlap = 0; f.gapUp = false; f.gapDown = false;
      f.consecutive = 0; f.iiCount = 0; f.pressureBull = 0; f.pressureBear = 0;
      f.barbwire = false; f.tightening = false; f.label = "NONE";
      if(b < 1 || b >= count) return f;
      MqlRates r = rates[b];
      double rg = BarRange(r);
      double body = BarBody(r);
      double br = body / rg;
      double cp = (r.close - r.low) / rg;
      int d = BarDir(r, cfg);
      double upT = r.high - MathMax(r.close, r.open);
      double loT = MathMin(r.close, r.open) - r.low;

      f.valid = true;
      f.dir = d; f.range = rg; f.body = body; f.bodyRatio = br; f.closePos = cp;
      f.upperTail = upT; f.lowerTail = loT; f.upperRatio = upT / rg; f.lowerRatio = loT / rg;
      f.isDoji = (br < cfg.DojiMaxBodyRatio);
      if(atr > 0)
        {
         f.isBig = (rg >= cfg.BigBarATRMult * atr);
         f.isSmall = (rg < cfg.SmallBarATRMult * atr);
        }
      f.isStrongBull = (d > 0 && cp >= cfg.StrongClosePct && br >= cfg.MinBodyRatio);
      f.isStrongBear = (d < 0 && (1.0 - cp) >= cfg.StrongClosePct && br >= cfg.MinBodyRatio);
      if(b + 1 < count)
        {
         MqlRates p = rates[b+1];
         f.isInside = (r.high <= p.high && r.low >= p.low);
         f.isOutside = (r.high >= p.high && r.low <= p.low && (r.high > p.high || r.low < p.low));
         f.overlap = PairOverlap(r, p);
         f.gapUp = (r.low > p.high);
         f.gapDown = (r.high < p.low);
        }
      f.consecutive = RunCount(rates, count, b, cfg);
      // doji pauses the run (Brooks): a doji bar itself carries 0
      if(f.isDoji) f.consecutive = 0;
      f.iiCount = InsideRun(rates, count, b);
      WindowStats(rates, count, b, atr, cfg, f.pressureBull, f.pressureBear, f.barbwire, f.tightening);

      if(f.isStrongBull) f.label = "STRONG_BULL";
      else if(f.isStrongBear) f.label = "STRONG_BEAR";
      else if(f.iiCount >= 2) f.label = "II" + IntegerToString(f.iiCount);
      else if(f.isBig) f.label = "BIG";
      else if(f.isDoji) f.label = "DOJI";
      else if(f.isOutside) f.label = "OUTSIDE";
      else if(f.isInside) f.label = "INSIDE";
      else if(f.gapUp || f.gapDown) f.label = "GAP";
      else f.label = "BAR";
      return f;
     }

   // Evidence-generated one-line interpretation (no generic text).
   static string Describe(const BarFeatures &f, int shift)
     {
      if(!f.valid) return StringFormat("Bar #%d forming/invalid (no analysis)", shift);
      string d = (f.dir > 0 ? "Bull" : (f.dir < 0 ? "Bear" : "Flat"));
      string q = (f.isStrongBull || f.isStrongBear ? " Strong" : (f.isDoji ? " Doji" : ""));
      string sz = (f.isBig ? " Big" : (f.isSmall ? " Small" : ""));
      string pat = "";
      if(f.iiCount >= 2) pat += StringFormat(" ii%d", f.iiCount);
      else if(f.isOutside) pat += " Outside";
      else if(f.isInside) pat += " Inside";
      if(f.gapUp) pat += " GapUp";
      if(f.gapDown) pat += " GapDown";
      string cp = "mid";
      if(f.closePos >= 0.7) cp = "near-high";
      else if(f.closePos <= 0.3) cp = "near-low";
      string res = StringFormat("Bar #%d %s%s%s%s Close:%s Body:%.0f%% AdvWick:%.0f%%",
         shift, d, q, sz, pat, cp, f.bodyRatio * 100.0,
         (f.dir >= 0 ? f.upperRatio : f.lowerRatio) * 100.0);
      res += StringFormat(" Run:%d P(10):+%d/-%d%s%s", f.consecutive,
         f.pressureBull, f.pressureBear,
         (f.barbwire ? " Barbwire" : ""), (f.tightening ? " Tight" : ""));
      return res;
     }
  };

#endif
