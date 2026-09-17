//+------------------------------------------------------------------+
//| MMRiskModel.mqh : SL/TP sizing as a % of Measured-Move size, plus |
//| risk-percent lot sizing. EA-side only (never included by the      |
//| indicator) — mirrors how RiskManager.mqh is already kept outside  |
//| Config.mqh/Inputs.mqh, since position sizing is an execution       |
//| concern, not an analysis-engine one. Pure computation, no orders. |
//+------------------------------------------------------------------+
#ifndef FM_MMRISKMODEL_MQH
#define FM_MMRISKMODEL_MQH

// Two supported risk:reward modes, both driven off the same MM size:
//   MM_RR_EQUAL  (1:1) — stop = 66% of MM size, target = same distance
//   MM_RR_DOUBLE (1:2) — stop = 33% of MM size, target = 2x that distance
// In both modes the stop distance is floored at InpMinStopPoints (default
// 500) so a small/early MM never produces an unrealistically tight stop.
enum ENUM_MM_RR_MODE
  {
   MM_RR_EQUAL  = 0, // ریسک = ریوارد (۱:۱) — استاپ ۶۶٪ اندازه MM
   MM_RR_DOUBLE = 1  // ریوارد = ۲×ریسک (۱:۲) — استاپ ۳۳٪ اندازه MM
  };

class CMMRiskModel
  {
private:
   static double NormalizeLot(const string symbol, double lots)
     {
      double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = minv;
      lots = MathFloor(lots / step + 1e-9) * step;
      if(lots < minv) lots = minv;
      if(lots > maxv) lots = maxv;
      int vd = 2;
      if(step >= 1.0)       vd = 0;
      else if(step >= 0.1)  vd = 1;
      else if(step >= 0.01) vd = 2;
      else                  vd = 3;
      return NormalizeDouble(lots, vd);
     }

public:
   // Step 1: MM size (in POINTS) → stop/target distance (in POINTS).
   //   mmRangePoints  = Projection.mm_range converted to points (mm_range/_Point)
   //   minFloorPoints = hard floor for the STOP distance (user asked for 500)
   static void ComputeStopTargetPoints(const double mmRangePoints,
                                       const ENUM_MM_RR_MODE mode,
                                       const double minFloorPoints,
                                       double &slPoints, double &tpPoints)
     {
      double pct = (mode == MM_RR_EQUAL) ? 0.66 : 0.33;
      slPoints = mmRangePoints * pct;
      if(slPoints < minFloorPoints)
         slPoints = minFloorPoints;
      tpPoints = (mode == MM_RR_EQUAL) ? slPoints : slPoints * 2.0;
     }

   // Step 2: lot size for a target risk % of BALANCE, given only the stop
   // distance in points (no entry/stop price pair needed yet). Uses the
   // manual contractSize/tickSize/tickValue formula exactly as requested.
   // tickValue is already contract-size-aware per MT5 docs, so contractSize
   // itself isn't part of the formula — it's still fetched below purely so
   // it's available to log/sanity-check against the symbol specification.
   //
   // NOTE: RiskManager.mqh's CRiskManager::ComputeVolume() already solves
   // this same problem via OrderCalcProfit(), which additionally adjusts for
   // the SYMBOL_TRADE_CALC_MODE if it's non-standard (e.g. some CFDs/futures
   // where tick value isn't simply linear). Prefer that path when an EA
   // already has both entry AND stop PRICES on hand; use this one when only
   // a stop DISTANCE in points is known (e.g. sizing ahead of order placement,
   // like right after ComputeStopTargetPoints() above).
   static double ComputeLotByRiskPercent(const string symbol,
                                         const double slPoints,
                                         const double riskPercent,
                                         double &riskMoney)
     {
      riskMoney = 0.0;
      if(slPoints <= 0.0 || riskPercent <= 0.0)
         return 0.0;

      double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
      double point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tickSize      = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double contractSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE); // log/sanity only

      if(point <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
        {
         PrintFormat("[MMRiskModel] %s: missing point/tick data (point=%.5f tickSize=%.5f tickValue=%.5f contractSize=%.2f)",
                     symbol, point, tickSize, tickValue, contractSize);
         return 0.0;
        }

      riskMoney = balance * riskPercent / 100.0;      // e.g. 1000 * 1% = 10

      double slPriceDistance = slPoints * point;       // points -> price units
      double ticksInSL       = slPriceDistance / tickSize;
      double moneyPerLotAtSL = ticksInSL * tickValue;  // loss for 1.0 lot at this SL distance

      if(moneyPerLotAtSL <= 0.0)
         return 0.0;

      double lots = riskMoney / moneyPerLotAtSL;       // e.g. 10 / (500pts worth) 
      return NormalizeLot(symbol, lots);
     }

   // Convenience: end-to-end from a Projection's mm_range + entry price to a
   // ready-to-send stop/target price pair and a risk%-sized lot count.
   //   dir = +1 (long) or -1 (short)
   //   mmRangePrice = Projection.mm_range (already in PRICE units, not points)
   static bool BuildOrderPlan(const string symbol, const double entry, const int dir,
                              const double mmRangePrice, const ENUM_MM_RR_MODE mode,
                              const double minFloorPoints, const double riskPercent,
                              double &stopPrice, double &targetPrice,
                              double &lots, double &riskMoney)
     {
      stopPrice = 0.0; targetPrice = 0.0; lots = 0.0; riskMoney = 0.0;
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0 || mmRangePrice <= 0.0 || (dir != 1 && dir != -1))
         return false;

      double mmRangePoints = mmRangePrice / point;
      double slPoints = 0.0, tpPoints = 0.0;
      ComputeStopTargetPoints(mmRangePoints, mode, minFloorPoints, slPoints, tpPoints);

      stopPrice   = entry - dir * slPoints * point;
      targetPrice = entry + dir * tpPoints * point;

      lots = ComputeLotByRiskPercent(symbol, slPoints, riskPercent, riskMoney);
      return (lots > 0.0);
     }
  };

#endif
