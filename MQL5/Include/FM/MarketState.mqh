//+------------------------------------------------------------------+
//| MarketState.mqh : CMarketState — TREND/CHANNEL/RANGE/BOM scores    |
//| Phase 3 of bar-by-bar engine (see docs/MARKET_STATE.md).           |
//| Stateless, closed bars only, read-only (DEBUG log; never gates FM).|
//| MT5 shifts: 0 = forming, >=1 closed, older = larger shift.         |
//+------------------------------------------------------------------+
#ifndef FM_MARKETSTATE_MQH
#define FM_MARKETSTATE_MQH
#include "Config.mqh"
#include "Defs.mqh"
#include "BarAnalyzer.mqh"
#include "PullbackPatterns.mqh"

struct MarketState
  {
   bool              valid;        // false = UNKNOWN (insufficient data / bad ATR)
   ENUM_MARKET_STATE state;        // argmax winner (TRANSITION on weak floor)
   int               pctBullTrend;
   int               pctBearTrend;
   int               pctBullChannel;
   int               pctBearChannel;
   int               pctRange;
   int               pctBreakout;
   double            trendScore;   // clamp11(gap/atr/2)
   double            rangeScore;   // (HH-LL)/atr over StateLookback
   double            chop;         // overlap-pair fraction over OverlapBars
   double            pressure;     // (pBull-pBear)/PressureLookback
   bool              tight;        // range < median of prior 4
   double            maxRaw;       // strongest raw (<1.0 → TRANSITION)
  };

class CMarketState
  {
public:
   static double Clamp01(double x) { return (x < 0 ? 0 : (x > 1 ? 1 : x)); }
   static double Clamp11(double x) { return (x < -1 ? -1 : (x > 1 ? 1 : x)); }

   // Main entry: score market state at closed-bar shift b (b>=1).
   static MarketState Analyze(const MqlRates &rates[], int count, int b,
                              double atr, const CFMConfig &cfg)
     {
      MarketState m;
      m.valid = false; m.state = MS_UNKNOWN;
      m.pctBullTrend = 0; m.pctBearTrend = 0; m.pctBullChannel = 0;
      m.pctBearChannel = 0; m.pctRange = 0; m.pctBreakout = 0;
      m.trendScore = 0; m.rangeScore = 0; m.chop = 0; m.pressure = 0;
      m.tight = false; m.maxRaw = 0;
      if(!cfg.EnableMarketState) return m;
      if(b < 1 || b >= count) return m;
      if(atr <= 0) return m;
      int L = cfg.StateLookback;
      if(L < 10) L = 10;
      int W = cfg.StateOverlapBars;
      if(W < 5) W = 5;
      int need = L + 1;
      if(W + 1 > need) need = W + 1;
      if(need < 6) need = 6;
      if(count - b < need) return m;

      // trendScore (Phase-2 EMA convention; 0 when <50 closes)
      m.trendScore = Clamp11(CPullbackPatterns::TrendGap(rates, count, b) / atr / 2.0);

      // rangeScore over last L closed bars: shifts [b .. b+L-1]
      int wEnd = b + L - 1;
      if(wEnd >= count) wEnd = count - 1;
      double hh = rates[b].high, ll = rates[b].low;
      for(int i = b + 1; i <= wEnd; i++)
        {
         if(rates[i].high > hh) hh = rates[i].high;
         if(rates[i].low < ll) ll = rates[i].low;
        }
      m.rangeScore = (hh - ll) / atr;

      // chop: overlap-pair fraction over last W bars: pairs j in [b .. b+W-2]
      int wE2 = b + W - 1;
      if(wE2 >= count) wE2 = count - 1;
      int pairs = 0, ov = 0;
      for(int j = b; j < wE2; j++)
        {
         if(CBarAnalyzer::PairOverlap(rates[j], rates[j+1]) >= cfg.OverlapRatio) ov++;
         pairs++;
        }
      if(pairs > 0) m.chop = (double)ov / (double)pairs;

      // pressure + tightening (same predicates as the bar engine)
      int pB = 0, pE = 0;
      bool bb = false, tight = false;
      CBarAnalyzer::WindowStats(rates, count, b, atr, cfg, pB, pE, bb, tight);
      m.tight = tight;
      int PL = cfg.PressureLookback;
      if(PL < 1) PL = 1;
      m.pressure = (double)(pB - pE) / (double)PL;

      double bullT = Clamp01(m.trendScore), bearT = Clamp01(-m.trendScore);
      double bullP = Clamp01(m.pressure), bearP = Clamp01(-m.pressure);
      double expand = Clamp01((m.rangeScore - 3.0) / 3.0);
      double compact = Clamp01((6.0 - m.rangeScore) / 4.0);
      double balance = 1.0 - MathAbs(m.pressure);

      double raws[6];
      raws[0] = bullT + bullP + expand;
      raws[1] = bearT + bearP + expand;
      raws[2] = bullT + m.chop + compact;
      raws[3] = bearT + m.chop + compact;
      raws[4] = compact + m.chop + balance;
      raws[5] = (m.tight ? 1.0 : 0.0) + compact + m.chop;
      double sum = 0;
      for(int i = 0; i < 6; i++) sum += raws[i];
      m.valid = true;
      if(sum <= 0)
        {
         m.state = MS_TRANSITION;
         return m;
        }
      // largest-remainder pcts (strict > scan → first-max-wins)
      int pct[6];
      double frac[6];
      int acc = 0;
      for(int i = 0; i < 6; i++)
        {
         double ex = raws[i] / sum * 100.0;
         pct[i] = (int)MathFloor(ex);
         frac[i] = ex - (double)pct[i];
         acc += pct[i];
        }
      for(int r = acc; r < 100; r++)
        {
         int bi = 0;
         for(int i = 1; i < 6; i++)
            if(frac[i] > frac[bi]) bi = i;
         pct[bi]++;
         frac[bi] = -1.0;
        }
      m.pctBullTrend = pct[0]; m.pctBearTrend = pct[1];
      m.pctBullChannel = pct[2]; m.pctBearChannel = pct[3];
      m.pctRange = pct[4]; m.pctBreakout = pct[5];
      // winner: strict > over fixed order (ties keep earliest)
      int bi = 0;
      for(int i = 1; i < 6; i++)
         if(raws[i] > raws[bi]) bi = i;
      m.maxRaw = raws[bi];
      if(m.maxRaw < 1.0)
         m.state = MS_TRANSITION;
      else
         m.state = (bi == 0 ? MS_BULL_TREND : (bi == 1 ? MS_BEAR_TREND :
                    (bi == 2 ? MS_BULL_CHANNEL : (bi == 3 ? MS_BEAR_CHANNEL :
                    (bi == 4 ? MS_TRADING_RANGE : MS_BREAKOUT_MODE)))));
      return m;
     }

   static string StateName(ENUM_MARKET_STATE s)
     {
      switch(s)
        {
         case MS_BULL_TREND:   return "BULL_TREND";
         case MS_BEAR_TREND:   return "BEAR_TREND";
         case MS_BULL_CHANNEL: return "BULL_CHANNEL";
         case MS_BEAR_CHANNEL: return "BEAR_CHANNEL";
         case MS_TRADING_RANGE:return "TRADING_RANGE";
         case MS_BREAKOUT_MODE:return "BREAKOUT_MODE";
         case MS_TRANSITION:   return "TRANSITION";
         default:              return "UNKNOWN";
        }
     }

   // Evidence-generated one-line summary (no generic text).
   static string Describe(const MarketState &m, int shift)
     {
      if(!m.valid) return StringFormat("MS #%d UNKNOWN (insufficient data)", shift);
      return StringFormat("MS #%d %s %d/%d/%d/%d/%d/%d T=%+.2f R=%.1f chop=%.2f P=%+.2f%s",
         shift, StateName(m.state),
         m.pctBullTrend, m.pctBearTrend, m.pctBullChannel,
         m.pctBearChannel, m.pctRange, m.pctBreakout,
         m.trendScore, m.rangeScore, m.chop, m.pressure,
         (m.tight ? " TIGHT" : ""));
     }
  };

#endif
