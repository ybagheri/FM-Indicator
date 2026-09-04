# EXP-0000 — template (copy per experiment, Phase 35+)

```text
Experiment ID:
Date:
Git Commit:
EA Version:
Strategy / Mode:
Symbol / Timeframe:
IS Range / OOS Range:
Parameters (changed):
Optimization Range:
Optimization Criterion:
IS Result (trades/PF/exp/DD/score):
OOS Result:
Robustness (optimal / range / sensitivity):
Decision: ACCEPT | REJECT
Reason:
```

Rules: one change family per experiment; OOS data never tunes (§22 — if it
does, relabel it IS); REJECT spikes without plateau; baselines in
`reports/README.md` stay the reference until an experiment is ACCEPTED *and*
promoted to a versioned preset (never overwrite in place).
