# VALIDATION METHODOLOGY — forward, OOS, walk-forward (Phases 37–39)

## 1. Definitions (no re-labeling games, §22)

- IS (in-sample): data used to choose anything (params, rules, gates).
- Forward: the tester-native forward slice of an optimization (unused here —
  our manual split below is the equivalent, stated as such).
- OOS: data NEVER used for any choice. If OOS changes a decision, it becomes
  IS retroactively and a NEW untouched OOS is required.

## 2. Current status (this repo, 2026-09-04)

No experiment has been ACCEPTED (EXP-0001 REJECTED), so there is NOTHING to
validate yet — defaults were never tuned. The IS/OOS runs below measure the
DEFAULTS' stability across time, which is weaker than validating a tuned
choice, and is labeled exactly that.

## 3. Split (Phase 37/38) — EXECUTED 2026-09-04

- IS: 2025.11.03–11.17 (240 bars) · OOS: 2025.11.18–12.03 (264 bars) ·
  AUTO DEMO defaults, Model 1, $10k. Reports: `reports/T-018*` (IS),
  `reports/T-019*` (OOS).
- IS: 1 trade, 0/1, −99.00, PF 0.00 · OOS: 5 trades, 2/5, +487.82,
  PF 2.26, exp +97.56. Veto regime stable (IS 207/240, OOS 205/264).
- Verdict: degradation NEGATIVE (OOS > IS) — but with 1 and 5 trades this
  is noise, not validation. No overfit detectable (nothing was ever tuned);
  no edge demonstrated either. OOS stays OOS: it changed no decision.

## 4. Walk-forward protocol (Phase 39, for future ACCEPTED experiments)

```text
Train W1 → select on IS → freeze → test F1 (OOS) → roll → repeat.
Record per step: window, selected config, IS score, F score.
Promote ONLY configs with Every-F ≥ 0 and median-F ≥ 0.
```

One WF cycle is demonstrated with defaults (no selection possible — honest);
live WF starts with the first ACCEPTED experiment.

## 5. Walk-forward demonstration (Phase 39) — defaults as W1→F1

W1 = IS window above, F1 = OOS window above, "selected config" = defaults
(EXP-0001 REJECTED, so no selection exists). IS score: 1 trade −99.00.
F score: 5 trades +487.82. A tuned config would need Every-F ≥ 0 across
rolled windows — with 1–5 trades/window, no config could qualify today.
Verdict: protocol ready, data too thin to promote anything. Next WF runs
when an experiment is ACCEPTED.
