// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interface.sol";

/** ⚠️this contract is for test. ignore plz */

contract CreditSystem is ICreditSystem {
    function getCCALCreditLine(address user) public override returns(uint) {
        return type(uint).max;
    }

    function getState(address user) public override returns(bool, bool) {
        return (false, true);
    }
}
