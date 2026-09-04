//+------------------------------------------------------------------+
//| Analysis.mqh : shared price-action analysis contract (Phase 21)     |
//| Single-source orchestration for Indicator adapter AND EA adapter.    |
//| Moves the FM_Indicator.mq5 OnCalculate new-bar pipeline VERBATIM:   |
//| ATR → swings → projections → FM engine → Phases 1–8 (read-only).    |
//| Adapters keep: new-bar gating, prev-state snapshots, DATA buffers,  |
//| visualization, alerts, MTF/LTF overlays, CSV export.                |
//| Closed bars only (shift>=1). Deterministic: same input → same result.|
//+------------------------------------------------------------------+
#ifndef FM_ANALYSIS_MQH
#define FM_ANALYSIS_MQH

#include "Config.mqh"
#include "Defs.mqh"
#include "Logger.mqh"
#include "ATR.mqh"
#include "Swings.mqh"
#include "BarAnalyzer.mqh"
#include "PullbackPatterns.mqh"
#include "MarketState.mqh"
#include "BreakoutEngine.mqh"
#include "ReversalEngine.mqh"
#include "SetupEngine.mqh"
#include "GeneralSetups.mqh"
#include "DecisionEngine.mqh"
#include "Confirmation.mqh"
#include "FMEngine.mqh"

#define FM_ANALYSIS_MAX_PLANS 20

// Full per-closed-bar analysis output. Plain data only (no handles).
struct FMAnalysisResult
  {
   bool              valid;
   datetime          barTime;       // rates[shift].time analyzed
   double            atr;           // ATR at analysis shift
   // Phase 1
   BarFeatures       bar;
   bool              barDone;
   // Phase 2
   int               trendDir;
   PullbackSignal    pbBull;
   PullbackSignal    pbBear;
   DoubleSignal      dTop;
   DoubleSignal      dBot;
   DoubleSignal      mTop;
   DoubleSignal      mBot;
   bool              pbDone;
   // Phase 3
   MarketState       mstate;
   bool              stateDone;
   // Phase 4
   BreakoutSignal    breakout;
   bool              boDone;
   // Phase 5
   ReversalSignal    revBull;
   ReversalSignal    revBear;
   ExhaustionReport  exBull;
   ExhaustionReport  exBear;
   LegCount          legBull;
   LegCount          legBear;
   bool              revDone;
   // Phase 6 (fixed cap: engine MaxActiveSetups default 20)
   SetupPlan         fmPlans[FM_ANALYSIS_MAX_PLANS];
   int               fmPlanCount;
   bool              setupDone;
   // Phase 7 (FM contest included: best may be SETUP_FM_FADE)
   GeneralSetup      best;
   bool              haveBest;
   bool              generalDone;
   // Phase 8
   DecisionContext   dctx;
   Decision          decision;
   bool              decisionDone;
   // Engine census
   int               fmActive;
  };

class CFMAnalysis
  {
private:
   CATR              m_atr;
   CSwingDetector    m_swings;
   CFMEngine         m_engine;
   CLogger          *m_log;

public:
                     CFMAnalysis(): m_log(NULL) {}
   void              Setup(const CFMConfig &cfg, CLogger *log)
     {
      m_atr.SetPeriod(cfg.AtrPeriod);
      m_swings.SetK(cfg.SwingK);
      m_log = log;
      m_engine.SetLogger(log);
     }
   void              Reset() { m_engine.Reset(); m_swings.Reset(); }
   CFMEngine        *EnginePtr() { return GetPointer(m_engine); }
   double            AtrAt(int shift) const { return m_atr.At(shift); }

   // Analyze closed bar `shift` (>=1). rates[] in MT5 series mode ([0]=forming).
   // Returns false only when history is insufficient for ATR+swings.
   bool              Update(const MqlRates &rates[], int count, const CFMConfig &cfg,
                            int shift, FMAnalysisResult &res)
     {
      ZeroMemory(res);
      res.valid = false;
      res.fmPlanCount = 0;
      CGeneralSetups::InitNone(res.best);
      res.haveBest = false;
      if(count < cfg.AtrPeriod + 2*cfg.SwingK + 20)
         return false;
      if(shift < 1 || shift >= count)
         return false;

      m_atr.Update(rates, count);
      m_swings.Update(rates, count, 1, cfg.PriceMode);

      SwingPoint sw[];
      ArrayResize(sw, m_swings.Count());
      for(int i = 0; i < m_swings.Count(); i++)
         m_swings.Get(i, sw[i]);

      m_engine.FormProjections(sw, rates, count, cfg, m_atr, rates[1].time);
      m_engine.Update(rates, count, 1, cfg, m_atr);

      res.barTime = rates[shift].time;
      res.atr = m_atr.At(shift);
      double atrNow = m_atr.At(1);

      // Phase 1 bar-by-bar analysis (read-only; never gates the state machine).
      if(cfg.EnableBarAnalysis)
        {
         res.bar = CBarAnalyzer::Analyze(rates, count, shift, res.atr, cfg);
         res.barDone = true;
         if(m_log != NULL)
            m_log.Debug(CBarAnalyzer::Describe(res.bar, shift));
        }
      // Phase 2 pullback patterns (read-only; never gates the state machine).
      if(cfg.EnablePullbackPatterns)
        {
         res.trendDir = CPullbackPatterns::TrendDir(rates, count, shift, res.atr, cfg);
         string pbMsg = StringFormat("PB trend=%d", res.trendDir);
         if(res.trendDir > 0)
           {
            res.pbBull = CPullbackPatterns::DetectBull(rates, count, shift, res.atr, cfg);
            if(res.pbBull.found)
               pbMsg += " " + CPullbackPatterns::DescribePB(res.pbBull, true);
           }
         else if(res.trendDir < 0)
           {
            res.pbBear = CPullbackPatterns::DetectBear(rates, count, shift, res.atr, cfg);
            if(res.pbBear.found)
               pbMsg += " " + CPullbackPatterns::DescribePB(res.pbBear, false);
           }
         res.dTop = CPullbackPatterns::FindDoubleTop(sw, res.atr, cfg);
         res.dBot = CPullbackPatterns::FindDoubleBottom(sw, res.atr, cfg);
         if(res.dTop.found)
            pbMsg += " " + CPullbackPatterns::DescribeDouble(res.dTop);
         if(res.dBot.found)
            pbMsg += " " + CPullbackPatterns::DescribeDouble(res.dBot);
         res.mTop = CPullbackPatterns::MicroDoubleTop(rates, count, shift, res.atr, cfg);
         res.mBot = CPullbackPatterns::MicroDoubleBottom(rates, count, shift, res.atr, cfg);
         if(res.mTop.found)
            pbMsg += " " + CPullbackPatterns::DescribeDouble(res.mTop);
         if(res.mBot.found)
            pbMsg += " " + CPullbackPatterns::DescribeDouble(res.mBot);
         res.pbDone = true;
         if(m_log != NULL)
            m_log.Debug(pbMsg);
        }
      // Phase 3 market-state engine (read-only; never gates the state machine).
      if(cfg.EnableMarketState)
        {
         res.mstate = CMarketState::Analyze(rates, count, shift, res.atr, cfg);
         res.stateDone = true;
         if(m_log != NULL)
            m_log.Debug(CMarketState::Describe(res.mstate, shift));
        }
      // Phase 4 breakout engine (read-only; never gates the state machine).
      if(cfg.EnableBreakout)
        {
         res.breakout = CBreakoutEngine::Analyze(rates, count, shift, res.atr, sw, cfg);
         res.boDone = true;
         if(res.breakout.found && m_log != NULL)
            m_log.Debug(CBreakoutEngine::Describe(res.breakout));
        }
      // Phase 5 reversal engine (read-only; never gates the state machine).
      if(cfg.EnableReversal)
        {
         res.revBull = CMajorReversal::Analyze(rates, count, shift, res.atr, sw, cfg, +1);
         res.revBear = CMajorReversal::Analyze(rates, count, shift, res.atr, sw, cfg, -1);
         if(res.revBull.found && m_log != NULL)
            m_log.Debug(CMajorReversal::Describe(res.revBull));
         if(res.revBear.found && m_log != NULL)
            m_log.Debug(CMajorReversal::Describe(res.revBear));
         res.exBull = CExhaustionAnalyzer::Report(rates, count, shift, +1, res.atr, cfg);
         res.exBear = CExhaustionAnalyzer::Report(rates, count, shift, -1, res.atr, cfg);
         if(res.exBull.breadth > 0 && m_log != NULL)
            m_log.Debug(CExhaustionAnalyzer::Describe(res.exBull, +1));
         if(res.exBear.breadth > 0 && m_log != NULL)
            m_log.Debug(CExhaustionAnalyzer::Describe(res.exBear, -1));
         res.legBull = CLegCounter::CountBull(sw);
         res.legBear = CLegCounter::CountBear(sw);
         if(res.legBull.valid && res.legBull.legs > 0 && m_log != NULL)
            m_log.Debug(CLegCounter::Describe(res.legBull, +1));
         if(res.legBear.valid && res.legBear.legs > 0 && m_log != NULL)
            m_log.Debug(CLegCounter::Describe(res.legBear, -1));
         res.revDone = true;
        }
      // Phase 6 FM setup plans (read-only; never gates the state machine).
      if(cfg.EnableSetup)
        {
         for(int i = 0; i < m_engine.ActiveCount(); i++)
           {
            CFMSetup s;
            if(!m_engine.GetSetup(i, s))
               continue;
            if(s.state != FM_DEVELOPING && s.state != FM_CONFIRMED)
               continue;
            int sh = -1;
            for(int k = 1; k < count; k++)
               if(rates[k].time == s.signal_time)
                 {
                  sh = k;
                  break;
                 }
            if(sh < 1)
               continue;
            SetupPlan pl = CSetupPlanner::Plan(rates[sh], s.dir, s.target, s.b0.price,
                                               res.atr, cfg, s.id, s.family,
                                               s.state == FM_CONFIRMED, sh);
            if(pl.valid)
              {
               if(res.fmPlanCount < FM_ANALYSIS_MAX_PLANS)
                  res.fmPlans[res.fmPlanCount++] = pl;
               if(m_log != NULL)
                  m_log.Debug(CSetupPlanner::Describe(pl));
              }
           }
         res.setupDone = true;
        }
      // Phase 7 general setup catalog (read-only; never gates the state machine).
      double atrNow7 = atrNow;
      if(cfg.EnableGeneralSetups && atrNow7 > 0)
        {
         GeneralSetup cand[];
         ArrayResize(cand, 0);
         int wEnd7 = 1 + cfg.MaxPullbackBars;
         if(wEnd7 >= count)
            wEnd7 = count - 1;
         int td7 = CPullbackPatterns::TrendDir(rates, count, 1, atrNow7, cfg);
         if(td7 > 0)
           {
            PullbackSignal pbB = CPullbackPatterns::DetectBull(rates, count, 1, atrNow7, cfg);
            if(pbB.found && pbB.signalBar >= 1 && pbB.signalBar < count)
              {
               double winH = rates[1].high;
               for(int w = 2; w <= wEnd7; w++)
                  if(rates[w].high > winH)
                     winH = rates[w].high;
               GeneralSetup g = CGeneralSetups::FromPullbackBull(pbB, rates[pbB.signalBar].high,
                                                                 pbB.stop, winH, atrNow7, cfg);
               if(g.valid)
                 {
                  int n = ArraySize(cand);
                  ArrayResize(cand, n + 1);
                  cand[n] = g;
                  if(m_log != NULL)
                     m_log.Debug(CGeneralSetups::Describe(g));
                 }
              }
           }
         else if(td7 < 0)
           {
            PullbackSignal pbS = CPullbackPatterns::DetectBear(rates, count, 1, atrNow7, cfg);
            if(pbS.found && pbS.signalBar >= 1 && pbS.signalBar < count)
              {
               double winL = rates[1].low;
               for(int w = 2; w <= wEnd7; w++)
                  if(rates[w].low < winL)
                     winL = rates[w].low;
               GeneralSetup g = CGeneralSetups::FromPullbackBear(pbS, rates[pbS.signalBar].low,
                                                                 pbS.stop, winL, atrNow7, cfg);
               if(g.valid)
                 {
                  int n = ArraySize(cand);
                  ArrayResize(cand, n + 1);
                  cand[n] = g;
                  if(m_log != NULL)
                     m_log.Debug(CGeneralSetups::Describe(g));
                 }
              }
           }
         DoubleSignal darr[4];
         darr[0] = CPullbackPatterns::FindDoubleTop(sw, atrNow7, cfg);
         darr[1] = CPullbackPatterns::FindDoubleBottom(sw, atrNow7, cfg);
         darr[2] = CPullbackPatterns::MicroDoubleTop(rates, count, 1, atrNow7, cfg);
         darr[3] = CPullbackPatterns::MicroDoubleBottom(rates, count, 1, atrNow7, cfg);
         for(int di = 0; di < 4; di++)
           {
            if(!darr[di].found)
               continue;
            int b1 = darr[di].bar1, b2 = darr[di].bar2;
            if(b1 < 1 || b2 < 1 || b1 >= count || b2 >= count)
               continue;
            int lo = (b2 < b1 ? b2 : b1), hi = (b2 < b1 ? b1 : b2);
            double trough = 0;
            bool tInit = false;
            for(int k = lo; k <= hi; k++)
              {
               double v = (darr[di].dir < 0 ? rates[k].low : rates[k].high);
               if(!tInit)
                 {
                  trough = v;
                  tInit = true;
                 }
               else if(darr[di].dir < 0)
                 {
                  if(v < trough)
                     trough = v;
                 }
               else
                 {
                  if(v > trough)
                     trough = v;
                 }
              }
            if(!tInit)
               continue;
            GeneralSetup g = CGeneralSetups::FromDouble(darr[di], trough, atrNow7, cfg);
            if(g.valid)
              {
               int n = ArraySize(cand);
               ArrayResize(cand, n + 1);
               cand[n] = g;
               if(m_log != NULL)
                  m_log.Debug(CGeneralSetups::Describe(g));
              }
           }
         BreakoutSignal bo7 = CBreakoutEngine::Analyze(rates, count, 1, atrNow7, sw, cfg);
         if(bo7.found)
           {
            GeneralSetup g = CGeneralSetups::FromBreakout(bo7, rates[1].close, atrNow7, cfg);
            if(g.valid)
              {
               int n = ArraySize(cand);
               ArrayResize(cand, n + 1);
               cand[n] = g;
               if(m_log != NULL)
                  m_log.Debug(CGeneralSetups::Describe(g));
              }
           }
         int revK = cfg.RevLookback;
         if(revK < 5)
            revK = 5;
         if(revK > 50)
            revK = 50;
         double emaTail[];
         CMajorReversal::EMA20Tail(rates, count, 1, revK, emaTail);
         if(ArraySize(emaTail) > 0)
           {
            ReversalSignal rvB = CMajorReversal::Analyze(rates, count, 1, atrNow7, sw, cfg, +1);
            ReversalSignal rvS = CMajorReversal::Analyze(rates, count, 1, atrNow7, sw, cfg, -1);
            if(rvB.found)
              {
               GeneralSetup g = CGeneralSetups::FromReversal(rvB, rates[1].close, emaTail[0], atrNow7, cfg);
               if(g.valid)
                 {
                  int n = ArraySize(cand);
                  ArrayResize(cand, n + 1);
                  cand[n] = g;
                  if(m_log != NULL)
                     m_log.Debug(CGeneralSetups::Describe(g));
                 }
              }
            if(rvS.found)
              {
               GeneralSetup g = CGeneralSetups::FromReversal(rvS, rates[1].close, emaTail[0], atrNow7, cfg);
               if(g.valid)
                 {
                  int n = ArraySize(cand);
                  ArrayResize(cand, n + 1);
                  cand[n] = g;
                  if(m_log != NULL)
                     m_log.Debug(CGeneralSetups::Describe(g));
                 }
              }
           }
         int best7 = CGeneralSetups::SelectBest(cand);
         if(best7 >= 0)
           {
            res.best = cand[best7];
            res.haveBest = true;
           }
         // FM contest: best DEVELOPING/CONFIRMED plan joins with its ScoreSignal
         // and displaces the general best only on a strictly greater score.
         int fmScoreBest = -1;
         SetupPlan fmPlanBest;
         fmPlanBest.valid = false;
         for(int i = 0; i < m_engine.ActiveCount(); i++)
           {
            CFMSetup s;
            if(!m_engine.GetSetup(i, s))
               continue;
            if(s.state != FM_DEVELOPING && s.state != FM_CONFIRMED)
               continue;
            int sh = -1;
            for(int k = 1; k < count; k++)
               if(rates[k].time == s.signal_time)
                 {
                  sh = k;
                  break;
                 }
            if(sh < 1)
               continue;
            SetupPlan pl = CSetupPlanner::Plan(rates[sh], s.dir, s.target, s.b0.price,
                                               atrNow7, cfg, s.id, s.family,
                                               s.state == FM_CONFIRMED, sh);
            if(!pl.valid)
               continue;
            int fdir = -s.dir;
            double dtAtr = (s.dir > 0 ? (s.target - rates[1].high) : (rates[1].low - s.target)) / atrNow7;
            int q = CConfirmation::ScoreSignal(rates, count, 1, fdir, cfg, s.dir, atrNow7, dtAtr, s.confidence);
            if(q > fmScoreBest)
              {
               fmScoreBest = q;
               fmPlanBest = pl;
              }
           }
         if(fmPlanBest.valid && (!res.haveBest || fmScoreBest > res.best.score))
           {
            GeneralSetup f;
            CGeneralSetups::InitNone(f);
            f.valid = true;
            f.type = SETUP_FM_FADE;
            f.dir = fmPlanBest.fadeDir;
            f.entry = fmPlanBest.entry;
            f.stop = fmPlanBest.stop;
            f.objective = fmPlanBest.objective;
            f.riskPts = fmPlanBest.riskPts;
            f.rewardPts = fmPlanBest.rewardPts;
            f.rMult = fmPlanBest.rMult;
            f.rrOK = fmPlanBest.rrOK;
            f.provisional = fmPlanBest.provisional;
            f.signalBar = fmPlanBest.signalShift;
            f.refPrice = fmPlanBest.entry;
            f.score = fmScoreBest;
            res.best = f;
            res.haveBest = true;
            if(m_log != NULL)
               m_log.Debug(CGeneralSetups::Describe(f));
           }
         res.generalDone = true;
        }
      // Phase 8 decision engine (read-only; never gates the state machine).
      if(cfg.EnableDecision)
        {
         DecisionContext dctx;
         MarketState ms8 = CMarketState::Analyze(rates, count, 1, atrNow, cfg);
         dctx.state = ms8.state;
         dctx.pct[0] = ms8.pctBullTrend;
         dctx.pct[1] = ms8.pctBearTrend;
         dctx.pct[2] = ms8.pctBullChannel;
         dctx.pct[3] = ms8.pctBearChannel;
         dctx.pct[4] = ms8.pctRange;
         dctx.pct[5] = ms8.pctBreakout;
         dctx.pctValid = ms8.valid;
         BarFeatures bf8 = CBarAnalyzer::Analyze(rates, count, 1, atrNow, cfg);
         dctx.barbwire = (bf8.valid && bf8.barbwire);
         dctx.close = rates[1].close;
         dctx.midRange = false;
         if(ms8.state == MS_TRADING_RANGE)
           {
            int L8 = cfg.StateLookback;
            if(L8 < 10)
               L8 = 10;
            if(L8 >= count)
               L8 = count - 1;
            double hh = rates[1].high, ll = rates[1].low;
            for(int w = 2; w <= L8; w++)
              {
               if(rates[w].high > hh)
                  hh = rates[w].high;
               if(rates[w].low < ll)
                  ll = rates[w].low;
              }
            if(hh > ll)
              {
               double pos = (rates[1].close - ll) / (hh - ll);
               dctx.midRange = (pos >= 1.0 / 3.0 && pos <= 2.0 / 3.0);
              }
           }
         dctx.failCount = 0;
         dctx.hasFollow = false;
         int scanN = 20;
         if(scanN >= count)
            scanN = count - 1;
         for(int j = 1; j <= scanN; j++)
           {
            BreakoutSignal bj = CBreakoutEngine::Analyze(rates, count, j, atrNow, sw, cfg);
            if(!bj.found)
               continue;
            if(bj.outcome == BO_FAILED)
               dctx.failCount++;
            if(bj.outcome == BO_FOLLOW_THROUGH)
               dctx.hasFollow = true;
           }
         res.dctx = dctx;
         res.decision = CDecisionEngine::Decide(res.best, dctx, atrNow, cfg);
         res.decisionDone = true;
         if(m_log != NULL)
            m_log.Debug(CDecisionEngine::Describe(res.decision));
        }

      res.fmActive = m_engine.ActiveCount();
      res.valid = true;
      return true;
     }
  };

#endif
