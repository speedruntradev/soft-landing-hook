# Soft Landing evidence

Evidence in this contributor repository is local and builder-declared unless explicitly labeled otherwise. It is not an audit, acceptance, deployment receipt, source verification, routing decision, or availability proof.

## Evidence-backed local results

- `forge fmt --check`: passed locally after formatting.
- `forge build --sizes`: passed with Solidity 0.8.26, Cancun, optimizer 200, via-IR, metadata hash disabled, and FFI disabled.
- `forge test -vvv`: 20 tests passed, 0 failed, 0 skipped across three suites.
- Fuzzing: 512 runs each for controller bounds/monotonicity, skipped-decay equivalence, gross fee accounting, and exact-output rounding.
- Invariants: two invariants × 128 runs × 48 calls = 12,288 useful calls, zero reverts and zero discards.
- Integration: real local v4 PoolManager, native quote and ERC-20 quote-as-currency1, all four swap quadrants, claims, partial-fill rollback, expiry, authentication, and permission mask.
- Deterministic builder check: legacy `PROTOTYPE_READY`; authoritative implementation `STRUCTURALLY_COMPLETE`; design `DESIGN_REVIEW_REQUIRED` because the directional controller and irreversible expiry are novel capability extensions.
- Repository closure: complete under the builder's declared-bytes and resolved Solidity/JavaScript import method.

Exact source and tests are `src/SoftLandingHook.sol`, `src/SoftLandingHookFactory.sol`, `src/lib/FlowFeeMath.sol`, `test/unit/FlowFeeMath.t.sol`, `test/integration/SoftLandingHook.t.sol`, and `test/invariant/ControllerInvariant.t.sol`. Exact package dependency versions and registry integrity strings are in `package-lock.json`; source revisions are declared in `submission.json` and the review target.

## Mandatory fee evidence

Policy: `programmable-volume-fee-v1@1.1.0`. Canonical basis: executed gross quote-side volume. Selected project fee: zero. Effective split: 10 bps Programmable, zero project. Owner and sole claim authority: `0x4957f49620AFf3Adbbe8195a4f633E49cc93376c`. Accrual mode: claimable liability. Claim availability: anytime to a nonzero owner-selected per-claim destination.

`testAllNativeQuoteQuadrantsAccrueExecutedGrossQuote` and `testErc20QuoteCurrencyOneCoversAllFourQuadrants` cover buy/sell × exact-input/exact-output and both quote positions. `testSpecifiedQuotePartialFillRevertsAtomically` covers fail-closed precollection. `testCumulativeRemainderResistsFragmentation`, `testDustAndExactOutputRounding`, and both fee fuzz tests cover rounding and the 1,000-unit minimum. `testProgrammableOwnerOnlyClaimToPerClaimDestination` reconciles liability and PoolManager claims through authorization and redemption. `testCanonicalPoolAndCallbackAuthentication` establishes the one-pool/no-cross-pool boundary. The hook exposes no same-pool swap function.

The accounting invariant is `PoolManager quote claims held by hook = totalQuoteFeesAccrued = liability(canonical PoolId, quote, owner)`. Claims burn exact backing and do not reset `programmableFeeRemainder`.

## Dependency observation

Agent-derived runtime observation on Ethereum mainnet at block 25,679,704 found PoolManager `0x000000000004444c5dc75cB358380D2e3dE08A90` with code hash `0x785f1014552b7ce7d5fb7d0c970ca60edee94fd00425d7ca21609acac7ce1293`. `deployment-evidence.json` binds the official record and source revision. This is a public RPC observation, not an assertion that any Soft Landing contract is deployed or source-matched.

## Open evidence and owners

| Layer | Current state | Next owner action |
| --- | --- | --- |
| Architecture | Required for novel controller/expiry | Programmable maintainers review exact mechanism and capability graph. |
| Security/accounting | No independent report | Independent reviewers assess return deltas, claims, solvency, and economics. |
| Static analysis | Forge lint run; Slither unavailable locally | Reviewer runs Slither and records dispositions. |
| Fork/router | Not run | Integrator pins a block and tests production Quoter/Router paths. |
| Deployment | Not deployed | Authorized deployer records salt, initcode, constructor, address, receipt, and runtime. |
| Verification | Not applicable yet | Independent verifier matches exact source/configuration after deployment. |
| Product/indexer/monitoring | Not implemented | Product owners implement and test only after acceptance. |
| Routing/discovery | Not requested/approved | Named providers decide independently. |
| Availability | Not claimed | Programmable release authority decides after all preceding gates. |

`compatibility-report.json`, `review-target.json`, and `gate-status.json` bind the exact local package state. Regenerate them after any source, test, document, dependency, or evidence change.
