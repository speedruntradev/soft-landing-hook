// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { BaseHook } from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import { CurrencySettler } from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { LPFeeLibrary } from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { FlowFeeMath } from "./lib/FlowFeeMath.sol";

struct SoftLandingConfig {
    uint24 baseFeePips;
    uint24 initialBuyFeePips;
    uint24 initialSellFeePips;
    uint24 maxFeePips;
    uint24 riseAt2xTargetPips;
    uint24 decayAtZeroPips;
    uint32 maxExcessBps;
    uint64 warmupBlocks;
    uint256 targetQuotePerBlock;
}

/// @title Soft Landing
/// @notice Block-stable directional congestion pricing for one Uniswap v4 launch pool.
/// @dev Prototype only. This contract is not independently audited, approved, deployed, routed, or live.
contract SoftLandingHook is BaseHook, IUnlockCallback, ReentrancyGuardTransient {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencySettler for Currency;
    using LPFeeLibrary for uint24;
    using SafeCast for *;

    uint256 public constant RATE_DENOMINATOR = 1_000_000;
    uint32 public constant PROGRAMMABLE_HUNDREDTHS_OF_BIP = 1000;
    uint256 public constant MIN_GROSS_QUOTE_AMOUNT = 1000;
    uint24 public constant MAX_PRODUCT_LP_FEE_PIPS = 30_000;
    uint32 public constant MAX_EXCESS_BPS_LIMIT = 100_000;
    uint64 public constant MAX_WARMUP_BLOCKS = 1_000_000;
    bool public constant SAME_POOL_SWAP_FORBIDDEN = true;
    address public constant PROGRAMMABLE_FEE_OWNER = 0x4957f49620AFf3Adbbe8195a4f633E49cc93376c;

    bytes4 private constant CLAIM_UNLOCK_MAGIC = bytes4(keccak256("SOFT_LANDING_PROGRAMMABLE_FEE_V1_CLAIM"));

    struct DirectionState {
        uint256 flow;
        uint24 fee;
    }

    address public immutable registrar;
    address public immutable quoteCurrencyAddress;
    uint24 public immutable baseFeePips;
    uint24 public immutable initialBuyFeePips;
    uint24 public immutable initialSellFeePips;
    uint24 public immutable maxFeePips;
    uint24 public immutable riseAt2xTargetPips;
    uint24 public immutable decayAtZeroPips;
    uint32 public immutable maxExcessBps;
    uint64 public immutable warmupBlocks;
    uint256 public immutable targetQuotePerBlock;

    bytes32 public canonicalPoolId;
    bool public canonicalPoolRegistered;
    bool public quoteIsCurrency0;

    DirectionState public buyState;
    DirectionState public sellState;
    uint256 public startBlock;
    uint256 public lastObservedBlock;
    bool public started;
    bool public expired;

    uint256 public totalQuoteFeesAccrued;
    uint256 public programmableFeeRemainder;
    uint256 private _pendingSpecifiedQuotePoolAmountPlusOne;
    uint256 private _pendingGrossQuoteAmount;
    mapping(bytes32 poolId => mapping(address currency => mapping(address owner => uint256 amount))) private
        _claimableLiability;

    error AlreadyRegistered(bytes32 poolId);
    error CurrenciesOutOfOrderOrEqual(address currency0, address currency1);
    error ExactOutputRoundingUnsupported(uint256 netQuoteAmount);
    error InvalidControllerConfiguration();
    error InvalidHook(address actual, address expected);
    error InvalidLpFee(uint24 fee);
    error InvalidQuoteCurrency(address currency0, address currency1, address expectedQuoteCurrency);
    error InvalidTickSpacing(int24 tickSpacing);
    error LiabilityInvariantBroken(uint256 claims, uint256 liability);
    error NoFeesToClaim();
    error PartialFillUnsupported(uint256 expectedQuotePoolAmount, uint256 actualQuotePoolAmount);
    error PendingSpecifiedQuoteCallback();
    error PoolNotRegistered();
    error QuoteAmountBelowFeeQuantum(uint256 grossQuoteAmount, uint256 minimumGrossQuoteAmount);
    error UnauthorizedClaim(address caller, address expected);
    error UnauthorizedInitializer(address caller, address expected);
    error UnauthorizedRegistrar(address caller, address expected);
    error UnexpectedPool(bytes32 actual, bytes32 expected);
    error UnexpectedUnlockData();
    error UnexpectedUnlockResult();
    error ZeroAddress();

    event CanonicalPoolRegistered(
        bytes32 indexed poolId,
        address indexed quoteCurrency,
        uint256 targetQuotePerBlock,
        uint64 warmupBlocks,
        uint24 baseFeePips,
        uint24 initialBuyFeePips,
        uint24 initialSellFeePips,
        uint24 maxFeePips
    );
    event ControllerStarted(uint256 indexed startBlock, uint256 indexed endBlockExclusive);
    event ControllerRolled(
        uint256 indexed completedBlock,
        uint256 indexed currentBlock,
        uint256 buyFlow,
        uint256 sellFlow,
        uint24 nextBuyFeePips,
        uint24 nextSellFeePips,
        uint256 emptyBlocks
    );
    event ControllerExpired(uint256 indexed blockNumber, uint24 baseFeePips);
    event QuoteFlowRecorded(
        bytes32 indexed poolId,
        uint256 indexed blockNumber,
        bool indexed isBuy,
        uint256 grossQuoteAmount,
        uint256 totalFlow
    );
    event QuoteFeesAccrued(
        bytes32 indexed poolId,
        address indexed quoteCurrency,
        address indexed swapSender,
        bool isBuy,
        uint256 grossQuoteAmount,
        uint256 programmableFee,
        uint256 programmableRemainder
    );
    event ProgrammableFeesClaimed(
        bytes32 indexed poolId, address indexed quoteCurrency, address indexed owner, address recipient, uint256 amount
    );

    constructor(
        IPoolManager poolManager_,
        address registrar_,
        address quoteCurrencyAddress_,
        SoftLandingConfig memory config
    ) BaseHook(poolManager_) {
        if (address(poolManager_) == address(0) || registrar_ == address(0)) {
            revert ZeroAddress();
        }
        _validateControllerConfig(config);
        registrar = registrar_;
        // address(0) is Uniswap v4's canonical native-currency representation.
        // slither-disable-next-line missing-zero-check
        quoteCurrencyAddress = quoteCurrencyAddress_;
        baseFeePips = config.baseFeePips;
        initialBuyFeePips = config.initialBuyFeePips;
        initialSellFeePips = config.initialSellFeePips;
        maxFeePips = config.maxFeePips;
        riseAt2xTargetPips = config.riseAt2xTargetPips;
        decayAtZeroPips = config.decayAtZeroPips;
        maxExcessBps = config.maxExcessBps;
        warmupBlocks = config.warmupBlocks;
        targetQuotePerBlock = config.targetQuotePerBlock;
        buyState.fee = config.initialBuyFeePips;
        sellState.fee = config.initialSellFeePips;
    }

    /// @notice Atomically binds and initializes the only PoolKey accepted by this hook.
    function registerCanonicalPool(PoolKey calldata key, uint160 sqrtPriceX96)
        external
        nonReentrant
        returns (bytes32 poolId, int24 initialTick)
    {
        if (msg.sender != registrar) revert UnauthorizedRegistrar(msg.sender, registrar);
        if (canonicalPoolRegistered) revert AlreadyRegistered(canonicalPoolId);
        _validatePoolShape(key);

        poolId = PoolId.unwrap(key.toId());
        canonicalPoolId = poolId;
        canonicalPoolRegistered = true;
        quoteIsCurrency0 = Currency.unwrap(key.currency0) == quoteCurrencyAddress;

        initialTick = poolManager.initialize(key, sqrtPriceX96);
        // Preserve an explicit stored base fee even though every swap uses a directional override.
        poolManager.updateDynamicLPFee(key, baseFeePips);
        emit CanonicalPoolRegistered(
            poolId,
            quoteCurrencyAddress,
            targetQuotePerBlock,
            warmupBlocks,
            baseFeePips,
            initialBuyFeePips,
            initialSellFeePips,
            maxFeePips
        );
    }

    function currentFee(bool isBuy) external view returns (uint24) {
        return expired ? baseFeePips : (isBuy ? buyState.fee : sellState.fee);
    }

    function endBlockExclusive() external view returns (uint256) {
        return started ? startBlock + warmupBlocks : 0;
    }

    function claimableLiability(bytes32 poolId, address currency, address owner) external view returns (uint256) {
        return _claimableLiability[poolId][currency][owner];
    }

    function programmableFeesAccrued() public view returns (uint256) {
        return _claimableLiability[canonicalPoolId][quoteCurrencyAddress][PROGRAMMABLE_FEE_OWNER];
    }

    function quoteGrossFee(uint256 grossQuoteAmount)
        external
        view
        returns (uint256 programmableFee, uint256 nextRemainder)
    {
        return _feeForGross(grossQuoteAmount);
    }

    function quoteExactOutputFee(uint256 netQuoteAmount)
        external
        view
        returns (uint256 grossQuoteAmount, uint256 programmableFee, uint256 nextRemainder)
    {
        return _feeForNet(netQuoteAmount);
    }

    /// @notice Only the fixed Programmable owner may initiate a claim and select its destination.
    function claimProgrammableFees(address recipient) external nonReentrant returns (uint256 amount) {
        if (msg.sender != PROGRAMMABLE_FEE_OWNER) revert UnauthorizedClaim(msg.sender, PROGRAMMABLE_FEE_OWNER);
        if (recipient == address(0)) revert ZeroAddress();
        if (!canonicalPoolRegistered) revert PoolNotRegistered();
        amount = programmableFeesAccrued();
        if (amount == 0) revert NoFeesToClaim();

        _claimableLiability[canonicalPoolId][quoteCurrencyAddress][PROGRAMMABLE_FEE_OWNER] = 0;
        totalQuoteFeesAccrued -= amount;
        _redeemQuote(recipient, amount);
        emit ProgrammableFeesClaimed(canonicalPoolId, quoteCurrencyAddress, PROGRAMMABLE_FEE_OWNER, recipient, amount);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
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
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address sender, PoolKey calldata key, uint160) internal view override returns (bytes4) {
        _requireCanonicalPool(key);
        if (sender != address(this)) revert UnauthorizedInitializer(sender, address(this));
        return IHooks.beforeInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _requireCanonicalPool(key);
        _prepareControllerForSwap();

        bool exactInput = params.amountSpecified < 0;
        bool specifiedIsCurrency0 = params.zeroForOne == exactInput;
        bool quoteIsSpecified = specifiedIsCurrency0 == quoteIsCurrency0;
        bool isBuy = params.zeroForOne == quoteIsCurrency0;
        uint24 feeOverride =
            (expired ? baseFeePips : (isBuy ? buyState.fee : sellState.fee)) | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        if (!quoteIsSpecified) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeOverride);
        }

        if (_pendingSpecifiedQuotePoolAmountPlusOne != 0) revert PendingSpecifiedQuoteCallback();
        uint256 quoteAmount = _absolute(params.amountSpecified);
        (uint256 grossQuoteAmount, uint256 programmableFee) = _chargeQuote(sender, isBuy, quoteAmount, !exactInput);
        uint256 expectedQuotePoolAmount = exactInput ? quoteAmount - programmableFee : quoteAmount + programmableFee;
        _pendingSpecifiedQuotePoolAmountPlusOne = expectedQuotePoolAmount + 1;
        _pendingGrossQuoteAmount = grossQuoteAmount;
        BeforeSwapDelta hookDelta = programmableFee == 0
            ? BeforeSwapDeltaLibrary.ZERO_DELTA
            : toBeforeSwapDelta(programmableFee.toInt256().toInt128(), 0);
        return (IHooks.beforeSwap.selector, hookDelta, feeOverride);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        _requireCanonicalPool(key);
        bool exactInput = params.amountSpecified < 0;
        bool specifiedIsCurrency0 = params.zeroForOne == exactInput;
        bool quoteIsSpecified = specifiedIsCurrency0 == quoteIsCurrency0;
        bool isBuy = params.zeroForOne == quoteIsCurrency0;

        if (quoteIsSpecified) {
            uint256 pendingPlusOne = _pendingSpecifiedQuotePoolAmountPlusOne;
            if (pendingPlusOne == 0) revert PendingSpecifiedQuoteCallback();
            uint256 expectedQuotePoolAmount = pendingPlusOne - 1;
            uint256 pendingGrossQuoteAmount = _pendingGrossQuoteAmount;
            _pendingSpecifiedQuotePoolAmountPlusOne = 0;
            _pendingGrossQuoteAmount = 0;
            uint256 actualQuotePoolAmount = _absolute(_quoteDelta(delta));
            if (actualQuotePoolAmount != expectedQuotePoolAmount) {
                revert PartialFillUnsupported(expectedQuotePoolAmount, actualQuotePoolAmount);
            }
            _recordFlow(isBuy, pendingGrossQuoteAmount);
            return (IHooks.afterSwap.selector, 0);
        }

        uint256 executedQuoteAmount = _absolute(_quoteDelta(delta));
        (uint256 grossQuoteAmount, uint256 programmableFee) =
            _chargeQuote(sender, isBuy, executedQuoteAmount, !exactInput);
        _recordFlow(isBuy, grossQuoteAmount);
        return (IHooks.afterSwap.selector, programmableFee == 0 ? int128(0) : programmableFee.toInt256().toInt128());
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        (bytes4 magic, address recipient, uint256 amount) = abi.decode(data, (bytes4, address, uint256));
        if (magic != CLAIM_UNLOCK_MAGIC || recipient == address(0) || amount == 0) revert UnexpectedUnlockData();
        Currency quote = Currency.wrap(quoteCurrencyAddress);
        quote.settle(poolManager, address(this), amount, true);
        quote.take(poolManager, recipient, amount, false);
        return "";
    }

    function _prepareControllerForSwap() private {
        uint256 currentBlock = block.number;
        if (!started) {
            started = true;
            startBlock = currentBlock;
            lastObservedBlock = currentBlock;
            emit ControllerStarted(currentBlock, currentBlock + warmupBlocks);
            return;
        }
        if (expired || currentBlock == lastObservedBlock) return;

        if (currentBlock >= startBlock + warmupBlocks) {
            expired = true;
            buyState = DirectionState({ flow: 0, fee: baseFeePips });
            sellState = DirectionState({ flow: 0, fee: baseFeePips });
            lastObservedBlock = currentBlock;
            emit ControllerExpired(currentBlock, baseFeePips);
            return;
        }

        uint256 completedBlock = lastObservedBlock;
        uint256 buyFlow = buyState.flow;
        uint256 sellFlow = sellState.flow;
        uint24 nextBuy = _nextFee(buyFlow, buyState.fee);
        uint24 nextSell = _nextFee(sellFlow, sellState.fee);
        uint256 emptyBlocks = currentBlock - completedBlock - 1;
        nextBuy = FlowFeeMath.decayEmptyBlocks(nextBuy, baseFeePips, decayAtZeroPips, emptyBlocks);
        nextSell = FlowFeeMath.decayEmptyBlocks(nextSell, baseFeePips, decayAtZeroPips, emptyBlocks);
        buyState = DirectionState({ flow: 0, fee: nextBuy });
        sellState = DirectionState({ flow: 0, fee: nextSell });
        lastObservedBlock = currentBlock;
        emit ControllerRolled(completedBlock, currentBlock, buyFlow, sellFlow, nextBuy, nextSell, emptyBlocks);
    }

    function _nextFee(uint256 flow, uint24 fee) private view returns (uint24) {
        return FlowFeeMath.nextFee(
            flow, targetQuotePerBlock, fee, baseFeePips, maxFeePips, riseAt2xTargetPips, decayAtZeroPips, maxExcessBps
        );
    }

    function _recordFlow(bool isBuy, uint256 grossQuoteAmount) private {
        if (expired || grossQuoteAmount == 0) return;
        DirectionState storage state = isBuy ? buyState : sellState;
        state.flow += grossQuoteAmount;
        emit QuoteFlowRecorded(canonicalPoolId, block.number, isBuy, grossQuoteAmount, state.flow);
    }

    function _chargeQuote(address sender, bool isBuy, uint256 quoteAmount, bool amountIsNet)
        private
        returns (uint256 grossQuoteAmount, uint256 programmableFee)
    {
        uint256 nextRemainder;
        if (amountIsNet) {
            (grossQuoteAmount, programmableFee, nextRemainder) = _feeForNet(quoteAmount);
        } else {
            grossQuoteAmount = quoteAmount;
            (programmableFee, nextRemainder) = _feeForGross(grossQuoteAmount);
        }
        if (grossQuoteAmount == 0) return (0, 0);

        programmableFeeRemainder = nextRemainder;
        _claimableLiability[canonicalPoolId][quoteCurrencyAddress][PROGRAMMABLE_FEE_OWNER] += programmableFee;
        totalQuoteFeesAccrued += programmableFee;
        uint256 liability = programmableFeesAccrued();
        if (totalQuoteFeesAccrued != liability) revert LiabilityInvariantBroken(totalQuoteFeesAccrued, liability);

        emit QuoteFeesAccrued(
            canonicalPoolId, quoteCurrencyAddress, sender, isBuy, grossQuoteAmount, programmableFee, nextRemainder
        );
        if (programmableFee != 0) {
            Currency.wrap(quoteCurrencyAddress).take(poolManager, address(this), programmableFee, true);
        }
    }

    function _feeForGross(uint256 grossQuoteAmount)
        private
        view
        returns (uint256 programmableFee, uint256 nextRemainder)
    {
        if (grossQuoteAmount != 0 && grossQuoteAmount < MIN_GROSS_QUOTE_AMOUNT) {
            revert QuoteAmountBelowFeeQuantum(grossQuoteAmount, MIN_GROSS_QUOTE_AMOUNT);
        }
        programmableFee = FullMath.mulDiv(grossQuoteAmount, PROGRAMMABLE_HUNDREDTHS_OF_BIP, RATE_DENOMINATOR);
        uint256 fractional = mulmod(grossQuoteAmount, PROGRAMMABLE_HUNDREDTHS_OF_BIP, RATE_DENOMINATOR);
        uint256 combinedRemainder = fractional + programmableFeeRemainder;
        programmableFee += combinedRemainder / RATE_DENOMINATOR;
        nextRemainder = combinedRemainder % RATE_DENOMINATOR;
    }

    function _feeForNet(uint256 netQuoteAmount)
        private
        view
        returns (uint256 grossQuoteAmount, uint256 programmableFee, uint256 nextRemainder)
    {
        if (netQuoteAmount == 0) return (0, 0, programmableFeeRemainder);
        uint256 estimate = FullMath.mulDivRoundingUp(
            netQuoteAmount, RATE_DENOMINATOR, RATE_DENOMINATOR - PROGRAMMABLE_HUNDREDTHS_OF_BIP
        );
        uint256 candidate = estimate > 8 ? estimate - 8 : MIN_GROSS_QUOTE_AMOUNT;
        if (candidate < MIN_GROSS_QUOTE_AMOUNT) candidate = MIN_GROSS_QUOTE_AMOUNT;
        for (uint256 index; index < 17; ++index) {
            (uint256 candidateFee, uint256 candidateRemainder) = _feeForGross(candidate);
            if (candidateFee <= candidate && candidate - candidateFee == netQuoteAmount) {
                return (candidate, candidateFee, candidateRemainder);
            }
            ++candidate;
        }
        revert ExactOutputRoundingUnsupported(netQuoteAmount);
    }

    function _redeemQuote(address recipient, uint256 amount) private {
        bytes memory result = poolManager.unlock(abi.encode(CLAIM_UNLOCK_MAGIC, recipient, amount));
        if (result.length != 0) revert UnexpectedUnlockResult();
    }

    function _requireCanonicalPool(PoolKey calldata key) private view returns (bytes32 poolId) {
        if (!canonicalPoolRegistered) revert PoolNotRegistered();
        _validatePoolShape(key);
        poolId = PoolId.unwrap(key.toId());
        if (poolId != canonicalPoolId) revert UnexpectedPool(poolId, canonicalPoolId);
    }

    function _validatePoolShape(PoolKey calldata key) private view {
        if (address(key.hooks) != address(this)) revert InvalidHook(address(key.hooks), address(this));
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        if (currency0 >= currency1) revert CurrenciesOutOfOrderOrEqual(currency0, currency1);
        if (key.tickSpacing < TickMath.MIN_TICK_SPACING || key.tickSpacing > TickMath.MAX_TICK_SPACING) {
            revert InvalidTickSpacing(key.tickSpacing);
        }
        if (!key.fee.isDynamicFee()) revert InvalidLpFee(key.fee);
        if (currency0 != quoteCurrencyAddress && currency1 != quoteCurrencyAddress) {
            revert InvalidQuoteCurrency(currency0, currency1, quoteCurrencyAddress);
        }
    }

    function _validateControllerConfig(SoftLandingConfig memory config) private pure {
        bool invalid = config.baseFeePips == 0 || config.baseFeePips > config.initialBuyFeePips
            || config.baseFeePips > config.initialSellFeePips || config.initialBuyFeePips > config.maxFeePips
            || config.initialSellFeePips > config.maxFeePips || config.maxFeePips > MAX_PRODUCT_LP_FEE_PIPS
            || config.riseAt2xTargetPips == 0 || config.riseAt2xTargetPips > config.maxFeePips - config.baseFeePips
            || config.decayAtZeroPips == 0 || config.decayAtZeroPips > config.maxFeePips - config.baseFeePips
            || config.maxExcessBps == 0 || config.maxExcessBps > MAX_EXCESS_BPS_LIMIT || config.warmupBlocks == 0
            || config.warmupBlocks > MAX_WARMUP_BLOCKS || config.targetQuotePerBlock == 0
            || config.targetQuotePerBlock > type(uint128).max;
        if (invalid) revert InvalidControllerConfiguration();
    }

    function _quoteDelta(BalanceDelta delta) private view returns (int256) {
        return quoteIsCurrency0 ? int256(delta.amount0()) : int256(delta.amount1());
    }

    function _absolute(int256 value) private pure returns (uint256) {
        return SignedMath.abs(value);
    }
}
