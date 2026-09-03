//+------------------------------------------------------------------+
//| Alerts.mqh : throttled multi-channel alerts, alert-once upstream   |
//+------------------------------------------------------------------+
#ifndef FM_ALERTS_MQH
#define FM_ALERTS_MQH
#include "Defs.mqh"
#include "Config.mqh"

class CAlertManager
  {
private:
   datetime          m_last_alert_time;
   int               m_cooldown_sec;
public:
   CAlertManager(): m_last_alert_time(0), m_cooldown_sec(60) {}
   void SetCooldown(int s) { m_cooldown_sec=s; }

   void Dispatch(const CFMConfig &cfg, long id, ENUM_FM_STATE st, int mm_dir,
                 string symbol, ENUM_TIMEFRAMES tf, double price, double target)
     {
      bool enabled = (st==FM_POTENTIAL && cfg.AlertPotential) ||
                     (st==FM_DEVELOPING && cfg.AlertDeveloping) ||
                     (st==FM_CONFIRMED && cfg.AlertConfirmed);
      if(!enabled) return;
      datetime now = TimeCurrent();
      if(now - m_last_alert_time < m_cooldown_sec && st != FM_CONFIRMED) return;
      m_last_alert_time = now;
      string sname = (st==FM_POTENTIAL?"POTENTIAL":(st==FM_DEVELOPING?"DEVELOPING":"CONFIRMED"));
      // fade direction: bull MM (dir+1) fades SHORT, bear MM fades LONG
      string side = (mm_dir > 0 ? "SELL" : (mm_dir < 0 ? "BUY" : ""));
      string msg = StringFormat("FM %s %s #%d %s %s @%.5f T=%.5f",
                                sname, side, (int)id, symbol,
                                EnumToString(tf), price, target);
      Alert(msg);
      if(cfg.UseSound) PlaySound(cfg.SoundFile);
      if(cfg.UsePush) SendNotification(msg);
      if(cfg.UseMail) SendMail("FM " + sname, msg);
     }
  };

#endif
