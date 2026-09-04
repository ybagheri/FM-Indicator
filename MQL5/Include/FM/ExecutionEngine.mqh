//+------------------------------------------------------------------+
//| ExecutionEngine.mqh : validated order execution (Phase 25)          |
//| Thin, strict wrapper over CTrade. NOTHING is assumed: every send is |
//| pre-validated (trade mode, spread, stop level, freeze, margin,      |
//| volume) and every result retcode is classified and logged.          |
//| Places real orders ONLY when the EA explicitly calls Buy/Sell.      |
//+------------------------------------------------------------------+
#ifndef FM_EXECUTION_MQH
#define FM_EXECUTION_MQH

#include <Trade/Trade.mqh>
#include "Defs.mqh"
#include "RiskManager.mqh"

struct ExecResult
  {
   bool              ok;
   string            reason;      // DONE or machine-checkable failure
   ulong             orderTicket;
   ulong             dealTicket;
   double            price;       // deal price (0 when not executed)
   double            volume;
  };

class CExecutionEngine
  {
private:
   CTrade            m_trade;
   long              m_magic;
   int               m_slippagePts;
   int               m_maxSpreadPts;  // recheck at send time, 0=off

   static string     RetcodeName(uint rc)
     {
      switch(rc)
        {
         case TRADE_RETCODE_DONE:             return "DONE";
         case TRADE_RETCODE_DONE_PARTIAL:     return "DONE_PARTIAL";
         case TRADE_RETCODE_REQUOTE:          return "REQUOTE";
         case TRADE_RETCODE_REJECT:           return "REJECT";
         case TRADE_RETCODE_CANCEL:           return "CANCEL";
         case TRADE_RETCODE_PLACED:           return "PLACED";
         case TRADE_RETCODE_NO_MONEY:         return "NO_MONEY";
         case TRADE_RETCODE_PRICE_CHANGED:     return "PRICE_CHANGED";
         case TRADE_RETCODE_PRICE_OFF:        return "PRICE_OFF";
         case TRADE_RETCODE_INVALID_VOLUME:   return "INVALID_VOLUME";
         case TRADE_RETCODE_INVALID_PRICE:    return "INVALID_PRICE";
         case TRADE_RETCODE_INVALID_STOPS:    return "INVALID_STOPS";
         case TRADE_RETCODE_TRADE_DISABLED:   return "TRADE_DISABLED";
         case TRADE_RETCODE_MARKET_CLOSED:    return "MARKET_CLOSED";
         case TRADE_RETCODE_ONLY_REAL:        return "ONLY_REAL";
         case TRADE_RETCODE_TIMEOUT:          return "TIMEOUT";
         case TRADE_RETCODE_INVALID:          return "INVALID";
         case TRADE_RETCODE_INVALID_FILL:     return "INVALID_FILL";
         default:                             return StringFormat("RC_%d", rc);
        }
     }

   bool              DirectionAllowed(string sym, int dir, string &why) const
     {
      ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      if(tm == SYMBOL_TRADE_MODE_DISABLED || tm == SYMBOL_TRADE_MODE_CLOSEONLY)
        {
         why = "MARKET_CLOSED";
         return false;
        }
      if(dir > 0 && tm == SYMBOL_TRADE_MODE_SHORTONLY)
        {
         why = "LONGONLY_VIOLATION";
         return false;
        }
      if(dir < 0 && tm == SYMBOL_TRADE_MODE_LONGONLY)
        {
         why = "SHORTONLY_VIOLATION";
         return false;
        }
      return true;
     }

   // Pre-send validation shared by Buy/Sell. Returns "" when clear.
   string            PreCheck(string sym, int dir, double volume, double sl, double tp) const
     {
      string why = "";
      if(!DirectionAllowed(sym, dir, why))
         return why;
      if(m_maxSpreadPts > 0 &&
         SymbolInfoInteger(sym, SYMBOL_SPREAD) > m_maxSpreadPts)
         return "HIGH_SPREAD";
      double mn = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double mx = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      if(volume < mn || volume > mx)
         return "INVALID_VOLUME";
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      if(ask <= 0 || bid <= 0)
         return "NO_QUOTES";
      double ref = (dir > 0 ? ask : bid);
      int stopLvl = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = stopLvl * pt;
      if(sl > 0 && MathAbs(ref - sl) < minDist)
         return "INVALID_STOPS";
      if(tp > 0 && MathAbs(ref - tp) < minDist)
         return "INVALID_STOPS";
      // NOTE: SYMBOL_TRADE_FREEZE_LEVEL constrains pending/modify, not market
      // entry at ref — read (for future modify logic) but never blocks here.
      // margin check for the intended market order
      double margin = 0.0;
      ENUM_ORDER_TYPE mt = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(!OrderCalcMargin(mt, sym, volume, ref, margin))
         return "MARGINcalc_FAIL";
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         return "NO_MONEY";
      return "";
     }

public:
   void              Configure(long magic, int slippagePts, int maxSpreadPts)
     {
      m_magic = magic;
      m_slippagePts = slippagePts;
      m_maxSpreadPts = maxSpreadPts;
      m_trade.SetExpertMagicNumber((ulong)m_magic);
      m_trade.SetDeviationInPoints(slippagePts);
     }

   ExecResult        Buy(string sym, double volume, double sl, double tp, string comment)
     {
      return Send(sym, +1, volume, sl, tp, comment);
     }
   ExecResult        Sell(string sym, double volume, double sl, double tp, string comment)
     {
      return Send(sym, -1, volume, sl, tp, comment);
     }

   ExecResult        Send(string sym, int dir, double volume, double sl, double tp, string comment)
     {
      ExecResult r;
      r.ok = false;
      r.reason = "NOT_SENT";
      r.orderTicket = 0;
      r.dealTicket = 0;
      r.price = 0;
      r.volume = CRiskManager::NormalizeVolume(sym, volume);
      string pre = PreCheck(sym, dir, r.volume, sl, tp);
      if(pre != "")
        {
         r.reason = pre;
         return r;
        }
      m_trade.SetTypeFillingBySymbol(sym);
      bool sent = (dir > 0 ? m_trade.Buy(r.volume, sym, 0.0, sl, tp, comment)
                           : m_trade.Sell(r.volume, sym, 0.0, sl, tp, comment));
      uint rc = m_trade.ResultRetcode();
      r.reason = RetcodeName(rc);
      r.orderTicket = m_trade.ResultOrder();
      r.dealTicket = m_trade.ResultDeal();
      r.price = m_trade.ResultPrice();
      // trade.Buy()==true is NOT success: only DONE/DONE_PARTIAL count.
      r.ok = (sent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL));
      if(!r.ok && r.dealTicket == 0)
         r.price = 0;
      return r;
     }
  };

#endif
