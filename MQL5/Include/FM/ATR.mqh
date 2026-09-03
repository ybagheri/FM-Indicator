//+------------------------------------------------------------------+
//| ATR.mqh : Wilder ATR on closed bars                                |
//+------------------------------------------------------------------+
#ifndef FM_ATR_MQH
#define FM_ATR_MQH

class CATR
  {
private:
   double            m_atr[];
   int               m_period;
public:
   CATR(): m_period(14) {}
   void SetPeriod(int p) { m_period = (p<2?2:p); }

   // Compute over series rates (series mode, [0]=forming). atr[shift] aligns
   // with rates shift. Only shifts>=1 are valid for detection.
   bool Update(const MqlRates &rates[], int count)
     {
      if(count < m_period + 2) return false;
      ArrayResize(m_atr, count);
      ArrayInitialize(m_atr, 0.0);
      // true ranges; iterate oldest->newest for Wilder seeding
      double tr[];
      ArrayResize(tr, count);
      for(int i = count-2; i >= 0; i--)
        {
         double h = rates[i].high, l = rates[i].low;
         double pc = rates[i+1].close;
         double r1 = h - l;
         double r2 = MathAbs(h - pc);
         double r3 = MathAbs(l - pc);
         tr[i] = MathMax(r1, MathMax(r2, r3));
        }
      // seed at oldest usable: simple mean of first `period` TRs (oldest side)
      int seed = count - 1 - m_period;
      if(seed < 1) return false;
      double sum = 0;
      for(int i = seed; i < seed + m_period && i < count; i++) sum += tr[i];
      m_atr[seed] = sum / m_period;
      for(int i = seed - 1; i >= 0; i--)
         m_atr[i] = (m_atr[i+1] * (m_period - 1) + tr[i]) / m_period;
      return true;
     }

   double At(int shift) const
     {
      if(shift < 0 || shift >= ArraySize(m_atr)) return 0.0;
      return m_atr[shift];
     }
  };

#endif
