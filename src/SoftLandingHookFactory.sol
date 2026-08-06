// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

import { SoftLandingConfig, SoftLandingHook, SoftLandingLaunchConfig } from "./SoftLandingHook.sol";

/// @notice Atomic CREATE2 deployment, one-pool binding, and initialization for Soft Landing.
contract SoftLandingHookFactory {
    uint160 public constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 public constant REQUIRED_HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    mapping(address hook => bytes32 configurationHash) public configurationHashOf;

    error DeploymentAddressMismatch(address actual, address predicted);
    error HookAlreadyDeployed(address hook);
    error InvalidHookAddress(address hook, uint160 actualFlags, uint160 requiredFlags);
    error LaunchIdentityMismatch(address expected, address actual);

    event SoftLandingHookDeployed(
        address indexed hook,
        address indexed poolManager,
        bytes32 indexed poolId,
        address quoteCurrency,
        bytes32 salt,
        bytes32 configurationHash
    );

    function deployAndInitialize(
        bytes32 salt,
        address expectedHook,
        IPoolManager poolManager,
        address quoteCurrency,
        SoftLandingConfig calldata config,
        SoftLandingLaunchConfig calldata launchConfig
    ) external returns (SoftLandingHook hook, PoolKey memory key, int24 initialTick) {
        bytes memory code = initCode(poolManager, quoteCurrency, config, launchConfig);
        address predicted = Create2.computeAddress(salt, keccak256(code));
        if (predicted != expectedHook) revert LaunchIdentityMismatch(expectedHook, predicted);
        uint160 actualFlags = uint160(predicted) & ALL_HOOK_MASK;
        if (actualFlags != REQUIRED_HOOK_FLAGS) {
            revert InvalidHookAddress(predicted, actualFlags, REQUIRED_HOOK_FLAGS);
        }
        if (predicted.code.length != 0) revert HookAlreadyDeployed(predicted);

        address deployed = Create2.deploy(0, salt, code);
        if (deployed != predicted) revert DeploymentAddressMismatch(deployed, predicted);
        hook = SoftLandingHook(deployed);
        key = hook.canonicalPoolKey();
        (, initialTick) = hook.registerCanonicalPool();

        bytes32 poolId = PoolId.unwrap(key.toId());
        bytes32 configurationHash = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                deployed,
                address(poolManager),
                poolId,
                quoteCurrency,
                config,
                launchConfig
            )
        );
        configurationHashOf[deployed] = configurationHash;
        emit SoftLandingHookDeployed(deployed, address(poolManager), poolId, quoteCurrency, salt, configurationHash);
    }

    function initCode(
        IPoolManager poolManager,
        address quoteCurrency,
        SoftLandingConfig calldata config,
        SoftLandingLaunchConfig calldata launchConfig
    ) public view returns (bytes memory) {
        return abi.encodePacked(
            type(SoftLandingHook).creationCode,
            abi.encode(poolManager, address(this), quoteCurrency, config, launchConfig)
        );
    }

    function initCodeHash(
        IPoolManager poolManager,
        address quoteCurrency,
        SoftLandingConfig calldata config,
        SoftLandingLaunchConfig calldata launchConfig
    ) external view returns (bytes32) {
        return keccak256(initCode(poolManager, quoteCurrency, config, launchConfig));
    }

    function predictHookAddress(
        bytes32 salt,
        IPoolManager poolManager,
        address quoteCurrency,
        SoftLandingConfig calldata config,
        SoftLandingLaunchConfig calldata launchConfig
    ) external view returns (address) {
        return Create2.computeAddress(salt, keccak256(initCode(poolManager, quoteCurrency, config, launchConfig)));
    }
}
