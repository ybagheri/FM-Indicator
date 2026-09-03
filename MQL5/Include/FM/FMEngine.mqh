//+------------------------------------------------------------------+
//| FMEngine.mqh : per-setup state machine, caps, alert-once           |
//+------------------------------------------------------------------+
#ifndef FM_ENGINE_MQH
#define FM_ENGINE_MQH
#include "Defs.mqh"
#include "Config.mqh"
#include "Confirmation.mqh"
#include "MeasuredMove.mqh"
#include "Context.mqh"
#include "Logger.mqh"

class CFMSetup
  {
public:
   long              id;
   ENUM_MM_FAMILY    family;
   int               dir;
   SwingPoint        a0, a1, b0;
   double            mm_range;
   double            target;
   ENUM_FM_STATE     state;
   int               bars_since_creation;
   datetime          created_time;
   int               created_shift_anchor; // count-based anchor not needed; use age counter
   bool              alerted_potential;
   bool              alerted_developing;
   bool              alerted_confirmed;
   ENUM_FM_CONTEXT   context;
   double            confidence;
   int               state_bar_age; // bars since last transition (for follow-through)
   datetime          signal_time;   // bar time of last transition (for BUY/SELL arrows)

   CFMSetup(): id(0), family(MM_REGULAR), dir(0), mm_range(0), target(0),
               state(FM_PROJECTED), bars_since_creation(0), created_time(0),
               created_shift_anchor(0), alerted_potential(false),
               alerted_developing(false), alerted_confirmed(false),
               context(FM_CTX_TRANSITION), confidence(0.5), state_bar_age(0), signal_time(0) {}
  };

class CFMEngine
  {
private:
   CFMSetup          m_setups[];
   long              m_next_id;
   CLegEqualityMM    m_mm;
   CContextClassifier m_ctx;
   CLogger          *m_log;

   void EvictIfNeeded(const CFMConfig &cfg, const MqlRates &rates[], int count)
     {
      int n = ArraySize(m_setups);
      if(n <= cfg.MaxActiveSetups) return;
      // evict farthest-from-target INVALIDATED/COMPLETED first, else oldest
      int victim = -1;
      for(int i = 0; i < n; i++)
         if(m_setups[i].state==FM_INVALIDATED || m_setups[i].state==FM_COMPLETED) { victim=i; break; }
      if(victim < 0) victim = 0; // oldest
      for(int i = victim; i < n - 1; i++) m_setups[i] = m_setups[i+1];
      ArrayResize(m_setups, n - 1);
     }

   bool SameProjection(const Projection &p) const
     {
      for(int i = 0; i < ArraySize(m_setups); i++)
        {
         if(m_setups[i].b0.bar==p.b0.bar && m_setups[i].dir==p.dir &&
            MathAbs(m_setups[i].target-p.target) < _Point*2 &&
            m_setups[i].state!=FM_INVALIDATED) return true;
        }
      return false;
     }

   void AddProjection(const Projection &p, datetime tnow)
     {
      CFMSetup s;
      s.id = m_next_id++;
      s.family = p.family; s.dir = p.dir;
      s.a0=p.a0; s.a1=p.a1; s.b0=p.b0;
      s.mm_range=p.mm_range; s.target=p.target;
      s.state=FM_PROJECTED; s.created_time=tnow;
      s.bars_since_creation=0; s.state_bar_age=0;
      int n=ArraySize(m_setups);
      ArrayResize(m_setups, n+1);
      m_setups[n]=s;
     }

public:
   CFMEngine(): m_next_id(1), m_log(NULL) {}
   void SetLogger(CLogger *l) { m_log=l; }
   void Reset() { ArrayResize(m_setups, 0); m_next_id=1; }
   int ActiveCount() const { return ArraySize(m_setups); }
   bool GetSetup(int i, CFMSetup &s) const
     {
      if(i<0||i>=ArraySize(m_setups)) return false;
      s=m_setups[i]; return true;
     }

   // Form projections from confirmed swings (call after Swings.Update).
   // swings[] chrono order (oldest→newest).
   void FormProjections(const SwingPoint &swings[], const MqlRates &rates[], int count,
                        const CFMConfig &cfg, const CATR &atr, datetime tnow)
     {
      int n = ArraySize(swings);
      if(n < 3) return;
      // try most recent triples only (bounded work): last 6 swings
      int start = (n > 8 ? n - 8 : 0);
      for(int i = start; i + 2 < n; i++)
        {
         Projection p; p.valid=false;
         double aref = atr.At(swings[i+1].bar);
         if(aref <= 0) continue;
         if(m_mm.Project(swings[i], swings[i+1], swings[i+2], cfg, aref, p))
           {
            if(!SameProjection(p))
              {
               AddProjection(p, tnow);
               if(m_log!=NULL) m_log.Debug(StringFormat("new projection id=%d dir=%d T=%.5f", (int)(m_next_id-1), p.dir, p.target));
              }
           }
        }
      // inverse family: build LegInfo from last legs
      if(cfg.EnableInverseMM)
        {
         for(int i = start; i + 1 < n; i++)
           {
            LegInfo leg;
            leg.a0=swings[i]; leg.a1=swings[i+1];
            if(leg.a0.dir==-1 && leg.a1.dir==+1) leg.dir=+1;
            else if(leg.a0.dir==+1 && leg.a1.dir==-1) leg.dir=-1;
            else continue;
            leg.range = MathAbs(leg.a1.price - leg.a0.price);
            double aref = atr.At(leg.a1.bar);
            Projection p;
            if(CInverseMMHelper::TryInverse(rates, count, leg, cfg, aref, p))
               if(!SameProjection(p)) AddProjection(p, tnow);
           }
        }
      // enforce cap placeholder (real eviction after update)
     }

   // Advance state machine one closed bar. `b` = newest closed shift (=1).
   // Evaluated oldest-setup-first; max one transition per setup per bar.
   void Update(const MqlRates &rates[], int count, int b,
               const CFMConfig &cfg, const CATR &atr)
     {
      double a = atr.At(b);
      if(a <= 0) return;
      double tol = cfg.MMToleranceATRMult * a;
      double approach = cfg.ApproachATRMult * a;
      double overmax = cfg.MaxOvershootATRMult * a;

      for(int i = 0; i < ArraySize(m_setups); i++)
         {
          if(m_setups[i].state==FM_INVALIDATED || m_setups[i].state==FM_COMPLETED) continue;
          m_setups[i].bars_since_creation++;
          m_setups[i].state_bar_age++;
          if(m_setups[i].bars_since_creation > cfg.MaxBarsForward) { m_setups[i].state=FM_INVALIDATED; continue; }

          MqlRates bar = rates[b];
          double extreme = (m_setups[i].dir > 0) ? bar.high : bar.low;
          double dist = (m_setups[i].dir > 0) ? (m_setups[i].target - extreme) : (extreme - m_setups[i].target);
          // invalidation by close overshoot
          double over = (m_setups[i].dir > 0) ? (bar.close - m_setups[i].target) : (m_setups[i].target - bar.close);
          if(over > overmax) { m_setups[i].state=FM_INVALIDATED; continue; }

          // context
          ENUM_FM_CONTEXT cx; double cf;
          m_ctx.Classify(rates, count, b, a, cx, cf);
          m_setups[i].context=cx; m_setups[i].confidence=cf;
          bool veto = (cfg.ContextFilter==CTX_VETO && cf < 0.3 &&
                       ((cx==FM_CTX_TREND && 1==1))); // weak-context veto (conservative)

          switch(m_setups[i].state)
            {
             case FM_PROJECTED:
                if(!veto && dist >= 0 && dist <= approach)
                  { m_setups[i].state=FM_POTENTIAL; m_setups[i].state_bar_age=0; m_setups[i].signal_time=rates[b].time; }
                break;
             case FM_POTENTIAL:
                if(MathAbs(extreme - m_setups[i].target) <= tol)
                  {
                   if(CConfirmation::ExhaustionAny(rates, count, b, m_setups[i].dir, a))
                     { m_setups[i].state=FM_DEVELOPING; m_setups[i].state_bar_age=0; m_setups[i].signal_time=rates[b].time; }
                  }
                else if(dist < 0 || dist > approach + tol)
                  {
                   // left zone without touching: back to PROJECTED (keeps history honest)
                   if(dist < 0 && MathAbs(extreme - m_setups[i].target) > tol)
                     { /* penetrated but no exhaustion → stay POTENTIAL one more bar */ }
                  }
                break;
             case FM_DEVELOPING:
               {
                int f = -m_setups[i].dir;
                // signal bar may be current bar b (closed) — must be within tol of target
                double sigExtreme = (m_setups[i].dir > 0) ? bar.high : bar.low;
                bool nearT = (MathAbs(sigExtreme - m_setups[i].target) <= tol + approach*0.0 + tol);
                if(CConfirmation::IsSignalBar(rates, count, b, f, cfg) && nearT)
                  {
                   bool ok = true;
                   if(cfg.RequireFollowThrough)
                     {
                      // need next-bar confirmation: stay DEVELOPING until older-bar... we check
                      // bar b-1 only if it is closed (b==1 → b-1==0 forming → not allowed)
                      ok = false; // wait one more bar; handled below via state_bar_age
                     }
                   if(ok)
                     {
                      if(cfg.ContextFilter==CTX_DEMOTE && cf < 0.5)
                        { /* stay DEVELOPING */ }
                      else { m_setups[i].state=FM_CONFIRMED; m_setups[i].state_bar_age=0; m_setups[i].signal_time=rates[b].time; }
                     }
                  }
                // delayed follow-through: if previous bar was signal and current confirms
                if(m_setups[i].state==FM_DEVELOPING && cfg.RequireFollowThrough && m_setups[i].state_bar_age>=1 && b>=2)
                  {
                   if(CConfirmation::IsSignalBar(rates, count, b+1, f, cfg) &&
                      CConfirmation::FollowThrough(rates, count, b+1, f))
                     {
                      double pe = (m_setups[i].dir>0)? rates[b+1].high : rates[b+1].low;
                      if(MathAbs(pe - m_setups[i].target) <= 2*tol) { m_setups[i].state=FM_CONFIRMED; m_setups[i].state_bar_age=0; m_setups[i].signal_time=rates[b].time; }
                     }
                  }
                // lost zone → back to POTENTIAL
                if(m_setups[i].state==FM_DEVELOPING && MathAbs(extreme - m_setups[i].target) > tol + approach)
                  { m_setups[i].state=FM_POTENTIAL; m_setups[i].state_bar_age=0; m_setups[i].signal_time=rates[b].time; }
                break;
               }
             case FM_CONFIRMED:
                m_setups[i].state=FM_COMPLETED;
                break;
             default: break;
            }
         }
      // prune invalidated beyond cap
      int w=0;
      for(int i=0;i<ArraySize(m_setups);i++)
        {
         if(m_setups[i].state==FM_INVALIDATED && i < ArraySize(m_setups)-cfg.MaxActiveSetups)
            continue; // drop old invalidated
         if(i!=w) m_setups[w]=m_setups[i];
         w++;
        }
      ArrayResize(m_setups, w);
     }

   // Mark alerted; returns true if this (id,state) was not yet alerted.
   bool ClaimAlert(long id, ENUM_FM_STATE st)
     {
      for(int i=0;i<ArraySize(m_setups);i++)
        {
         if(m_setups[i].id!=id) continue;
         if(st==FM_POTENTIAL && !m_setups[i].alerted_potential)
           { m_setups[i].alerted_potential=true; return true; }
         if(st==FM_DEVELOPING && !m_setups[i].alerted_developing)
           { m_setups[i].alerted_developing=true; return true; }
         if(st==FM_CONFIRMED && !m_setups[i].alerted_confirmed)
           { m_setups[i].alerted_confirmed=true; return true; }
         return false;
        }
      return false;
     }
  };

#endif
