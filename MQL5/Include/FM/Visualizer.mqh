//+------------------------------------------------------------------+
//| Visualizer.mqh : FM_<id>_* object lifecycle                        |
//+------------------------------------------------------------------+
#ifndef FM_VISUALIZER_MQH
#define FM_VISUALIZER_MQH
#include "Defs.mqh"
#include "Config.mqh"
#include "FMEngine.mqh"

class CVisualizer
  {
private:
   string Prefix(long id) const { return StringFormat("FM_%d_", (int)id); }

   void EnsureTrend(string name, datetime t1, double p1, datetime t2, double p2, color c, int width, bool ray)
     {
      if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   void EnsureHLine(string name, double price, color c, int style, int width)
     {
      if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
     }
   void EnsureLabel(string name, datetime t, double price, string text, color c)
     {
      if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectMove(0, name, 0, t, price);
     }

public:
   void Sync(const MqlRates &rates[], int count, CFMEngine &engine, const CFMConfig &cfg)
     {
      // index desired ids
      for(int i = 0; i < engine.ActiveCount(); i++)
        {
         CFMSetup s;
         if(!engine.GetSetup(i, s)) continue;
         if(s.state==FM_INVALIDATED) { DeleteSetup(s.id); continue; }
         string px = Prefix(s.id);
         color tgtColor = (s.state==FM_CONFIRMED ? clrLime :
                           s.state==FM_DEVELOPING ? clrOrange : clrDodgerBlue);
         datetime tB0 = (s.b0.bar<count)? rates[s.b0.bar].time : TimeCurrent();
         datetime tA1 = (s.a1.bar<count)? rates[s.a1.bar].time : TimeCurrent();
         datetime tA0 = (s.a0.bar<count)? rates[s.a0.bar].time : TimeCurrent();
         if(cfg.ShowLegs) EnsureTrend(px+"LEG", tA0, s.a0.price, tA1, s.a1.price, clrGray, 1, false);
         if(cfg.ShowPullbacks) EnsureTrend(px+"PB", tA1, s.a1.price, tB0, s.b0.price, clrSilver, 1, false);
         if(cfg.ShowTargets) EnsureHLine(px+"TGT", s.target, tgtColor, STYLE_DASH, 1);
         if(cfg.ShowZones)
           {
            string zname = px+"ZONE";
            // zone = rectangle target±tol between B0 time and now
            if(ObjectFind(0, zname) < 0)
               ObjectCreate(0, zname, OBJ_RECTANGLE, 0, tB0, s.target, TimeCurrent(), s.target);
            ObjectSetInteger(0, zname, OBJPROP_COLOR, tgtColor);
            ObjectSetInteger(0, zname, OBJPROP_FILL, true);
            ObjectSetInteger(0, zname, OBJPROP_BACK, true);
            ObjectMove(0, zname, 1, TimeCurrent(), s.target);
           }
         string st = (s.state==FM_PROJECTED?"MM":(s.state==FM_POTENTIAL?"POTENTIAL":(s.state==FM_DEVELOPING?"DEVELOPING":(s.state==FM_CONFIRMED?"CONFIRMED ✓":"DONE"))));
         string fam = (s.family==MM_INVERSE?"INV ":"");
         EnsureLabel(px+"LABEL", TimeCurrent(), s.target,
                     StringFormat("%s%s #%d T=%.5f", fam, st, (int)s.id, s.target), tgtColor);
         // state glyph at confirmation: arrow object on B0 bar handled via buffer; label suffices
        }
     }

   void DeleteSetup(long id)
     {
      string px = Prefix(id);
      string names[5] = {px+"LEG", px+"PB", px+"TGT", px+"ZONE", px+"LABEL"};
      for(int i=0;i<5;i++) if(ObjectFind(0, names[i])>=0) ObjectDelete(0, names[i]);
     }

   void DeleteAll()
     {
      ObjectsDeleteAll(0, "FM_");
     }
  };

#endif
