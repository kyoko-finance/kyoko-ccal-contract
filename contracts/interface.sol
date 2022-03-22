// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;


interface ICreditSystem {
    function getCCALCreditLine(address user) external returns(uint);
    function getState(address user) external returns(bool, bool);
}

enum AssetStatus { INITIAL, BORROW, REPAY, WITHDRAW, LIQUIDATE }

struct DepositTool {
    uint cycle;
    uint minPay;
    AssetStatus status;
    uint[] toolIds;
    address holder;
    uint borrowTime;
    uint depositTime;
    uint totalAmount;
    address borrower;
    uint amountPerDay;
    uint internalId;
    address game;
    address token;
}

struct FreezeTokenInfo {
    address operator;
    uint internalId;
    bool useCredit;
    address game;
    uint amount;
    uint interest;
    address token;
}

struct InterestInfo {
    uint internalId;
    address game;
    uint amount;
    address token;
}
