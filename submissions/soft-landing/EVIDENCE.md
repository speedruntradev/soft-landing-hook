# Soft Landing evidence

Evidence in this contributor repository is local and builder-declared unless explicitly labeled otherwise. It is not an audit, acceptance, deployment receipt, source verification, routing decision, or availability proof.

## Evidence-backed local results

- `forge fmt --check`: passed locally after formatting.
- `forge build --sizes`: passed with Solidity 0.8.26, Cancun, optimizer 200, via-IR, metadata hash disabled, and FFI disabled.
- `forge test -vvv`: 26 tests passed, 0 failed, 0 skipped across four suites.
- Fuzzing: 512 runs each for controller bounds/monotonicity, skipped-decay equivalence, gross fee accounting, and exact-output rounding.
- Invariants: two invariants × 128 runs × 48 calls = 12,288 useful calls, zero reverts and zero discards.
- Integration: real local v4 PoolManager, native quote and ERC-20 quote-as-currency1, all four swap quadrants, claims,
  partial-fill rollback, expiry, authentication, permission mask, full launch-parameter initcode binding, and
  expected-address mismatch rejection. The launch suite additionally covers fixed token CREATE2 deployment, exact
  hook and PoolId binding, one-sided full-supply liquidity, paid initial buy, permanent custody, direct buy/sell,
  position-bound and settlement rollback, and negative callback authentication.
- Deterministic builder check: legacy `PROTOTYPE_READY`; authoritative implementation `STRUCTURALLY_COMPLETE`; design `DESIGN_REVIEW_REQUIRED` because the directional controller and irreversible expiry are novel capability extensions.
- Repository closure: complete under the builder's declared-bytes and resolved Solidity/JavaScript import method.
- Build-info normalization: Foundry 1.7.1 shortened `solcLongVersion` for a local compiler path; the committed
  normalization script queried the exact executed binary, required matching `0.8.26`, and filled canonical identity
  `0.8.26+commit.8a97fa7a` without changing standard-json compiler input or output.

Exact source and tests are `src/SoftLandingHook.sol`, `src/SoftLandingHookFactory.sol`, `src/SoftLandingLaunch.sol`,
`src/SoftLandingToken.sol`, `src/lib/FlowFeeMath.sol`, `test/unit/FlowFeeMath.t.sol`,
`test/integration/SoftLandingHook.t.sol`, `test/integration/SoftLandingLaunch.t.sol`, and
`test/invariant/ControllerInvariant.t.sol`. Exact package dependency versions and registry integrity strings are in
`package-lock.json`; source revisions are declared in `submission.json` and the review target.

## Mandatory fee evidence

Policy: `programmable-volume-fee-v1@1.1.0`. Canonical basis: executed gross quote-side volume. Selected project fee: zero. Effective split: 10 bps Programmable, zero project. Owner and sole claim authority: `0x4957f49620AFf3Adbbe8195a4f633E49cc93376c`. Accrual mode: claimable liability. Claim availability: anytime to a nonzero owner-selected per-claim destination.

`testAllNativeQuoteQuadrantsAccrueExecutedGrossQuote` and `testErc20QuoteCurrencyOneCoversAllFourQuadrants` cover buy/sell × exact-input/exact-output and both quote positions. `testSpecifiedQuotePartialFillRevertsAtomically` covers fail-closed precollection. `testCumulativeRemainderResistsFragmentation`, `testDustAndExactOutputRounding`, and both fee fuzz tests cover rounding and the 1,000-unit minimum. `testProgrammableOwnerOnlyClaimToPerClaimDestination` reconciles liability and PoolManager claims through authorization and redemption. `testCanonicalPoolAndCallbackAuthentication` establishes the one-pool/no-cross-pool boundary and committed initialization price. `testCreate2IdentityBindsEveryLaunchParameter` proves that either currency, tick spacing, or initial sqrt price changes the initcode hash. `testLaunchIdentityMismatchRevertsBeforeDeployment` proves that parameter drift from a mined launch identity fails closed. The hook exposes no same-pool swap function.

The accounting invariant is `PoolManager quote claims held by hook = totalQuoteFeesAccrued = liability(canonical PoolId, quote, owner)`. Claims burn exact backing and do not reset `programmableFeeRemainder`.

## Executable launch evidence

`testAtomicLaunchCreatesTradableTokenHookAndPermanentlyLockedPosition` executes the entire token → hook → canonical
pool → one-sided position → paid initial buy graph through a real local PoolManager. It checks mask `0x20cc`, exact
token/hook/PoolId, launcher position ownership, active liquidity, fixed metadata/supply, supply conservation, 25,789
wei-token launcher dust, and a post-launch direct buy and sell. The bound position is liquidity
`36856093846670599562186` over ticks `[-887220, 204180]` and commits
`999999999999999999999974211` token units. The exact 0.001 ETH initial buy returns
`727555259216957636340100` token units in the deterministic local lifecycle.

`testPositionAmountFailureRollsBackTokenHookPoolAndLaunchRecord` and
`testInitialBuySettlementFailureRollsBackEverything` prove atomic rollback across CREATE2 children and launch state.
`testCallbackRejectsDirectAndWrongManagerCalls` covers direct caller rejection and a PoolManager-originated callback
whose bytes are not the active unlock commitment. These are applicant-owned negative settlement/callback tests and
are passed locally; they do not replace the platform's production-route fork parity.

## Dependency observation

Agent-derived runtime observation on Ethereum mainnet at block 25,679,704 found PoolManager `0x000000000004444c5dc75cB358380D2e3dE08A90` with code hash `0x785f1014552b7ce7d5fb7d0c970ca60edee94fd00425d7ca21609acac7ce1293`. `deployment-evidence.json` binds the official record and source revision. The Soft Landing hook is not deployed, and no source match for the hook is claimed.

## Open evidence and owners

| Layer | Current state | Next owner action |
| --- | --- | --- |
| Architecture | Required for novel controller/expiry | Programmable maintainers review exact mechanism and capability graph. |
| Security/accounting | No independent report | Independent reviewers assess return deltas, claims, solvency, and economics. |
| Static analysis | Forge lint passed with all reported casts bounded or explicitly dispositioned; Slither unavailable | Independent reviewer runs Slither on the exact source commit and records every finding/disposition. |
| Pinned fork lifecycle | Platform-owned; not run and not passed | Platform integrator pins Ethereum block, RPC/runtime identities, executes launch/buy/sell/claim lifecycle, and records receipts/state. |
| Production routing parity | Platform-owned; not run and not passed | Platform integrator tests exact production Universal Router, V4Planner, Permit2, V4Quoter, and StateView paths against the canonical PoolKey. |
| Negative settlement/callback | Applicant-owned; passed locally | Re-run the three exact rollback/authentication tests against the bound source commit. |
| Independent review | Platform-owned required gate; not passed | Programmable assigns an attributable independent reviewer; contributor evidence cannot complete this gate. |
| Deployment | No deployment is claimed | Authorized deployer records salt, initcode, constructor, address, receipt, and runtime. |
| Verification | Not applicable yet | Independent verifier matches exact source/configuration after deployment. |
| Product/indexer/monitoring | Not implemented | Product owners implement and test only after acceptance. |
| Routing/discovery | Not requested/approved | Named providers decide independently. |
| Availability | Not claimed | Programmable release authority decides after all preceding gates. |

`compatibility-report.json`, `review-target.json`, and `gate-status.json` bind the exact local package state. Regenerate them after any source, test, document, dependency, or evidence change.
