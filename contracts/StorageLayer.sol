// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./interface.sol";

contract StorageLayer {
    // depositor => internalId[]
    mapping(address => EnumerableSetUpgradeable.UintSet) internal nftHolderMap;

    // borrower => internalId[]
    mapping(address => EnumerableSetUpgradeable.UintSet) internal nftBorrowMap;

    mapping(address => InterestInfo[]) public pendingWithdrawInterest;

    mapping(bytes => FreezeTokenInfo) public freezeMap;

    // internalId => DepositTool
    mapping(uint => DepositTool) public nftMap;

    mapping(address => uint) public creditUsed;

    mapping(address => FreezeTokenInfo[]) public pendingWithdrawFreezeToken;
}
