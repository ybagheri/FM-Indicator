# TRADE EXPLANATION — why engine data supports every word (Phase 32)

> Map for §36. Every field traces to a named engine output. Anything the
> engine does not produce is marked N/A, never invented. Modify/close
> reasons go live with orders (Phase 34); the record format already
> reserves them.

| §36 question | Record field | Engine source |
|---|---|---|
| Why entered | `entryReason` | strategy + provisional flag (registry/catalog) |
| Why direction | dir + `strategyName` | setup.dir (engines) |
| Why strategy | `strategyName` + score | Select/SelectAuto winner |
| Why entry price | `entryPrice` | setup.entry (plan/catalog geometry) |
| Why stop | `stopReason` + `invalidation` | plan/catalog stop + invalidClose |
| Why target | `targetReason` | B0 / window extreme / 2ATR (setup.objective) |
| Why lot size | `volume` + `riskMoney` | CRiskManager (mode + caps) |
| Why no alternative | `alternates[]` reject reasons | DISABLED_BY_MODE / veto / LOST_SELECTION |
| Why modified | NOT YET (no orders) | Phase 34: BE/trail ModifyResult |
| Why closed | NOT YET (no orders) | Phase 34: deal scan profit |

Context: `contextName` + `contextScore` = Phase-3 winner + its share
(0–100 share, NOT a probability). Signal quality: FM = ScoreSignal,
others N/A ("catalog score only"). EA logs `EXPLAIN ...` per WOULD_ intent.
