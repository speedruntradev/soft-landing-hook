# Threat model

## Assets, actors and trust boundaries

List assets at risk, trusted and untrusted actors, external systems, privilege boundaries and maximum losses.

## Capability-specific risks

### Custom Uniswap v4 hook

- [ ] Callback or accounting mistakes can affect every swap
- [ ] Custom routing or hookData can narrow provider support

### Custom hook behavior

- [ ] The callback sender is not the end user
- [ ] Returned deltas create hook liabilities and require explicit conservation
- [ ] Every unnecessary permission expands the attack surface

### Dynamic LP fee

- [ ] A manipulable input can create predatory pricing
- [ ] Provider quotes can diverge from dynamic execution

### Metadata, tags and disclosures

- [ ] Invisible or confusable text can hide identity or economics
- [ ] Provider tags can become stale or imply support that does not exist
- [ ] Mutable media can change after review

### Mandatory Programmable volume fee

- [ ] Incorrect gross-volume basis can overcharge or undercharge
- [ ] Rounding and partial fills can break exact conservation
- [ ] Mutable or shared claim authority can redirect accrued fees

### Tests, evidence and threat model

- [ ] Template text is not project-specific evidence
- [ ] Skipped or unavailable checks cannot be reported as passing
- [ ] Local tests do not prove audit, deployment, indexing or availability

### Directional block congestion controller (owner-defined)

- [ ] Identify attacker goals, authority abuse, value-loss bounds, dependency failures and user-exit failures.

### Irreversible launch expiry (owner-defined)

- [ ] Identify attacker goals, authority abuse, value-loss bounds, dependency failures and user-exit failures.

## Security properties

Write falsifiable safety, solvency, conservation, authorization, liveness and exit properties. Template text is not evidence.

