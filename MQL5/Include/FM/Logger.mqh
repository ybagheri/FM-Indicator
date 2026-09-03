//+------------------------------------------------------------------+
//| Logger.mqh : level-gated logging                                   |
//+------------------------------------------------------------------+
#ifndef FM_LOGGER_MQH
#define FM_LOGGER_MQH
#include "Defs.mqh"

class CLogger
  {
private:
   ENUM_LOG_LEVEL    m_level;
public:
   CLogger(): m_level(LOG_INFO) {}
   void SetLevel(ENUM_LOG_LEVEL l) { m_level=l; }
   void Error(string s) { if(m_level>=LOG_ERROR) PrintFormat("[FM][ERR] %s", s); }
   void Info(string s)  { if(m_level>=LOG_INFO)  PrintFormat("[FM] %s", s); }
   void Debug(string s) { if(m_level>=LOG_DEBUG) PrintFormat("[FM][DBG] %s", s); }
   // Retrospective gap-type labels: DEBUG ONLY, never live states.
   void GapLabel(string s) { if(m_level>=LOG_DEBUG) PrintFormat("[FM][GAP-hindsight] %s", s); }
  };

#endif
