//+------------------------------------------------------------------+
//| Config.mqh : CFMConfig — all inputs, presets, validation           |
//+------------------------------------------------------------------+
#ifndef FM_CONFIG_MQH
#define FM_CONFIG_MQH
#include "Defs.mqh"

class CFMConfig
  {
public:
   int               SwingK;
   double            MinLegATRMult;
   int               MinLegBars;
   int               MaxLegBars;
   double            MinPullbackRatio;
   double            MaxPullbackRatio;
   int               MaxPullbackBars;
   double            MMToleranceATRMult;
   double            MaxOvershootATRMult;
   double            ApproachATRMult;
   double            SignalClosePct;
   double            MinBodyRatio;
   double            MaxWickRatio;
   bool              RequireEngulf;
   bool              RequireFollowThrough;
   bool              EnableInverseMM;
   int               FailedBOBars;
   ENUM_CTX_FILTER   ContextFilter;
   int               MaxActiveSetups;
   int               MaxBarsForward;
   bool              UseIntrabarPotential;
   int               AtrPeriod;
   // display
   bool              ShowLegs;
   bool              ShowPullbacks;
   bool              ShowTargets;
   bool              ShowZones;
   // alerts
   bool              AlertPotential;
   bool              AlertDeveloping;
   bool              AlertConfirmed;
   bool              UseSound;
   bool              UsePush;
   bool              UseMail;
   string            SoundFile;
   // misc
   ENUM_LOG_LEVEL    LogLevel;
   int               AtrWarmupExtra;

   CFMConfig() { SetBalanced(); }

   void SetBalanced()
     {
      SwingK=3; MinLegATRMult=1.0; MinLegBars=3; MaxLegBars=100;
      MinPullbackRatio=0.15; MaxPullbackRatio=0.90; MaxPullbackBars=50;
      MMToleranceATRMult=0.25; MaxOvershootATRMult=0.50; ApproachATRMult=1.0;
      SignalClosePct=0.50; MinBodyRatio=0.30; MaxWickRatio=0.60;
      RequireEngulf=false; RequireFollowThrough=false;
      EnableInverseMM=true; FailedBOBars=5;
      ContextFilter=CTX_LOG_ONLY; MaxActiveSetups=20; MaxBarsForward=100;
      UseIntrabarPotential=false; AtrPeriod=14;
      ShowLegs=true; ShowPullbacks=true; ShowTargets=true; ShowZones=true;
      AlertPotential=true; AlertDeveloping=true; AlertConfirmed=true;
      UseSound=false; UsePush=false; UseMail=false; SoundFile="alert.wav";
      LogLevel=LOG_INFO; AtrWarmupExtra=50;
     }
   void SetConservative()
     {
      SetBalanced();
      SwingK=4; MinLegATRMult=1.5; MMToleranceATRMult=0.20; ApproachATRMult=0.75;
      MinBodyRatio=0.40; RequireFollowThrough=true;
     }
   void SetAggressive()
     {
      SetBalanced();
      SwingK=2; MinLegATRMult=0.75; MMToleranceATRMult=0.35; ApproachATRMult=1.5;
      MinBodyRatio=0.25; RequireFollowThrough=false;
     }
   // Clamp nonsense; returns false if anything was clamped.
   bool Validate()
     {
      bool ok=true;
      if(SwingK<1) { SwingK=1; ok=false; }
      if(SwingK>10) { SwingK=10; ok=false; }
      if(MinLegBars<1) { MinLegBars=1; ok=false; }
      if(MaxLegBars<MinLegBars) { MaxLegBars=MinLegBars; ok=false; }
      if(MinPullbackRatio<0.0) { MinPullbackRatio=0.0; ok=false; }
      if(MaxPullbackRatio>1.5) { MaxPullbackRatio=1.5; ok=false; }
      if(MaxPullbackRatio<MinPullbackRatio) { MaxPullbackRatio=MinPullbackRatio; ok=false; }
      if(MMToleranceATRMult<=0.0) { MMToleranceATRMult=0.25; ok=false; }
      if(MaxOvershootATRMult<MMToleranceATRMult) { MaxOvershootATRMult=MMToleranceATRMult; ok=false; }
      if(ApproachATRMult<MMToleranceATRMult) { ApproachATRMult=MMToleranceATRMult; ok=false; }
      if(SignalClosePct<0.1) { SignalClosePct=0.1; ok=false; }
      if(SignalClosePct>1.0) { SignalClosePct=1.0; ok=false; }
      if(MaxActiveSetups<1) { MaxActiveSetups=1; ok=false; }
      if(MaxActiveSetups>100) { MaxActiveSetups=100; ok=false; }
      if(AtrPeriod<2) { AtrPeriod=2; ok=false; }
      if(FailedBOBars<1) { FailedBOBars=1; ok=false; }
      return ok;
     }
  };

#endif
