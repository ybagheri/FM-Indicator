//+------------------------------------------------------------------+
//| SessionMeasuredMove.mqh : v1.3 pre-open session-range dual        |
//| projection (docs/SESSION_MM.md)                                    |
//|                                                                    |
//| Setup this models: before the US cash session opens (RTH), the     |
//| overnight/Globex range on an index like US30/YM is marked as a     |
//| trading range. UNLIKE CRangeHeightMM (which only fires AFTER a     |
//| confirmed breakout, and only on the side that broke), this family  |
//| projects BOTH sides at once, before either side has broken:        |
//|   upside target  = rangeHigh + rangeHeight                         |
//|   downside target = rangeLow  - rangeHeight                        |
//| i.e. the classic "double the range" measured-move technique,       |
//| drawn pre-emptively on both sides of the pre-open range so the     |
//| existing FM (Fading Measured Move) state machine can watch price   |
//| approach whichever side actually breaks and fade it at the         |
//| projected 2x-range zone — exactly like every other MM family,      |
//| just with two live candidates and an earlier (pre-breakout) birth. |
//|                                                                    |
//| Non-repainting / closed-bars-only, like every sibling class here:  |
//| it fires exactly once per calendar day, the first closed bar whose |
//| time is at/after CFMConfig.SessionCutoffHour:Min (broker/server     |
//| time — set this to your broker's US cash-open time, NOT UTC).      |
//+------------------------------------------------------------------+
#ifndef FM_SESSIONMEASUREDMOVE_MQH
#define FM_SESSIONMEASUREDMOVE_MQH
#include "Defs.mqh"
#include "Config.mqh"
#include "MeasuredMove.mqh" // Projection struct

class CSessionRangeMM
  {
public:
   // rates[] series (rates[1] = newest closed bar). Emits BOTH outUp and
   // outDown together, exactly once per calendar day, at the first closed
   // bar on/after cfg.SessionCutoffHour:Min. Everything before that bar in
   // the same day returns false (window not reached yet); everything after
   // it the same day also returns false (already emitted for today).
   static bool ProjectPair(const MqlRates &rates[], int count, const CFMConfig &cfg,
                           double atr_ref, Projection &outUp, Projection &outDown)
     {
      outUp.valid = false;
      outDown.valid = false;
      if(!cfg.EnableSessionMM || atr_ref <= 0) return false;
      if(count < 2) return false;

      MqlDateTime dtBar1;
      TimeToStruct(rates[1].time, dtBar1);

      int barMinutes    = dtBar1.hour * 60 + dtBar1.min;
      int cutoffMinutes = cfg.SessionCutoffHour * 60 + cfg.SessionCutoffMin;
      if(barMinutes < cutoffMinutes)
         return false; // today's cutoff not reached yet — nothing to do

      // Once-per-calendar-day guard (function-local static: persists for the
      // lifetime of this indicator/EA instance, same pattern the rest of the
      // engine relies on for its per-bar, non-repainting evaluation).
      int dayKey = dtBar1.year * 10000 + dtBar1.mon * 100 + dtBar1.day;
      static int s_lastDayKey = 0;
      if(dayKey == s_lastDayKey)
         return false; // already emitted (or attempted) today
      s_lastDayKey = dayKey; // mark "handled" now, success or not — never retry same day

      int startMinutes = cfg.SessionStartHour * 60 + cfg.SessionStartMin;
      bool wraps = (startMinutes >= cutoffMinutes); // e.g. 18:00 → 09:30 next day

      double hh = 0.0, ll = 0.0;
      int hiBar = -1, loBar = -1, barsCounted = 0;
      int cap = MathMin(cfg.SessionMaxBars, count - 1);

      for(int shift = 1; shift <= cap; shift++)
        {
         MqlDateTime dt;
         TimeToStruct(rates[shift].time, dt);
         int mins = dt.hour * 60 + dt.min;
         int keyOfBar = dt.year * 10000 + dt.mon * 100 + dt.day;

         bool inSession;
         if(!wraps)
           {
            // same-day window, e.g. 06:00 -> 09:30
            inSession = (keyOfBar == dayKey && mins >= startMinutes && mins < cutoffMinutes);
            // stop once we've walked back before the window on the target day
            if(keyOfBar == dayKey && mins < startMinutes) break;
            if(keyOfBar < dayKey) break;
           }
         else
           {
            // overnight window, e.g. 18:00 (prev day) -> 09:30 (today)
            bool onCutoffDay = (keyOfBar == dayKey && mins < cutoffMinutes);
            bool onPrevDay   = (keyOfBar < dayKey && mins >= startMinutes);
            inSession = (onCutoffDay || onPrevDay);
            // stop once we've walked back more than one calendar day short of
            // the session start (bounded, safety net against odd data gaps)
            if(keyOfBar < dayKey && mins < startMinutes) break;
            if(dayKey - keyOfBar > 1) break;
           }

         if(!inSession) continue;

         if(hiBar < 0 || rates[shift].high > hh) { hh = rates[shift].high; hiBar = shift; }
         if(loBar < 0 || rates[shift].low  < ll) { ll = rates[shift].low;  loBar = shift; }
         barsCounted++;
        }

      if(barsCounted < cfg.SessionMinBars)
         return false; // not enough bars in the window (short history / gaps)

      double height = hh - ll;
      if(height < cfg.MinLegATRMult * atr_ref)
         return false; // session range too small to bother projecting

      // Upside candidate: if price breaks above the session high, fade back
      // down from hh+height. Objective (b0.price) = the range's own edge —
      // same convention CRangeHeightMM uses (magnet before the full target).
      outUp.valid = true; outUp.family = MM_SESSION; outUp.dir = +1;
      outUp.a0.bar = loBar; outUp.a0.price = ll; outUp.a0.dir = -1; outUp.a0.valid = true;
      outUp.a1.bar = hiBar; outUp.a1.price = hh; outUp.a1.dir = +1; outUp.a1.valid = true;
      outUp.b0.bar = 1;     outUp.b0.price = hh; outUp.b0.dir  = +1; outUp.b0.valid = true;
      outUp.mm_range = height; outUp.target = hh + height;

      // Downside candidate: mirror image.
      outDown.valid = true; outDown.family = MM_SESSION; outDown.dir = -1;
      outDown.a0.bar = hiBar; outDown.a0.price = hh; outDown.a0.dir = +1; outDown.a0.valid = true;
      outDown.a1.bar = loBar; outDown.a1.price = ll; outDown.a1.dir = -1; outDown.a1.valid = true;
      outDown.b0.bar = 1;     outDown.b0.price = ll; outDown.b0.dir  = -1; outDown.b0.valid = true;
      outDown.mm_range = height; outDown.target = ll - height;

      return true;
     }
  };

#endif
