#!/usr/bin/env node

import fs from "node:fs";

const path = new URL("../submissions/soft-landing/submission.json", import.meta.url);
const submission = JSON.parse(fs.readFileSync(path, "utf8"));

submission.$schema = "urn:programmable:v4-hook-submission:1.3.0";
submission.standardVersion = "1.3.0";
delete submission.builderTemplate;
delete submission.publicMetadata.localDiscoveryTags;
delete submission.integration.sdkSafetyProfile;
delete submission.tokenMechanics;
submission.programmableFee.policyVersion = "1.0.0";
delete submission.programmableFee.accounting.roundingPolicy;
delete submission.programmableFee.accounting.remainderScope;
delete submission.programmableFee.accounting.claimResetsRemainders;
delete submission.programmableFee.accounting.minimumGrossQuoteUnits;
delete submission.programmableFee.accounting.fragmentationResistant;

const SOURCE_PATHS = [
  "src/SoftLandingHook.sol",
  "src/SoftLandingHookFactory.sol",
  "src/lib/FlowFeeMath.sol",
  "simulations/launch-traces.mjs",
];
const TEST_PATHS = [
  "test/helpers/MockToken.sol",
  "test/unit/FlowFeeMath.t.sol",
  "test/integration/SoftLandingHook.t.sol",
  "test/invariant/ControllerInvariant.t.sol",
];
const EVIDENCE_PATHS = ["MECHANISM.md", "SECURITY.md", "EVIDENCE.md", "README.md"];
const ALL_SWAP_MODES = [
  "zeroForOne-exactInput",
  "zeroForOne-exactOutput",
  "oneForZero-exactInput",
  "oneForZero-exactOutput",
];

submission.stage = "prototype";
submission.target.dependencyBaseline = "model-specific-pinned";
submission.model = {
  id: "soft-landing",
  name: "Soft Landing",
  summary:
    "A temporary Uniswap v4 launch hook that prices completed directional quote throughput one block later, keeps each block's LP fee stable, and irreversibly returns to the base fee after the launch window.",
  userOutcome:
    "A creator launches one canonical pool with an immutable initial premium and public throughput target; traders receive one predictable buy or sell LP fee for the whole block, sustained directional congestion reprices only the following block, and the fee permanently settles to base after launch.",
  category: "market-structure",
  whyV4:
    "Uniswap v4 can apply a directional per-swap LP-fee override from canonical pool state and collect the mandatory quote-volume fee through quadrant-dependent beforeSwap and afterSwap return deltas in the same non-bypassable hook.",
};
submission.builder = {
  github: "speedruntradev",
  contact: "https://github.com/speedruntradev",
  beneficiary: null,
  licenseDeclaration:
    "MIT for first-party source, tests, simulations, and documents; pinned dependencies retain the licenses recorded in package-lock.json.",
};
submission.publicMetadata.project = {
  name: "Soft Landing",
  description:
    "Block-stable directional congestion pricing for the temporary launch phase of a canonical Uniswap v4 pool.",
  projectUri: "https://github.com/speedruntradev/soft-landing-hook",
  logoUri: null,
  logoContentHash: null,
  metadataMutable: false,
  metadataOwner: null,
};
submission.publicMetadata.token = {
  name: "Soft Landing Launch Token",
  symbol: "SLAND",
  metadataUri: null,
  metadataContentHash: null,
  logoUri: null,
  logoContentHash: null,
  metadataMutable: false,
  metadataOwner: null,
};
submission.publicMetadata.claimedAffiliations = [
  { organization: "Uniswap v4", relationship: "technology-use", evidenceUri: null },
  { organization: "OpenZeppelin Uniswap Hooks", relationship: "technology-use", evidenceUri: null },
];

submission.assets[1].initialSupply = "1000000000000000000000000000";

const lifecycle = submission.launchLifecycle;
lifecycle.tokenCreation = {
  applicable: true,
  actor:
    "The launch integration creates one standard fixed-supply 18-decimal token with 1,000,000,000 tokens and no remaining mint, pause, freeze, blacklist, confiscation, or transfer-tax authority.",
  valueFlow: "The complete fixed supply is delivered to the external launcher for liquidity formation.",
  custody: "The hook never mints or holds the initial token supply.",
  failure: "Invalid token creation parameters revert before pool deployment; no partial supply is created.",
  event: "The external token factory's creation event identifies the exact token address.",
  notApplicableReason: null,
};
lifecycle.poolInitialization = {
  applicable: true,
  actor:
    "Anyone may call the factory with immutable configuration, the expected hook address, and a mined salt; every PoolKey member and the initial sqrt price are committed to the CREATE2 identity before atomic deployment and initialization.",
  valueFlow: "No value moves; the hook records one canonical PoolId and the factory records a configuration hash.",
  custody: "No custody exists at initialization.",
  failure:
    "Invalid configuration, permission bits, PoolKey shape, quote asset, tick spacing, salt, initial price, or expected CREATE2 identity reverts deployment and registration together.",
  event: "SoftLandingHookDeployed and CanonicalPoolRegistered.",
  notApplicableReason: null,
};
lifecycle.liquidityFormation = {
  applicable: true,
  actor: "The external launcher or LPs add standard concentrated liquidity through the PositionManager.",
  valueFlow: "Quote and launched tokens enter standard v4 LP positions.",
  custody: "LP positions own pool liquidity; the hook has no add/remove-liquidity callback or position custody.",
  failure: "A liquidity failure reverts without changing controller or liability state.",
  event: "Standard PoolManager liquidity events.",
  notApplicableReason: null,
};
lifecycle.initialTransaction = {
  applicable: true,
  actor: "The first successful canonical-pool swap starts the launch window inside beforeSwap.",
  valueFlow:
    "The swap pays the immutable initial directional LP fee and the 10 bps Programmable fee; executed gross quote is recorded after successful execution.",
  custody: "The hook begins holding quote-denominated PoolManager claims backing the Programmable liability.",
  failure: "A reverted first swap rolls back startBlock, flow, and fee accrual atomically.",
  event: "ControllerStarted, QuoteFeesAccrued, and QuoteFlowRecorded.",
  notApplicableReason: null,
};
lifecycle.trading = {
  applicable: true,
  actor: "Traders use standard v4 routers in every direction and exactness mode without identity checks.",
  valueFlow:
    "The current block-stable directional LP fee goes to LPs; 10 bps of executed gross quote accrues to the Programmable liability; there is no project charge.",
  custody: "Only the fee liability is held as quote ERC-6909 claims; the hook holds no LP position or launched tokens.",
  failure:
    "Core slippage or price-limit failures, quote below 1,000 smallest units, and specified-quote partial fills revert atomically.",
  event: "ControllerRolled, QuoteFeesAccrued, and QuoteFlowRecorded.",
  notApplicableReason: null,
};
lifecycle.feesAndClaims = {
  applicable: true,
  actor:
    "PoolManager-authenticated callbacks accrue the liability; only the immutable Programmable owner may claim it to a nonzero per-claim destination.",
  valueFlow: "Exactly 10 bps of lifetime executed gross quote is claimable by the immutable owner; project share is zero.",
  custody: "The hook holds an equal quote ERC-6909 claim balance keyed in the liability ledger by PoolId, currency, and owner.",
  failure: "Unauthorized, zero-destination, empty, or failed claims revert without reducing liability or rounding remainder.",
  event: "QuoteFeesAccrued and ProgrammableFeesClaimed.",
  notApplicableReason: null,
};
lifecycle.dependencyFailure = {
  applicable: true,
  actor: "The immutable PoolManager is the only runtime dependency entered by the hook.",
  valueFlow: "A PoolManager failure reverts the complete swap or claim; no partial liability persists.",
  custody: "Previously settled liabilities remain backed and unchanged.",
  failure: "Fail closed; there is no oracle, keeper, bridge, upgrade, or fallback execution path.",
  event: "A reverted action emits no persistent event.",
  notApplicableReason: null,
};
lifecycle.retirement = {
  applicable: true,
  actor: "No administrator retires the hook; the first swap at or after the immutable end block expires only the controller.",
  valueFlow: "LP fees become base forever while the mandatory 10 bps charge continues for the pool's lifetime.",
  custody: "Existing and later Programmable liabilities remain owner-claimable.",
  failure: "Expiry is irreversible; a different behavior requires a new hook and PoolKey.",
  event: "ControllerExpired.",
  notApplicableReason: null,
};

submission.pool.tickSpacing = 60;
submission.pool.lpFee = {
  classification: "lp-fee",
  mode: "dynamic",
  hundredthsOfBip: null,
  initialHundredthsOfBip: 10_000,
  initializationPath: "factory-post-initialize-updateDynamicLPFee",
  applicationMode: "before-swap-override",
  overrideFlagPolicy:
    "Every beforeSwap returns the current buy or sell fee ORed with LPFeeLibrary.OVERRIDE_FEE_FLAG; the PoolKey fee is DYNAMIC_FEE_FLAG.",
  persistentUpdateActor: null,
  persistentUpdateCallSites: [],
  rateLimit: null,
  updatePath:
    "Atomic registration sets the stored dynamic fee to base after initialization; beforeSwap lazily applies the completed observed block once, applies intervening zero-flow decay in constant time, and returns the directional override.",
  minimum: 3_000,
  maximum: 30_000,
  inputMetric: "Executed gross quote throughput in the completed block, independently for buys and sells.",
  referenceAsset: "The canonical quote asset; no price, tick, liquidity, wallet, or oracle value is used.",
  measurementUnit: "Smallest quote-asset units per block; utilization ratios use basis points.",
  observationMode: "delayed",
  observationWindow: "One completed observed block plus constant-time zero-flow treatment for skipped blocks.",
  curve:
    "Above target, add ceil(excessBps*riseAt2x/10000) capped by maxExcessBps and maxFee; at or below target, subtract ceil(slackBps*decayAtZero/10000) floored by baseFee.",
  updateCadence: "Once per observed block on the next block's first swap; every same-block directional fee is stable.",
  liquidityDecreaseBehavior: "The target is immutable and independent of current liquidity; liquidity changes do not directly rewrite it.",
  manipulationResistance:
    "A swap cannot change its own LP fee and same-block ordering cannot assign different fees, but paid executed flow can deliberately raise the following block; the immutable 300 bps cap bounds direct impact.",
  failureRule: "Checked full-precision arithmetic clamps to immutable bounds; invalid constructor parameters cannot deploy.",
  recipient: "pool-liquidity-providers",
};

const hook = submission.hook;
hook.used = true;
hook.base = "Pinned OpenZeppelin BaseHook with project-specific controller and Programmable fee accounting";
hook.upgradeable = false;
hook.sharedAcrossPools = false;
hook.poolNamespace = "One hook deployment admits one atomically registered PoolId; all controller and liability state belongs to it.";
hook.poolAdmission = {
  enforcement:
    "SoftLandingHookFactory commits the full dynamic-fee PoolKey and initial sqrt price to hook initcode, verifies the expected CREATE2 address, and initializes exactly that immutable configuration in one transaction.",
  factoryOrRegistry: "SoftLandingHookFactory is the immutable one-shot registrar; its deploy function is permissionless and has no later control.",
  alternativePoolBehavior: "Alternative pools may exist but this hook rejects them and no policy coverage is implied.",
  rejectionRule: "Revert every callback from a non-PoolManager caller or PoolKey whose derived PoolId differs from canonicalPoolId.",
};
hook.permissions = {
  beforeInitialize: true,
  afterInitialize: false,
  beforeAddLiquidity: false,
  afterAddLiquidity: false,
  beforeRemoveLiquidity: false,
  afterRemoveLiquidity: false,
  beforeSwap: true,
  afterSwap: true,
  beforeDonate: false,
  afterDonate: false,
  beforeSwapReturnDelta: true,
  afterSwapReturnDelta: true,
  afterAddLiquidityReturnDelta: false,
  afterRemoveLiquidityReturnDelta: false,
};
hook.callbackPolicies = [
  {
    callback: "beforeInitialize",
    necessity: "Authenticates atomic self-initialization of the constructor-bound canonical PoolKey at its committed price.",
    allowedReverts:
      "Wrong sender, PoolKey, quote asset, dynamic flag, initial sqrt price, CREATE2 identity, or repeat registration reverts initialization.",
    userExitImpact: "Initialization occurs before liquidity and cannot govern later LP exits.",
    noSelfCallImpact: "The callback performs no swap or liquidity action.",
  },
  {
    callback: "beforeSwap",
    necessity: "Applies the lazy block transition, returns the directional LP fee override, and collects specified-quote fee quadrants.",
    allowedReverts: "Wrong pool, dust, exact-output gross-up failure, pending callback, or settlement failure reverts the swap.",
    userExitImpact: "It affects swaps only and does not gate liquidity removal or token transfers.",
    noSelfCallImpact: "The hook exposes no same-pool swap function.",
  },
  {
    callback: "afterSwap",
    necessity: "Verifies specified-quote full fills, collects unspecified-quote quadrants, and records executed gross directional flow.",
    allowedReverts: "Partial-fill, sign, conversion, settlement, or liability mismatch reverts the complete swap.",
    userExitImpact: "It affects swaps only and does not gate liquidity removal.",
    noSelfCallImpact: "The hook exposes no same-pool swap function.",
  },
];
hook.hookData = {
  used: false,
  schema: null,
  identitySource: null,
  trustedRouterDeploymentRecordId: null,
  callbackSenderRule: null,
  validation: null,
};

const feeComponent = (currency, basis, formula) => ({
  currency,
  basis,
  formula,
  rounding: "down",
  maximumHundredthsOfBip: 1_000,
});
hook.feeMechanism = {
  used: true,
  classification: "hook-owned-fee",
  chargedCurrency: "Native ETH, currency0 and canonical quote asset, in every supported quadrant.",
  swapQuadrants: {
    zeroForOneExactInput: feeComponent(
      "currency0",
      "gross-input",
      "Before: fee=floor((grossQuote*1000+remainder)/1000000); the residual AMM input is gross-fee and afterSwap verifies full execution.",
    ),
    zeroForOneExactOutput: feeComponent(
      "currency0",
      "gross-input",
      "After: derive gross quote input from executed BalanceDelta and apply the cumulative 10 bps stream.",
    ),
    oneForZeroExactInput: feeComponent(
      "currency0",
      "gross-output",
      "After: derive gross quote output from executed BalanceDelta and deduct the cumulative 10 bps stream.",
    ),
    oneForZeroExactOutput: feeComponent(
      "currency0",
      "gross-output",
      "Before: search the bounded exact-output gross-up so gross-fee=requested net; afterSwap verifies the specified quote amount.",
    ),
  },
  maximumHundredthsOfBip: 1_000,
  collectionPath: "quadrant-dependent-swap-return-delta",
  collectionValueFlowId: "programmable-volume-fee",
  liabilityKeyDimensions: ["poolId", "currency", "beneficiary"],
  collectionEvent:
    "QuoteFeesAccrued(bytes32 indexed poolId,address indexed quoteCurrency,address indexed swapSender,bool isBuy,uint256 grossQuoteAmount,uint256 programmableFee,uint256 programmableRemainder)",
  recipients: [
    {
      role: "programmable-platform",
      sharePpm: 1_000_000,
      addressSource: "fixed-address",
      address: "0x4957f49620AFf3Adbbe8195a4f633E49cc93376c",
      binding: "exact-address",
      derivationRule: null,
      mutable: false,
      mutationController: "none",
      newAddressValidation: "none",
      mutationEvent: null,
    },
  ],
  ownership: "The immutable Programmable owner is the sole beneficiary; project share is zero and no rescue or redirect surface exists.",
  claimPolicy: "Only the immutable owner may claim anytime to itself or a nonzero destination supplied for that claim.",
};
hook.customAccounting = {
  used: true,
  backingSource: "The hook mints equal quote-denominated PoolManager ERC-6909 claims through take(...,claims=true).",
  conservationEquation:
    "hook quote claim balance equals totalQuoteFeesAccrued, which equals the liability keyed by canonical PoolId, quote currency, and immutable owner.",
  settlement:
    "A callback records the fee and mints an equal claim before returning an equal positive hook delta; a claim burns the exact claim then takes underlying quote in its own unlock.",
  partialFillBehavior:
    "Quote-unspecified modes charge actual executed BalanceDelta; quote-specified modes verify the residual amount and revert unsupported partial fills.",
  liabilityNamespace: "One liability by canonical PoolId, quote currency, and immutable Programmable owner.",
  liabilityKeyDimensions: ["poolId", "currency", "beneficiary"],
  crossPoolNetting: false,
  duplicateCurrencyPolicy: "One hook accepts one PoolId, and no other pool may share or net the liability.",
  failureIsolation: "Any arithmetic, backing, or settlement mismatch reverts the complete action.",
  withdrawalOrdering: "Authorize owner, zero liability, unlock PoolManager, burn exact claim, take underlying to destination, and require empty unlock return.",
};

const zeroComponent = () => ({
  mode: "zero-only",
  formula: null,
  minimum: "0",
  maximum: "0",
  minimumSign: "zero",
  maximumSign: "zero",
  positiveSettlementActions: [],
  negativeSettlementActions: [],
});
const positiveSpecified = (description) => ({
  mode: "positive-only",
  formula: description,
  minimum: "zero when no quote executes",
  maximum: "strictly less than gross specified quote",
  minimumSign: "zero",
  maximumSign: "positive",
  positiveSettlementActions: [
    {
      order: 1,
      actor: "hook",
      operation: "take",
      currency: "specified",
      assetKind: "native",
      deltaOwner: "hook",
      deltaEffect: "negative",
      counterparty: "hook",
      authorizationRule: "onlyPoolManager callback",
      msgValueRule: null,
      amountRule: "Mint exactly the computed fee as PoolManager ERC-6909 quote claims to the hook.",
      completionDeadline: "before-hook-return",
    },
    {
      order: 2,
      actor: "hook",
      operation: "internal-ledger-update",
      currency: "specified",
      assetKind: "native",
      deltaOwner: "hook",
      deltaEffect: "none",
      counterparty: "not-applicable",
      authorizationRule: null,
      msgValueRule: null,
      amountRule: "Credit exactly the computed fee to the canonical owner liability and persist the lifetime remainder.",
      completionDeadline: "before-hook-return",
    },
  ],
  negativeSettlementActions: [],
});
const beforeQuadrant = (specifiedCurrency, unspecifiedCurrency, amountSign, active, description) => ({
  supported: true,
  specifiedCurrency,
  unspecifiedCurrency,
  amountSign,
  specifiedComponent: active ? positiveSpecified(description) : zeroComponent(),
  unspecifiedComponent: zeroComponent(),
  residualAmmEquation: "amountSpecified-plus-specifiedDelta",
  finalCallerDeltaEquation: "pool-manager-swap-delta-minus-hook-delta",
  specifiedDeltaCanConsumeEntireAmount: false,
  rounding: active ? "Lifetime cumulative floor with a persistent numerator remainder." : "beforeSwap returns zero fee delta; afterSwap applies the fee.",
  zeroAmmLeg: "forbidden",
  partialFillRule: active
    ? "afterSwap verifies the executed specified quote pool amount and reverts any mismatch."
    : "afterSwap uses the actual executed quote BalanceDelta.",
  slippageInvariant: "The external router checks the final caller delta after both LP and hook fees.",
  failureRule: "Any sign, bound, gross-up, partial-fill, or settlement mismatch reverts atomically.",
});
hook.returnDeltaAccounting = {
  used: true,
  quadrants: {
    zeroForOneExactInput: beforeQuadrant(
      "currency0",
      "currency1",
      "negative-exact-input",
      true,
      "Return the cumulative 10 bps fee as a positive specified quote delta; the residual input enters the AMM.",
    ),
    zeroForOneExactOutput: beforeQuadrant("currency1", "currency0", "positive-exact-output", false, ""),
    oneForZeroExactInput: beforeQuadrant("currency1", "currency0", "negative-exact-input", false, ""),
    oneForZeroExactOutput: beforeQuadrant(
      "currency0",
      "currency1",
      "positive-exact-output",
      true,
      "Return the bounded gross-up fee as a positive specified quote delta so final net output equals the request.",
    ),
  },
  executionEvent: "QuoteFeesAccrued",
};
const afterComponent = {
  mode: "positive-only",
  formula: "Return the cumulative 10 bps fee on executed gross unspecified quote as a positive unspecified delta.",
  minimum: "zero when no quote executes",
  maximum: "the 10 bps cumulative stream on executed gross quote",
  minimumSign: "zero",
  maximumSign: "positive",
  positiveSettlementActions: [
    {
      order: 1,
      actor: "hook",
      operation: "take",
      currency: "unspecified",
      assetKind: "native",
      deltaOwner: "hook",
      deltaEffect: "negative",
      counterparty: "hook",
      authorizationRule: "onlyPoolManager callback",
      msgValueRule: null,
      amountRule: "Mint exactly the computed fee as quote ERC-6909 claims to the hook.",
      completionDeadline: "before-hook-return",
    },
    {
      order: 2,
      actor: "hook",
      operation: "internal-ledger-update",
      currency: "unspecified",
      assetKind: "native",
      deltaOwner: "hook",
      deltaEffect: "none",
      counterparty: "not-applicable",
      authorizationRule: null,
      msgValueRule: null,
      amountRule: "Credit the owner liability and lifetime remainder before returning the equal positive delta.",
      completionDeadline: "before-hook-return",
    },
  ],
  negativeSettlementActions: [],
};
hook.postReturnDeltaAccounting.afterSwap = {
  used: true,
  returnedDeltaShape: "unspecified-currency-int128",
  positiveMeaning: "hook-credit-caller-debit",
  negativeMeaning: "hook-debt-caller-credit",
  backingSource: "An equal quote ERC-6909 claim is minted to the hook before return.",
  callerDeltaEquation: "protocol-delta-minus-hook-delta",
  componentPolicies: { unspecified: afterComponent, currency0: null, currency1: null },
  bounds: "Nonnegative 10 bps cumulative charge, checked to int128.",
  rounding: "Lifetime cumulative floor with one persistent platform remainder.",
  slippageOrMinimums: "The external router applies bounds to the final caller delta.",
  failureRule: "Any calculation, cast, take, or liability mismatch reverts the complete swap.",
  executionEvent: "QuoteFeesAccrued",
};
for (const name of ["afterAddLiquidity", "afterRemoveLiquidity"]) {
  hook.postReturnDeltaAccounting[name].used = false;
}
hook.erc6909Claims = {
  used: true,
  currencyIdDerivation: "currency-address-uint160",
  claimBalanceScope: "claim-owner-and-currency",
  poolIdIncludedInClaimId: false,
  owner: "The hook owns quote claims backing only the immutable Programmable owner liability.",
  operatorPolicy: "No external operator is set.",
  mintFlow: "Fee collection calls take(...,claims=true) to mint quote claims to the hook.",
  burnFlow: "An authorized claim calls settle(...,burn=true) before taking underlying quote.",
  takeSettleFlow: "Mint inside the swap unlock; burn then take underlying inside a claim-specific unlock.",
  liabilityKeys: "canonical PoolId, quote currency, immutable owner",
  liabilityKeyDimensions: ["poolId", "currency", "beneficiary"],
  crossPoolNetting: false,
  transferPolicy: "Claims are never transferred to an operator or arbitrary caller.",
  redemption: "Only the immutable owner initiates redemption to its selected nonzero destination.",
  roundingDust: "The lifetime numerator remainder stays below 1,000,000 and is unchanged by claims.",
  aggregateSolvencyEquation: "hook quote claim balance equals totalQuoteFeesAccrued and the owner liability.",
};
hook.nestedActions = {
  used: false,
  directPoolManagerCalls: false,
  routerCalls: false,
  allowedActions: [],
  samePoolPolicy: "The hook exposes no PoolManager swap, modify-liquidity, or donate entry point; same-pool swaps are forbidden.",
  crossPoolPolicy: "No other pool is accepted or touched.",
  callbackSuppression: "Claim unlock settlement does not enter a swap callback.",
  directCallbackBehavior: "self-call-hook-callbacks-skipped",
  routerCallbackBehavior: null,
  maximumDepth: 1,
  stateCommitOrder: "Prepare controller, collect or verify fee, then record successful executed gross flow.",
  transientDeltaOwner: "The hook owns and zeros its settlement delta before unlock completion.",
  syncInterleaving: "ERC-6909 mint and burn use take(claims=true) and settle(burn=true); no ERC-20 transfer-before-sync occurs.",
  slippageAggregation: "The router validates the final caller delta after all fees.",
  failureAtomicity: "Any failure reverts all controller, liability, claim, and flow writes.",
};

const pfee = submission.programmableFee;
pfee.rates.selectedHundredthsOfBip = 0;
pfee.rates.effectiveHundredthsOfBip = 1_000;
pfee.rates.projectHundredthsOfBip = 0;
pfee.collection.status = "implemented";
pfee.collection.supportedSwapModes = ALL_SWAP_MODES;
pfee.collection.swapModePaths = {
  zeroForOneExactInput: "before-swap-return-delta",
  zeroForOneExactOutput: "after-swap-return-delta",
  oneForZeroExactInput: "after-swap-return-delta",
  oneForZeroExactOutput: "before-swap-return-delta",
};
pfee.accounting.valueFlowId = "programmable-volume-fee";
const collectionEvent =
  "QuoteFeesAccrued(bytes32 indexed poolId,address indexed quoteCurrency,address indexed swapSender,bool isBuy,uint256 grossQuoteAmount,uint256 programmableFee,uint256 programmableRemainder)";
const claimEvent =
  "ProgrammableFeesClaimed(bytes32 indexed poolId,address indexed quoteCurrency,address indexed owner,address recipient,uint256 amount)";
pfee.accounting.collectionEvent = collectionEvent;
pfee.accounting.claimEvent = claimEvent;
pfee.evidence.sourcePaths = ["src/SoftLandingHook.sol"];
pfee.evidence.testPaths = ["test/integration/SoftLandingHook.t.sol"];

for (const capability of Object.values(submission.capabilities)) capability.used = false;
submission.capabilities.externalCalls = {
  used: true,
  targets: ["Immutable Uniswap v4 PoolManager: initialize, take, unlock, settle"],
  callSites: ["factory initialization", "beforeSwap", "afterSwap", "claimProgrammableFees", "unlockCallback"],
  reentrancyPolicy: "BaseHook authenticates callbacks and transient reentrancy guards protect deployment registration and claims.",
  stateDriftPolicy: "Only canonical PoolManager and PoolId state is accepted; any revert is atomic.",
  returnValuePolicy: "Require exact callback selectors and an empty claim-unlock result.",
  failureAtomicity: "Any external-call failure reverts all state changes.",
};
submission.capabilities.externalLiquidity = {
  used: true,
  custody: "The hook holds quote ERC-6909 claims in PoolManager and no LP position or external-protocol asset.",
  ownership: "Every held claim unit backs the immutable Programmable owner liability.",
  shareAccounting: "No shares; one scalar liability and one lifetime numerator remainder.",
  solvencyEquation: "hook quote claim balance == totalQuoteFeesAccrued == owner liability.",
  lossAllocation: "None; a claim burns exactly the backed claim amount.",
  donationPolicy: "Unsolicited assets create no liability and there is no sweep path.",
  exitPath: "The immutable owner may claim at any time to a destination chosen for that claim.",
  dependencyFailure: "A failed PoolManager operation reverts without changing liability.",
};

const integration = submission.integration;
integration.routerGeneration = null;
integration.sdkDependencies = [
  {
    packageName: "@openzeppelin/contracts",
    version: "5.6.1",
    integrity: "sha512-Ly6SlsVJ3mj+b18W3R8gNufB7dTICT105fJhodGAGgyC2oqnBAhqSiNDJ8V8DLY05cCz81GLI0CU5vNYA1EC/w==",
    repository: "https://github.com/OpenZeppelin/openzeppelin-contracts",
    revision: "5fd1781b1454fd1ef8e722282f86f9293cacf256",
  },
  {
    packageName: "@openzeppelin/uniswap-hooks",
    version: "1.1.1",
    integrity: "sha512-DI5lNlNsWCcSbEGdc2SCmxpkAAjlnwf4a1MQcpPEO6kRi1OQUZwYwGG/n379wJdrcj5n0/z7uhZ/wWetG92lrQ==",
    repository: "https://github.com/OpenZeppelin/uniswap-hooks",
    revision: "a5f831963087d44a857ec41ddff4da01949f38ff",
  },
  {
    packageName: "@uniswap/v4-core",
    version: "1.0.2",
    integrity: "sha512-X15Tm2wWd+USAzEExMbo+g9naA6QN6mPgWm0MzDwRNlOfaNlepfUpSyt9RSrUfEODspwbyWbcLg6t5nwc/e7lg==",
    repository: "https://github.com/Uniswap/v4-core",
    revision: "59d3ecf53afa9264a16bba0e38f4c5d2231f80bc",
  },
  {
    packageName: "@uniswap/v4-periphery",
    version: "1.0.3",
    integrity: "sha512-JxLL0Djv9XcMvI2PatEnWrCrxuEaYNVhHxstndBOP+aJfh1XLg5ec8SDZ0xyoVfg2ElJTvuKpBgnu90bNValsg==",
    repository: "https://github.com/Uniswap/v4-periphery",
    revision: "60cd93803ac2b7fa65fd6cd351fd5fd4cc8c9db5",
  },
];
integration.swapModes = ALL_SWAP_MODES;
integration.partialFills =
  "Quote-unspecified paths charge actual executed gross quote; specified-quote paths verify full residual execution and revert unsupported partial fills.";
integration.slippage = "The external router must enforce minimum output or maximum input against the final caller delta after both fees.";
integration.deadline = "Enforced by the external router; the hook adds no deadline or identity field.";
integration.permit2 = "Handled by the external router; the hook stores no trader allowance.";
integration.stateReads = "Controller and liability state come from hook storage; PoolManager supplies the executed BalanceDelta.";
integration.events = [
  "SoftLandingHookDeployed",
  "CanonicalPoolRegistered",
  "ControllerStarted",
  "ControllerRolled",
  "ControllerExpired",
  "QuoteFlowRecorded",
  collectionEvent,
  claimEvent,
];
integration.routingAndDiscoverability = {
  routingMode: "not-planned",
  allowlistTriggers: { usesDeltaFlag: true, addressStartsWith91: false, targetsMajorPair: false, permissionedPool: false },
  uniswapRoutingStatus: "not-applicable",
  hookRegistryStatus: "not-submitted",
  customHookDataRequired: false,
  standardRouterCompatible: true,
  permissionedRouting: {
    required: false,
    minimumRouterGeneration: null,
    adapterCurrencyUsed: null,
    allowedWrapperBindings: null,
    positionManagerBinding: null,
    routingAllowlistRequiredPerChain: null,
  },
  sourcePaths: [],
  testPaths: [],
};
integration.dataReconstruction = {
  mode: "events-with-confirmed-reads",
  eventCoverage: "Factory, registration, controller, flow, accrual, and claim events reconstruct the complete public lifecycle.",
  cursor: "block-number-transaction-index-log-index",
  startBlockPolicy: "Index from SoftLandingHookDeployed for the canonical hook.",
  finalityDepth: 12,
  reorgPolicy: "Roll back to the last finalized cursor and replay before publishing state.",
  backfillPolicy: "Replay all canonical hook events from deployment.",
  checkpointPolicy: "Checkpoint controller states, cumulative flow, liability, remainder, and claim balance at finalized blocks.",
  freshnessTargetSeconds: 60,
  staleAfterSeconds: 300,
  freshnessMeasurement: "Wall-clock lag from chain head to last indexed finalized block.",
  reconciliation: "At one confirmed block, event-derived liability must equal getter state and the hook's quote claim balance.",
  reserveReconstruction: {
    used: true,
    balanceSources: ["Hook ERC-6909 quote claim balance in PoolManager"],
    liabilitySources: ["QuoteFeesAccrued and ProgrammableFeesClaimed plus getters"],
    attributionKeys: ["poolId", "currency", "beneficiary"],
    solvencyEquation: "hook quote claim balance == totalQuoteFeesAccrued == owner liability",
    poolLiquidityTreatment: "excluded-from-hook-reserves",
    donationAndDustPolicy: "Unsolicited balances are not liability and cannot be swept; the numerator remainder is accounting state, not a token unit.",
    reconciliation: "Withhold results on any event/getter/claim-balance mismatch.",
  },
  sourcePaths: ["src/SoftLandingHook.sol", "src/SoftLandingHookFactory.sol"],
  testPaths: ["test/integration/SoftLandingHook.t.sol"],
};
integration.platformHandoff = {
  intended: true,
  websiteRegistryPath: null,
  uiSourcePaths: [],
  apiSourcePaths: [],
  indexerSourcePaths: [],
  testPaths: [],
  reviewStatus: "not-requested",
  maintainerReviewRequired: true,
  selfApproval: false,
  availabilityClaimed: false,
  handoffNotes:
    "The custom hook, controller math, atomic factory, fee accounting, tests, and specifications are implemented. UI, API, production indexer, deployment, routing, monitoring, and availability remain separate maintainer-owned work.",
};

submission.operations.monitoring =
  "Index controller, flow, fee, and claim events; alert if the confirmed claim balance differs from totalQuoteFeesAccrued or if effective fees leave immutable bounds.";
submission.operations.incidentResponse =
  "The immutable hook has no pause, rescue, upgrade, or redirect authority. Publish the exact PoolId, block, event reconstruction, and liability on any mismatch; a code change requires a new hook and PoolKey.";
submission.security = {
  usesTxOrigin: false,
  userControlledDelegatecall: false,
  arbitraryExecution: false,
  unboundedCriticalLoop: false,
  ignoredCallResults: false,
  hiddenControls: false,
  assumesOnchainSecrecy: false,
  bypassesHookAddressValidation: false,
  signatureScheme: {
    used: false,
    standard: null,
    nonce: null,
    deadline: null,
    chain: null,
    verifyingContract: null,
    action: null,
    parameters: null,
    erc1271: null,
  },
};
submission.authorities = [
  {
    role: "Programmable fee owner",
    controller: "0x4957f49620AFf3Adbbe8195a4f633E49cc93376c",
    capabilities: ["claim only its accrued 10 bps quote liability to an owner-selected destination per claim"],
    mutable: false,
    delay: null,
    userExitImpact: "Claims never touch LP liquidity, controller state, or trader balances.",
  },
  {
    role: "Immutable launch configuration",
    controller: "none; constructor and atomic registration only",
    capabilities: [
      "No party can mutate fees, duration, PoolManager, quote, currencies, tick spacing, initial price, or canonical PoolId.",
    ],
    mutable: false,
    delay: null,
    userExitImpact: "No authority can pause or selectively block a trader or LP exit.",
  },
];
submission.dependencies = {
  onchain: [
    {
      id: "v4-poolmanager",
      name: "Uniswap v4 PoolManager",
      kind: "protocol-singleton",
      repository: "https://github.com/Uniswap/v4-core",
      revision: "af7c077a438d5556b75f0ca722c6d3d53a7a1a9b",
      packageVersion: "1.0.0",
      license: "BUSL-1.1/MIT mixed by file",
      sourceProvenance: "pinned-source",
      deploymentRecordId: "v4-poolmanager-ethereum",
      chainAddress: "0x000000000004444c5dc75cB358380D2e3dE08A90",
      runtimeHash: "0x785f1014552b7ce7d5fb7d0c970ca60edee94fd00425d7ca21609acac7ce1293",
      deploymentEvidencePath: "submissions/soft-landing/deployment-evidence.json",
      trust: "The address is from Uniswap's pinned deployment feed; runtime was observed over a public RPC and Sourcify match 6376919 binds the deployed source to the npm 1.0.0 gitHead.",
      failure: "A missing, wrong, or reverting PoolManager blocks deployment or reverts the action.",
      fallback: "No fallback PoolManager; deployment evidence must bind the intended Ethereum record later.",
    },
  ],
  offchain: [],
};
submission.valueFlows = [
  {
    id: "core-swap",
    action: "execute the canonical AMM swap",
    asset: "native ETH quote and launched token",
    from: "trader and pool",
    to: "pool and trader",
    amountRule: "Standard v4 settlement with the current directional LP fee override and final caller slippage bounds.",
    settlement: "PoolManager settles final deltas before unlock completion.",
    failure: "Core or router bound failure reverts the complete swap.",
  },
  {
    id: "programmable-volume-fee",
    action: "accrue the mandatory hook-owned volume charge",
    asset: "canonical quote asset",
    from: "executed gross quote-side swap volume",
    to: "immutable Programmable owner liability",
    amountRule: "effective=max(0,1000)=1000 hundredths of a bip; cumulative platform fee floor with lifetime remainder; project=0.",
    settlement: "Quadrant-dependent before/after return delta mints equal quote ERC-6909 claims to the hook.",
    failure: "Dust, gross-up, partial-fill, cast, take, or liability mismatch reverts the swap.",
  },
  {
    id: "programmable-fee-claim",
    action: "claim the platform liability",
    asset: "canonical quote asset",
    from: "hook-owned quote ERC-6909 claims",
    to: "immutable owner or its selected nonzero destination",
    amountRule: "Exactly the full accrued liability; claim leaves the lifetime numerator remainder unchanged.",
    settlement: "Zero liability, unlock, burn exact claim, and take underlying quote atomically.",
    failure: "Unauthorized, zero, empty, or failed claims revert completely.",
  },
  {
    id: "dynamic-lp-fee",
    action: "pay the block-stable directional LP fee",
    asset: "swap input asset",
    from: "trader swap input",
    to: "pool liquidity providers",
    amountRule: "Immutable bounded controller fee from completed directional quote flow; separate from hook-owned fees.",
    settlement: "PoolManager applies the beforeSwap LP fee override in core swap accounting.",
    failure: "Invalid configuration cannot deploy; runtime fee is clamped to [base,max].",
  },
];

const surface = submission.projectSurfaces[0];
const capabilityIds = [
  "canonical-v4-pool",
  "claimable-platform-fee",
  "custom-hook-behavior",
  "dynamic-lp-fee",
  "evidence-plan",
  "provider-disclosures",
  "public-metadata",
  "quote-side-volume-accounting",
  "security-properties",
  "directional-block-congestion-controller",
  "irreversible-launch-expiry",
];
surface.id = "soft-landing-hook";
surface.name = "Soft Landing hook";
surface.summary = "The one canonical-pool hook containing the controller and mandatory quote-volume fee accounting.";
surface.capabilityIds = capabilityIds;
surface.authorityRefs = ["Programmable fee owner", "Immutable launch configuration"];
surface.valueFlowRefs = ["core-swap", "programmable-volume-fee", "programmable-fee-claim", "dynamic-lp-fee"];
surface.assetRefs = ["eth", "launched-token"];
surface.sourcePaths = SOURCE_PATHS.slice(0, 3);
surface.testPaths = TEST_PATHS;
surface.evidencePaths = EVIDENCE_PATHS;
surface.exposure = {
  movesValue: true,
  usesSignatures: false,
  makesExternalCalls: true,
  holdsCustody: true,
  handlesPii: false,
  usesGeolocation: false,
  usesSecrets: false,
};
surface.profiles.authority = {
  status: "applicable",
  summary: "PoolManager callback authentication, exact pool admission, immutable configuration, and one fixed claim owner cover every authority.",
  controls: ["Reject non-PoolManager callbacks and noncanonical PoolKeys; expose no admin mutation, rescue, pause, or upgrade."],
  evidenceRefs: ["SECURITY.md"],
};
surface.profiles.valueFlow = {
  status: "applicable",
  summary: "The hook applies an LP-fee override and accrues one quote liability backed by equal PoolManager claims.",
  controls: ["Reconcile claim balance, totalQuoteFeesAccrued, and owner liability after every swap and claim."],
  evidenceRefs: ["MECHANISM.md", "EVIDENCE.md"],
};
surface.profiles.sourceOfTruth = {
  status: "applicable",
  summary: "Confirmed PoolManager and hook state for the canonical PoolId is authoritative.",
  controls: ["Key reconstruction by chain, hook, PoolId, block, transaction, and log index."],
  evidenceRefs: ["MECHANISM.md"],
};
surface.profiles.externalCalls = {
  status: "applicable",
  summary: "The hook calls only its immutable PoolManager for initialization, claim mint/burn, unlock, and take.",
  controls: ["Use atomic failure and exact return checks; no arbitrary target or calldata exists."],
  evidenceRefs: ["SECURITY.md"],
};
surface.profiles.custody = {
  status: "applicable",
  summary: "The hook holds only quote ERC-6909 claims that back the immutable owner liability.",
  controls: ["Maintain claim balance == total liability; no sweep, rescue, project claim, or operator."],
  evidenceRefs: ["SECURITY.md", "EVIDENCE.md"],
};
surface.profiles.sourceTestSchema.evidenceRefs = ["EVIDENCE.md"];
surface.profiles.failureRecovery = {
  status: "applicable",
  summary: "Every invalid transition, fill, settlement, or claim fails atomically; a new code path requires a new hook.",
  controls: ["Test rollback, expiry, partial fills, long gaps, claims, and callback authentication."],
  evidenceRefs: ["SECURITY.md", "EVIDENCE.md"],
};

const profileNames = {
  authority: "authority",
  valueFlow: "value-flow",
  sourceOfTruth: "source-of-truth",
  signaturesReplay: "signatures-replay",
  externalCalls: "external-calls",
  custody: "custody",
  piiGeolocation: "pii-geolocation",
  secretBoundary: "secret-boundary",
  sourceTestSchema: "source-test-schema",
  failureRecovery: "failure-recovery",
};
const triggers = {
  authority: true,
  valueFlow: true,
  sourceOfTruth: true,
  signaturesReplay: false,
  externalCalls: true,
  custody: true,
  piiGeolocation: false,
  secretBoundary: false,
  sourceTestSchema: true,
  failureRecovery: true,
};
submission.projectCapabilities = capabilityIds.map((id) => ({
  id,
  kind: id,
  summary: `Soft Landing capability ${id} is implemented in the single canonical hook boundary and bound to the declared source, tests, value flows, and failure rules.`,
  surfaceIds: ["soft-landing-hook"],
  securityTriggers: triggers,
  requiredProfiles: Object.entries(triggers)
    .filter(([, enabled]) => enabled)
    .map(([name]) => profileNames[name]),
}));
submission.capabilityExtensions = [
  {
    capabilityId: "directional-block-congestion-controller",
    summary: "Independent buy and sell LP fees use completed gross quote flow and remain stable within each block.",
    interactionRefs: ["hook.beforeSwap", "hook.afterSwap"],
    trustBoundary: "Only authenticated canonical-pool execution can add flow; no wallet, router identity, oracle, keeper, or admin input exists.",
    failureMode: "Checked bounded arithmetic or settlement failure reverts atomically; fee remains inside immutable bounds.",
    schemaPath: null,
    sourcePaths: ["src/SoftLandingHook.sol", "src/lib/FlowFeeMath.sol"],
    testPaths: ["test/unit/FlowFeeMath.t.sol", "test/invariant/ControllerInvariant.t.sol", "test/integration/SoftLandingHook.t.sol"],
    evidencePaths: ["MECHANISM.md", "EVIDENCE.md"],
  },
  {
    capabilityId: "irreversible-launch-expiry",
    summary: "The first successful swap starts a fixed block window whose first post-window swap permanently fixes both effective LP fees at base.",
    interactionRefs: ["hook.beforeSwap"],
    trustBoundary: "Expiry depends only on block.number and immutable warmupBlocks; no party can reset or extend it.",
    failureMode: "Expiry and fee collection occur in the swap transaction; a reverted swap leaves the prior state and a later swap retries the boundary.",
    schemaPath: null,
    sourcePaths: ["src/SoftLandingHook.sol"],
    testPaths: ["test/integration/SoftLandingHook.t.sol"],
    evidencePaths: ["MECHANISM.md", "SECURITY.md"],
  },
];

submission.risk = {
  dimensions: {
    complexity: 3,
    customMath: 2,
    externalDependencies: 1,
    externalLiquidity: 1,
    valueAtRisk: 2,
    teamMaturity: 1,
    upgradeability: 0,
    autonomy: 0,
    priceImpact: 2,
  },
  rationales: {
    complexity: "Quadrant-dependent deltas, cumulative remainder accounting, claims, and a two-direction block state machine interact in one hook.",
    customMath: "Full-precision piecewise utilization math and exact-output gross-up are bounded and differentially fuzzed.",
    externalDependencies: "Only immutable PoolManager and standard token behavior; no oracle, keeper, bridge, vault, or upgrade.",
    externalLiquidity: "The hook holds quote ERC-6909 claims backing one fee liability but no LP or external protocol position.",
    valueAtRisk: "The hook custodies accrued 10 bps claims until the immutable owner claims them.",
    teamMaturity: "Conservative nonzero process score until independent review and fork evidence complete.",
    upgradeability:
      "Hook, controller, owner, quote, full PoolKey, initial sqrt price, PoolId, parameters, and factory registration are immutable.",
    autonomy: "State changes only during user-initiated swaps; no independent agent, keeper, or mutable control acts.",
    priceImpact: "The bounded LP fee changes swap cost but core concentrated-liquidity price formation remains unchanged.",
  },
  declaredTotal: 12,
  declaredTier: "high",
  featureTriggers: [
    "custom-accounting",
    "custom-math",
    "external-calls",
    "external-liquidity",
    "hook-held-liquidity",
    "price-impact",
    "project-custody",
    "project-external-calls",
    "project-value-flow",
    "return-delta",
  ],
};
const buildInfoFiles = fs.existsSync(new URL("../evidence/build-info", import.meta.url))
  ? fs
      .readdirSync(new URL("../evidence/build-info", import.meta.url))
      .filter((name) => name.endsWith(".json"))
      .sort()
      .map((name) => `evidence/build-info/${name}`)
  : [];
submission.implementation = {
  sourcePaths: SOURCE_PATHS,
  testPaths: TEST_PATHS,
  compilerBuildInfoPaths: buildInfoFiles,
  specificationPath: "MECHANISM.md",
  testEvidencePath: "EVIDENCE.md",
  dependencyLockPath: "submissions/soft-landing/dependency-lock.json",
  gateStatusPath: "submissions/soft-landing/gate-status.json",
  reviewTargetPath: "submissions/soft-landing/review-target.json",
  runtimeAssetManifestPath: null,
};
submission.disclosures = [
  "Prototype only: repository tests passed locally, but the hook is not audited, accepted, deployed, source-verified, runtime-matched, routed, monitored, or live.",
  "Soft Landing prices sustained directional launch congestion one block later; it does not stop reordering, private bundles, wash flow, or a packed first-block snipe.",
  "Paid executed flow can raise a following block's directional LP fee; the hook cannot distinguish manipulative and organic throughput without identity or an external dependency.",
  "A higher sell fee during panic can increase exit cost; immutable base, decay, duration, targets, and a 300 bps product cap must be publicly reviewed before deployment.",
  "The hook-owned charge is exactly 10 bps to the immutable Programmable owner and zero to the project; LP fees are separate and belong to LPs.",
  "Specified-quote partial fills and positive gross quote below 1,000 smallest units revert under the declared accounting policy.",
  "The canonical application uses native ETH as currency0 quote and a standard fixed-supply launched token as currency1; the implementation tests both quote orderings.",
  "No wallet identity, tx.origin, holding time, allowlist, denylist, oracle, keeper, pause, upgrade, rescue, creator claim, project fee, or mutable fee setter exists.",
];
submission.noHookArchitecture = null;
submission.tokenBehaviorExtensions = [];
submission.unresolved = [];

fs.writeFileSync(path, `${JSON.stringify(submission, null, 2)}\n`);
