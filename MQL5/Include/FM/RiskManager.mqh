//+------------------------------------------------------------------+
//| RiskManager.mqh : dedicated risk layer (Phase 24)                   |
//| Sizing (fixed / risk-% / money) + safety caps. Pure computation +   |
//| account/symbol queries; places NO orders. All rejections carry a    |
//| machine-checkable reason string (tests assert them).                |
//+------------------------------------------------------------------+
#ifndef FM_RISKMANAGER_MQH
#define FM_RISKMANAGER_MQH

#include "Defs.mqh"
#include "GeneralSetups.mqh"

enum ENUM_LOT_MODE
  {
   LOT_FIXED=0,      // InpFixedLot (normalized to symbol)
   LOT_RISK_PCT=1,   // % of equity risked on the stop distance
   LOT_MONEY=2       // fixed money risked on the stop distance
  };

struct RiskDecision
  {
   bool              allowed;
   string            reason;      // OK or machine-checkable veto
   double            volume;      // normalized, symbol-clamped
   double            riskMoney;   // money at risk at this volume
   double            rMult;       // setup echo
  };

class CRiskManager
  {
private:
   ENUM_LOT_MODE     m_lotMode;
   double            m_fixedLot;
   double            m_riskPct;
   double            m_moneyRisk;
   double            m_maxDailyLossMoney; // 0 = off
   int               m_maxTradesDay;      // 0 = off
   int               m_maxOpen;           // 0 = off
   int               m_maxPerSymbol;      // 0 = off
   int               m_maxConsecLosses;   // 0 = off
   int               m_maxSpreadPoints;   // 0 = off
   double            m_minRR;             // 0 = off
   long              m_magic;

   int               m_day;               // YYYYMMDD anchor
   int               m_tradesToday;
   double            m_dailyPL;
   int               m_consecLosses;

   static double     NormVol(string sym, double v)
     {
      double mn = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double mx = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double st = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(st <= 0)
         st = 0.01;
      v = MathFloor(v / st) * st;
      v = NormalizeDouble(v, 8);
      if(v < mn)
         v = mn;
      if(v > mx)
         v = mx;
      return v;
     }

   int               CountPositions(string sym) const
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(sym != "" && PositionGetString(POSITION_SYMBOL) != sym)
            continue;
         n++;
        }
      return n;
     }

public:
                     CRiskManager()
     {
      m_lotMode = LOT_RISK_PCT; m_fixedLot = 0.10; m_riskPct = 1.0;
      m_moneyRisk = 100.0; m_maxDailyLossMoney = 0.0; m_maxTradesDay = 5;
      m_maxOpen = 1; m_maxPerSymbol = 1; m_maxConsecLosses = 3;
      m_maxSpreadPoints = 50; m_minRR = 1.0; m_magic = 0;
      m_day = 0; m_tradesToday = 0; m_dailyPL = 0.0; m_consecLosses = 0;
     }

   void              Configure(ENUM_LOT_MODE lotMode, double fixedLot, double riskPct,
                               double moneyRisk, double maxDailyLossMoney,
                               int maxTradesDay, int maxOpen, int maxPerSymbol,
                               int maxConsecLosses, int maxSpreadPoints,
                               double minRR, long magic)
     {
      m_lotMode = lotMode; m_fixedLot = fixedLot; m_riskPct = riskPct;
      m_moneyRisk = moneyRisk; m_maxDailyLossMoney = maxDailyLossMoney;
      m_maxTradesDay = maxTradesDay; m_maxOpen = maxOpen;
      m_maxPerSymbol = maxPerSymbol; m_maxConsecLosses = maxConsecLosses;
      m_maxSpreadPoints = maxSpreadPoints; m_minRR = minRR; m_magic = magic;
     }

   // Call once per new bar (day rollover) and on closed trades (Phase 26).
   void              OnNewDay(int yyyymmdd)
     {
      if(yyyymmdd != m_day)
        {
         m_day = yyyymmdd;
         m_tradesToday = 0;
         m_dailyPL = 0.0;
        }
     }
   void              NotifyTradeClosed(double profit)
     {
      m_tradesToday++;
      m_dailyPL += profit;
      if(profit < 0)
         m_consecLosses++;
      else
         m_consecLosses = 0;
     }
   void              NotifyTradeOpened() { m_tradesToday++; }

   // Volume for entry→stop on symbol (never zero; symbol-clamped).
   double            ComputeVolume(string sym, double entry, double stop) const
     {
      double dist = MathAbs(entry - stop);
      if(dist <= 0)
         return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double riskMoney = m_moneyRisk;
      if(m_lotMode == LOT_FIXED)
         return NormVol(sym, m_fixedLot);
      if(m_lotMode == LOT_RISK_PCT)
         riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * m_riskPct / 100.0;
      if(riskMoney <= 0)
         return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double loss1 = 0.0;
      // loss on 1.0 lot if price moves entry→stop (direction-aware)
      if(stop < entry)
        {
         if(!OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, entry, stop, loss1))
            return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
        }
      else
        {
         if(!OrderCalcProfit(ORDER_TYPE_SELL, sym, 1.0, entry, stop, loss1))
            return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
        }
      loss1 = -loss1; // OrderCalcProfit is negative for a loss
      if(loss1 <= 0)
         return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      return NormVol(sym, riskMoney / loss1);
     }

   // Full gate for a candidate setup. Spread in POINTS (passed by caller so
   // tests stay platform-free; EA passes SymbolInfoInteger(SYMBOL_SPREAD)).
   RiskDecision      Check(string sym, const GeneralSetup &s, int spreadPoints,
                           int yyyymmdd)
     {
      RiskDecision r;
      r.allowed = false;
      r.reason = "NO_SETUP";
      r.volume = 0;
      r.riskMoney = 0;
      r.rMult = s.rMult;
      if(!s.valid)
         return r;
      OnNewDay(yyyymmdd);
      if(m_minRR > 0 && s.rMult < m_minRR)
        {
         r.reason = "LOW_RR";
         return r;
        }
      if(m_maxSpreadPoints > 0 && spreadPoints > m_maxSpreadPoints)
        {
         r.reason = "HIGH_SPREAD";
         return r;
        }
      if(m_maxDailyLossMoney > 0 && m_dailyPL <= -m_maxDailyLossMoney)
        {
         r.reason = "DAILY_LOSS";
         return r;
        }
      if(m_maxTradesDay > 0 && m_tradesToday >= m_maxTradesDay)
        {
         r.reason = "MAX_TRADES_DAY";
         return r;
        }
      if(m_maxConsecLosses > 0 && m_consecLosses >= m_maxConsecLosses)
        {
         r.reason = "CONSEC_LOSSES";
         return r;
        }
      if(m_maxOpen > 0 && CountPositions("") >= m_maxOpen)
        {
         r.reason = "MAX_OPEN";
         return r;
        }
      if(m_maxPerSymbol > 0 && CountPositions(sym) >= m_maxPerSymbol)
        {
         r.reason = "MAX_PER_SYMBOL";
         return r;
        }
      r.volume = ComputeVolume(sym, s.entry, s.stop);
      if(r.volume <= 0)
        {
         r.reason = "BAD_VOLUME";
         return r;
        }
      // realized money at risk at the chosen volume (for the record)
      double loss1 = 0.0;
      bool calcOK = false;
      if(s.stop < s.entry)
         calcOK = OrderCalcProfit(ORDER_TYPE_BUY, sym, r.volume, s.entry, s.stop, loss1);
      else
         calcOK = OrderCalcProfit(ORDER_TYPE_SELL, sym, r.volume, s.entry, s.stop, loss1);
      r.riskMoney = (calcOK ? -loss1 : 0.0);
      r.allowed = true;
      r.reason = "OK";
      return r;
     }

   // Public normalizer (execution layer reuses the same symbol clamping).
   static double     NormalizeVolume(string sym, double v) { return NormVol(sym, v); }

   // Introspection for logs/tests.
   int               TradesToday() const { return m_tradesToday; }
   double            DailyPL() const { return m_dailyPL; }
   int               ConsecLosses() const { return m_consecLosses; }
  };

#endif
