// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { FlowFeeMath } from "../../src/lib/FlowFeeMath.sol";

contract ControllerInvariantHandler {
    uint256 internal constant TARGET = 10 ether;
    uint24 internal constant BASE = 3000;
    uint24 internal constant MAX = 30_000;
    uint24 internal constant RISE = 5000;
    uint24 internal constant DECAY = 2500;
    uint32 internal constant MAX_EXCESS_BPS = 30_000;

    uint24 public productionBuyFee = 10_000;
    uint24 public referenceBuyFee = 10_000;
    uint24 public productionSellFee = 10_000;
    uint24 public referenceSellFee = 10_000;
    bool public equivalenceViolated;
    uint256 public usefulCalls;

    function roll(uint128 rawBuyFlow, uint128 rawSellFlow, uint8 rawEmptyBlocks) external {
        uint256 buyFlow = uint256(rawBuyFlow) % (1000 ether + 1);
        uint256 sellFlow = uint256(rawSellFlow) % (1000 ether + 1);
        uint256 emptyBlocks = uint256(rawEmptyBlocks) % 33;

        productionBuyFee = _next(buyFlow, productionBuyFee);
        productionSellFee = _next(sellFlow, productionSellFee);
        productionBuyFee = FlowFeeMath.decayEmptyBlocks(productionBuyFee, BASE, DECAY, emptyBlocks);
        productionSellFee = FlowFeeMath.decayEmptyBlocks(productionSellFee, BASE, DECAY, emptyBlocks);

        referenceBuyFee = _next(buyFlow, referenceBuyFee);
        referenceSellFee = _next(sellFlow, referenceSellFee);
        for (uint256 index; index < emptyBlocks; ++index) {
            referenceBuyFee = _next(0, referenceBuyFee);
            referenceSellFee = _next(0, referenceSellFee);
        }

        if (productionBuyFee != referenceBuyFee || productionSellFee != referenceSellFee) {
            equivalenceViolated = true;
        }
        ++usefulCalls;
    }

    function _next(uint256 flow, uint24 fee) private pure returns (uint24) {
        return FlowFeeMath.nextFee(flow, TARGET, fee, BASE, MAX, RISE, DECAY, MAX_EXCESS_BPS);
    }
}

contract ControllerInvariantTest is Test {
    ControllerInvariantHandler internal handler;

    function setUp() public {
        handler = new ControllerInvariantHandler();
        targetContract(address(handler));
    }

    function invariantConstantTimeDecayMatchesExplicitHistory() public view {
        assertFalse(handler.equivalenceViolated());
    }

    function invariantFeesRemainBounded() public view {
        assertGe(handler.productionBuyFee(), 3000);
        assertLe(handler.productionBuyFee(), 30_000);
        assertGe(handler.productionSellFee(), 3000);
        assertLe(handler.productionSellFee(), 30_000);
    }
}
