//+------------------------------------------------------------------+
//| Context.mqh : Trend/Range/Transition + confidence (closed bars)    |
//+------------------------------------------------------------------+
#ifndef FM_CONTEXT_MQH
#define FM_CONTEXT_MQH
#include "Defs.mqh"

class CContextClassifier
  {
private:
   int               m_ema_fast;
   int               m_ema_slow;
   int               m_lookback;
public:
   CContextClassifier(): m_ema_fast(20), m_ema_slow(50), m_lookback(50) {}

   // Pure on copied closes; no future data.
   void Classify(const MqlRates &rates[], int count, int shift, double atr,
                 ENUM_FM_CONTEXT &ctx, double &conf) const
     {
      ctx = FM_CTX_TRANSITION; conf = 0.5;
      if(shift < 1 || shift + m_lookback >= count || atr <= 0) return;
      double ef = 0, es = 0, k_f = 2.0/(m_ema_fast+1), k_s = 2.0/(m_ema_slow+1);
      // seed from oldest
      ef = rates[shift + m_ema_fast].close;
      for(int i = shift + m_ema_fast - 1; i >= shift; i--)
         ef = rates[i].close * k_f + ef * (1 - k_f);
      es = rates[shift + m_ema_slow].close;
      for(int i = shift + m_ema_slow - 1; i >= shift; i--)
         es = rates[i].close * k_s + es * (1 - k_s);
      double hh = rates[shift].high, ll = rates[shift].low;
      for(int i = shift; i < shift + m_lookback && i < count; i++)
        {
         if(rates[i].high > hh) hh = rates[i].high;
         if(rates[i].low  < ll) ll = rates[i].low;
        }
      double trend_score = (ef - es) / atr;
      double range_score = (hh - ll) / atr;
      if(MathAbs(trend_score) > 0.8 && range_score > 3.0)
        {
         ctx = FM_CTX_TREND;
         conf = MathMin(1.0, (MathAbs(trend_score) - 0.8) / 1.2 + 0.5);
        }
      else if(MathAbs(trend_score) < 0.4 && range_score < 6.0)
        {
         ctx = FM_CTX_RANGE;
         conf = MathMin(1.0, (0.4 - MathAbs(trend_score)) / 0.4 * 0.5 + 0.5);
        }
      else
        {
         ctx = FM_CTX_TRANSITION;
         conf = 0.5;
        }
     }
  };

#endif
