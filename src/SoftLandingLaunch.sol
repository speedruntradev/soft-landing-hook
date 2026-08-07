// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { CurrencySettler } from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { ModifyLiquidityParams, SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { SoftLandingConfig, SoftLandingHook, SoftLandingLaunchConfig } from "./SoftLandingHook.sol";
import { SoftLandingHookFactory } from "./SoftLandingHookFactory.sol";
import { SoftLandingToken, SoftLandingTokenMetadata } from "./SoftLandingToken.sol";

struct SoftLandingTokenLaunchConfig {
    string name;
    string symbol;
    uint256 totalSupply;
    bytes32 salt;
    address expectedToken;
    SoftLandingTokenMetadata metadata;
}

struct SoftLandingPositionConfig {
    bytes32 salt;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 minimumTokenAmount;
    uint256 maximumTokenAmount;
}

struct SoftLandingInitialBuyConfig {
    uint256 nativeAmount;
    uint256 minimumTokenAmount;
    uint160 sqrtPriceLimitX96;
    address recipient;
}

struct SoftLandingLaunchRequest {
    SoftLandingTokenLaunchConfig token;
    SoftLandingConfig controller;
    bytes32 hookSalt;
    address expectedHook;
    bytes32 expectedPoolId;
    int24 tickSpacing;
    uint160 initialSqrtPriceX96;
    SoftLandingPositionConfig position;
    SoftLandingInitialBuyConfig initialBuy;
    uint256 deadline;
}

/// @title Soft Landing Launch
/// @notice Creates the token, hook, canonical pool, permanently locked liquidity, and first buy in one transaction.
/// @dev The launcher owns each direct PoolManager position and exposes no remove-liquidity, transfer, rescue, or
///      arbitrary-call path. The full token supply is committed to the one-sided position; only rounding dust remains
///      in this contract. Any failed child deployment, pool initialization, settlement, buy, or postcondition reverts
///      the complete launch, including CREATE2 children.
contract SoftLandingLaunch is IUnlockCallback, ReentrancyGuardTransient {
    using CurrencySettler for Currency;
    using SafeCast for int256;

    IPoolManager public immutable poolManager;
    SoftLandingHookFactory public immutable hookFactory;

    mapping(address token => bytes32 launchHash) public launchHashOf;

    bytes32 private _activeUnlockHash;
    bool private _unlockActive;

    struct LaunchResult {
        address token;
        address hook;
        bytes32 poolId;
        uint256 tokenLiquidityAmount;
        uint256 lockedTokenDust;
        uint256 initialBuyNativeAmount;
        uint256 initialBuyTokenAmount;
        bytes32 launchHash;
    }

    struct LiquidityCallbackData {
        PoolKey key;
        SoftLandingPositionConfig position;
        SoftLandingInitialBuyConfig initialBuy;
    }

    error InvalidOneSidedPosition(int24 initialTick, int24 tickLower, int24 tickUpper);
    error DeadlineExpired(uint256 deadline, uint256 timestamp);
    error DependencyMismatch(address dependency);
    error HookConfigurationMissing(address hook);
    error InvalidExpectedIdentity(address expected);
    error InvalidExpectedPoolId(bytes32 expectedPoolId);
    error InvalidLiquidity(uint128 liquidity);
    error InvalidLiquidityDelta(int128 amount0, int128 amount1);
    error InvalidLiquidityLimits(uint256 minimum, uint256 maximum);
    error LiquidityAmountOutsideBounds(uint256 amount, uint256 minimum, uint256 maximum);
    error InvalidInitialBuy(uint256 supplied, uint256 expected);
    error InvalidInitialBuyDelta(int128 nativeDelta, int128 tokenDelta);
    error InvalidRecipient(address recipient);
    error LaunchAlreadyExists(address token);
    error NativeBalancePostcondition(uint256 actual, uint256 expected);
    error PoolIdentityMismatch(bytes32 actual, bytes32 expected);
    error TokenAddressMismatch(address actual, address expected);
    error TokenBalancePostcondition(uint256 actual, uint256 expected);
    error TokenBudgetExceedsSupply(uint256 budget, uint256 supply);
    error UnauthorizedUnlockCallback(address caller);
    error UnexpectedUnlock(bytes32 actualHash, bytes32 expectedHash);

    event SoftLandingLaunched(
        address indexed creator,
        address indexed token,
        address indexed hook,
        bytes32 poolId,
        bytes32 launchHash,
        uint256 totalSupply,
        uint256 tokenLiquidityAmount,
        uint256 lockedTokenDust,
        uint256 initialBuyNativeAmount,
        uint256 initialBuyTokenAmount,
        address initialBuyRecipient
    );

    event SoftLandingPositionLocked(
        bytes32 indexed poolId,
        address indexed owner,
        bytes32 indexed positionSalt,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 tokenAmount
    );

    constructor(IPoolManager poolManager_, SoftLandingHookFactory hookFactory_) {
        if (address(poolManager_) == address(0) || address(poolManager_).code.length == 0) {
            revert DependencyMismatch(address(poolManager_));
        }
        if (address(hookFactory_) == address(0) || address(hookFactory_).code.length == 0) {
            revert DependencyMismatch(address(hookFactory_));
        }
        poolManager = poolManager_;
        hookFactory = hookFactory_;
    }

    function predictTokenAddress(SoftLandingTokenLaunchConfig calldata token, address creator)
        external
        view
        returns (address)
    {
        return Create2.computeAddress(token.salt, keccak256(_tokenInitCode(token, creator)));
    }

    function launch(SoftLandingLaunchRequest calldata request)
        external
        payable
        nonReentrant
        returns (LaunchResult memory result)
    {
        // A timestamp deadline is intentionally a coarse stale-transaction bound; miner tolerance does not alter
        // any price, amount, identity, custody, or fee parameter committed by the request.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > request.deadline) revert DeadlineExpired(request.deadline, block.timestamp);
        _validateRequest(request);

        uint256 residualNativeBalance = address(this).balance - msg.value;
        result.token = _createToken(request.token, msg.sender);
        if (launchHashOf[result.token] != bytes32(0)) revert LaunchAlreadyExists(result.token);

        SoftLandingLaunchConfig memory hookLaunchConfig = SoftLandingLaunchConfig({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(result.token),
            tickSpacing: request.tickSpacing,
            sqrtPriceX96: request.initialSqrtPriceX96
        });
        SoftLandingHook hook;
        PoolKey memory key;
        int24 initialTick;
        (hook, key, initialTick) = hookFactory.deployAndInitialize(
            request.hookSalt, request.expectedHook, poolManager, address(0), request.controller, hookLaunchConfig
        );
        result.hook = address(hook);
        result.poolId = PoolId.unwrap(key.toId());
        if (result.poolId != request.expectedPoolId) {
            revert PoolIdentityMismatch(result.poolId, request.expectedPoolId);
        }
        if (hookFactory.configurationHashOf(result.hook) == bytes32(0)) {
            revert HookConfigurationMissing(result.hook);
        }
        if (!(request.position.tickLower < initialTick && initialTick == request.position.tickUpper)) {
            revert InvalidOneSidedPosition(initialTick, request.position.tickLower, request.position.tickUpper);
        }

        (result.tokenLiquidityAmount, result.initialBuyTokenAmount) =
            _addLockedLiquidityAndBuy(key, request.position, request.initialBuy);
        result.initialBuyNativeAmount = request.initialBuy.nativeAmount;
        Currency.wrap(result.token).transfer(request.initialBuy.recipient, result.initialBuyTokenAmount);
        result.lockedTokenDust = request.token.totalSupply - result.tokenLiquidityAmount;

        uint256 tokenBalance = IERC20(result.token).balanceOf(address(this));
        if (tokenBalance != result.lockedTokenDust) {
            revert TokenBalancePostcondition(tokenBalance, result.lockedTokenDust);
        }
        if (address(this).balance != residualNativeBalance) {
            revert NativeBalancePostcondition(address(this).balance, residualNativeBalance);
        }

        result.launchHash = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                msg.sender,
                result.token,
                result.hook,
                result.poolId,
                request,
                result.tokenLiquidityAmount,
                result.lockedTokenDust,
                result.initialBuyNativeAmount,
                result.initialBuyTokenAmount
            )
        );
        launchHashOf[result.token] = result.launchHash;

        emit SoftLandingPositionLocked(
            result.poolId,
            address(this),
            request.position.salt,
            request.position.tickLower,
            request.position.tickUpper,
            request.position.liquidity,
            result.tokenLiquidityAmount
        );
        emit SoftLandingLaunched(
            msg.sender,
            result.token,
            result.hook,
            result.poolId,
            result.launchHash,
            request.token.totalSupply,
            result.tokenLiquidityAmount,
            result.lockedTokenDust,
            result.initialBuyNativeAmount,
            result.initialBuyTokenAmount,
            request.initialBuy.recipient
        );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert UnauthorizedUnlockCallback(msg.sender);
        bytes32 actualHash = keccak256(data);
        if (!_unlockActive || actualHash != _activeUnlockHash) {
            revert UnexpectedUnlock(actualHash, _activeUnlockHash);
        }

        LiquidityCallbackData memory callback = abi.decode(data, (LiquidityCallbackData));
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            callback.key,
            ModifyLiquidityParams({
                tickLower: callback.position.tickLower,
                tickUpper: callback.position.tickUpper,
                liquidityDelta: int256(uint256(callback.position.liquidity)),
                salt: callback.position.salt
            }),
            ""
        );
        int128 amount0Delta = delta.amount0();
        int128 amount1Delta = delta.amount1();
        if (amount0Delta != 0 || amount1Delta >= 0) {
            revert InvalidLiquidityDelta(amount0Delta, amount1Delta);
        }
        uint256 positionTokenAmount = (-int256(amount1Delta)).toUint256();
        _validateAmount(positionTokenAmount, callback.position.minimumTokenAmount, callback.position.maximumTokenAmount);

        BalanceDelta swapDelta = poolManager.swap(
            callback.key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -SafeCast.toInt256(callback.initialBuy.nativeAmount),
                sqrtPriceLimitX96: callback.initialBuy.sqrtPriceLimitX96
            }),
            ""
        );
        int128 nativeDelta = swapDelta.amount0();
        int128 tokenDelta = swapDelta.amount1();
        if (nativeDelta >= 0 || tokenDelta <= 0) {
            revert InvalidInitialBuyDelta(nativeDelta, tokenDelta);
        }

        uint256 initialBuyNativeAmount = (-int256(nativeDelta)).toUint256();
        uint256 initialBuyTokenAmount = int256(tokenDelta).toUint256();
        if (initialBuyNativeAmount != callback.initialBuy.nativeAmount) {
            revert InvalidInitialBuy(initialBuyNativeAmount, callback.initialBuy.nativeAmount);
        }
        if (initialBuyTokenAmount < callback.initialBuy.minimumTokenAmount) {
            revert LiquidityAmountOutsideBounds(
                initialBuyTokenAmount, callback.initialBuy.minimumTokenAmount, type(uint256).max
            );
        }
        if (initialBuyTokenAmount >= positionTokenAmount) {
            revert TokenBudgetExceedsSupply(initialBuyTokenAmount, positionTokenAmount);
        }

        callback.key.currency0.settle(poolManager, address(this), initialBuyNativeAmount, false);
        callback.key.currency1.settle(poolManager, address(this), positionTokenAmount - initialBuyTokenAmount, false);
        return abi.encode(positionTokenAmount, initialBuyTokenAmount);
    }

    function _addLockedLiquidityAndBuy(
        PoolKey memory key,
        SoftLandingPositionConfig calldata position,
        SoftLandingInitialBuyConfig calldata initialBuy
    ) private returns (uint256 tokenLiquidityAmount, uint256 initialBuyTokenAmount) {
        bytes memory data = abi.encode(LiquidityCallbackData({ key: key, position: position, initialBuy: initialBuy }));
        _activeUnlockHash = keccak256(data);
        _unlockActive = true;
        bytes memory output = poolManager.unlock(data);
        _unlockActive = false;
        _activeUnlockHash = bytes32(0);
        return abi.decode(output, (uint256, uint256));
    }

    function _createToken(SoftLandingTokenLaunchConfig calldata token, address creator)
        private
        returns (address deployed)
    {
        bytes memory code = _tokenInitCode(token, creator);
        address predicted = Create2.computeAddress(token.salt, keccak256(code));
        if (predicted != token.expectedToken) revert TokenAddressMismatch(predicted, token.expectedToken);
        if (predicted.code.length != 0) revert LaunchAlreadyExists(predicted);
        deployed = Create2.deploy(0, token.salt, code);
        if (deployed != predicted) revert TokenAddressMismatch(deployed, predicted);
    }

    function _tokenInitCode(SoftLandingTokenLaunchConfig calldata token, address creator)
        private
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            type(SoftLandingToken).creationCode,
            abi.encode(token.name, token.symbol, token.totalSupply, creator, address(this), token.metadata)
        );
    }

    function _validateRequest(SoftLandingLaunchRequest calldata request) private view {
        if (request.token.expectedToken == address(0) || request.expectedHook == address(0)) {
            revert InvalidExpectedIdentity(address(0));
        }
        if (request.expectedPoolId == bytes32(0)) revert InvalidExpectedPoolId(request.expectedPoolId);
        if (request.initialBuy.recipient == address(0) || request.initialBuy.recipient == address(this)) {
            revert InvalidRecipient(request.initialBuy.recipient);
        }
        if (request.position.liquidity == 0 || request.position.liquidity > uint128(type(int128).max)) {
            revert InvalidLiquidity(request.position.liquidity);
        }
        _validateLimits(request.position.minimumTokenAmount, request.position.maximumTokenAmount);
        if (request.position.maximumTokenAmount > request.token.totalSupply) {
            revert TokenBudgetExceedsSupply(request.position.maximumTokenAmount, request.token.totalSupply);
        }
        if (
            request.initialBuy.nativeAmount == 0 || request.initialBuy.minimumTokenAmount == 0
                || request.initialBuy.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_PRICE
                || request.initialBuy.sqrtPriceLimitX96 >= request.initialSqrtPriceX96
        ) {
            revert InvalidInitialBuy(msg.value, request.initialBuy.nativeAmount);
        }
        if (msg.value != request.initialBuy.nativeAmount) {
            revert InvalidInitialBuy(msg.value, request.initialBuy.nativeAmount);
        }
    }

    function _validateLimits(uint256 minimum, uint256 maximum) private pure {
        if (minimum == 0 || minimum > maximum) revert InvalidLiquidityLimits(minimum, maximum);
    }

    function _validateAmount(uint256 amount, uint256 minimum, uint256 maximum) private pure {
        if (amount < minimum || amount > maximum) {
            revert LiquidityAmountOutsideBounds(amount, minimum, maximum);
        }
    }
}
