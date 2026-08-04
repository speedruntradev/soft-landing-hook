# Test plan

> Record exact commands, tool versions, fixture identities, seeds, passes, failures and skips. A skipped test is not passing evidence.

## Required scenarios

### Custom Uniswap v4 hook

- [ ] PoolManager authentication and PoolKey admission
- [ ] Permission-mask and hook-address checks
- [ ] Value-conservation fuzzing and stateful invariants
- [ ] Complete lifecycle and failure recovery

### Custom hook behavior

- [ ] Direct non-PoolManager callback rejection
- [ ] Permission mask and deployed address bits
- [ ] Value conservation and settlement ordering
- [ ] Unexpected PoolKey, malformed hookData and reentrancy paths

### Dynamic LP fee

- [ ] Minimum, maximum and rate-limit boundaries
- [ ] Manipulated, stale, unavailable and extreme inputs
- [ ] Quote-to-execution parity
- [ ] Liquidity decrease and failure behavior

### Metadata, tags and disclosures

- [ ] NFC, confusable, bidirectional, invisible and control-character checks
- [ ] URI, media-byte, content-type and hash binding
- [ ] Fee and restriction parity across public surfaces
- [ ] Unknown, stale, unsupported and confirmed provider states

### Mandatory Programmable volume fee

- [ ] Ten-basis-point floor and non-additive split
- [ ] All four swap quadrants and both swap directions
- [ ] Rounding, dust, partial fills and self-call policy
- [ ] Immutable owner-only claims and arbitrary safe per-claim destination
- [ ] No bypass, cross-pool netting or liability leakage

### Tests, evidence and threat model

- [ ] Unit, integration, fuzz and invariant checks appropriate to the project
- [ ] Every authority, boundary, failure and recovery path
- [ ] Adversarial dependencies and malformed inputs
- [ ] Reproducible clean-environment build and test

### Directional block congestion controller (owner-defined)

- [ ] Add capability-specific unit, integration, adversarial and property tests after architecture review.

### Irreversible launch expiry (owner-defined)

- [ ] Add capability-specific unit, integration, adversarial and property tests after architecture review.

## Reproducibility

- [ ] Build and test from a clean pinned environment without secrets.
- [ ] Bind every executed check to the exact source revision and dependency closure.
- [ ] Keep local, independent-review, deployment, provider and live evidence separate.

