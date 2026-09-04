//+------------------------------------------------------------------+
//| SafetyManager.mqh : kill-switches + trading modes (Phase 33)        |
//| Default = ANALYSIS_ONLY (safest). Live execution needs explicit    |
//| configuration AND a real account AND a confirm token. Halts latch  |
//| until reload (tester) / manual reset.                              |
//+------------------------------------------------------------------+
#ifndef FM_SAFETY_MQH
#define FM_SAFETY_MQH

#include "Defs.mqh"

enum ENUM_FM_TRADE_MODE
  {
   TRADE_ANALYSIS_ONLY=0, // default: decide + log only, never orders
   TRADE_PAPER=1,         // virtual fills (PaperTrader), never orders
   TRADE_DEMO=2,          // real orders ONLY on non-real accounts
   TRADE_LIVE=3           // real orders ONLY on real account + confirm token
  };

struct SafetyState
  {
   bool              halted;
   string            haltReason;
   double            equityPeak;
   bool              peakInit;
  };

class CSafetyManager
  {
private:
   ENUM_FM_TRADE_MODE m_mode;
   string            m_liveToken;      // required exact match for LIVE
   bool              m_emergencyStop;
   double            m_maxDailyLossMoney; // 0=off (mirror of risk cap as halt)
   double            m_maxDrawdownPct;    // 0=off
   int               m_sessionStartH;     // 0..24, start==end = always
   int               m_sessionEndH;
   bool              m_closeOnHalt;
   SafetyState       m_st;

public:
                     CSafetyManager()
     {
      m_mode = TRADE_ANALYSIS_ONLY; m_liveToken = "";
      m_emergencyStop = false; m_maxDailyLossMoney = 0.0;
      m_maxDrawdownPct = 20.0; m_sessionStartH = 0; m_sessionEndH = 24;
      m_closeOnHalt = false;
      m_st.halted = false; m_st.haltReason = "";
      m_st.equityPeak = 0; m_st.peakInit = false;
     }

   void              Configure(ENUM_FM_TRADE_MODE mode, string liveToken,
                               bool emergencyStop, double maxDailyLossMoney,
                               double maxDrawdownPct, int sessionStartH,
                               int sessionEndH, bool closeOnHalt)
     {
      m_mode = mode; m_liveToken = liveToken;
      m_emergencyStop = emergencyStop;
      m_maxDailyLossMoney = maxDailyLossMoney;
      m_maxDrawdownPct = maxDrawdownPct;
      m_sessionStartH = sessionStartH; m_sessionEndH = sessionEndH;
      m_closeOnHalt = closeOnHalt;
     }

   ENUM_FM_TRADE_MODE Mode() const { return m_mode; }
   bool              CloseOnHalt() const { return m_closeOnHalt; }

   static string     ModeName(ENUM_FM_TRADE_MODE m)
     {
      switch(m)
        {
         case TRADE_ANALYSIS_ONLY: return "ANALYSIS_ONLY";
         case TRADE_PAPER:         return "PAPER";
         case TRADE_DEMO:          return "DEMO";
         case TRADE_LIVE:          return "LIVE";
         default:                  return "?";
        }
     }

   // Session gate on server hour (start==end or full span = always open).
   bool              SessionOpen(int hour) const
     {
      if(m_sessionStartH == m_sessionEndH)
         return true;
      if(m_sessionStartH < m_sessionEndH)
         return (hour >= m_sessionStartH && hour < m_sessionEndH);
      return (hour >= m_sessionStartH || hour < m_sessionEndH); // overnight
     }

   // Real-order permission for the CURRENT account (call at each send).
   // Tester accounts report their simulated mode; ANALYSIS_ONLY/PAPER never
   // reach here for real orders.
   bool              RealOrdersAllowed(string &why) const
     {
      ENUM_ACCOUNT_TRADE_MODE tm =
         (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
      if(m_mode == TRADE_DEMO)
        {
         if(tm == ACCOUNT_TRADE_MODE_REAL)
           {
            why = "DEMO_MODE_ON_REAL_ACCOUNT";
            return false;
           }
         why = "";
         return true;
        }
      if(m_mode == TRADE_LIVE)
        {
         if(tm != ACCOUNT_TRADE_MODE_REAL)
           {
            why = "LIVE_MODE_NEEDS_REAL_ACCOUNT";
            return false;
           }
         if(m_liveToken != "TRADE_LIVE")
           {
            why = "LIVE_TOKEN_MISSING";
            return false;
           }
         why = "";
         return true;
        }
      why = "MODE_FORBIDS_ORDERS";
      return false;
     }

   // Per-bar evaluation. Returns false when trading must stop now.
   bool              Evaluate(double equity, double dailyPL, int hour, string &why)
     {
      if(m_st.halted)
        {
         why = m_st.haltReason;
         return false;
        }
      if(m_emergencyStop)
        {
         Halt("EMERGENCY_STOP");
         why = m_st.haltReason;
         return false;
        }
      if(!m_st.peakInit || equity > m_st.equityPeak)
        {
         m_st.equityPeak = equity;
         m_st.peakInit = true;
        }
      if(m_maxDrawdownPct > 0 && m_st.equityPeak > 0)
        {
         double dd = (m_st.equityPeak - equity) / m_st.equityPeak * 100.0;
         if(dd >= m_maxDrawdownPct)
           {
            Halt(StringFormat("MAX_DRAWDOWN_%.1f", dd));
            why = m_st.haltReason;
            return false;
           }
        }
      if(m_maxDailyLossMoney > 0 && dailyPL <= -m_maxDailyLossMoney)
        {
         Halt("MAX_DAILY_LOSS");
         why = m_st.haltReason;
         return false;
        }
      if(!SessionOpen(hour))
        {
         why = "SESSION_CLOSED";
         return false;   // session is a pause, NOT a latch
        }
      why = "";
      return true;
     }

   void              Halt(string reason)
     {
      m_st.halted = true;
      m_st.haltReason = reason;
     }
   bool              Halted(string &reason) const
     {
      reason = m_st.haltReason;
      return m_st.halted;
     }
  };

#endif
