// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Immutable metadata committed to a Soft Landing token's CREATE2 identity.
struct SoftLandingTokenMetadata {
    string description;
    string website;
    string image;
    bytes extraData;
}

/// @title Soft Landing Token
/// @notice Fixed-supply ERC-20 with immutable creator and launch metadata and no administrative powers.
contract SoftLandingToken is ERC20 {
    address public immutable creator;
    string public description;
    string public website;
    string public image;
    bytes public extraData;
    bytes32 public immutable metadataHash;

    error EmptyName();
    error EmptySymbol();
    error InvalidCreator();
    error InvalidSupply();
    error InvalidSupplyRecipient();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address creator_,
        address supplyRecipient_,
        SoftLandingTokenMetadata memory metadata_
    ) ERC20(name_, symbol_) {
        if (bytes(name_).length == 0) revert EmptyName();
        if (bytes(symbol_).length == 0) revert EmptySymbol();
        if (totalSupply_ == 0) revert InvalidSupply();
        if (creator_ == address(0)) revert InvalidCreator();
        if (supplyRecipient_ == address(0)) revert InvalidSupplyRecipient();

        creator = creator_;
        description = metadata_.description;
        website = metadata_.website;
        image = metadata_.image;
        extraData = metadata_.extraData;
        metadataHash =
            keccak256(abi.encode(metadata_.description, metadata_.website, metadata_.image, metadata_.extraData));
        _mint(supplyRecipient_, totalSupply_);
    }
}
