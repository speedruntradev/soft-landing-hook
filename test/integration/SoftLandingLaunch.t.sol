// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { SoftLandingConfig, SoftLandingHook, SoftLandingLaunchConfig } from "../../src/SoftLandingHook.sol";
import { SoftLandingHookFactory } from "../../src/SoftLandingHookFactory.sol";
import {
    SoftLandingInitialBuyConfig,
    SoftLandingLaunch,
    SoftLandingLaunchRequest,
    SoftLandingPositionConfig,
    SoftLandingTokenLaunchConfig
} from "../../src/SoftLandingLaunch.sol";
import { SoftLandingToken, SoftLandingTokenMetadata } from "../../src/SoftLandingToken.sol";

contract SoftLandingLaunchTest is Deployers {
    using StateLibrary for IPoolManager;

    int24 internal constant TICK_SPACING = 60;
    int24 internal constant INITIAL_TICK = 204_180;
    int24 internal constant LOWER_TICK = -887_220;
    uint256 internal constant TOKEN_SUPPLY = 1_000_000_000 ether;
    uint256 internal constant INITIAL_BUY_NATIVE_AMOUNT = 0.001 ether;

    SoftLandingHookFactory internal hookFactory;
    SoftLandingLaunch internal launcher;
    SoftLandingConfig internal controller;
    PoolSwapTest.TestSettings internal settings =
        PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });

    function setUp() public {
        deployFreshManagerAndRouters();
        vm.deal(address(this), 1_000_000 ether);
        hookFactory = new SoftLandingHookFactory();
        launcher = new SoftLandingLaunch(manager, hookFactory);
        controller = SoftLandingConfig({
            baseFeePips: 3000,
            initialBuyFeePips: 10_000,
            initialSellFeePips: 10_000,
            maxFeePips: 30_000,
            riseAt2xTargetPips: 5000,
            decayAtZeroPips: 2500,
            maxExcessBps: 30_000,
            warmupBlocks: 10,
            targetQuotePerBlock: 1 ether
        });
    }

    function testAtomicLaunchCreatesTradableTokenHookAndPermanentlyLockedPosition() public {
        // Literal salts are at most 10 bytes and therefore cannot truncate when right-padded to bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        SoftLandingLaunchRequest memory request = _request(bytes32("token-a"), bytes32("position-a"));
        uint256 nativeBefore = address(this).balance;

        SoftLandingLaunch.LaunchResult memory result =
            launcher.launch{ value: request.initialBuy.nativeAmount }(request);

        assertEq(result.token, request.token.expectedToken);
        assertEq(result.hook, request.expectedHook);
        assertEq(result.poolId, request.expectedPoolId);
        assertEq(result.initialBuyNativeAmount, INITIAL_BUY_NATIVE_AMOUNT);
        assertGt(result.initialBuyTokenAmount, 0);
        assertGt(result.tokenLiquidityAmount, TOKEN_SUPPLY - 1 ether);
        assertEq(result.lockedTokenDust, TOKEN_SUPPLY - result.tokenLiquidityAmount);
        assertLt(result.lockedTokenDust, 1 ether);
        assertEq(address(this).balance, nativeBefore - INITIAL_BUY_NATIVE_AMOUNT);
        assertEq(launcher.launchHashOf(result.token), result.launchHash);

        SoftLandingToken token = SoftLandingToken(result.token);
        assertEq(token.totalSupply(), TOKEN_SUPPLY);
        assertEq(token.balanceOf(address(launcher)), result.lockedTokenDust);
        assertEq(token.balanceOf(address(this)), result.initialBuyTokenAmount);
        assertEq(token.name(), "Soft Landing Launch Token");
        assertEq(token.symbol(), "SLAND");
        assertEq(token.creator(), address(this));
        assertEq(token.description(), "Block-stable directional congestion launch token.");
        assertEq(token.website(), "https://github.com/speedruntradev/soft-landing-hook");
        assertEq(token.image(), "ipfs://soft-landing-placeholder");
        assertEq(token.extraData(), bytes("{\"schema\":\"soft-landing-token-metadata-v1\"}"));
        assertEq(
            token.balanceOf(address(manager)) + token.balanceOf(address(this)) + token.balanceOf(address(launcher)),
            TOKEN_SUPPLY
        );

        (uint128 positionLiquidity,,) = manager.getPositionInfo(
            PoolId.wrap(result.poolId),
            address(launcher),
            request.position.tickLower,
            request.position.tickUpper,
            request.position.salt
        );
        assertEq(positionLiquidity, request.position.liquidity);
        assertGt(manager.getLiquidity(PoolId.wrap(result.poolId)), 0);
        assertEq(hookFactory.REQUIRED_HOOK_FLAGS(), 0x20cc);
        assertEq(uint160(result.hook) & hookFactory.ALL_HOOK_MASK(), hookFactory.REQUIRED_HOOK_FLAGS());
        assertTrue(hookFactory.configurationHashOf(result.hook) != bytes32(0));

        PoolKey memory key = SoftLandingHook(result.hook).canonicalPoolKey();
        uint256 tokensAfterLaunch = token.balanceOf(address(this));
        BalanceDelta buyDelta = swapRouter.swap{ value: 0.0001 ether }(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -int256(0.0001 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            settings,
            ZERO_BYTES
        );
        assertGt(buyDelta.amount1(), 0);
        assertGt(token.balanceOf(address(this)), tokensAfterLaunch);

        uint256 sellAmount = result.initialBuyTokenAmount / 10;
        token.approve(address(swapRouter), sellAmount);
        uint256 nativeBeforeSell = address(this).balance;
        BalanceDelta sellDelta = swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -SafeCast.toInt256(sellAmount), sqrtPriceLimitX96: MAX_PRICE_LIMIT
            }),
            settings,
            ZERO_BYTES
        );
        assertGt(sellDelta.amount0(), 0);
        assertGt(address(this).balance, nativeBeforeSell);
        assertTrue(SoftLandingHook(result.hook).started());
    }

    function testPositionAmountFailureRollsBackTokenHookPoolAndLaunchRecord() public {
        // Literal salts are at most 10 bytes and therefore cannot truncate when right-padded to bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        SoftLandingLaunchRequest memory request = _request(bytes32("token-b"), bytes32("position-b"));
        request.position.minimumTokenAmount = TOKEN_SUPPLY;

        vm.expectRevert();
        launcher.launch{ value: request.initialBuy.nativeAmount }(request);

        assertEq(request.token.expectedToken.code.length, 0, "token CREATE2 deployment rolls back");
        assertEq(request.expectedHook.code.length, 0, "hook CREATE2 deployment rolls back");
        assertEq(launcher.launchHashOf(request.token.expectedToken), bytes32(0));
    }

    function testInitialBuySettlementFailureRollsBackEverything() public {
        // Literal salts are at most 10 bytes and therefore cannot truncate when right-padded to bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        SoftLandingLaunchRequest memory request = _request(bytes32("token-c"), bytes32("position-c"));
        request.initialBuy.minimumTokenAmount = TOKEN_SUPPLY;

        vm.expectRevert();
        launcher.launch{ value: request.initialBuy.nativeAmount }(request);

        assertEq(request.token.expectedToken.code.length, 0);
        assertEq(request.expectedHook.code.length, 0);
        assertEq(launcher.launchHashOf(request.token.expectedToken), bytes32(0));
    }

    function testCallbackRejectsDirectAndWrongManagerCalls() public {
        // Literal salts are at most 10 bytes and therefore cannot truncate when right-padded to bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        SoftLandingLaunchRequest memory request = _request(bytes32("token-d"), bytes32("position-d"));
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(request.token.expectedToken),
            fee: 0x800000,
            tickSpacing: request.tickSpacing,
            hooks: IHooks(request.expectedHook)
        });
        bytes memory data = abi.encode(
            SoftLandingLaunch.LiquidityCallbackData({
                key: key, position: request.position, initialBuy: request.initialBuy
            })
        );

        vm.expectRevert(abi.encodeWithSelector(SoftLandingLaunch.UnauthorizedUnlockCallback.selector, address(this)));
        launcher.unlockCallback(data);

        vm.prank(address(manager));
        vm.expectRevert();
        launcher.unlockCallback(data);
    }

    function _request(bytes32 tokenSalt, bytes32 positionSalt)
        private
        view
        returns (SoftLandingLaunchRequest memory request)
    {
        request.token = SoftLandingTokenLaunchConfig({
            name: "Soft Landing Launch Token",
            symbol: "SLAND",
            totalSupply: TOKEN_SUPPLY,
            salt: tokenSalt,
            expectedToken: address(1),
            metadata: SoftLandingTokenMetadata({
                description: "Block-stable directional congestion launch token.",
                website: "https://github.com/speedruntradev/soft-landing-hook",
                image: "ipfs://soft-landing-placeholder",
                extraData: bytes("{\"schema\":\"soft-landing-token-metadata-v1\"}")
            })
        });
        request.token.expectedToken = launcher.predictTokenAddress(request.token, address(this));

        uint160 initialSqrtPriceX96 = TickMath.getSqrtPriceAtTick(INITIAL_TICK);
        SoftLandingLaunchConfig memory hookLaunchConfig = SoftLandingLaunchConfig({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(request.token.expectedToken),
            tickSpacing: TICK_SPACING,
            sqrtPriceX96: initialSqrtPriceX96
        });
        (request.expectedHook, request.hookSalt) = HookMiner.find(
            address(hookFactory),
            hookFactory.REQUIRED_HOOK_FLAGS(),
            type(SoftLandingHook).creationCode,
            abi.encode(manager, address(hookFactory), address(0), controller, hookLaunchConfig)
        );
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(request.token.expectedToken),
            fee: 0x800000,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(request.expectedHook)
        });
        request.expectedPoolId = PoolId.unwrap(key.toId());
        request.controller = controller;
        request.tickSpacing = TICK_SPACING;
        request.initialSqrtPriceX96 = initialSqrtPriceX96;
        uint128 positionLiquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(LOWER_TICK), initialSqrtPriceX96, TOKEN_SUPPLY
        );
        request.position = SoftLandingPositionConfig({
            salt: positionSalt,
            tickLower: LOWER_TICK,
            tickUpper: INITIAL_TICK,
            liquidity: positionLiquidity,
            minimumTokenAmount: TOKEN_SUPPLY - 1 ether,
            maximumTokenAmount: TOKEN_SUPPLY
        });
        request.initialBuy = SoftLandingInitialBuyConfig({
            nativeAmount: INITIAL_BUY_NATIVE_AMOUNT,
            minimumTokenAmount: 1,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
            recipient: address(this)
        });
        request.deadline = block.timestamp + 1 hours;
    }
}
