//+------------------------------------------------------------------+
//| PaperTrader.mqh : virtual fills for PAPER mode (Phase 33)           |
//| No orders, no margin, no spread modeling beyond entry/exit prices.  |
//| Settlement per closed bar OHLC; same-bar SL+TP both hit → SL first  |
//| (conservative). R = profit / initial risk (risk>0 guaranteed by     |
//| the risk layer before an intent is built).                          |
//+------------------------------------------------------------------+
#ifndef FM_PAPERTRADER_MQH
#define FM_PAPERTRADER_MQH

#include "Defs.mqh"
#include "StrategyRegistry.mqh"
#include "TradeIntent.mqh"

struct VirtualPosition
  {
   bool              open;
   ENUM_FM_STRATEGY  strategy;
   int               dir;
   string            symbol;
   double            entry;
   double            stop;
   double            objective;
   double            volume;
   double            riskMoney;
   datetime          openedBar;
  };

struct PaperStats
  {
   int               trades;
   int               wins;
   int               losses;
   double            profit;
   double            totalR;
   double            maxWin;
   double            maxLoss;
  };

class CPaperTrader
  {
private:
   VirtualPosition   m_pos[];
   PaperStats        m_stats;
   int               m_maxOpen;

   static double     CalcProfit(string sym, int dir, double vol,
                                double entry, double exitPx)
     {
      double p = 0.0;
      ENUM_ORDER_TYPE t = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(!OrderCalcProfit(t, sym, vol, entry, exitPx, p))
         return 0.0;
      return p;
     }

public:
                     CPaperTrader(): m_maxOpen(1)
     {
      ArrayResize(m_pos, 0);
      ZeroMemory(m_stats);
     }

   void              Configure(int maxOpen) { m_maxOpen = maxOpen; }

   int               OpenCount() const
     {
      int n = 0;
      for(int i = 0; i < ArraySize(m_pos); i++)
         if(m_pos[i].open)
            n++;
      return n;
     }

   // Virtual market fill at price px (EA passes current ask/bid).
   bool              Open(string sym, const TradeIntent &in, double volume,
                          double riskMoney, double px, datetime barTime)
     {
      if(!in.valid || OpenCount() >= m_maxOpen)
         return false;
      int n = ArraySize(m_pos);
      ArrayResize(m_pos, n + 1);
      m_pos[n].open = true;
      m_pos[n].strategy = in.strategy;
      m_pos[n].dir = in.dir;
      m_pos[n].symbol = sym;
      m_pos[n].entry = px;
      m_pos[n].stop = in.stop;
      m_pos[n].objective = in.objective;
      m_pos[n].volume = volume;
      m_pos[n].riskMoney = (riskMoney > 0 ? riskMoney : 1e-9);
      m_pos[n].openedBar = barTime;
      return true;
     }

   // Settle on closed-bar OHLC. Returns realized R sum this bar (for logs).
   double            SettleBar(string sym, double high, double low,
                               datetime barTime, string &log)
     {
      log = "";
      double rSum = 0.0;
      for(int i = 0; i < ArraySize(m_pos); i++)
        {
         if(!m_pos[i].open || m_pos[i].symbol != sym)
            continue;
         // SL first on ambiguity (conservative); BE-moved stops are honored
         // because in.stop tracks the live stop (EA updates it, Phase 34+).
         bool hitSL = (m_pos[i].dir > 0 ? (low <= m_pos[i].stop)
                                        : (high >= m_pos[i].stop));
         bool hitTP = (m_pos[i].dir > 0 ? (high >= m_pos[i].objective)
                                        : (low <= m_pos[i].objective));
         double exitPx = 0.0;
         string how = "";
         if(hitSL)
           {
            exitPx = m_pos[i].stop;
            how = "SL";
           }
         else if(hitTP)
           {
            exitPx = m_pos[i].objective;
            how = "TP";
           }
         else
            continue;
         double profit = CalcProfit(sym, m_pos[i].dir, m_pos[i].volume,
                                    m_pos[i].entry, exitPx);
         double r = profit / m_pos[i].riskMoney;
         m_stats.trades++;
         if(profit >= 0)
            m_stats.wins++;
         else
            m_stats.losses++;
         m_stats.profit += profit;
         m_stats.totalR += r;
         if(profit > m_stats.maxWin)
            m_stats.maxWin = profit;
         if(profit < m_stats.maxLoss)
            m_stats.maxLoss = profit;
         rSum += r;
         log += StringFormat("PAPER_CLOSE %s %s exit=%s R=%.2f P=%.2f ",
                             CStrategyRegistry::StrategyName(m_pos[i].strategy),
                             how, DoubleToString(exitPx, 8), r, profit);
         m_pos[i].open = false;
        }
      return rSum;
     }

   void              Stats(PaperStats &s) const { s = m_stats; }

   string            Summary() const
     {
      double avgR = (m_stats.trades > 0 ? m_stats.totalR / m_stats.trades : 0.0);
      return StringFormat("PAPER trades=%d W/L=%d/%d P=%.2f avgR=%.2f maxW=%.2f maxL=%.2f open=%d",
                          m_stats.trades, m_stats.wins, m_stats.losses,
                          m_stats.profit, avgR, m_stats.maxWin, m_stats.maxLoss,
                          OpenCount());
     }
  };

#endif
