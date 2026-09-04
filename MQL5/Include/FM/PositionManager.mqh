//+------------------------------------------------------------------+
//| PositionManager.mqh : own-position lifecycle (Phase 26)             |
//| Magic+symbol filtered. NEVER touches foreign positions. Own CTrade |
//| instance for modify/close/partial. Restart recovery adopts magic   |
//| positions (strategy parsed from comment, else generic). Trailing /  |
//| break-even only when the caller allows (strategy permits).         |
//+------------------------------------------------------------------+
#ifndef FM_POSITIONMANAGER_MQH
#define FM_POSITIONMANAGER_MQH

#include <Trade/Trade.mqh>
#include "Defs.mqh"
#include "StrategyRegistry.mqh"

struct PositionFix
  {
   ulong             ticket;
   string            symbol;
   ENUM_FM_STRATEGY  strategy;   // STRAT_NONE when unparsed (adopted)
   long              setupId;    // 0 when unknown
   int               dir;        // +1 buy / -1 sell
   double            entry;
   double            sl;
   double            tp;
   double            volume;
   datetime          opened;
  };

struct ModifyResult
  {
   bool              ok;
   string            reason;
  };

class CPositionManager
  {
private:
   CTrade            m_trade;
   long              m_magic;
   bool              m_useTrailing;
   int               m_trailStartPts;
   int               m_trailStepPts;
   bool              m_useBreakEven;
   int               m_beTriggerPts;
   int               m_beOffsetPts;
   ulong             m_lastDealScanned;
   bool              m_firstScan;

   // Comment wire format: "FM|<strategy>|<setupId>"
   static string     EncodeComment(ENUM_FM_STRATEGY st, long setupId)
     {
      return StringFormat("FM|%d|%d", (int)st, setupId);
     }

   static bool       ParseComment(string c, ENUM_FM_STRATEGY &st, long &setupId)
     {
      st = STRAT_NONE;
      setupId = 0;
      string parts[];
      if(StringSplit(c, '|', parts) != 3)
         return false;
      if(parts[0] != "FM")
         return false;
      st = (ENUM_FM_STRATEGY)StringToInteger(parts[1]);
      if(st <= STRAT_NONE || st >= STRAT_COUNT)
        {
         st = STRAT_NONE;
         return false;
        }
      setupId = StringToInteger(parts[2]);
      return true;
     }

   bool              LoadTicket(ulong ticket, PositionFix &p) const
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      if(PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;
      p.ticket = ticket;
      p.symbol = PositionGetString(POSITION_SYMBOL);
      long typ = PositionGetInteger(POSITION_TYPE);
      p.dir = (typ == POSITION_TYPE_BUY ? +1 : -1);
      p.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl = PositionGetDouble(POSITION_SL);
      p.tp = PositionGetDouble(POSITION_TP);
      p.volume = PositionGetDouble(POSITION_VOLUME);
      p.opened = (datetime)PositionGetInteger(POSITION_TIME);
      ENUM_FM_STRATEGY st;
      long sid;
      if(ParseComment(PositionGetString(POSITION_COMMENT), st, sid))
        {
         p.strategy = st;
         p.setupId = sid;
        }
      else
        {
         p.strategy = STRAT_NONE;
         p.setupId = 0;
        }
      return true;
     }

public:
                     CPositionManager(): m_magic(0), m_useTrailing(false),
      m_trailStartPts(0), m_trailStepPts(0), m_useBreakEven(false),
      m_beTriggerPts(0), m_beOffsetPts(0), m_lastDealScanned(0), m_firstScan(true) {}

   void              Configure(long magic, int slippagePts, bool useTrailing,
                               int trailStartPts, int trailStepPts,
                               bool useBreakEven, int beTriggerPts,
                               int beOffsetPts)
     {
      m_magic = magic;
      m_useTrailing = useTrailing;
      m_trailStartPts = trailStartPts;
      m_trailStepPts = trailStepPts;
      m_useBreakEven = useBreakEven;
      m_beTriggerPts = beTriggerPts;
      m_beOffsetPts = beOffsetPts;
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints(slippagePts);
     }

   static string     MakeComment(ENUM_FM_STRATEGY st, long setupId)
     { return EncodeComment(st, setupId); }

   // All OWN positions (magic match), optionally symbol-filtered.
   int               Refresh(string symbolFilter, PositionFix &out[])
     {
      ArrayResize(out, 0);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0)
            continue;
         PositionFix p;
         if(!LoadTicket(tk, p))
            continue;                    // foreign position: never touched
         if(symbolFilter != "" && p.symbol != symbolFilter)
            continue;
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = p;
        }
      return ArraySize(out);
     }

   int               Count(string symbolFilter)
     {
      PositionFix tmp[];
      return Refresh(symbolFilter, tmp);
     }

   bool              HasOpen(string symbolFilter, ENUM_FM_STRATEGY st)
     {
      PositionFix arr[];
      Refresh(symbolFilter, arr);
      for(int i = 0; i < ArraySize(arr); i++)
         if(st == STRAT_NONE || arr[i].strategy == st)
            return true;
      return false;
     }

   // Stop/target modification with stop-level + freeze validation.
   ModifyResult      ModifySLTP(ulong ticket, double newSL, double newTP)
     {
      ModifyResult r;
      r.ok = false;
      r.reason = "NOT_FOUND";
      PositionFix p;
      if(!LoadTicket(ticket, p))
         return r;                       // foreign or gone: refuse
      string sym = p.symbol;
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      int stopLvl = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      int frz = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ref = (p.dir > 0 ? bid : ask);   // worst case for SL distance
      if(newSL > 0 && MathAbs(ref - newSL) < stopLvl * pt)
        {
         r.reason = "INVALID_STOPS";
         return r;
        }
      if(newTP > 0 && MathAbs(ref - newTP) < stopLvl * pt)
        {
         r.reason = "INVALID_STOPS";
         return r;
        }
      if(frz > 0)
        {
         double curSLdist = (p.sl > 0 ? MathAbs(ref - p.sl) / pt : 1e9);
         double newSLdist = (newSL > 0 ? MathAbs(ref - newSL) / pt : 1e9);
         if(MathAbs(newSLdist - curSLdist) < frz && newTP == p.tp)
           {
            r.reason = "FROZEN";
            return r;
           }
        }
      m_trade.SetTypeFillingBySymbol(sym);
      if(!m_trade.PositionModify(ticket, newSL, newTP))
        {
         r.reason = StringFormat("MODIFY_FAIL_%d", m_trade.ResultRetcode());
         return r;
        }
      r.ok = true;
      r.reason = "DONE";
      return r;
     }

   // Break-even: move SL to entry±offset once profit exceeds trigger.
   // Returns true when a modification was SENT (check result separately).
   bool              MaybeBreakEven(const PositionFix &p, bool allowed, ModifyResult &res)
     {
      res.ok = false;
      res.reason = "SKIPPED";
      if(!allowed || !m_useBreakEven || m_beTriggerPts <= 0)
         return false;
      double pt = SymbolInfoDouble(p.symbol, SYMBOL_POINT);
      double price = (p.dir > 0 ? SymbolInfoDouble(p.symbol, SYMBOL_BID)
                                : SymbolInfoDouble(p.symbol, SYMBOL_ASK));
      double profitPts = (p.dir > 0 ? (price - p.entry) : (p.entry - price)) / pt;
      if(profitPts < m_beTriggerPts)
         return false;
      double beSL = (p.dir > 0 ? p.entry + m_beOffsetPts * pt
                               : p.entry - m_beOffsetPts * pt);
      bool already = (p.dir > 0 ? (p.sl >= beSL - pt * 0.5)
                                : (p.sl <= beSL + pt * 0.5 && p.sl > 0));
      if(p.sl > 0 && already)
         return false;
      res = ModifySLTP(p.ticket, beSL, p.tp);
      return true;
     }

   // Trailing: ratchet SL behind price by step once profit exceeds start.
   bool              MaybeTrail(const PositionFix &p, bool allowed, ModifyResult &res)
     {
      res.ok = false;
      res.reason = "SKIPPED";
      if(!allowed || !m_useTrailing || m_trailStartPts <= 0 || m_trailStepPts <= 0)
         return false;
      double pt = SymbolInfoDouble(p.symbol, SYMBOL_POINT);
      double price = (p.dir > 0 ? SymbolInfoDouble(p.symbol, SYMBOL_BID)
                                : SymbolInfoDouble(p.symbol, SYMBOL_ASK));
      double profitPts = (p.dir > 0 ? (price - p.entry) : (p.entry - price)) / pt;
      if(profitPts < m_trailStartPts)
         return false;
      double base = (p.sl > 0 ? p.sl : p.entry);
      double want = (p.dir > 0 ? price - m_trailStartPts * pt
                               : price + m_trailStartPts * pt);
      bool improve = (p.dir > 0 ? (want > base + m_trailStepPts * pt)
                                : (want < base - m_trailStepPts * pt));
      if(!improve)
         return false;
      res = ModifySLTP(p.ticket, want, p.tp);
      return true;
     }

   ModifyResult      ClosePosition(ulong ticket)
     {
      ModifyResult r;
      r.ok = false;
      r.reason = "NOT_FOUND";
      PositionFix p;
      if(!LoadTicket(ticket, p))
         return r;
      m_trade.SetTypeFillingBySymbol(p.symbol);
      if(!m_trade.PositionClose(ticket))
        {
         r.reason = StringFormat("CLOSE_FAIL_%d", m_trade.ResultRetcode());
         return r;
        }
      uint rc = m_trade.ResultRetcode();
      r.ok = (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL);
      r.reason = (r.ok ? "DONE" : StringFormat("CLOSE_RC_%d", rc));
      return r;
     }

   int               CloseAll(string symbolFilter, string &log)
     {
      log = "";
      PositionFix arr[];
      Refresh(symbolFilter, arr);
      int closed = 0;
      for(int i = 0; i < ArraySize(arr); i++)
        {
         ModifyResult r = ClosePosition(arr[i].ticket);
         log += StringFormat("#%d:%s ", arr[i].ticket, r.reason);
         if(r.ok)
            closed++;
        }
      return closed;
     }

   ModifyResult      PartialClose(ulong ticket, double volumeToClose)
     {
      ModifyResult r;
      r.ok = false;
      r.reason = "NOT_FOUND";
      PositionFix p;
      if(!LoadTicket(ticket, p))
         return r;
      double step = SymbolInfoDouble(p.symbol, SYMBOL_VOLUME_STEP);
      double mn = SymbolInfoDouble(p.symbol, SYMBOL_VOLUME_MIN);
      if(volumeToClose < mn || volumeToClose >= p.volume)
        {
         r.reason = "INVALID_VOLUME";
         return r;
        }
      m_trade.SetTypeFillingBySymbol(p.symbol);
      if(!m_trade.PositionClosePartial(ticket, volumeToClose))
        {
         r.reason = StringFormat("PARTIAL_FAIL_%d", m_trade.ResultRetcode());
         return r;
        }
      uint rc = m_trade.ResultRetcode();
      r.ok = (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL);
      r.reason = (r.ok ? "DONE" : StringFormat("PARTIAL_RC_%d", rc));
      return r;
     }

   // Closed-deal scan for risk accounting: profits of NEW ENTRY_OUT deals
   // with our magic since the previous scan. EA forwards each to risk.
   // RESTART RULE: the first scan only fast-forwards the cursor (history
   // before EA start is never replayed into daily P/L); open positions are
   // adopted via Refresh() instead.
   int               ScanClosedDeals(double &profits[])
     {
      ArrayResize(profits, 0);
      HistorySelect(0, TimeCurrent() + 86400);
      int n = HistoryDealsTotal();
      if(m_firstScan)
        {
         for(int i = 0; i < n; i++)
           {
            ulong dt = HistoryDealGetTicket(i);
            if(dt > m_lastDealScanned)
               m_lastDealScanned = dt;
           }
         m_firstScan = false;
         return 0;
        }
      for(int i = 0; i < n; i++)
        {
         ulong dt = HistoryDealGetTicket(i);
         if(dt == 0 || dt <= m_lastDealScanned)
            continue;
         m_lastDealScanned = dt;
         if(HistoryDealGetInteger(dt, DEAL_MAGIC) != m_magic)
            continue;
         long entry = HistoryDealGetInteger(dt, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
            continue;
         int m = ArraySize(profits);
         ArrayResize(profits, m + 1);
         profits[m] = HistoryDealGetDouble(dt, DEAL_PROFIT) +
                      HistoryDealGetDouble(dt, DEAL_SWAP) +
                      HistoryDealGetDouble(dt, DEAL_COMMISSION);
        }
      return ArraySize(profits);
     }
  };

#endif
