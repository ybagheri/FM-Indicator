# DECISION ENGINE — systematic specification (Phase 8, normative)

> Companion to `BROOKS_CONCEPTS.md` (§7: trader's equation, no-trade doctrine;
> §8: never certainty — WAIT liberally), `MARKET_CONTEXT.md` (§4: no-trade
> doctrine preview), `MARKET_STATE.md`, `BAR_BY_BAR_ENGINE.md` (barbwire),
> `GENERAL_SETUPS.md` (candidate setups), and `SETUP_ENGINE.md` (FM plans).
> Normative for the decision layer: identical closed-bar input → identical
> decisions (float tol 1e-9, enums exact). Read-only in Phase 8 (DEBUG log +
> optional chart label; never writes FM states, buffers, alerts, or objects
> beyond its own `FM_DECISION` label). No profitability claims. Scores stay
> scores. This completes the bar-by-bar expansion (Phases 1–8).

## 0. Conventions (same as prior layers)

- MQL5: MT5 series shifts (`0` = forming, `>=1` closed). Python mirror:
  oldest-first indices. Only closed bars feed the decision. `atr<=0` → no
  trade direction (safety veto path, §3 rule 1 still evaluates `enable` first).
- `CFMEngine`, `CConfirmation`, all Phase 1–7 engines are UNTOUCHED. This
  layer reads ONE candidate setup (hook-selected per `GENERAL_SETUPS.md` §5,
  FM plans included via their `ScoreSignal`) plus context flags and publishes
  a decision. It never confirms a setup, never fires alerts, never trades.
- The indicator stays execution-free: BUY/SELL are interpretation labels
  (Brooks-style "the setup earns a direction"), not orders.

## 1. Inputs (new; all prior inputs unchanged and reused, not duplicated)

| Input | Type | Default | Meaning |
|---|---|---|---|
| `InpEnableDecision` | bool | true | master switch; false = layer idle |
| `InpMinDecisionScore` | int | 40 | min setup score to earn a direction |
| `InpMaxLateEntryATRMult` | double | 0.50 | chase veto: price past entry toward objective beyond this ×ATR |
| `InpDecisionConflictPpts` | int | 10 | top-two state pcts within this → conflicting context |
| `InpDecisionMaxFailedBO` | int | 2 | ≥ this many failed BOs in 20 bars with no follow → trap-repeat veto |

Validation: `0<=MinScore<=100`, `0.0<=Late<=2.0`, `5<=Conflict<=30`,
`1<=MaxFailed<=5`; clamp + `Validate()` false.
Reused: `SetupMinRR` (RR veto threshold — one source of truth with Phase 6/7).

## 2. Decision inputs (hook-resolved, pure-consumed)

The pure `Decide` takes a candidate `setup`
`{valid, type, dir(±1), entry, stop, objective, rMult, rrOK, score}` plus a
context `{state (winner enum), pct[6] (sum 100 when valid), midRange,
barbwire, close, atr, failCount, hasFollow}`:

- `midRange` = winner is `TRADING_RANGE` AND `close` in the middle third of
  the `StateLookback` window (`(close−LL)/(HH−LL)` in `[1/3, 2/3]`). Hook
  computes; pure layer consumes the bool (unit-testable).
- `barbwire` = `BarFeatures.barbwire` at the analysis bar.
- `conflict` = derived inside `Decide` from `pct`: valid pcts (sum 100) with
  top-two gap `<= ConflictPpts` → true. UNKNOWN (pcts all 0) never conflicts
  (guard: sum must be 100).
- `failCount` = failed-BO outcomes at any of the last 20 closed bars;
  `hasFollow` = any `FOLLOW_THROUGH` in the same window (hook scans with
  `CBreakoutEngine::Analyze`; pure layer consumes the pair).
- `late` = derived inside `Decide`: `dir>0 ? close−entry > Late×atr :
  entry−close > Late×atr` (price already ran past the entry → chasing).

## 3. Veto priority (first match wins — deterministic, machine-checkable)

```
1. !EnableDecision            → NO_TRADE  DISABLED
2. !setup.valid               → NO_TRADE  NO_SETUP
3. barbwire                   → NO_TRADE  BARBWIRE
4. midRange                   → NO_TRADE  MID_RANGE
5. conflict                   → NO_TRADE  CONFLICT
6. state ∈ {UNKNOWN, TRANSITION} → WAIT   NO_EDGE
7. score < MinScore            → WAIT      LOW_SCORE
8. !rrOK                      → WAIT      LOW_RR
9. late                       → WAIT      LATE_ENTRY
10. failCount >= MaxFailed AND !hasFollow → NO_TRADE TRAP_REPEAT
11. else                       → BUY (dir>0) / SELL (dir<0), reason OK
```

Rationale (doctrine §4 + concepts §7–8): structural vetoes (3–5, 10) are
`NO_TRADE` (market untradeable for this style); quality/timing vetoes (6–9)
are `WAIT` (setup exists, entry not earned now). `NO_EDGE` covers the
Always-In ambiguity (concepts §3: never force a direction at ~50/50).
Ordering note: `CONFLICT` precedes `NO_EDGE` so a split-state print is
reported as conflict even when the winner label is `TRANSITION` via the weak
floor; a clean `TRANSITION` (spread-out pcts) reports `NO_EDGE`.

## 4. Output structs/enums (`DecisionEngine.mqh`, `Defs.mqh`)

```
ENUM_DECISION_ACTION {DEC_NO_TRADE=0, DEC_WAIT=1, DEC_BUY=2, DEC_SELL=3}
ENUM_DECISION_REASON {REASON_OK=0, REASON_DISABLED=1, REASON_NO_SETUP=2,
  REASON_BARBWIRE=3, REASON_MID_RANGE=4, REASON_CONFLICT=5, REASON_NO_EDGE=6,
  REASON_LOW_SCORE=7, REASON_LOW_RR=8, REASON_LATE_ENTRY=9, REASON_TRAP_REPEAT=10}
Decision {action, reason, dir, setupType, entry, stop, objective, rMult, score}
```

`Describe()`, e.g. `DECISION SELL REVERSAL NO_TRADE/MID_RANGE` — every token
has a predicate in §2–3. The indicator hook additionally draws one
`FM_DECISION` chart label (`BUY` lime / `SELL` red / `WAIT` orange /
`NO_TRADE` gray + reason) that it creates/moves/deletes itself; the pure
engine draws nothing.

## 5. No-look-ahead / repaint contract (extends prior layers)

1. Candidate setup + all context flags are closed-bar values (`sh>=1`); bar 0
   never feeds a decision.
2. Pure/stateless: `(setup, context, atr, cfg)` → decision. Extending history
   never changes an old decision (tested).
3. The engine writes no FM states, no DATA buffers, no alerts; the hook's
   `FM_DECISION` label is the only chart artifact and is diff-synced.

## 6. Python mirror + tests

- Mirror: `tests/decision.py` — `DecisionCfg(...)`, `decide(setup, ctx,
  atr, cfg)`, oldest-first indexing (no bar indexing needed — pure inputs).
- Suites (`tests/test_decision.py`, 10): clean BUY/SELL pass-through; disabled
  + no-setup; barbwire + mid-range structural vetoes; conflict veto (and
  UNKNOWN-guard + TRANSITION→NO_EDGE ordering); low-score + low-RR waits; late
  chase veto both sides; trap-repeat veto + hasFollow rescue; priority order
  (barbwire beats everything after enable/setup; conflict beats NO_EDGE);
  determinism + freeze (identical re-call; history extension irrelevant —
  pure inputs).
