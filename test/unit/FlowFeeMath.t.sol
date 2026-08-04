// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { FlowFeeMath } from "../../src/lib/FlowFeeMath.sol";

contract FlowFeeMathHarness {
    function nextFee(
        uint256 flow,
        uint256 target,
        uint24 currentFee,
        uint24 baseFee,
        uint24 maxFee,
        uint24 rise,
        uint24 decay,
        uint32 maxExcessBps
    ) external pure returns (uint24) {
        return FlowFeeMath.nextFee(flow, target, currentFee, baseFee, maxFee, rise, decay, maxExcessBps);
    }

    function decayEmptyBlocks(uint24 fee, uint24 baseFee, uint24 decay, uint256 emptyBlocks)
        external
        pure
        returns (uint24)
    {
        return FlowFeeMath.decayEmptyBlocks(fee, baseFee, decay, emptyBlocks);
    }
}

contract FlowFeeMathTest is Test {
    uint256 internal constant TARGET = 10 ether;
    uint24 internal constant BASE = 3000;
    uint24 internal constant INITIAL = 10_000;
    uint24 internal constant MAX = 30_000;
    uint24 internal constant RISE = 5000;
    uint24 internal constant DECAY = 2500;
    uint32 internal constant MAX_EXCESS_BPS = 30_000;

    FlowFeeMathHarness internal math;

    function setUp() public {
        math = new FlowFeeMathHarness();
    }

    function testWorkedExamples() public view {
        assertEq(_next(10 ether, INITIAL), 10_000, "target leaves fee unchanged");
        assertEq(_next(20 ether, INITIAL), 15_000, "2x target adds configured rise");
        assertEq(_next(25 ether, INITIAL), 17_500, "150% excess adds 75 bps");
        assertEq(_next(2 ether, INITIAL), 8000, "80% slack removes 20 bps");
        assertEq(_next(0, INITIAL), 7500, "zero flow removes full decay");
        assertEq(math.decayEmptyBlocks(17_500, BASE, DECAY, 3), 10_000, "three empty blocks apply at once");
        assertEq(_next(110 ether, INITIAL), 25_000, "excess utilization is capped at 300%");
        assertEq(_next(100 ether, 25_000), MAX, "increase clamps at max");
        assertEq(math.decayEmptyBlocks(5000, BASE, DECAY, 100), BASE, "decay clamps at base");
    }

    function testRoundingMovesByAtLeastOnePip() public view {
        uint256 oneUtilizationBip = TARGET / 10_000;
        assertEq(
            math.nextFee(TARGET + oneUtilizationBip, TARGET, INITIAL, BASE, MAX, RISE, DECAY, MAX_EXCESS_BPS),
            INITIAL + 1
        );
        assertEq(
            math.nextFee(TARGET - oneUtilizationBip, TARGET, INITIAL, BASE, MAX, RISE, DECAY, MAX_EXCESS_BPS),
            INITIAL - 1
        );
    }

    function testFuzzBoundsAndMonotonicity(uint128 rawA, uint128 rawB, uint24 rawFee) public view {
        uint256 a = bound(uint256(rawA), 0, 1000 ether);
        uint256 b = bound(uint256(rawB), a, 1000 ether);
        uint24 fee = uint24(bound(rawFee, BASE, MAX));
        uint24 nextA = _next(a, fee);
        uint24 nextB = _next(b, fee);
        assertGe(nextA, BASE);
        assertLe(nextA, MAX);
        assertGe(nextB, BASE);
        assertLe(nextB, MAX);
        assertGe(nextB, nextA);
    }

    function testFuzzSkippedDecayMatchesIteration(uint24 rawFee, uint16 rawBlocks) public view {
        uint24 fee = uint24(bound(rawFee, BASE, MAX));
        uint256 blocks_ = bound(uint256(rawBlocks), 0, 1000);
        uint24 iterated = fee;
        for (uint256 index; index < blocks_; ++index) {
            iterated = _next(0, iterated);
        }
        assertEq(math.decayEmptyBlocks(fee, BASE, DECAY, blocks_), iterated);
    }

    function _next(uint256 flow, uint24 fee) private view returns (uint24) {
        return math.nextFee(flow, TARGET, fee, BASE, MAX, RISE, DECAY, MAX_EXCESS_BPS);
    }
}
