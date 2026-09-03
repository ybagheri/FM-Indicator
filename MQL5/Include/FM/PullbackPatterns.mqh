//+------------------------------------------------------------------+
//| PullbackPatterns.mqh : CPullbackPatterns — H1/H2/L1/L2 + doubles   |
//| Phase 2 of bar-by-bar engine (see docs/PULLBACK_PATTERNS.md).      |
//| Stateless, closed bars only, read-only (DEBUG log; never gates FM).|
//| MT5 shifts: 0 = forming, >=1 closed, older = larger shift.         |
//+------------------------------------------------------------------+
#ifndef FM_PULLBACKPATTERNS_MQH
#define FM_PULLBACKPATTERNS_MQH
#include "Config.mqh"
#include "Defs.mqh"

struct PullbackSignal
  {
   bool              found;        // H1/H2 (bull) or L1/L2 (bear) pattern present
   int               legs;         // 1 = H1/L1 only, 2 = H2/L2
   int               signalBar;    // MT5 shift of entry bar (H1 or H2 / L1 or L2)
   int               anchorBar;    // MT5 shift of first-leg bar (H1 / L1)
   double            entry;        // H[signal]+_Point (bull) / L[signal]-_Point (bear)
   double            stop;         // pullback low (bull) / pullback high (bear)
  };

struct DoubleSignal
  {
   bool              found;
   int               dir;          // -1 double-top (bearish), +1 double-bottom (bullish)
   int               bar1;         // MT5 shift, older extreme
   int               bar2;         // MT5 shift, newer extreme
   double            price1;
   double            price2;
   bool              micro;        // false = confirmed swings, true = raw bar extremes
  };

class CPullbackPatterns
  {
public:
   // Raw EMA20−EMA50 gap on closes ending at closed bar b (price units).
   // Oldest-seed EMA (seed = oldest close, forward to b); <50 closes → 0.
   // Shared with the Phase-3 market-state engine (single EMA convention).
   static double TrendGap(const MqlRates &rates[], int count, int b)
     {
      if(b < 1 || b >= count) return 0.0;
      if(count - b < 50) return 0.0;
      double k20 = 2.0 / 21.0, k50 = 2.0 / 51.0;
      double e20 = rates[count-1].close, e50 = e20;
      for(int i = count - 2; i >= b; i--)
        {
         e20 = rates[i].close * k20 + e20 * (1.0 - k20);
         e50 = rates[i].close * k50 + e50 * (1.0 - k50);
        }
      return (e20 - e50);
     }

   // Trend gate: EMA20/EMA50 gap on closes ending at closed bar b.
   // Needs 50+ closed bars (count-b >= 50); atr<=0 → 0. See spec §2.
   static int TrendDir(const MqlRates &rates[], int count, int b, double atr,
                       const CFMConfig &cfg)
     {
      if(b < 1 || b >= count) return 0;
      if(atr <= 0) return 0;
      double gap = TrendGap(rates, count, b) / atr;
      if(gap > 0.4) return +1;
      if(gap < -0.4) return -1;
      return 0;
     }

   // Bull pullback: H1 = first break above prior high scanning oldest→newest;
   // H2 = first break after the second-leg low. Most advanced wins. Spec §3.
   // Disambiguation (spec: "exists j"): second-leg anchor = OLDEST bar newer
   // than H1 with L < lowAtH1; H2 = oldest break newer than that anchor.
   static PullbackSignal DetectBull(const MqlRates &rates[], int count, int b,
                                    double atr, const CFMConfig &cfg)
     {
      PullbackSignal s;
      s.found = false; s.legs = 0; s.signalBar = -1; s.anchorBar = -1;
      s.entry = 0; s.stop = 0;
      if(!cfg.EnablePullbackPatterns) return s;
      if(b < 1 || b >= count) return s;
      if(atr <= 0) return s;
      if(TrendDir(rates, count, b, atr, cfg) != +1) return s;
      int w0 = b + cfg.MaxPullbackBars;
      if(w0 >= count) w0 = count - 1;
      if(w0 - 1 < b) return s;
      double mxH = rates[b].high, mnL = rates[b].low;
      for(int i = b + 1; i <= w0; i++)
        {
         if(rates[i].high > mxH) mxH = rates[i].high;
         if(rates[i].low < mnL) mnL = rates[i].low;
        }
      if(mxH - mnL < cfg.MinPullbackDepthATRMult * atr) return s;
      int h1 = -1;
      for(int i = w0 - 1; i >= b; i--)
        {
         if(rates[i].high > rates[i+1].high) { h1 = i; break; }
        }
      if(h1 < 0) return s;
      double lowAt = rates[h1].low;
      for(int k = h1 + 1; k <= w0; k++)
        {
         if(rates[k].low < lowAt) lowAt = rates[k].low;
        }
      int jLow = -1;
      for(int j = h1 - 1; j >= b; j--)
        {
         if(rates[j].low < lowAt) { jLow = j; break; }
        }
      if(jLow < 0)
        {
         s.found = true; s.legs = 1; s.signalBar = h1; s.anchorBar = h1;
         s.entry = rates[h1].high + _Point; s.stop = mnL;
         return s;
        }
      int h2 = -1;
      for(int k = jLow - 1; k >= b; k--)
        {
         if(rates[k].high > rates[k+1].high) { h2 = k; break; }
        }
      if(h2 < 0)
        {
         s.found = true; s.legs = 1; s.signalBar = h1; s.anchorBar = h1;
         s.entry = rates[h1].high + _Point; s.stop = mnL;
         return s;
        }
      s.found = true; s.legs = 2; s.signalBar = h2; s.anchorBar = h1;
      s.entry = rates[h2].high + _Point; s.stop = mnL;
      return s;
     }

   // Bear mirror: L1 = first break below prior low; L2 after second-leg high.
   static PullbackSignal DetectBear(const MqlRates &rates[], int count, int b,
                                    double atr, const CFMConfig &cfg)
     {
      PullbackSignal s;
      s.found = false; s.legs = 0; s.signalBar = -1; s.anchorBar = -1;
      s.entry = 0; s.stop = 0;
      if(!cfg.EnablePullbackPatterns) return s;
      if(b < 1 || b >= count) return s;
      if(atr <= 0) return s;
      if(TrendDir(rates, count, b, atr, cfg) != -1) return s;
      int w0 = b + cfg.MaxPullbackBars;
      if(w0 >= count) w0 = count - 1;
      if(w0 - 1 < b) return s;
      double mxH = rates[b].high, mnL = rates[b].low;
      for(int i = b + 1; i <= w0; i++)
        {
         if(rates[i].high > mxH) mxH = rates[i].high;
         if(rates[i].low < mnL) mnL = rates[i].low;
        }
      if(mxH - mnL < cfg.MinPullbackDepthATRMult * atr) return s;
      int l1 = -1;
      for(int i = w0 - 1; i >= b; i--)
        {
         if(rates[i].low < rates[i+1].low) { l1 = i; break; }
        }
      if(l1 < 0) return s;
      double highAt = rates[l1].high;
      for(int k = l1 + 1; k <= w0; k++)
        {
         if(rates[k].high > highAt) highAt = rates[k].high;
        }
      int jHigh = -1;
      for(int j = l1 - 1; j >= b; j--)
        {
         if(rates[j].high > highAt) { jHigh = j; break; }
        }
      if(jHigh < 0)
        {
         s.found = true; s.legs = 1; s.signalBar = l1; s.anchorBar = l1;
         s.entry = rates[l1].low - _Point; s.stop = mxH;
         return s;
        }
      int l2 = -1;
      for(int k = jHigh - 1; k >= b; k--)
        {
         if(rates[k].low < rates[k+1].low) { l2 = k; break; }
        }
      if(l2 < 0)
        {
         s.found = true; s.legs = 1; s.signalBar = l1; s.anchorBar = l1;
         s.entry = rates[l1].low - _Point; s.stop = mxH;
         return s;
        }
      s.found = true; s.legs = 2; s.signalBar = l2; s.anchorBar = l1;
      s.entry = rates[l2].low - _Point; s.stop = mxH;
      return s;
     }

   // Double top on confirmed swings (chrono oldest→newest, same sw[] as FM).
   // Most-recent pair wins; no signal bar required at this layer. Spec §4.
   static DoubleSignal FindDoubleTop(const SwingPoint &sw[], double atr,
                                     const CFMConfig &cfg)
     {
      DoubleSignal d;
      d.found = false; d.dir = -1; d.bar1 = -1; d.bar2 = -1;
      d.price1 = 0; d.price2 = 0; d.micro = false;
      if(!cfg.EnablePullbackPatterns) return d;
      if(atr <= 0) return d;
      int n = ArraySize(sw);
      double tol = cfg.DoubleTopTolATRMult * atr;
      double need = cfg.MinDoubleTroughATRMult * atr;
      for(int j = n - 1; j >= 0; j--)
        {
         if(!sw[j].valid || sw[j].dir != +1) continue;
         for(int i = j - 1; i >= 0; i--)
           {
            if(!sw[i].valid || sw[i].dir != +1) continue;
            if(MathAbs(sw[j].price - sw[i].price) > tol) continue;
            int apart = sw[i].bar - sw[j].bar;
            if(apart < 0) apart = -apart;
            if(apart > cfg.MaxDoubleBars) continue;
            double base = MathMin(sw[i].price, sw[j].price);
            bool ok = false;
            for(int k = i + 1; k < j; k++)
              {
               if(sw[k].valid && sw[k].dir == -1 && base - sw[k].price >= need)
                 { ok = true; break; }
              }
            if(!ok) continue;
            d.found = true; d.bar1 = sw[i].bar; d.bar2 = sw[j].bar;
            d.price1 = sw[i].price; d.price2 = sw[j].price;
            return d;
           }
        }
      return d;
     }

   // Double bottom mirror (swing lows + intervening high). Spec §4.
   static DoubleSignal FindDoubleBottom(const SwingPoint &sw[], double atr,
                                        const CFMConfig &cfg)
     {
      DoubleSignal d;
      d.found = false; d.dir = +1; d.bar1 = -1; d.bar2 = -1;
      d.price1 = 0; d.price2 = 0; d.micro = false;
      if(!cfg.EnablePullbackPatterns) return d;
      if(atr <= 0) return d;
      int n = ArraySize(sw);
      double tol = cfg.DoubleTopTolATRMult * atr;
      double need = cfg.MinDoubleTroughATRMult * atr;
      for(int j = n - 1; j >= 0; j--)
        {
         if(!sw[j].valid || sw[j].dir != -1) continue;
         for(int i = j - 1; i >= 0; i--)
           {
            if(!sw[i].valid || sw[i].dir != -1) continue;
            if(MathAbs(sw[j].price - sw[i].price) > tol) continue;
            int apart = sw[i].bar - sw[j].bar;
            if(apart < 0) apart = -apart;
            if(apart > cfg.MaxDoubleBars) continue;
            double base = MathMax(sw[i].price, sw[j].price);
            bool ok = false;
            for(int k = i + 1; k < j; k++)
              {
               if(sw[k].valid && sw[k].dir == +1 && sw[k].price - base >= need)
                 { ok = true; break; }
              }
            if(!ok) continue;
            d.found = true; d.bar1 = sw[i].bar; d.bar2 = sw[j].bar;
            d.price1 = sw[i].price; d.price2 = sw[j].price;
            return d;
           }
        }
      return d;
     }

   // Micro double top on raw bar highs over MicroDoubleBars newest closed
   // bars; trough requirement halved for the short window. Spec §5.
   static DoubleSignal MicroDoubleTop(const MqlRates &rates[], int count, int b,
                                      double atr, const CFMConfig &cfg)
     {
      DoubleSignal d;
      d.found = false; d.dir = -1; d.bar1 = -1; d.bar2 = -1;
      d.price1 = 0; d.price2 = 0; d.micro = true;
      if(!cfg.EnablePullbackPatterns) return d;
      if(b < 1 || b >= count) return d;
      if(atr <= 0) return d;
      int w = cfg.MicroDoubleBars;
      if(w < 3) w = 3;
      int wEnd = b + w - 1;
      if(wEnd >= count) wEnd = count - 1;
      if(wEnd - b + 1 < 3) return d;
      double tol = cfg.DoubleTopTolATRMult * atr;
      double need = cfg.MinDoubleTroughATRMult * atr * 0.5;
      for(int j = b; j <= wEnd; j++)
        {
         for(int i = j + 1; i <= wEnd; i++)
           {
            if(MathAbs(rates[j].high - rates[i].high) > tol) continue;
            if(i - j > cfg.MaxDoubleBars) continue;
            double base = MathMin(rates[i].high, rates[j].high);
            bool ok = false;
            for(int k = j + 1; k < i; k++)
              {
               if(base - rates[k].low >= need) { ok = true; break; }
              }
            if(!ok) continue;
            d.found = true; d.bar1 = i; d.bar2 = j;
            d.price1 = rates[i].high; d.price2 = rates[j].high;
            return d;
           }
        }
      return d;
     }

   // Micro double bottom mirror on raw bar lows. Spec §5.
   static DoubleSignal MicroDoubleBottom(const MqlRates &rates[], int count, int b,
                                         double atr, const CFMConfig &cfg)
     {
      DoubleSignal d;
      d.found = false; d.dir = +1; d.bar1 = -1; d.bar2 = -1;
      d.price1 = 0; d.price2 = 0; d.micro = true;
      if(!cfg.EnablePullbackPatterns) return d;
      if(b < 1 || b >= count) return d;
      if(atr <= 0) return d;
      int w = cfg.MicroDoubleBars;
      if(w < 3) w = 3;
      int wEnd = b + w - 1;
      if(wEnd >= count) wEnd = count - 1;
      if(wEnd - b + 1 < 3) return d;
      double tol = cfg.DoubleTopTolATRMult * atr;
      double need = cfg.MinDoubleTroughATRMult * atr * 0.5;
      for(int j = b; j <= wEnd; j++)
        {
         for(int i = j + 1; i <= wEnd; i++)
           {
            if(MathAbs(rates[j].low - rates[i].low) > tol) continue;
            if(i - j > cfg.MaxDoubleBars) continue;
            double base = MathMax(rates[i].low, rates[j].low);
            bool ok = false;
            for(int k = j + 1; k < i; k++)
              {
               if(rates[k].high - base >= need) { ok = true; break; }
              }
            if(!ok) continue;
            d.found = true; d.bar1 = i; d.bar2 = j;
            d.price1 = rates[i].low; d.price2 = rates[j].low;
            return d;
           }
        }
      return d;
     }

   // Evidence-generated one-line summaries (no generic text).
   static string DescribePB(const PullbackSignal &s, bool bull)
     {
      if(!s.found) return "PB none";
      string tag = bull ? (s.legs == 2 ? "H2" : "H1") : (s.legs == 2 ? "L2" : "L1");
      return StringFormat("%s legs=%d sig#%d anchor#%d entry=%s stop=%s", tag, s.legs,
         s.signalBar, s.anchorBar, DoubleToString(s.entry, _Digits),
         DoubleToString(s.stop, _Digits));
     }

   static string DescribeDouble(const DoubleSignal &d)
     {
      if(!d.found) return "DBL none";
      string tag = (d.dir < 0 ? "DT" : "DB");
      if(d.micro) tag += "-micro";
      return StringFormat("%s #(%d,%.5f)->#(%d,%.5f)", tag,
         d.bar1, d.price1, d.bar2, d.price2);
     }
  };

#endif
