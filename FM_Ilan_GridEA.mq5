//+------------------------------------------------------------------+
//| FM_Ilan_GridEA.mq5                                               |
//| Grid + Martingale + Basket Break-Even execution engine (Ilan1)   |
//| driven by a selectable entry engine: Manual / MA3 Cross / the    |
//| FM-Indicator strategy suite (Pullback, Breakout, Reversal,       |
//| Double, Measured-Move Fade, Failed-Breakout, or AUTO contest).   |
//|                                                                    |
//| Requires the FM-Indicator include library at MQL5/Include/FM/... |
//| (ship this file next to that folder, same as FM_EA.mq5).         |
//|                                                                    |
//| Base grid/martingale engine adapted from                          |
//| Ilan1_MartingaleGrid_MT5.mq5 v1.30. Entry logic extended so the   |
//| basket-management engine can be driven by the FM-Indicator's      |
//| shared analysis + strategy-selection pipeline (Analysis.mqh,     |
//| StrategyRegistry.mqh, ParityDecision.mqh) instead of only manual  |
//| direction or a 3-MA cross.                                        |
//+------------------------------------------------------------------+
#property copyright "Ilan1 MT5 conversion + FM-Indicator strategy engine"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

// FM-Indicator shared engine (read-only analysis — no orders placed by it;
// this EA's own grid/martingale layer below is the only thing that trades).
#include <FM/Analysis.mqh>
#include <FM/StrategyRegistry.mqh>
#include <FM/ParityDecision.mqh>

CTrade trade;

//====================================================================
// ENUMS
//====================================================================
enum EntryMode
{
   ENTRY_MANUAL       = 0,   // جهت دستی (InpManualDirection)
   ENTRY_MA3_CROSS    = 1,   // هم‌راستایی سه میانگین متحرک (روش قدیمی Ilan1)
   ENTRY_FM_AUTO      = 2,   // FM-Indicator: مسابقه AUTO بین همه استراتژی‌های فعال
   ENTRY_FM_PULLBACK  = 3,   // FM-Indicator: فقط Trend Pullback (H1/H2/L1/L2)
   ENTRY_FM_BREAKOUT  = 4,   // FM-Indicator: فقط Breakout / Follow-Through
   ENTRY_FM_REVERSAL  = 5,   // FM-Indicator: فقط Major Trend Reversal (MTR)
   ENTRY_FM_DOUBLE    = 6,   // FM-Indicator: فقط Double Top/Bottom
   ENTRY_FM_FADE      = 7,   // FM-Indicator: فقط Measured-Move Fade
   ENTRY_FM_FAILED_BO = 8    // FM-Indicator: فقط Failed-Breakout Fade
};

enum InitialDirection
{
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = 2
};

//====================================================================
// INPUTS
//====================================================================
input group "=== Core ==="
input long              InpMagic                  = 119202401;
input EntryMode         InpEntryMode              = ENTRY_MA3_CROSS;
input InitialDirection  InpManualDirection        = DIR_NONE;
input bool              InpTradeOnNewBar          = false;

input group "=== MA3 Cross Entry (only if InpEntryMode = ENTRY_MA3_CROSS) ==="
input int               InpFastMAPeriod           = 3;
input int               InpMediumMAPeriod         = 8;
input int               InpSlowMAPeriod           = 21;
input ENUM_MA_METHOD    InpMAMethod               = MODE_EMA;

input group "=== FM-Indicator Strategy Engine (only if InpEntryMode = ENTRY_FM_*) ==="
input int               InpFMHistoryBars          = 1500;   // closed bars fed to the analysis engine
input bool              InpApplyStructuralVeto    = true;   // honor BARBWIRE/MID_RANGE/CONFLICT/NO_EDGE/TRAP_REPEAT vetoes
input int               InpAutoTrendBonus         = 10;     // ENTRY_FM_AUTO only
input int               InpAutoProvPenalty        = 5;      // ENTRY_FM_AUTO only
input int               InpAutoRRBonus            = 5;      // ENTRY_FM_AUTO only
input double            InpAutoRRLevel            = 2.0;    // ENTRY_FM_AUTO only
input bool              InpFMVerboseLog           = false;  // print every FM selection to the Experts log

input group "=== FM-Indicator Analysis Parameters (shared engine — used by all ENTRY_FM_* modes) ==="
#include <FM/Inputs.mqh>

input group "=== First position & limits ==="
input double            InpInitialLot             = 0.01;
input int               InpMaxTrades              = 20;          // hard cap on open positions
input int               InpMaxSpreadPoints        = 25;          // 0 = ignore
input double            InpInitialTPPoints        = 200.0;       // TP for the FIRST trade only (0 = no TP until basket BE)

input group "=== Grid / Martingale ==="
input string            InpPipStepString          = "500"; // points (SYMBOL_POINT units)
input double            InpLotExponent            = 1.0;         // multiplicative factor per group
input double            InpAddToLot               = 0.01;        // additive lot per group
input int               InpAddLotEveryNTrades     = 2;           // group size (e.g. 5 → levels 0-4 same lot)
input bool              InpPlaceFullGridOnOpen    = true;        // place ALL pending levels when first trade opens

input group "=== Basket Break-Even ==="
input bool              InpEnableBasketBE         = true;
input int               InpMinTradesForBE         = 2;
input double            InpBEOffsetPoints         = 200.0;        // TP = BE ± this (in points)
input bool              InpIncludeCommission      = true;
input bool              InpIncludeSwap            = true;
input bool              InpIncludeCurrentSpread   = true;        // conservative adjustment
input bool              InpSetTPAtBE              = true;
input bool              InpDrawBELine             = true;
input color             InpBELineColor            = clrMagenta;

input group "=== Hard protection (grid-end SL & basket kill-switch) ==="
input bool              InpUseBasketStopLoss      = true;
input double            InpStopLossExtraPoints    = 0.0;         // extra points beyond last grid level
input double            InpMaxBasketLossMoney     = 0.0;         // NEW: force-close whole basket if floating loss >= this (account ccy, 0 = off)

input group "=== Execution & Recovery ==="
input int               InpDeviationPoints        = 10;
input bool              InpDeletePendingsIfNoPos  = true;        // if no positions left → delete leftover pendings
input int               InpProcessIntervalSec     = 1;

input group "=== Commission ==="
input double            InpCommissionPerLot       = 12.0;

input group "=== Prevent News Trade or Big Bar ==="
//--- تنظیمات مربوط به شرط کندل
input bool   InpWaitBarClose     = true; // صبر برای بسته شدن کندل قبل از معامله؟
input double InpMaxCandleADRMult = 3.0;  // حداکثر ضریب اندازه کندل نسبت به ADR (صفر برای غیرفعال‌سازی)
input int    InpADRPeriod        = 14;   // دوره زمانی محاسبه ADR (روزانه)

//====================================================================
// GLOBALS
//====================================================================
double   g_pip_steps[];
datetime g_last_process   = 0;
datetime g_last_bar_time  = 0;
int      g_fast_handle    = INVALID_HANDLE;
int      g_mid_handle     = INVALID_HANDLE;
int      g_slow_handle    = INVALID_HANDLE;

string   BE_LINE_NAME;

// ADR cache (NEW: avoids re-pulling D1 history + resumming every tick)
double   g_adr_value      = 0.0;
datetime g_adr_day        = 0;

// FM-Indicator engine state (only used when InpEntryMode is ENTRY_FM_*)
CFMConfig         g_fm_cfg;
CLogger           g_fm_log;
CFMAnalysis       g_fm_analysis;
CStrategyRegistry g_fm_registry;
ENUM_STRATEGY_MODE g_fm_mode = STRAT_MODE_SINGLE;
datetime          g_fm_last_bar = 0;   // last closed bar time already analyzed
int               g_fm_dir      = 0;   // cached signal for that bar

//====================================================================
// UTILITIES
//====================================================================
double PointValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

int DigitsValue()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, DigitsValue());
}

double NormalizeVolume(double volume)
{
   double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minv;

   volume = MathMax(minv, MathMin(maxv, volume));
   volume = MathFloor(volume / step + 1e-9) * step;

   int vd = 2;
   if(step >= 1.0)       vd = 0;
   else if(step >= 0.1)  vd = 1;
   else if(step >= 0.01) vd = 2;
   else                  vd = 3;

   return NormalizeDouble(volume, vd);
}

void ParsePipSteps()
{
   ArrayFree(g_pip_steps);
   string parts[];
   int n = StringSplit(InpPipStepString, ',', parts);
   if(n <= 0)
   {
      ArrayResize(g_pip_steps, 1);
      g_pip_steps[0] = 75.0;
      return;
   }
   ArrayResize(g_pip_steps, n);
   for(int i = 0; i < n; i++)
      g_pip_steps[i] = MathMax(0.0, StringToDouble(parts[i]));
}

double GridStepPoints(const int level)
{
   if(ArraySize(g_pip_steps) == 0) return 0.0;
   int idx = level;
   if(idx < 0) idx = 0;
   if(idx >= ArraySize(g_pip_steps))
      idx = ArraySize(g_pip_steps) - 1;
   return g_pip_steps[idx];
}

double LotForLevel(const int level)
{
   int group = 0;
   if(InpAddLotEveryNTrades > 0)
      group = level / InpAddLotEveryNTrades;

   double lot = InpInitialLot * MathPow(InpLotExponent, group)
                + group * InpAddToLot;
   return NormalizeVolume(lot);
}

//====================================================================
// POSITION / ORDER DISCOVERY
//====================================================================
bool IsOurPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   return ((long)PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

bool IsOurPending(const ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket))
      return false;
   if(OrderGetString(ORDER_SYMBOL) != _Symbol)
      return false;
   if((long)OrderGetInteger(ORDER_MAGIC) != InpMagic)
      return false;
   ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   return (t == ORDER_TYPE_BUY_LIMIT  || t == ORDER_TYPE_SELL_LIMIT ||
           t == ORDER_TYPE_BUY_STOP   || t == ORDER_TYPE_SELL_STOP);
}

int CountPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket)) c++;
   }
   return c;
}

int CountPendingOrders()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(IsOurPending(ticket)) c++;
   }
   return c;
}

bool GetBasketDirection(ENUM_POSITION_TYPE &direction)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      direction = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

bool GetAdversePrice(const ENUM_POSITION_TYPE direction, double &adverse_price)
{
   bool found = false;
   adverse_price = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      if(!found)
      {
         adverse_price = p;
         found = true;
      }
      else
      {
         if(direction == POSITION_TYPE_BUY)
            adverse_price = MathMin(adverse_price, p);
         else
            adverse_price = MathMax(adverse_price, p);
      }
   }
   return found;
}

bool GetFirstPositionPrice(double &first_price)
{
   bool found = false;
   datetime earliest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      if(!found || t < earliest)
      {
         found = true;
         earliest = t;
         first_price = p;
      }
   }
   return found;
}

//====================================================================
// SPREAD FILTER
//====================================================================
bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0) return true;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread_pts = (ask - bid) / PointValue();
   return (spread_pts <= InpMaxSpreadPoints);
}

//====================================================================
// BASKET STATISTICS & BREAK-EVEN
//====================================================================
double BasketFloatingProfit(const bool include_costs)
{
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      total += PositionGetDouble(POSITION_PROFIT);
      if(include_costs)
      {
         double lots = PositionGetDouble(POSITION_VOLUME);
         double comm = lots * InpCommissionPerLot;
         if(InpIncludeSwap)
            total += PositionGetDouble(POSITION_SWAP);
         if(InpIncludeCommission)
            total += comm;
      }
   }
   return total;
}

bool CalculateBasketBreakEven(double &be_price, ENUM_POSITION_TYPE &direction)
{
   if(!GetBasketDirection(direction))
      return false;

   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return false;

   double total_volume  = 0.0;
   double weighted_open = 0.0;
   double fixed_cost    = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;

      double v = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      total_volume  += v;
      weighted_open += v * p;

      if(InpIncludeCommission)
         fixed_cost += v * InpCommissionPerLot;
      if(InpIncludeSwap)
         fixed_cost += PositionGetDouble(POSITION_SWAP);
   }

   if(total_volume <= 0.0)
      return false;

   weighted_open /= total_volume;

   double money_per_price = total_volume * tick_value / tick_size;
   if(money_per_price <= 0.0)
      return false;

   double required_move = -fixed_cost / money_per_price;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = MathMax(0.0, ask - bid);

   if(direction == POSITION_TYPE_BUY)
   {
      be_price = weighted_open + required_move;
      if(InpIncludeCurrentSpread)
         be_price += spread;
   }
   else
   {
      be_price = weighted_open - required_move;
      if(InpIncludeCurrentSpread)
         be_price -= spread;
   }

   be_price = NormalizePrice(be_price);
   return true;
}

//====================================================================
// CHART OBJECTS
//====================================================================
void DrawBELine(const double price)
{
   if(!InpDrawBELine) return;

   if(ObjectFind(0, BE_LINE_NAME) < 0)
   {
      ObjectCreate(0, BE_LINE_NAME, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, BE_LINE_NAME, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, BE_LINE_NAME, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, BE_LINE_NAME, OBJPROP_COLOR, InpBELineColor);
      ObjectSetInteger(0, BE_LINE_NAME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, BE_LINE_NAME, OBJPROP_HIDDEN, false);
      ObjectSetString (0, BE_LINE_NAME, OBJPROP_TOOLTIP, "Basket Break-Even");
   }
   ObjectSetDouble(0, BE_LINE_NAME, OBJPROP_PRICE, price);
}

void RemoveBELine()
{
   if(ObjectFind(0, BE_LINE_NAME) >= 0)
      ObjectDelete(0, BE_LINE_NAME);
}

//====================================================================
// TRADE HELPERS
//====================================================================
bool ModifyPositionSLTP(const ulong ticket, const double sl, const double tp)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   double cur_sl = PositionGetDouble(POSITION_SL);
   double cur_tp = PositionGetDouble(POSITION_TP);

   if(MathAbs(cur_sl - sl) < PointValue()*0.5 &&
      MathAbs(cur_tp - tp) < PointValue()*0.5)
      return true;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.magic    = InpMagic;
   req.sl       = (sl > 0.0 ? NormalizePrice(sl) : 0.0);
   req.tp       = (tp > 0.0 ? NormalizePrice(tp) : 0.0);

   if(!OrderSend(req, res))
   {
      Print("Modify SLTP failed ticket=", ticket, " ret=", res.retcode, " ", res.comment);
      return false;
   }
   return (res.retcode == TRADE_RETCODE_DONE ||
           res.retcode == TRADE_RETCODE_DONE_PARTIAL ||
           res.retcode == TRADE_RETCODE_NO_CHANGES);
}

void DeleteAllPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurPending(ticket)) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      req.symbol = _Symbol;
      req.magic  = InpMagic;
      if(!OrderSend(req, res))
         Print("Delete pending failed ticket=", ticket, " ret=", res.retcode);
   }
}

bool PendingExistsNear(const ENUM_ORDER_TYPE type, const double price)
{
   double tol = MathMax(PointValue(), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)) * 3.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurPending(ticket)) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;
      double p = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(p - price) <= tol)
         return true;
   }
   return false;
}

bool PlaceLimit(const ENUM_POSITION_TYPE direction,
                const double price,
                const double volume)
{
   if(volume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   double nprice = NormalizePrice(price);
   bool ok = false;
   if(direction == POSITION_TYPE_BUY)
      ok = trade.BuyLimit(volume, nprice, _Symbol, 0.0, 0.0,
                          ORDER_TIME_GTC, 0, "FM_Ilan Grid BUY");
   else
      ok = trade.SellLimit(volume, nprice, _Symbol, 0.0, 0.0,
                           ORDER_TIME_GTC, 0, "FM_Ilan Grid SELL");

   if(!ok)
      Print("PlaceLimit failed dir=", direction, " price=", nprice,
            " vol=", volume, " err=", trade.ResultRetcode(), " ", trade.ResultComment());
   return ok;
}

//====================================================================
// GRID ENGINE
//====================================================================
double GridLevelPrice(const double first_price,
                      const ENUM_POSITION_TYPE direction,
                      const int level)
{
   if(level <= 0)
      return first_price;

   double price = first_price;
   for(int i = 0; i < level; i++)
   {
      double step_pts = GridStepPoints(i);
      if(step_pts <= 0.0) continue;
      if(direction == POSITION_TYPE_BUY)
         price -= step_pts * PointValue();
      else
         price += step_pts * PointValue();
   }
   return NormalizePrice(price);
}

void PlaceFullGrid()
{
   int count = CountPositions();
   if(count <= 0 || count >= InpMaxTrades)
      return;

   // NEW (perf): if the grid is already fully placed, skip the O(levels*orders)
   // rescan below — this used to run every InpProcessIntervalSec even in steady
   // state (grid untouched), which is pure waste once all pendings exist.
   int pendingsNeeded = InpMaxTrades - count;
   if(CountPendingOrders() >= pendingsNeeded)
      return;

   ENUM_POSITION_TYPE direction;
   if(!GetBasketDirection(direction))
      return;

   double first_price = 0.0;
   if(!GetFirstPositionPrice(first_price))
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist  = stops_level * PointValue();

   for(int level = count; level < InpMaxTrades; level++)
   {
      double price = GridLevelPrice(first_price, direction, level);

      ENUM_ORDER_TYPE pending_type;
      if(direction == POSITION_TYPE_BUY)
      {
         pending_type = ORDER_TYPE_BUY_LIMIT;
         double max_allowed = bid - min_dist;
         if(price > max_allowed)
            continue;
      }
      else
      {
         pending_type = ORDER_TYPE_SELL_LIMIT;
         double min_allowed = ask + min_dist;
         if(price < min_allowed)
            continue;
      }

      price = NormalizePrice(price);

      if(PendingExistsNear(pending_type, price))
         continue;

      double lot = LotForLevel(level);
      PlaceLimit(direction, price, lot);
   }
}

void EnsureNextPending()
{
   int count = CountPositions();
   if(count <= 0 || count >= InpMaxTrades)
      return;

   ENUM_POSITION_TYPE direction;
   if(!GetBasketDirection(direction))
      return;

   double adverse = 0.0;
   if(!GetAdversePrice(direction, adverse))
      return;

   int next_level = count;
   double step_pts = GridStepPoints(next_level - 1);
   if(step_pts <= 0.0)
      return;

   double step_price = step_pts * PointValue();
   double price;
   ENUM_ORDER_TYPE pending_type;

   if(direction == POSITION_TYPE_BUY)
   {
      price = adverse - step_price;
      pending_type = ORDER_TYPE_BUY_LIMIT;
   }
   else
   {
      price = adverse + step_price;
      pending_type = ORDER_TYPE_SELL_LIMIT;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist  = stops_level * PointValue();

   if(direction == POSITION_TYPE_BUY)
   {
      double max_allowed = bid - min_dist;
      if(price > max_allowed)
         price = max_allowed - step_price;
   }
   else
   {
      double min_allowed = ask + min_dist;
      if(price < min_allowed)
         price = min_allowed + step_price;
   }

   price = NormalizePrice(price);

   if(direction == POSITION_TYPE_BUY  && price >= bid) return;
   if(direction == POSITION_TYPE_SELL && price <= ask) return;

   if(PendingExistsNear(pending_type, price))
      return;

   double lot = LotForLevel(next_level);
   PlaceLimit(direction, price, lot);
}

void ManageGrid()
{
   if(InpPlaceFullGridOnOpen)
      PlaceFullGrid();
   else
      EnsureNextPending();
}

//====================================================================
// GRID-END STOP-LOSS
//====================================================================
double GridBoundaryPrice(const ENUM_POSITION_TYPE direction)
{
   double first_price = 0.0;
   if(!GetFirstPositionPrice(first_price))
      return 0.0;

   if(InpMaxTrades <= 1)
      return first_price;

   double boundary = first_price;
   for(int lvl = 1; lvl < InpMaxTrades; lvl++)
   {
      double step_pts = GridStepPoints(lvl - 1);
      if(step_pts <= 0.0) break;
      if(direction == POSITION_TYPE_BUY)
         boundary -= step_pts * PointValue();
      else
         boundary += step_pts * PointValue();
   }

   double extra = InpStopLossExtraPoints * PointValue();
   if(direction == POSITION_TYPE_BUY)
      boundary -= extra;
   else
      boundary += extra;

   return NormalizePrice(boundary);
}

void SetBasketStopLoss(const ENUM_POSITION_TYPE direction)
{
   if(!InpUseBasketStopLoss || InpMaxTrades <= 1)
      return;

   double sl = GridBoundaryPrice(direction);
   if(sl <= 0.0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist  = stops_level * PointValue();

   if(direction == POSITION_TYPE_BUY)
   {
      if(sl > bid - min_dist)
         sl = NormalizePrice(bid - min_dist - PointValue());
   }
   else
   {
      if(sl < ask + min_dist)
         sl = NormalizePrice(ask + min_dist + PointValue());
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      double cur_tp = PositionGetDouble(POSITION_TP);
      ModifyPositionSLTP(ticket, sl, cur_tp);
   }
}

//====================================================================
// INITIAL TP (for the very first trade only)
//====================================================================
void SetInitialTPIfNeeded()
{
   if(InpInitialTPPoints <= 0.0)
      return;

   int count = CountPositions();
   if(count != 1)
      return;

   ENUM_POSITION_TYPE direction;
   if(!GetBasketDirection(direction))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;

      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_tp     = PositionGetDouble(POSITION_TP);
      double cur_sl     = PositionGetDouble(POSITION_SL);

      double tp = 0.0;
      if(direction == POSITION_TYPE_BUY)
         tp = NormalizePrice(open_price + InpInitialTPPoints * PointValue());
      else
         tp = NormalizePrice(open_price - InpInitialTPPoints * PointValue());

      if(MathAbs(cur_tp - tp) > PointValue()*0.5)
         ModifyPositionSLTP(ticket, cur_sl, tp);
   }
}

//====================================================================
// BREAK-EVEN MANAGEMENT
//====================================================================
double BasketTargetPrice(const double be_price, const ENUM_POSITION_TYPE direction)
{
   double offset = InpBEOffsetPoints * PointValue();
   if(direction == POSITION_TYPE_BUY)
      return NormalizePrice(be_price + offset);
   return NormalizePrice(be_price - offset);
}

bool BasketTargetReached(const double target, const ENUM_POSITION_TYPE direction)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(direction == POSITION_TYPE_BUY)
      return (bid >= target);
   return (ask <= target);
}

void SetAllBasketTP(const double be_price, const ENUM_POSITION_TYPE direction)
{
   if(!InpSetTPAtBE) return;

   double target = BasketTargetPrice(be_price, direction);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      double cur_sl = PositionGetDouble(POSITION_SL);
      ModifyPositionSLTP(ticket, cur_sl, target);
   }
}

void CloseBasketAndRestart()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
         trade.PositionClose(ticket, InpDeviationPoints);
   }
   DeleteAllPending();
   RemoveBELine();
}

// NEW: hard money kill-switch for the whole basket (protects against a grid
// that has run past InpMaxTrades levels against strong sustained trend).
void CheckBasketKillSwitch()
{
   if(InpMaxBasketLossMoney <= 0.0) return;
   if(CountPositions() == 0) return;

   double floatingLoss = -BasketFloatingProfit(true);
   if(floatingLoss >= InpMaxBasketLossMoney)
   {
      Print("Basket kill-switch: floating loss ", DoubleToString(floatingLoss, 2),
            " >= limit ", DoubleToString(InpMaxBasketLossMoney, 2), " — closing basket.");
      CloseBasketAndRestart();
   }
}

void ManageBreakEven()
{
   int count = CountPositions();
   if(count == 0)
   {
      RemoveBELine();
      return;
   }

   ENUM_POSITION_TYPE direction;
   double be = 0.0;
   if(!CalculateBasketBreakEven(be, direction))
      return;

   SetBasketStopLoss(direction);

   if(count == 1)
   {
      SetInitialTPIfNeeded();
      RemoveBELine();
      return;
   }

   if(!InpEnableBasketBE || count < InpMinTradesForBE)
   {
      RemoveBELine();
      return;
   }

   DrawBELine(be);
   SetAllBasketTP(be, direction);

   double target = BasketTargetPrice(be, direction);
   if(BasketTargetReached(target, direction) && BasketFloatingProfit(true) > 0.0)
   {
      CloseBasketAndRestart();
      return;
   }
}

//====================================================================
// ENTRY — shared helpers
//====================================================================
bool OpenInitial(const ENUM_POSITION_TYPE direction)
{
   if(CountPositions() > 0)
      return false;
   if(!SpreadOK())
   {
      Print("Spread too wide, skip initial entry");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   double lot = NormalizeVolume(InpInitialLot);

   double tp = 0.0;
   if(InpInitialTPPoints > 0.0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(direction == POSITION_TYPE_BUY)
         tp = NormalizePrice(ask + InpInitialTPPoints * PointValue());
      else
         tp = NormalizePrice(bid - InpInitialTPPoints * PointValue());
   }

   bool ok = false;
   if(direction == POSITION_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, 0.0, 0.0, tp, "FM_Ilan Initial BUY");
   else
      ok = trade.Sell(lot, _Symbol, 0.0, 0.0, tp, "FM_Ilan Initial SELL");

   if(!ok)
      Print("OpenInitial failed: ", trade.ResultRetcode(), " ", trade.ResultComment());
   return ok;
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == 0) return false;
   if(t != g_last_bar_time)
   {
      g_last_bar_time = t;
      return true;
   }
   return false;
}

bool GetMAValue(const int handle, const int shift, double &value)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1)
      return false;
   value = buf[0];
   return true;
}

//====================================================================
// ENTRY — ENTRY_MA3_CROSS
//====================================================================
int MA3CrossSignal()
{
   double f0, m0, s0, f1, m1, s1;
   if(!GetMAValue(g_fast_handle, 0, f0) ||
      !GetMAValue(g_mid_handle,  0, m0) ||
      !GetMAValue(g_slow_handle, 0, s0) ||
      !GetMAValue(g_fast_handle, 1, f1) ||
      !GetMAValue(g_mid_handle,  1, m1) ||
      !GetMAValue(g_slow_handle, 1, s1))
      return 0;

   bool bull_now  = (f0 > m0 && m0 > s0);
   bool bull_prev = (f1 <= m1 || m1 <= s1);
   bool bear_now  = (f0 < m0 && m0 < s0);
   bool bear_prev = (f1 >= m1 || m1 >= s1);

   if(bull_now && bull_prev) return 1;
   if(bear_now && bear_prev) return -1;
   return 0;
}

//====================================================================
// ENTRY — ENTRY_FM_* (FM-Indicator strategy engine)
//====================================================================
bool IsFMEntryMode(const EntryMode m)
{
   return (m == ENTRY_FM_AUTO      || m == ENTRY_FM_PULLBACK ||
           m == ENTRY_FM_BREAKOUT  || m == ENTRY_FM_REVERSAL ||
           m == ENTRY_FM_DOUBLE    || m == ENTRY_FM_FADE     ||
           m == ENTRY_FM_FAILED_BO);
}

// Configures the shared FM analysis engine + strategy registry for whichever
// single strategy (or AUTO contest) InpEntryMode selected. Mirrors FM_EA.mq5's
// OnInit wiring (Analysis.mqh → StrategyRegistry.mqh → ParityDecision.mqh),
// just without its own execution/position layer — that job belongs to the
// grid/martingale engine above.
bool InitFMEngine()
{
   if(!IsFMEntryMode(InpEntryMode))
      return true; // nothing to do for MANUAL / MA3_CROSS

   FM_ApplyInputs(g_fm_cfg);
   g_fm_log.SetLevel(g_fm_cfg.LogLevel);
   g_fm_analysis.Setup(g_fm_cfg, GetPointer(g_fm_log));

   bool useFM = false, usePB = false, useBO = false, useRev = false, useDbl = false, useFBO = false;
   ENUM_FM_STRATEGY single = STRAT_NONE;

   switch(InpEntryMode)
   {
      case ENTRY_FM_AUTO:
         g_fm_mode = STRAT_MODE_AUTO;
         useFM = usePB = useBO = useRev = useDbl = useFBO = true;
         break;
      case ENTRY_FM_PULLBACK:  g_fm_mode = STRAT_MODE_SINGLE; single = STRAT_PULLBACK;  usePB  = true; break;
      case ENTRY_FM_BREAKOUT:  g_fm_mode = STRAT_MODE_SINGLE; single = STRAT_BREAKOUT;  useBO  = true; break;
      case ENTRY_FM_REVERSAL:  g_fm_mode = STRAT_MODE_SINGLE; single = STRAT_REVERSAL;  useRev = true; break;
      case ENTRY_FM_DOUBLE:    g_fm_mode = STRAT_MODE_SINGLE; single = STRAT_DOUBLE;    useDbl = true; break;
      case ENTRY_FM_FADE:      g_fm_mode = STRAT_MODE_SINGLE; single = STRAT_FM_FADE;   useFM  = true; break;
      case ENTRY_FM_FAILED_BO: g_fm_mode = STRAT_MODE_SINGLE; single = STRAT_FAILED_BO; useFBO = true; break;
      default: return true;
   }

   g_fm_registry.Configure(g_fm_mode, single, useFM, usePB, useBO, useRev, useDbl, useFBO);
   g_fm_last_bar = 0;
   g_fm_dir      = 0;

   PrintFormat("[FM_Ilan_GridEA] FM engine ready: mode=%s strategy=%s history=%d bars",
               CStrategyRegistry::ModeName(g_fm_mode),
               CStrategyRegistry::StrategyName(single), InpFMHistoryBars);
   return true;
}

// Runs the shared closed-bar analysis pipeline and returns +1/-1/0. Cached
// per closed bar (the engine is non-repainting by design, so recomputing
// intrabar on every tick would be wasted work — same signal every tick
// until the next bar closes).
int FMStrategySignal()
{
   int need = MathMax(InpFMHistoryBars, g_fm_cfg.AtrPeriod + 2 * g_fm_cfg.SwingK + 30);

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, need, rates);
   if(copied < 50)
      return 0;
   ArraySetAsSeries(rates, true);

   datetime bar1 = rates[1].time;
   if(g_fm_last_bar != 0 && bar1 == g_fm_last_bar)
      return g_fm_dir; // same closed bar already analyzed — reuse cached signal

   g_fm_last_bar = bar1;
   g_fm_dir      = 0;

   FMAnalysisResult res;
   if(!g_fm_analysis.Update(rates, copied, g_fm_cfg, 1, res) || !res.valid)
      return 0;

   StrategyCandidate cand[];
   CParityBuilder::BuildUniverse(res, g_fm_cfg, g_fm_registry, cand);

   StrategySelection sel;
   if(g_fm_mode == STRAT_MODE_AUTO)
   {
      AutoTuning at;
      at.trendBonus  = InpAutoTrendBonus;
      at.provPenalty = InpAutoProvPenalty;
      at.rrBonus     = InpAutoRRBonus;
      at.rrLevel     = InpAutoRRLevel;
      int finalScore = -1;
      sel = g_fm_registry.SelectAuto(cand, res, at, finalScore);
   }
   else
      sel = g_fm_registry.Select(cand);

   if(!sel.hasTrade)
      return 0;

   string vetoWhy = "";
   ENUM_DECISION_REASON vdr;
   CParityBuilder::DetectVeto(res, sel, vetoWhy, vdr);
   if(vetoWhy != "" && InpApplyStructuralVeto)
   {
      if(InpFMVerboseLog)
         PrintFormat("[FM_Ilan_GridEA] %s %s vetoed: %s",
                     TimeToString(bar1), CStrategyRegistry::StrategyName(sel.strategy), vetoWhy);
      return 0;
   }

   int dir = (sel.setup.dir > 0) ? 1 : (sel.setup.dir < 0 ? -1 : 0);
   g_fm_dir = dir;

   if(InpFMVerboseLog && dir != 0)
      PrintFormat("[FM_Ilan_GridEA] %s %s dir=%s entry=%s score=%d R=%.2f%s",
                  TimeToString(bar1), CStrategyRegistry::StrategyName(sel.strategy),
                  (dir > 0 ? "BUY" : "SELL"), DoubleToString(sel.setup.entry, _Digits),
                  sel.setup.score, sel.setup.rMult,
                  (sel.setup.provisional ? " PROV" : ""));

   return dir;
}

//====================================================================
// ENTRY — dispatcher
//====================================================================
int GetEntrySignal()
{
   switch(InpEntryMode)
   {
      case ENTRY_MANUAL:
         if(InpManualDirection == DIR_BUY)  return 1;
         if(InpManualDirection == DIR_SELL) return -1;
         return 0;

      case ENTRY_MA3_CROSS:
         return MA3CrossSignal();

      default: // all ENTRY_FM_* modes
         return FMStrategySignal();
   }
}

//+------------------------------------------------------------------+
//| تابع محاسبه ADR (میانگین دامنه حرکت روزانه) — با کش روزانه        |
//+------------------------------------------------------------------+
double GetADR(string symbol, int period)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   // دریافت اطلاعات کندل‌های روزانه (D1)
   if(CopyRates(symbol, PERIOD_D1, 1, period, rates) < period)
     {
      Print("خطا در دریافت داده‌های روزانه برای ADR");
      return 0.0;
     }

   double totalRange = 0.0;
   for(int i = 0; i < period; i++)
     {
      totalRange += (rates[i].high - rates[i].low);
     }

   return (totalRange / period);
  }

// NEW: caches the ADR value for the current D1 bar so it is computed once
// per day instead of on every single tick (previous version re-pulled and
// re-summed InpADRPeriod daily candles every InpProcessIntervalSec).
double GetCachedADR(const int period)
  {
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != g_adr_day || g_adr_value <= 0.0)
     {
      g_adr_value = GetADR(_Symbol, period);
      g_adr_day   = today;
     }
   return g_adr_value;
  }

//+------------------------------------------------------------------+
//| تابع بررسی شرایط ورود مجاز برای معامله                            |
//| isNewBar از OnTick گرفته می‌شود (به‌جای ردیابی جداگانه در این تابع) |
//+------------------------------------------------------------------+
bool IsTradeAllowed(const bool isNewBar)
  {
   // 1. بررسی شرط بسته شدن کندل (در صورت فعال بودن در تنظیمات)
   if(InpWaitBarClose && !isNewBar)
      return false; // هنوز کندل جدید بسته نشده است

   // 2. بررسی شرط اندازه کندل قبلی نسبت به ADR (در صورت فعال بودن)
   if(InpMaxCandleADRMult > 0)
     {
      // دریافت اطلاعات کندل قبلی (اندیس 1)
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, rates) < 1) return false;

      // محاسبه اندازه کندل قبلی (High - Low)
      double lastCandleSize = rates[0].high - rates[0].low;

      // دریافت ADR (کش‌شده)
      double adr = GetCachedADR(InpADRPeriod);

      if(adr > 0)
        {
         // اگر اندازه کندل بیش از حد مجاز (مثلاً 3 برابر ADR) بود، معامله مجاز نیست
         if(lastCandleSize > (adr * InpMaxCandleADRMult))
           {
            Print("معامله انجام نشد: اندازه کندل قبلی (", lastCandleSize,
                  ") بیش از ", InpMaxCandleADRMult, " برابر ADR (", adr * InpMaxCandleADRMult, ") است.");
            return false;
           }
        }
     }

   return true; // تمامی شرایط برقرار است
  }

//====================================================================
// RECOVERY
//====================================================================
void RecoverState()
{
   int positions = CountPositions();
   int pendings  = CountPendingOrders();

   if(positions == 0)
   {
      if(InpDeletePendingsIfNoPos && pendings > 0)
      {
         Print("Recovery: no positions left – deleting ", pendings, " leftover pending order(s)");
         DeleteAllPending();
      }
      RemoveBELine();
      return;
   }

   CheckBasketKillSwitch();
   ManageGrid();
   ManageBreakEven();
}

//====================================================================
// LIFECYCLE
//====================================================================
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("FM_Ilan_GridEA requires a HEDGING account. Netting accounts are not supported.");
      return INIT_FAILED;
   }

   ParsePipSteps();
   BE_LINE_NAME = "FM_Ilan_BE_" + IntegerToString(InpMagic) + "_" + _Symbol;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpEntryMode == ENTRY_MA3_CROSS)
   {
      g_fast_handle = iMA(_Symbol, PERIOD_CURRENT, InpFastMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      g_mid_handle  = iMA(_Symbol, PERIOD_CURRENT, InpMediumMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      g_slow_handle = iMA(_Symbol, PERIOD_CURRENT, InpSlowMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      if(g_fast_handle == INVALID_HANDLE ||
         g_mid_handle  == INVALID_HANDLE ||
         g_slow_handle == INVALID_HANDLE)
      {
         Print("Failed to create MA handles");
         return INIT_FAILED;
      }
   }

   if(!InitFMEngine())
      return INIT_FAILED;

   RecoverState();

   Print("FM_Ilan_GridEA v2.00 started. EntryMode=", EnumToString(InpEntryMode),
         " MaxTrades=", InpMaxTrades,
         " AddLotEveryN=", InpAddLotEveryNTrades,
         " InitialTP=", InpInitialTPPoints,
         " FullGrid=", InpPlaceFullGridOnOpen,
         " PipSteps=", InpPipStepString);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fast_handle != INVALID_HANDLE) IndicatorRelease(g_fast_handle);
   if(g_mid_handle  != INVALID_HANDLE) IndicatorRelease(g_mid_handle);
   if(g_slow_handle != INVALID_HANDLE) IndicatorRelease(g_slow_handle);
   RemoveBELine();
}

void OnTick()
{
   datetime now = TimeCurrent();
   if(InpProcessIntervalSec > 0 && (now - g_last_process) < InpProcessIntervalSec)
      return;
   g_last_process = now;

   bool isNewBar = IsNewBar(); // single shared bar-time tracker (was duplicated before)

   int positions = CountPositions();

   if(positions == 0)
   {
      if(InpDeletePendingsIfNoPos && CountPendingOrders() > 0)
      {
         Print("No positions – cleaning leftover pendings");
         DeleteAllPending();
      }
      RemoveBELine();

      bool can_signal = InpTradeOnNewBar ? isNewBar : true;

      if(can_signal && CountPendingOrders() == 0)
      {
         int signal = GetEntrySignal();

         bool otherCheck = IsTradeAllowed(isNewBar);

         if(signal > 0 && otherCheck)
            OpenInitial(POSITION_TYPE_BUY);
         else if(signal < 0 && otherCheck)
            OpenInitial(POSITION_TYPE_SELL);
      }
      return;
   }

   CheckBasketKillSwitch();
   ManageGrid();
   ManageBreakEven();
}
//+------------------------------------------------------------------+
