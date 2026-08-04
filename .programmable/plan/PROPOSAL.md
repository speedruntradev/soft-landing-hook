# Project proposal

> This starter is an accelerator, not an allowlist, approval, audit, deployment receipt or provider promise.

## Outcome

Describe what the user can do and what a complete successful lifecycle looks like.

## Selected foundation

- Starter: Custom Uniswap v4 hook (`custom-hook`)
- Capability pack: Custom hook behavior (`custom-hook-behavior`)
- Capability pack: Dynamic LP fee (`dynamic-lp-fee`)
- Capability pack: Metadata, tags and disclosures (`metadata-disclosures`)
- Capability pack: Mandatory Programmable volume fee (`programmable-volume-fee`)
- Capability pack: Tests, evidence and threat model (`test-evidence-threat-model`)
- Owner-defined capability: Directional block congestion controller (`directional-block-congestion-controller`), routed to architecture review
- Owner-defined capability: Irreversible launch expiry (`irreversible-launch-expiry`), routed to architecture review

## Architecture-changing facts

- [ ] Why each enabled callback is necessary
- [ ] The exact PoolKey, permission mask and hook address derivation
- [ ] All currency flows, settlement rules, authorities and exits
- [ ] How custom behavior composes with the mandatory Programmable fee
- [ ] Every enabled callback and why it is necessary
- [ ] Canonical PoolManager authentication and PoolKey admission
- [ ] Permission bits, HookMiner preimage and deployment address
- [ ] All returned deltas, settlement steps and callback failure effects
- [ ] Minimum, maximum, update actor and update cadence
- [ ] Input metric, observation window, manipulation resistance and failure rule
- [ ] Whether the fee is returned per swap or persisted in PoolManager state
- [ ] Clear separation from the mandatory Programmable and project hook-owned fees
- [ ] Project and token names, symbol, description, URIs and exact logo bytes or hash
- [ ] Metadata owners, mutability, update authority and history
- [ ] All fees, restrictions, external dependencies and affiliations in public language
- [ ] Provider tags and support as separate time-bounded evidence states
- [ ] The effective total is the greater of the selected fee and 10 basis points
- [ ] Exactly 10 basis points belongs to 0x4957f49620AFf3Adbbe8195a4f633E49cc93376c and the remainder belongs to the project
- [ ] The executed gross quote-side basis for all four swap quadrants
- [ ] Rounding, dust, partial-fill and same-hook PoolManager-call behavior
- [ ] Pool-scoped liabilities and owner-only claims to a selected per-claim destination
- [ ] Assets, actors, authorities, trust boundaries and attacker goals
- [ ] Safety, solvency, conservation, liveness and user-exit properties
- [ ] Exact commands, tool versions, fixtures, seeds, results and skipped checks
- [ ] Which claims need maintainer, deployment, provider or onchain evidence

### Directional block congestion controller (owner-defined)

- [ ] Actors and assets
- [ ] Authority and trust boundary
- [ ] Value flow and conservation
- [ ] Failure, recovery and user exit
- [ ] Source, tests and attributable evidence

### Irreversible launch expiry (owner-defined)

- [ ] Actors and assets
- [ ] Authority and trust boundary
- [ ] Value flow and conservation
- [ ] Failure, recovery and user exit
- [ ] Source, tests and attributable evidence

## Lifecycle

Describe creation, configuration, normal use, claims, exits, failures, recovery, upgrades if any, and retirement.

## Value and authority

List every asset movement and every actor that can change behavior, move value, pause a path, replace a dependency or affect a user exit.

## Open decisions

Keep unresolved facts explicit. A missing catalog label is not a rejection; preserve the capability and request architecture review.

