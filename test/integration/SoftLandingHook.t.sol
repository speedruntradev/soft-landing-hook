// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseHook } from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { CustomRevert } from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { LPFeeLibrary } from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { BeforeSwapDelta } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { ModifyLiquidityParams, SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { SoftLandingConfig, SoftLandingHook } from "../../src/SoftLandingHook.sol";
import { SoftLandingHookFactory } from "../../src/SoftLandingHookFactory.sol";
import { MockToken } from "../helpers/MockToken.sol";

contract SoftLandingHookTest is Deployers {
    using SafeCast for uint256;

    uint256 internal constant RATE_DENOMINATOR = 1_000_000;
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant TARGET = 1 ether;

    SoftLandingHookFactory internal hookFactory;
    SoftLandingHook internal hook;
    MockToken internal projectToken;
    PoolKey internal hookKey;
    bytes32 internal poolId;
    SoftLandingConfig internal config;

    address internal attacker = makeAddr("attacker");
    PoolSwapTest.TestSettings internal settings =
        PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });

    function setUp() public {
        deployFreshManagerAndRouters();
        vm.deal(address(this), 1_000_000 ether);

        config = SoftLandingConfig({
            baseFeePips: 3000,
            initialBuyFeePips: 10_000,
            initialSellFeePips: 10_000,
            maxFeePips: 30_000,
            riseAt2xTargetPips: 5000,
            decayAtZeroPips: 2500,
            maxExcessBps: 30_000,
            warmupBlocks: 10,
            targetQuotePerBlock: TARGET
        });

        hookFactory = new SoftLandingHookFactory();
        projectToken = new MockToken("Soft Landing Project", "SLP", 1_000_000 ether);
        projectToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        projectToken.approve(address(swapRouter), type(uint256).max);

        (hook, hookKey,) = _deployNativeQuoteHook(config);
        poolId = PoolId.unwrap(hookKey.toId());
        _addNativeQuoteLiquidity(hookKey, 100_000 ether);
    }

    function testFirstSwapStartsWindowAndRecordsGrossBuyFlow() public {
        uint256 launchBlock = block.number;
        _swapNativeQuote(true, -int256(2.5 ether), 2.5 ether);

        assertTrue(hook.started());
        assertFalse(hook.expired());
        assertEq(hook.startBlock(), launchBlock);
        assertEq(hook.lastObservedBlock(), launchBlock);
        (uint256 buyFlow, uint24 buyFee) = hook.buyState();
        assertEq(buyFlow, 2.5 ether);
        assertEq(buyFee, config.initialBuyFeePips);
        (uint256 sellFlow, uint24 sellFee) = hook.sellState();
        assertEq(sellFlow, 0);
        assertEq(sellFee, config.initialSellFeePips);
    }

    function testCompletedDirectionalFlowSetsOnlyNextBlockFee() public {
        _swapNativeQuote(true, -int256(2.5 ether), 2.5 ether);
        assertEq(hook.currentFee(true), 10_000);
        assertEq(hook.currentFee(false), 10_000);

        vm.roll(block.number + 1);
        _swapNativeQuote(false, -int256(0.01 ether), 0);
        assertEq(hook.currentFee(true), 17_500, "buy fee reflects prior 150% excess");
        assertEq(hook.currentFee(false), 7500, "zero sell flow decays independently");

        _swapNativeQuote(true, -int256(0.01 ether), 0.01 ether);
        assertEq(hook.currentFee(true), 17_500, "same-block buy fee is stable");
        assertEq(hook.currentFee(false), 7500, "same-block sell fee is stable");
    }

    function testSkippedBlocksDecayInConstantTime() public {
        _swapNativeQuote(true, -int256(2.5 ether), 2.5 ether);
        vm.roll(block.number + 4);
        _swapNativeQuote(false, -int256(0.01 ether), 0);

        assertEq(hook.currentFee(true), 10_000, "17,500 after flow then three empty decays");
        assertEq(hook.currentFee(false), 3000, "sell fee saturates at base");
    }

    function testExpiryIsIrreversibleAndStopsFlowWritesButNotPlatformFees() public {
        _swapNativeQuote(true, -int256(2.5 ether), 2.5 ether);
        uint256 end = hook.startBlock() + config.warmupBlocks;
        uint256 feesBefore = hook.programmableFeesAccrued();
        vm.roll(end);
        _swapNativeQuote(true, -int256(1 ether), 1 ether);

        assertTrue(hook.expired());
        assertEq(hook.currentFee(true), config.baseFeePips);
        assertEq(hook.currentFee(false), config.baseFeePips);
        (uint256 buyFlow,) = hook.buyState();
        (uint256 sellFlow,) = hook.sellState();
        assertEq(buyFlow, 0);
        assertEq(sellFlow, 0);
        assertGt(hook.programmableFeesAccrued(), feesBefore, "mandatory fee survives controller expiry");

        vm.roll(end + 1000);
        _swapNativeQuote(false, -int256(0.01 ether), 0);
        assertTrue(hook.expired());
        assertEq(hook.currentFee(true), config.baseFeePips);
        assertEq(hook.currentFee(false), config.baseFeePips);
    }

    function testDynamicOverridePermissionAndSameBlockValue() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.beforeSwapReturnDelta);
        assertTrue(permissions.afterSwapReturnDelta);
        assertEq(uint160(address(hook)) & hookFactory.ALL_HOOK_MASK(), hookFactory.REQUIRED_HOOK_FLAGS());

        SwapParams memory sellExactInput =
            SwapParams({ zeroForOne: false, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: MAX_PRICE_LIMIT });
        vm.prank(address(manager));
        (, BeforeSwapDelta delta, uint24 firstOverride) =
            hook.beforeSwap(address(this), hookKey, sellExactInput, ZERO_BYTES);
        vm.prank(address(manager));
        (, BeforeSwapDelta secondDelta, uint24 secondOverride) =
            hook.beforeSwap(address(this), hookKey, sellExactInput, ZERO_BYTES);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(BeforeSwapDelta.unwrap(secondDelta), 0);
        assertEq(firstOverride, config.initialSellFeePips | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        assertEq(secondOverride, firstOverride);
    }

    function testAllNativeQuoteQuadrantsAccrueExecutedGrossQuote() public {
        uint256 beforeFees = hook.programmableFeesAccrued();
        _swapNativeQuote(true, -int256(1 ether), 1 ether); // quote specified, exact input
        uint256 afterFirst = hook.programmableFeesAccrued();
        assertGt(afterFirst, beforeFees);

        _swapNativeQuote(true, int256(0.01 ether), 1 ether); // quote unspecified, exact output
        uint256 afterSecond = hook.programmableFeesAccrued();
        assertGt(afterSecond, afterFirst);

        _swapNativeQuote(false, -int256(0.01 ether), 0); // quote unspecified, exact input
        uint256 afterThird = hook.programmableFeesAccrued();
        assertGt(afterThird, afterSecond);

        _swapNativeQuote(false, int256(0.005 ether), 0); // quote specified, exact output
        assertGt(hook.programmableFeesAccrued(), afterThird);
    }

    function testErc20QuoteCurrencyOneCoversAllFourQuadrants() public {
        MockToken tokenA = new MockToken("Token A", "A", 100_000 ether);
        MockToken tokenB = new MockToken("Token B", "B", 100_000 ether);
        MockToken lower = address(tokenA) < address(tokenB) ? tokenA : tokenB;
        MockToken quote = address(tokenA) < address(tokenB) ? tokenB : tokenA;
        lower.approve(address(modifyLiquidityRouter), type(uint256).max);
        quote.approve(address(modifyLiquidityRouter), type(uint256).max);
        lower.approve(address(swapRouter), type(uint256).max);
        quote.approve(address(swapRouter), type(uint256).max);

        (SoftLandingHook erc20Hook, PoolKey memory key,) =
            _deployHook(Currency.wrap(address(lower)), Currency.wrap(address(quote)), address(quote), config);
        ModifyLiquidityParams memory liquidity =
            ModifyLiquidityParams({ tickLower: -120, tickUpper: 120, liquidityDelta: 10_000 ether, salt: 0 });
        modifyLiquidityRouter.modifyLiquidity(key, liquidity, ZERO_BYTES);
        assertFalse(erc20Hook.quoteIsCurrency0());

        swapRouter.swap(
            key,
            SwapParams({ zeroForOne: true, amountSpecified: -int256(0.01 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT }),
            settings,
            ZERO_BYTES
        );
        uint256 first = erc20Hook.programmableFeesAccrued();
        swapRouter.swap(
            key,
            SwapParams({ zeroForOne: true, amountSpecified: int256(0.005 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT }),
            settings,
            ZERO_BYTES
        );
        uint256 second = erc20Hook.programmableFeesAccrued();
        swapRouter.swap(
            key,
            SwapParams({ zeroForOne: false, amountSpecified: -int256(0.01 ether), sqrtPriceLimitX96: MAX_PRICE_LIMIT }),
            settings,
            ZERO_BYTES
        );
        uint256 third = erc20Hook.programmableFeesAccrued();
        swapRouter.swap(
            key,
            SwapParams({ zeroForOne: false, amountSpecified: int256(0.005 ether), sqrtPriceLimitX96: MAX_PRICE_LIMIT }),
            settings,
            ZERO_BYTES
        );
        assertGt(first, 0);
        assertGt(second, first);
        assertGt(third, second);
        assertGt(erc20Hook.programmableFeesAccrued(), third);
        (uint256 buyFlow,) = erc20Hook.buyState();
        (uint256 sellFlow,) = erc20Hook.sellState();
        assertGt(buyFlow, 0, "quote-input swaps are buys even when quote is currency1");
        assertGt(sellFlow, 0, "quote-output swaps are sells even when quote is currency1");
    }

    function testSpecifiedQuotePartialFillRevertsAtomically() public {
        try swapRouter.swap{ value: 100 ether }(
            hookKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(100 ether),
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(-1)
            }),
            settings,
            ZERO_BYTES
        ) returns (
            BalanceDelta
        ) {
            fail();
        } catch (bytes memory reason) {
            _assertWrappedPartialFillError(reason);
        }
        assertEq(hook.totalQuoteFeesAccrued(), 0);
        assertFalse(hook.started(), "controller start rolls back too");
    }

    function testCumulativeRemainderResistsFragmentation() public {
        uint256 grossPerSwap = 1999;
        _swapNativeQuote(true, -grossPerSwap.toInt256(), grossPerSwap);
        _swapNativeQuote(true, -grossPerSwap.toInt256(), grossPerSwap);
        uint256 cumulativeGross = grossPerSwap * 2;
        assertEq(
            hook.programmableFeesAccrued(),
            FullMath.mulDiv(cumulativeGross, hook.PROGRAMMABLE_HUNDREDTHS_OF_BIP(), RATE_DENOMINATOR)
        );
        assertEq(hook.programmableFeeRemainder(), 998_000);
    }

    function testDustAndExactOutputRounding() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SoftLandingHook.QuoteAmountBelowFeeQuantum.selector, uint256(999), hook.MIN_GROSS_QUOTE_AMOUNT()
            )
        );
        hook.quoteGrossFee(999);
        (uint256 fee,) = hook.quoteGrossFee(1000);
        assertEq(fee, 1);
        (uint256 gross, uint256 exactOutputFee,) = hook.quoteExactOutputFee(999);
        assertEq(gross, 1000);
        assertEq(exactOutputFee, 1);
        assertEq(gross - exactOutputFee, 999);
    }

    function testProgrammableOwnerOnlyClaimToPerClaimDestination() public {
        _swapNativeQuote(true, -int256(1 ether), 1 ether);
        address owner = hook.PROGRAMMABLE_FEE_OWNER();
        uint256 amount = hook.programmableFeesAccrued();
        address recipient = makeAddr("programmableDestination");

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(SoftLandingHook.UnauthorizedClaim.selector, attacker, owner));
        hook.claimProgrammableFees(attacker);

        uint256 remainderBefore = hook.programmableFeeRemainder();
        assertEq(
            manager.balanceOf(address(hook), CurrencyLibrary.ADDRESS_ZERO.toId()),
            amount,
            "PoolManager claims back the liability"
        );
        vm.prank(owner);
        hook.claimProgrammableFees(recipient);
        assertEq(recipient.balance, amount);
        assertEq(hook.programmableFeesAccrued(), 0);
        assertEq(hook.totalQuoteFeesAccrued(), 0);
        assertEq(hook.programmableFeeRemainder(), remainderBefore, "claims never reset cumulative remainder");
    }

    function testCanonicalPoolAndCallbackAuthentication() public {
        PoolKey memory altered = hookKey;
        altered.tickSpacing = 10;
        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT });

        vm.prank(address(manager));
        vm.expectRevert();
        hook.beforeSwap(address(this), altered, params, ZERO_BYTES);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), hookKey, params, ZERO_BYTES);
        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterSwap(address(this), hookKey, params, BalanceDelta.wrap(0), ZERO_BYTES);
        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.unlockCallback(ZERO_BYTES);
    }

    function testFuzzGrossFeePolicy(uint96 rawGross) public view {
        uint256 gross = bound(uint256(rawGross), 1000, 1_000_000 ether);
        (uint256 fee,) = hook.quoteGrossFee(gross);
        assertEq(fee, FullMath.mulDiv(gross, hook.PROGRAMMABLE_HUNDREDTHS_OF_BIP(), RATE_DENOMINATOR));
    }

    function testFuzzExactOutputRounding(uint96 rawNet) public view {
        uint256 net = bound(uint256(rawNet), 1000, 1_000_000 ether);
        (uint256 gross, uint256 fee,) = hook.quoteExactOutputFee(net);
        assertEq(gross - fee, net);
    }

    function _deployNativeQuoteHook(SoftLandingConfig memory config_)
        private
        returns (SoftLandingHook deployed, PoolKey memory key, int24 tick)
    {
        return _deployHook(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(projectToken)), address(0), config_);
    }

    function _deployHook(
        Currency currency0,
        Currency currency1,
        address quoteCurrency,
        SoftLandingConfig memory config_
    ) private returns (SoftLandingHook deployed, PoolKey memory key, int24 tick) {
        (, bytes32 salt) = HookMiner.find(
            address(hookFactory),
            hookFactory.REQUIRED_HOOK_FLAGS(),
            type(SoftLandingHook).creationCode,
            abi.encode(manager, address(hookFactory), quoteCurrency, config_)
        );
        return hookFactory.deployAndInitialize(
            salt, manager, currency0, currency1, TICK_SPACING, quoteCurrency, config_, SQRT_PRICE_1_1
        );
    }

    function _addNativeQuoteLiquidity(PoolKey memory key, uint256 amount) private {
        ModifyLiquidityParams memory liquidity =
            ModifyLiquidityParams({ tickLower: -120, tickUpper: 120, liquidityDelta: 100_000 ether, salt: 0 });
        modifyLiquidityRouter.modifyLiquidity{ value: amount }(key, liquidity, ZERO_BYTES);
    }

    function _swapNativeQuote(bool zeroForOne, int256 amountSpecified, uint256 value) private returns (BalanceDelta) {
        return swapRouter.swap{ value: value }(
            hookKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            settings,
            ZERO_BYTES
        );
    }

    function decodeWrappedError(bytes calldata reason)
        external
        pure
        returns (address target, bytes4 callbackSelector, bytes memory innerReason, bytes memory details)
    {
        require(reason.length >= 4 && bytes4(reason[:4]) == CustomRevert.WrappedError.selector, "not WrappedError");
        return abi.decode(reason[4:], (address, bytes4, bytes, bytes));
    }

    function _assertWrappedPartialFillError(bytes memory reason) private view {
        (address target, bytes4 callbackSelector, bytes memory innerReason,) = this.decodeWrappedError(reason);
        assertEq(target, address(hook));
        assertEq(callbackSelector, IHooks.afterSwap.selector);
        assertEq(_leadingSelector(innerReason), SoftLandingHook.PartialFillUnsupported.selector);
    }

    function _leadingSelector(bytes memory data) private pure returns (bytes4 selector) {
        require(data.length >= 4, "missing selector");
        selector = bytes4(data);
    }
}
