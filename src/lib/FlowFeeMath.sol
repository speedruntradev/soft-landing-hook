// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @notice Pure reference math for Soft Landing's directional block-to-block controller.
library FlowFeeMath {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Applies one completed block of flow to one directional LP fee.
    function nextFee(
        uint256 flow,
        uint256 target,
        uint24 currentFee,
        uint24 baseFee,
        uint24 maxFee,
        uint24 riseAt2xTarget,
        uint24 decayAtZero,
        uint32 maxExcessBps
    ) internal pure returns (uint24) {
        if (flow == target) return currentFee;

        if (flow > target) {
            uint256 excess = flow - target;
            uint256 cappedExcess = FullMath.mulDiv(target, maxExcessBps, BPS_DENOMINATOR);
            uint256 excessBps = excess >= cappedExcess ? maxExcessBps : FullMath.mulDiv(excess, BPS_DENOMINATOR, target);
            uint256 increase = FullMath.mulDivRoundingUp(excessBps, riseAt2xTarget, BPS_DENOMINATOR);
            uint256 increased = uint256(currentFee) + increase;
            return increased >= maxFee ? maxFee : SafeCast.toUint24(increased);
        }

        uint256 slackBps = FullMath.mulDiv(target - flow, BPS_DENOMINATOR, target);
        uint256 decrease = FullMath.mulDivRoundingUp(slackBps, decayAtZero, BPS_DENOMINATOR);
        return decrease >= uint256(currentFee - baseFee) ? baseFee : SafeCast.toUint24(uint256(currentFee) - decrease);
    }

    /// @notice Applies any number of empty blocks in constant time with saturation at the base fee.
    function decayEmptyBlocks(uint24 fee, uint24 baseFee, uint24 decayAtZero, uint256 emptyBlocks)
        internal
        pure
        returns (uint24)
    {
        if (emptyBlocks == 0 || fee == baseFee) return fee;
        uint256 distance = fee - baseFee;
        uint256 blocksToBase = (distance + decayAtZero - 1) / decayAtZero;
        if (emptyBlocks >= blocksToBase) return baseFee;
        return SafeCast.toUint24(uint256(fee) - emptyBlocks * decayAtZero);
    }
}
