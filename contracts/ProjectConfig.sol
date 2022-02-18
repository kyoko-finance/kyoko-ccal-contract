// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interface.sol";

contract ProjectConfig {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    bytes32 public constant ROBOT_ROLE = keccak256("ROBOT_ROLE");

    ICreditSystem internal creditSystem;

    address public allowCurrency;

    bool public isMainChain;

    address public vault;

    bool internal _paused;

    uint public fee = 5;

}
