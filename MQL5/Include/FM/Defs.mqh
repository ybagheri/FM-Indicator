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
    MM_INVERSE=1,   // failed-BO inverse
    MM_RANGE=2,     // v1.2: trading-range height breakout
    MM_CHANNEL=3,   // v1.2: shallow-pullback channel continuation
    MM_GAP=4        // v1.2: measuring-gap projection
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

enum ENUM_FM_PRICE_MODE
  {
   FM_PRICE_HIGHLOW=0, // candle extremes (default): swings/legs/targets on H/L
   FM_PRICE_CLOSE=1    // line-chart mode: swings/legs/targets/distances on Close
  };

// Phase 3 market-state engine (docs/MARKET_STATE.md §7). BO / pullback /
// reversal lifecycle states live in dedicated engines by design:
// ENUM_BO_OUTCOME (Phase 4), ENUM_REV_VERDICT (Phase 5), ENUM_SETUP_TYPE
// (Phase 7, GeneralSetups.mqh), ENUM_DECISION_ACTION/REASON (Phase 8,
// DecisionEngine.mqh) — not as members here.
enum ENUM_MARKET_STATE
  {
   MS_UNKNOWN=0,
   MS_BULL_TREND=1,
   MS_BEAR_TREND=2,
   MS_BULL_CHANNEL=3,
   MS_BEAR_CHANNEL=4,
   MS_TRADING_RANGE=5,
   MS_BREAKOUT_MODE=6,
   MS_TRANSITION=7
  };

// Phase 4 breakout lifecycle (docs/BREAKOUT_ENGINE.md §7). Full breakout
// setup states (BULL_BREAKOUT etc.) belong to the Phase-7 setup engine.
enum ENUM_BO_OUTCOME
  {
   BO_NONE=0,
   BO_PENDING=1,
   BO_FOLLOW_THROUGH=2,
   BO_FAILED=3
  };

// Phase 5 reversal verdicts (docs/REVERSAL_ENGINE.md §5). Full reversal
// setup states belong to the Phase-7 setup engine.
enum ENUM_REV_VERDICT
  {
   REV_NONE=0,
   REV_MINOR=1,
   REV_MAJOR=2
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
