//+------------------------------------------------------------------+
//| DecisionEngine.mqh : BUY/SELL/WAIT/NO_TRADE + machine reasons      |
//| Phase 8 of bar-by-bar engine (see docs/DECISION_ENGINE.md).         |
//| Stateless, closed bars only, read-only (DEBUG log + FM_DECISION    |
//| label by the hook; never gates FM, never alerts, never trades).    |
//+------------------------------------------------------------------+
#ifndef FM_DECISIONENGINE_MQH
#define FM_DECISIONENGINE_MQH
#include "Config.mqh"
#include "Defs.mqh"
#include "GeneralSetups.mqh"
#include "MarketState.mqh"

enum ENUM_DECISION_ACTION
  {
   DEC_NO_TRADE=0,
   DEC_WAIT=1,
   DEC_BUY=2,
   DEC_SELL=3
  };

enum ENUM_DECISION_REASON
  {
   REASON_OK=0,
   REASON_DISABLED=1,
   REASON_NO_SETUP=2,
   REASON_BARBWIRE=3,
   REASON_MID_RANGE=4,
   REASON_CONFLICT=5,
   REASON_NO_EDGE=6,
   REASON_LOW_SCORE=7,
   REASON_LOW_RR=8,
   REASON_LATE_ENTRY=9,
   REASON_TRAP_REPEAT=10
  };

struct DecisionContext
  {
   ENUM_MARKET_STATE state;      // winner (UNKNOWN/TRANSITION → NO_EDGE)
   int               pct[6];     // state pcts (sum 100 when valid)
   bool              pctValid;   // false (e.g. UNKNOWN) → conflict guard off
   bool              midRange;   // hook: RANGE winner + close in middle third
   bool              barbwire;   // hook: BarFeatures.barbwire at analysis bar
   double            close;      // close at analysis bar (late-entry check)
   int               failCount;  // hook: FAILED outcomes in last 20 bars
   bool              hasFollow;  // hook: any FOLLOW_THROUGH in same window
  };

struct Decision
  {
   ENUM_DECISION_ACTION action;
   ENUM_DECISION_REASON reason;
   int               dir;        // setup dir echo (±1, 0 when no setup)
   ENUM_SETUP_TYPE   setupType;  // setup type echo
   double            entry;
   double            stop;
   double            objective;
   double            rMult;
   int               score;
  };

class CDecisionEngine
  {
public:
   // Conflict: valid pcts with top-two gap <= ConflictPpts (spec §2).
   static bool IsConflict(const DecisionContext &ctx, const CFMConfig &cfg)
     {
      if(!ctx.pctValid) return false;
      int sum=0;
      for(int i=0;i<6;i++) sum+=ctx.pct[i];
      if(sum!=100) return false;
      int top1=-1, top2=-1;
      for(int i=0;i<6;i++)
        {
         if(top1<0 || ctx.pct[i]>ctx.pct[top1]) { top2=top1; top1=i; }
         else if(top2<0 || ctx.pct[i]>ctx.pct[top2]) top2=i;
        }
      if(top1<0 || top2<0) return false;
      int gap=ctx.pct[top1]-ctx.pct[top2];
      int th=cfg.DecisionConflictPpts;
      if(th<5) th=5;
      if(th>30) th=30;
      return (gap<=th);
     }

   // Late: price already ran past entry toward objective (chasing).
   static bool IsLate(const GeneralSetup &s, double close, double atr,
                      const CFMConfig &cfg)
     {
      if(!s.valid) return false;
      if(atr<=0) return false;
      double late=cfg.MaxLateEntryATRMult*atr;
      if(s.dir>0) return (close-s.entry>late);
      if(s.dir<0) return (s.entry-close>late);
      return false;
     }

   // Pure decision (spec §3 priority). atr = ATR at the analysis bar.
   static Decision Decide(const GeneralSetup &s, const DecisionContext &ctx,
                          double atr, const CFMConfig &cfg)
     {
      Decision d;
      d.action=DEC_NO_TRADE; d.reason=REASON_NO_SETUP;
      d.dir=s.dir; d.setupType=s.type;
      d.entry=s.entry; d.stop=s.stop; d.objective=s.objective;
      d.rMult=s.rMult; d.score=s.score;
      int minScore=cfg.MinDecisionScore;
      if(minScore<0) minScore=0;
      if(minScore>100) minScore=100;
      int maxFail=cfg.DecisionMaxFailedBO;
      if(maxFail<1) maxFail=1;
      if(maxFail>5) maxFail=5;
      if(!cfg.EnableDecision) { d.reason=REASON_DISABLED; return d; }
      if(!s.valid) { d.reason=REASON_NO_SETUP; return d; }
      if(ctx.barbwire) { d.reason=REASON_BARBWIRE; return d; }
      if(ctx.midRange) { d.reason=REASON_MID_RANGE; return d; }
      if(IsConflict(ctx,cfg)) { d.reason=REASON_CONFLICT; return d; }
      if(ctx.state==MS_UNKNOWN || ctx.state==MS_TRANSITION)
        { d.action=DEC_WAIT; d.reason=REASON_NO_EDGE; return d; }
      if(s.score<minScore) { d.action=DEC_WAIT; d.reason=REASON_LOW_SCORE; return d; }
      if(!s.rrOK) { d.action=DEC_WAIT; d.reason=REASON_LOW_RR; return d; }
      if(IsLate(s,ctx.close,atr,cfg)) { d.action=DEC_WAIT; d.reason=REASON_LATE_ENTRY; return d; }
      if(ctx.failCount>=maxFail && !ctx.hasFollow)
        { d.reason=REASON_TRAP_REPEAT; return d; }
      d.reason=REASON_OK;
      if(s.dir>0) d.action=DEC_BUY;
      else if(s.dir<0) d.action=DEC_SELL;
      else { d.action=DEC_WAIT; d.reason=REASON_NO_SETUP; }
      return d;
     }

   static string ActionName(ENUM_DECISION_ACTION a)
     {
      switch(a)
        {
         case DEC_BUY:      return "BUY";
         case DEC_SELL:     return "SELL";
         case DEC_WAIT:     return "WAIT";
         default:           return "NO_TRADE";
        }
     }

   static string ReasonName(ENUM_DECISION_REASON r)
     {
      switch(r)
        {
         case REASON_OK:          return "OK";
         case REASON_DISABLED:    return "DISABLED";
         case REASON_NO_SETUP:    return "NO_SETUP";
         case REASON_BARBWIRE:    return "BARBWIRE";
         case REASON_MID_RANGE:   return "MID_RANGE";
         case REASON_CONFLICT:    return "CONFLICT";
         case REASON_NO_EDGE:     return "NO_EDGE";
         case REASON_LOW_SCORE:   return "LOW_SCORE";
         case REASON_LOW_RR:      return "LOW_RR";
         case REASON_LATE_ENTRY:  return "LATE_ENTRY";
         case REASON_TRAP_REPEAT: return "TRAP_REPEAT";
         default:                 return "UNKNOWN";
        }
     }

   static string Describe(const Decision &d)
     {
      return StringFormat("DECISION %s %s %s/%s R=%.2f score=%d",
         ActionName(d.action), CGeneralSetups::TypeName(d.setupType),
         (d.dir>0 ? "BUY" : (d.dir<0 ? "SELL" : "FLAT")),
         ReasonName(d.reason), d.rMult, d.score);
     }
  };

#endif
