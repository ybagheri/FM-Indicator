//+------------------------------------------------------------------+
//| Swings.mqh : fractal-k swings, confirmed-only output               |
//| Anti-repaint: swing s visible only when lastClosed >= s+k          |
//+------------------------------------------------------------------+
#ifndef FM_SWINGS_MQH
#define FM_SWINGS_MQH
#include "Defs.mqh"

class CSwingDetector
  {
private:
   int               m_k;
   SwingPoint        m_swings[];
   int               m_last_closed_seen;
public:
   CSwingDetector(): m_k(3), m_last_closed_seen(0)
     {
      ArrayResize(m_swings, 0);
     }
   void SetK(int k) { m_k = (k<1?1:(k>10?10:k)); }

   void Reset() { ArrayResize(m_swings, 0); m_last_closed_seen=0; }

   int Count() const { return ArraySize(m_swings); }
   bool Get(int idx, SwingPoint &s) const
     {
      if(idx<0 || idx>=ArraySize(m_swings)) return false;
      s = m_swings[idx];
      return true;
     }

   // Rebuild confirmed swings from series rates. `lastClosed` = shift of the
   // newest closed bar (=1 in MT5 terms is newest; here we pass count-based).
   // We scan candidate s in (lastClosed+k .. oldest) — only confirmed ones.
   void Update(const MqlRates &rates[], int count, int newest_closed_shift)
     {
      // newest_closed_shift is normally 1; count = ArraySize(rates)
      ArrayResize(m_swings, 0);
      if(count < 2*m_k + 3) return;
      int oldest = count - 1 - m_k;
      for(int s = newest_closed_shift + m_k; s <= oldest; s++)
        {
         bool isHigh = true, isLow = true;
         for(int j = s - m_k; j <= s + m_k; j++)
           {
            if(j==s || j<1 || j>=count) continue; // closed bars only
            if(rates[j].high > rates[s].high) isHigh = false;
            if(rates[j].low  < rates[s].low ) isLow  = false;
           }
         // strict-greater tie-break: earliest bar wins; skip if equal extreme exists older
         if(isHigh)
           {
            for(int j = s+1; j <= s+m_k && j<count; j++)
               if(rates[j].high == rates[s].high) { isHigh=false; break; }
           }
         if(isLow)
           {
            for(int j = s+1; j <= s+m_k && j<count; j++)
               if(rates[j].low == rates[s].low) { isLow=false; break; }
           }
         if(isHigh || isLow)
           {
            SwingPoint sp;
            sp.bar = s;
            sp.dir = isHigh ? +1 : -1;
            // if both (rare flat), prefer high; low will appear via neighbor scan
            sp.price = isHigh ? rates[s].high : rates[s].low;
            sp.confirmed_bar = s - m_k; // newest-closed shift at confirmation... stored as shift
            // NOTE: confirmation bar in "bars-ago" shifts moves as data grows;
            // engine uses bar time comparison instead. Keep field informative.
            sp.valid = true;
            int n = ArraySize(m_swings);
            ArrayResize(m_swings, n+1);
            m_swings[n] = sp;
           }
        }
      // m_swings now oldest-first? We scanned newest->oldest; reverse for chrono order
      int n = ArraySize(m_swings);
      for(int i=0;i<n/2;i++)
        {
         SwingPoint t=m_swings[i]; m_swings[i]=m_swings[n-1-i]; m_swings[n-1-i]=t;
        }
      m_last_closed_seen = newest_closed_shift;
     }
  };

#endif
