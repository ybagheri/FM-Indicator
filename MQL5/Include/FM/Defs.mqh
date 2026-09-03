//+------------------------------------------------------------------+
//| FM_Indicator.mqh : shared enums/structs                            |
//| Part of FM (Fading Measured Move) Indicator v1                     |
//+------------------------------------------------------------------+
#ifndef FM_DEFS_MQH
#define FM_DEFS_MQH

enum ENUM_FM_STATE
  {
   FM_IDLE=0,
   FM_PROJECTED=1,
   FM_POTENTIAL=2,
   FM_DEVELOPING=3,
   FM_CONFIRMED=4,
   FM_INVALIDATED=5,
   FM_COMPLETED=6
  };

enum ENUM_MM_FAMILY
  {
   MM_REGULAR=0,   // Leg1=Leg2
   MM_INVERSE=1    // failed-BO inverse
  };

enum ENUM_FM_CONTEXT
  {
   FM_CTX_TREND=0,
   FM_CTX_RANGE=1,
   FM_CTX_TRANSITION=2
  };

enum ENUM_CTX_FILTER
  {
   CTX_LOG_ONLY=0,
   CTX_DEMOTE=1,
   CTX_VETO=2
  };

enum ENUM_LOG_LEVEL
  {
   LOG_OFF=0,
   LOG_ERROR=1,
   LOG_INFO=2,
   LOG_DEBUG=3
  };

struct SwingPoint
  {
   int               bar;            // closed-bar shift at swing extreme
   double            price;
   int               dir;            // +1 swing high, -1 swing low
   int               confirmed_bar;  // last-closed bar when it confirmed
   bool              valid;
  };

struct FMSetupSnapshot
  {
   long              id;
   ENUM_MM_FAMILY    family;
   int               dir;            // +1 bull target above, -1 bear below
   double            a0_price;
   double            a1_price;
   double            b0_price;
   double            target;
   ENUM_FM_STATE     state;
   int               created_bar;
   ENUM_FM_CONTEXT   context;
   double            confidence;
  };

#endif
