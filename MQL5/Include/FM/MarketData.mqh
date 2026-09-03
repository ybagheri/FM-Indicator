//+------------------------------------------------------------------+
//| MarketData.mqh : closed-bar disciplined series copy                |
//+------------------------------------------------------------------+
#ifndef FM_MARKETDATA_MQH
#define FM_MARKETDATA_MQH

class CMarketData
  {
private:
   MqlRates          m_rates[];   // series: m_rates[0] = forming bar
   datetime          m_last_bar_time;
   int               m_bars_cached;
public:
   CMarketData(): m_last_bar_time(0), m_bars_cached(0) {}

   bool Refresh(string sym, ENUM_TIMEFRAMES tf, int need_bars)
     {
      int need = need_bars + 5;
      if(Bars(sym, tf) < need)
         need = Bars(sym, tf);
      if(CopyRates(sym, tf, 0, need, m_rates) < 1)
         return false;
      ArraySetAsSeries(m_rates, true);
      m_bars_cached = ArraySize(m_rates);
      return true;
     }

   bool IsNewBar()
     {
      if(m_bars_cached==0) return false;
      if(m_rates[m_bars_cached-1].time==0) return false;
      // newest bar is index 0 in series mode
      datetime t0 = m_rates[0].time;
      if(t0 != m_last_bar_time) { m_last_bar_time = t0; return true; }
      return false;
     }
   void SyncBarTime() { if(m_bars_cached>0) m_last_bar_time = m_rates[0].time; }

   int Count() const { return m_bars_cached; }
   // Closed-bar accessor: i>=1 required. Returns false if out of range.
   bool Closed(int shift, MqlRates &r) const
     {
      if(shift < 1 || shift >= m_bars_cached) return false;
      r = m_rates[shift];
      return true;
     }
   bool Forming(MqlRates &r) const
     {
      if(m_bars_cached==0) return false;
      r = m_rates[0];
      return true;
     }
   int LastClosed() const { return m_bars_cached - 1; } // oldest shift
  };

#endif
