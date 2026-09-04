//+------------------------------------------------------------------+
//| TradeIntent.mqh : strategy → trade intent (Phases 27–30)            |
//| Pure builders (no I/O, no orders). A TradeIntent is what the EA     |
//| WOULD trade at next open when risk + mode allow (Phase 33).         |
//| Entry model v1: MARKET at next open with chase guard (pending stop  |
//| orders deferred — see EA_ARCHITECTURE). Provisional setups trade    |
//| only when InpTradeProvisional=true.                                 |
//+------------------------------------------------------------------+
#ifndef FM_TRADEINTENT_MQH
#define FM_TRADEINTENT_MQH

#include "Defs.mqh"
#include "GeneralSetups.mqh"
#include "SetupEngine.mqh"
#include "BreakoutEngine.mqh"
#include "Analysis.mqh"
#include "StrategyRegistry.mqh"

struct TradeIntent
  {
   bool              valid;
   ENUM_FM_STRATEGY  strategy;
   int               dir;           // ±1
   double            entry;         // setup entry (stop-order proxy)
   double            stop;
   double            objective;
   double            rMult;
   int               score;
   bool              provisional;
   string            invalidation;  // machine-checkable text
   double            invalidClose;  // FM only (0 when N/A)
   int               maxHoldBars;
   bool              allowBE;
   bool              allowTrail;
   bool              allowPartial;
   string            note;          // human evidence summary
  };

class CTradeIntentBuilder
  {
private:
   bool              m_tradeProvisional;
   int               m_maxHoldBars;
   double            m_chaseATRMult;

   static void       Permits(ENUM_FM_STRATEGY st, bool &be, bool &trail, bool &partial)
     {
      // Rationale (STRATEGY_CATALOG.md): fixed-objective fades/reversals/
      // doubles use BE only (trailing fights the measured objective);
      // continuation styles (pullback/breakout) may trail. No partials v1.
      be = true;
      trail = false;
      partial = false;
      if(st == STRAT_PULLBACK || st == STRAT_BREAKOUT)
         trail = true;
     }

   bool              GateProvisional(bool provisional, string &why) const
     {
      if(provisional && !m_tradeProvisional)
        {
         why = "PROVISIONAL_OFF";
         return false;
        }
      return true;
     }

   // Chase guard (mirrors Phase-8 late rule): market already beyond entry
   // toward objective by more than chase×ATR → LATE_ENTRY.
   bool              GateChase(int dir, double entry, double price, double atr,
                               string &why) const
     {
      if(atr <= 0)
         return true;
      double beyond = (dir > 0 ? (price - entry) : (entry - price)) / atr;
      if(beyond > m_chaseATRMult + 1e-9)
        {
         why = "LATE_ENTRY";
         return false;
        }
      return true;
     }

   void              FillFromSetup(TradeIntent &in, ENUM_FM_STRATEGY st,
                                   const GeneralSetup &s) const
     {
      in.valid = true;
      in.strategy = st;
      in.dir = s.dir;
      in.entry = s.entry;
      in.stop = s.stop;
      in.objective = s.objective;
      in.rMult = s.rMult;
      in.score = s.score;
      in.provisional = s.provisional;
      in.maxHoldBars = m_maxHoldBars;
      in.invalidClose = 0;
      Permits(st, in.allowBE, in.allowTrail, in.allowPartial);
     }

public:
                     CTradeIntentBuilder(): m_tradeProvisional(false),
      m_maxHoldBars(5), m_chaseATRMult(0.5) {}

   void              Configure(bool tradeProvisional, int maxHoldBars,
                               double chaseATRMult)
     {
      m_tradeProvisional = tradeProvisional;
      m_maxHoldBars = maxHoldBars;
      m_chaseATRMult = chaseATRMult;
     }

   // Phase 27 — FM fade: from the winning FM setup + matched FM plan
   // (invalidClose when the plan is found by dir+entry, else STOP only).
   bool              FromFM(const GeneralSetup &s, const FMAnalysisResult &res,
                            double price, string &skipWhy, TradeIntent &in) const
     {
      ZeroMemory(in);
      if(!s.valid || s.type != SETUP_FM_FADE)
        {
         skipWhy = "NOT_FM";
         return false;
        }
      if(!GateProvisional(s.provisional, skipWhy))
         return false;
      if(!GateChase(s.dir, s.entry, price, res.atr, skipWhy))
         return false;
      FillFromSetup(in, STRAT_FM_FADE, s);
      in.invalidation = "STOP";
      for(int i = 0; i < res.fmPlanCount; i++)
        {
         if(res.fmPlans[i].valid && res.fmPlans[i].fadeDir == s.dir &&
            res.fmPlans[i].entry == s.entry)
           {
            in.invalidClose = res.fmPlans[i].invalidClose;
            in.invalidation = StringFormat("STOP_or_INVALID_CLOSE_%s",
                                           DoubleToString(in.invalidClose, 8));
            break;
           }
        }
      in.note = StringFormat("FM fade %s score=%d R=%.2f%s",
                             (s.dir > 0 ? "BUY" : "SELL"), s.score, s.rMult,
                             (s.provisional ? " PROV" : ""));
      return true;
     }

   // Phase 28 — failed-breakout fade intent (registry-built setup).
   bool              FromFailedBO(const GeneralSetup &s,
                                  double price, double atr,
                                  string &skipWhy, TradeIntent &in) const
     {
      ZeroMemory(in);
      if(!s.valid || s.type != SETUP_FAILED_BO)
        {
         skipWhy = "NOT_FAILED_BO";
         return false;
        }
      if(!GateProvisional(s.provisional, skipWhy))
         return false;
      if(!GateChase(s.dir, s.entry, price, atr, skipWhy))
         return false;
      FillFromSetup(in, STRAT_FAILED_BO, s);
      in.invalidation = "STOP_failed_level";
      in.note = StringFormat("Failed-BO fade %s score=%d R=%.2f",
                             (s.dir > 0 ? "BUY" : "SELL"), s.score, s.rMult);
      return true;
     }

   // Phase 29 — pullback (firm H2/L2 or provisional H1/L1 via flag).
   bool              FromPullback(const GeneralSetup &s,
                                  double price, double atr,
                                  string &skipWhy, TradeIntent &in) const
     {
      ZeroMemory(in);
      if(!s.valid || s.type != SETUP_TREND_PULLBACK)
        {
         skipWhy = "NOT_PULLBACK";
         return false;
        }
      if(!GateProvisional(s.provisional, skipWhy))
         return false;
      if(!GateChase(s.dir, s.entry, price, atr, skipWhy))
         return false;
      FillFromSetup(in, STRAT_PULLBACK, s);
      in.invalidation = "STOP_pullback_extreme";
      in.note = StringFormat("Pullback %s score=%d R=%.2f%s",
                             (s.dir > 0 ? "BUY" : "SELL"), s.score, s.rMult,
                             (s.provisional ? " H1-PROV" : " H2-FIRM"));
      return true;
     }

   // Phase 29b — breakout FOLLOW (firm) / PENDING (provisional).
   bool              FromBreakout(const GeneralSetup &s,
                                  double price, double atr,
                                  string &skipWhy, TradeIntent &in) const
     {
      ZeroMemory(in);
      if(!s.valid || s.type != SETUP_BREAKOUT)
        {
         skipWhy = "NOT_BREAKOUT";
         return false;
        }
      if(!GateProvisional(s.provisional, skipWhy))
         return false;
      if(!GateChase(s.dir, s.entry, price, atr, skipWhy))
         return false;
      FillFromSetup(in, STRAT_BREAKOUT, s);
      in.invalidation = (s.provisional ? "STALE_or_ref_reclaim"
                                       : "STOP_breakout_ref");
      in.note = StringFormat("Breakout %s score=%d R=%.2f%s",
                             (s.dir > 0 ? "BUY" : "SELL"), s.score, s.rMult,
                             (s.provisional ? " PENDING-PROV" : " FOLLOW-FIRM"));
      return true;
     }

   // Phase 30 — reversal MTR (MAJOR firm / MINOR provisional) + doubles
   // (swing firm / micro provisional). Both ride the catalog setup.
   bool              FromReversal(const GeneralSetup &s,
                                  double price, double atr,
                                  string &skipWhy, TradeIntent &in) const
     {
      ZeroMemory(in);
      if(!s.valid || s.type != SETUP_REVERSAL)
        {
         skipWhy = "NOT_REVERSAL";
         return false;
        }
      if(!GateProvisional(s.provisional, skipWhy))
         return false;
      if(!GateChase(s.dir, s.entry, price, atr, skipWhy))
         return false;
      FillFromSetup(in, STRAT_REVERSAL, s);
      in.invalidation = "STOP_mtr_anchor";
      in.note = StringFormat("MTR %s score=%d R=%.2f%s",
                             (s.dir > 0 ? "BUY" : "SELL"), s.score, s.rMult,
                             (s.provisional ? " MINOR-PROV" : " MAJOR-FIRM"));
      return true;
     }

   bool              FromDouble(const GeneralSetup &s,
                                double price, double atr,
                                string &skipWhy, TradeIntent &in) const
     {
      ZeroMemory(in);
      if(!s.valid || s.type != SETUP_DOUBLE)
        {
         skipWhy = "NOT_DOUBLE";
         return false;
        }
      if(!GateProvisional(s.provisional, skipWhy))
         return false;
      if(!GateChase(s.dir, s.entry, price, atr, skipWhy))
         return false;
      FillFromSetup(in, STRAT_DOUBLE, s);
      in.invalidation = "STOP_double_level";
      in.note = StringFormat("Double %s score=%d R=%.2f%s",
                             (s.dir > 0 ? "BUY" : "SELL"), s.score, s.rMult,
                             (s.provisional ? " MICRO-PROV" : " SWING-FIRM"));
      return true;
     }
  };

#endif
