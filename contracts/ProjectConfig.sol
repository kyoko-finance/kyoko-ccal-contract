// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./interface.sol";

contract ProjectConfig {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    bytes32 public constant ROBOT_ROLE = keccak256("ROBOT_ROLE");

    ICreditSystem internal creditSystem;

    bool public isMainChain;

    address public vault;

    bool internal _paused;

    uint public fee;

    EnumerableSetUpgradeable.AddressSet internal normal_tokens;

    EnumerableSetUpgradeable.AddressSet internal stable_tokens;

    // max subsidy token one-time
    uint public max_discount;

    uint public discount_percent;
}
